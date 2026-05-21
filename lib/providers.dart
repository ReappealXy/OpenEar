import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/database/app_database.dart';
import 'data/models/app_settings.dart';
import 'data/models/recording.dart';
import 'data/repositories/settings_repository.dart';
import 'data/services/audio_player_service.dart';
import 'data/services/audio_recorder_service.dart';
import 'data/services/cos_service.dart';
import 'data/services/export_service.dart';
import 'data/services/llm_service.dart';
import 'data/services/tencent_asr_service.dart';

// ---- 仓库与数据 ----

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase.instance);

final settingsRepoProvider =
    Provider<SettingsRepository>((ref) => SettingsRepository());

final settingsProvider =
    AsyncNotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.read(settingsRepoProvider).load();

  Future<void> save(AppSettings s) async {
    state = AsyncData(s);
    await ref.read(settingsRepoProvider).save(s);
  }
}

// ---- 服务 ----

final audioRecorderProvider = Provider<AudioRecorderService>((ref) {
  final s = AudioRecorderService();
  ref.onDispose(() => s.dispose());
  return s;
});

final audioPlayerProvider = Provider<AudioPlayerService>((ref) {
  final s = AudioPlayerService();
  ref.onDispose(() => s.dispose());
  return s;
});

final exportServiceProvider = Provider<ExportService>((ref) => ExportService());

final cosServiceProvider = Provider<CosService?>((ref) {
  final s = ref.watch(settingsProvider).valueOrNull;
  if (s == null || !s.cloudReady) return null;
  return CosService(
    secretId: s.secretId,
    secretKey: s.secretKey,
    region: s.cosRegion,
    bucket: s.cosBucket,
  );
});

final asrServiceProvider = Provider<TencentAsrService?>((ref) {
  final s = ref.watch(settingsProvider).valueOrNull;
  if (s == null || !s.cloudReady) return null;
  return TencentAsrService(
    secretId: s.secretId,
    secretKey: s.secretKey,
    appId: s.appId,
    enableSpeakerDiarization: s.enableSpeakerDiarization,
    speakerCount: s.speakerCount,
  );
});

final llmServiceProvider = Provider<LlmService?>((ref) {
  final s = ref.watch(settingsProvider).valueOrNull;
  if (s == null || !s.llmReady) return null;
  return LlmService(
    baseUrl: s.llmBaseUrl,
    apiKey: s.llmApiKey,
    model: s.llmModel,
    temperature: s.llmTemperature,
  );
});

// ---- 录音列表 ----

final recordingsProvider =
    AsyncNotifierProvider<RecordingsNotifier, List<Recording>>(
        RecordingsNotifier.new);

class RecordingsNotifier extends AsyncNotifier<List<Recording>> {
  @override
  Future<List<Recording>> build() =>
      ref.read(databaseProvider).listRecordings();

  Future<void> refresh() async {
    state = AsyncData(await ref.read(databaseProvider).listRecordings());
  }

  Future<void> upsert(Recording r) async {
    await ref.read(databaseProvider).upsert(r);
    await refresh();
  }

  Future<void> delete(String id) async {
    await ref.read(databaseProvider).delete(id);
    await refresh();
  }
}

final recordingByIdProvider =
    FutureProvider.family<Recording?, String>((ref, id) async {
  ref.watch(recordingsProvider);
  return ref.read(databaseProvider).getById(id);
});

// ---- 处理管线 ----

final processingPipelineProvider =
    Provider<ProcessingPipeline>((ref) => ProcessingPipeline(ref));

class ProcessingPipeline {
  final Ref ref;
  ProcessingPipeline(this.ref);

