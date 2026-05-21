import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// 录音服务：封装 `record` 包，统一输出 mp3/m4a 文件以便阿里云 ASR 识别。
///
/// 阿里云录音文件识别支持 wav / mp3 / m4a / aac 等格式，我们用 AAC-LC（m4a 容器），
/// 它的体积小、识别效果好、在 Android 上原生硬件编码器支持广泛。
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  StreamSubscription<Amplitude>? _ampSub;
  final StreamController<Amplitude> _ampController =
      StreamController<Amplitude>.broadcast();
  Stream<Amplitude> get amplitudeStream => _ampController.stream;

  DateTime? _startedAt;
  Duration _elapsedBeforePause = Duration.zero;

  /// 当前录制累计时长（仅适用 isRecording 状态时正确，pause 时返回累计）。
  Duration get elapsed {
    if (_startedAt == null) return _elapsedBeforePause;
    return _elapsedBeforePause + DateTime.now().difference(_startedAt!);
  }

  Future<bool> ensurePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<bool> isRecording() => _recorder.isRecording();
  Future<bool> isPaused() => _recorder.isPaused();

  /// 开始录音；返回输出文件路径。
  Future<String> start() async {
    if (!await ensurePermission()) {
      throw StateError('未授予麦克风权限');
    }
    final dir = await getApplicationDocumentsDirectory();
    final audioDir = Directory(p.join(dir.path, 'recordings'));
    if (!await audioDir.exists()) await audioDir.create(recursive: true);

    final fileName =
        'rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final filePath = p.join(audioDir.path, fileName);

    const config = RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 96000,
      sampleRate: 16000, // ASR 16k 采样率是最优配置
      numChannels: 1,
    );

    await _recorder.start(config, path: filePath);
    _startedAt = DateTime.now();
    _elapsedBeforePause = Duration.zero;

    _ampSub?.cancel();
    _ampSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen(_ampController.add);

    return filePath;
  }

  Future<void> pause() async {
    if (await _recorder.isRecording() && _startedAt != null) {
      _elapsedBeforePause += DateTime.now().difference(_startedAt!);
      _startedAt = null;
      await _recorder.pause();
    }
  }

  Future<void> resume() async {
    if (await _recorder.isPaused()) {
      _startedAt = DateTime.now();
      await _recorder.resume();
    }
  }

  /// 停止并返回最终文件路径与时长。
  Future<({String path, Duration duration, int size})?> stop() async {
    final path = await _recorder.stop();
    _ampSub?.cancel();
    _ampSub = null;
    if (path == null) return null;

    final dur = elapsed;
    _startedAt = null;
    _elapsedBeforePause = Duration.zero;

    final file = File(path);
    final size = await file.exists() ? await file.length() : 0;
    return (path: path, duration: dur, size: size);
  }

  Future<void> cancel() async {
    await _recorder.cancel();
    _ampSub?.cancel();
    _ampSub = null;
    _startedAt = null;
    _elapsedBeforePause = Duration.zero;
  }

  Future<void> dispose() async {
    await _ampSub?.cancel();
    await _ampController.close();
    await _recorder.dispose();
  }
}