  Future<void> run(
    Recording recording, {
    void Function(String message)? onProgress,
  }) async {
    final notifier = ref.read(recordingsProvider.notifier);
    var current = recording;

    Future<void> setStatus(RecordingStatus s, {String? err}) async {
      // 若录音已被用户删除，停止处理
      final exists = await ref.read(databaseProvider).getById(current.id);
      if (exists == null) {
        debugPrint('[Pipeline] 录音 ${current.id} 已被删除，终止处理');
        throw StateError('cancelled');
      }
      current = current.copyWith(status: s, errorMessage: err);
      await notifier.upsert(current);
    }

    try {
      final cos = ref.read(cosServiceProvider);
      final asr = ref.read(asrServiceProvider);
      final llm = ref.read(llmServiceProvider);
      if (cos == null || asr == null) {
        throw StateError('请先在设置中配置腾讯云 SecretId / SecretKey / COS Bucket / AppID');
      }

      // 1. 上传 COS
      await setStatus(RecordingStatus.uploading);
      onProgress?.call('上传录音到对象存储…');
      debugPrint('[Pipeline] Step 1: 开始上传 COS');
      final settings = ref.read(settingsProvider).requireValue;
      final ext = recording.filePath.split('.').last.toLowerCase();
      final objectKey = '${settings.cosPrefix}${recording.id}.$ext';
      final fileUrl = await cos.uploadFile(
        file: File(recording.filePath),
        key: objectKey,
        contentType: ext == 'm4a' || ext == 'mp4' ? 'audio/mp4' : 'audio/mpeg',
      );
      debugPrint('[Pipeline] Step 1: COS 上传成功 → $fileUrl');
      current = current.copyWith(ossUrl: fileUrl);
      await notifier.upsert(current);

      // 2. 提交 ASR
      await setStatus(RecordingStatus.transcribing);
      onProgress?.call('提交识别任务…');
      debugPrint('[Pipeline] Step 2: 提交 ASR 任务');
      final taskId = await asr.submitTask(fileUrl: fileUrl);
      debugPrint('[Pipeline] Step 2: ASR taskId = $taskId');
      current = current.copyWith(taskId: taskId.toString());
      await notifier.upsert(current);

      // 3. 轮询结果
      onProgress?.call('等待转写结果…');
      debugPrint('[Pipeline] Step 3: 开始轮询 ASR 结果');
      final result = await asr.waitForResult(
        taskId: taskId,
        onProgress: (s) {
          debugPrint('[Pipeline] Step 3: ASR 状态 = $s');
          onProgress?.call('转写中（$s）…');
        },
      );
      debugPrint('[Pipeline] Step 3: ASR 完成，文本长度 = ${result.plain.length}');
      current = current.copyWith(
        sentences: result.sentences,
        plainTranscript: result.plain,
      );
      await notifier.upsert(current);

      // 4. LLM 分析
      if (llm != null && result.plain.isNotEmpty) {
        await setStatus(RecordingStatus.analyzing);
        onProgress?.call('AI 正在生成摘要 / 待办 / 纪要 / Q&A…');
        debugPrint('[Pipeline] Step 4: 开始 LLM 分析，模型 = ${settings.llmModel}');
        debugPrint('[Pipeline] Step 4: LLM base_url = ${settings.llmBaseUrl}');
        final out = await llm.analyzeAll(
          result.plain,
          onStepDone: (step) => debugPrint('[Pipeline] Step 4: LLM $step 完成'),
        );
        debugPrint('[Pipeline] Step 4: LLM 全部完成');
        current = current.copyWith(
          summary: out.summary,
          todos: out.todos,
          minutes: out.minutes,
          qa: out.qa,
        );
        await notifier.upsert(current);
      } else if (llm == null) {
        debugPrint('[Pipeline] Step 4: 跳过 LLM（未配置）');
      } else {
        debugPrint('[Pipeline] Step 4: 跳过 LLM（转写文本为空）');
      }

      await setStatus(RecordingStatus.done);
      onProgress?.call('全部完成');
      debugPrint('[Pipeline] 全部完成');
    } catch (e) {
      if (e is StateError && e.message == 'cancelled') return;
      await setStatus(RecordingStatus.failed, err: e.toString()).catchError((_) {});
      rethrow;
    }
  }
}
