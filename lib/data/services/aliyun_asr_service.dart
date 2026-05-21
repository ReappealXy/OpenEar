import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/recording.dart';
import 'aliyun_signer.dart';

/// 阿里云"录音文件识别"客户端
///
/// 1. 通过 NLS Meta CreateToken 拿到 Token（24h 缓存）
/// 2. 调用 filetrans SubmitTask 提交任务（传 OSS 预签名 URL）
/// 3. 轮询 GetTaskResult 直到完成
/// 4. 解析返回的 Sentences（包含说话人 ID、起止时间、文本）
///
/// 文档：
/// - Token: https://help.aliyun.com/zh/isi/getting-started/use-http-or-https-to-obtain-an-access-token
/// - 录音文件识别: https://help.aliyun.com/zh/isi/developer-reference/restful-api-7
class AliyunAsrService {
  final String accessKeyId;
  final String accessKeySecret;
  final String appKey;
  final bool enableSpeakerDiarization;
  final int speakerCount; // 0 = 自动

  static const _tokenEndpoint = 'https://nls-meta.cn-shanghai.aliyuncs.com/';
  static const _fileTransEndpoint =
      'https://filetrans.cn-shanghai.aliyuncs.com/';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.json,
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  String? _cachedToken;
  DateTime? _tokenExpiresAt;

  AliyunAsrService({
    required this.accessKeyId,
    required this.accessKeySecret,
    required this.appKey,
    this.enableSpeakerDiarization = true,
    this.speakerCount = 0,
  });

  // ---------------- Token ----------------

  Future<String> _getToken() async {
    if (_cachedToken != null &&
        _tokenExpiresAt != null &&
        DateTime.now().isBefore(_tokenExpiresAt!.subtract(const Duration(minutes: 5)))) {
      return _cachedToken!;
    }
    final query = AliyunRpcSigner.signedQuery(
      accessKeyId: accessKeyId,
      accessKeySecret: accessKeySecret,
      httpMethod: 'GET',
      params: const {
        'Action': 'CreateToken',
        'Version': '2019-02-28',
        'RegionId': 'cn-shanghai',
      },
    );
    final res = await _dio.get<dynamic>(
      _tokenEndpoint,
      queryParameters: query,
    );
    final data = _parseJson(res.data);
    final token = data['Token'];
    if (token == null) {
      throw Exception('CreateToken 失败：${res.data}');
    }
    final id = token['Id'] as String;
    final expireSec = (token['ExpireTime'] as num).toInt();
    _cachedToken = id;
    _tokenExpiresAt = DateTime.fromMillisecondsSinceEpoch(expireSec * 1000);
    return id;
  }

  // ---------------- SubmitTask ----------------

  /// 提交识别任务，返回 TaskId。
  Future<String> submitTask({required String fileLink}) async {
    final token = await _getToken();
    final taskParams = <String, dynamic>{
      'appkey': appKey,
      'token': token,
      'file_link': fileLink,
      'version': '4.0',
      'enable_words': false,
      if (enableSpeakerDiarization) ...{
        'enable_speaker_diarization': true,
        if (speakerCount > 0) 'speaker_count': speakerCount,
      },
    };

    final query = AliyunRpcSigner.signedQuery(
      accessKeyId: accessKeyId,
      accessKeySecret: accessKeySecret,
      httpMethod: 'POST',
      params: {
        'Action': 'SubmitTask',
        'Version': '2018-08-17',
        'RegionId': 'cn-shanghai',
        'Task': jsonEncode(taskParams),
      },
    );
    final res = await _dio.post<dynamic>(
      _fileTransEndpoint,
      queryParameters: query,
    );
    final data = _parseJson(res.data);
    final statusText = data['StatusText'];
    final statusCode = data['StatusCode']?.toString();
    if (statusText != 'SUCCESS' && statusCode != '21050000') {
      throw Exception('SubmitTask 失败：${data['StatusText']} / ${data['StatusCode']}');
    }
    return data['TaskId'] as String;
  }

  // ---------------- 轮询结果 ----------------

  /// 轮询直至完成；返回解析后的句子列表与逐字稿。
  /// [onProgress] 用于汇报状态文本（如 RUNNING / QUEUEING）。
  Future<({List<TranscriptSentence> sentences, String plain})> waitForResult({
    required String taskId,
    Duration interval = const Duration(seconds: 8),
    Duration timeout = const Duration(minutes: 30),
    void Function(String status)? onProgress,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final query = AliyunRpcSigner.signedQuery(
        accessKeyId: accessKeyId,
        accessKeySecret: accessKeySecret,
        httpMethod: 'GET',
        params: {
          'Action': 'GetTaskResult',
          'Version': '2018-08-17',
          'RegionId': 'cn-shanghai',
          'TaskId': taskId,
        },
      );
      final res = await _dio.get<dynamic>(
        _fileTransEndpoint,
        queryParameters: query,
      );
      final data = _parseJson(res.data);
      final statusText = (data['StatusText'] as String?) ?? '';
      onProgress?.call(statusText);

      // 21050000 SUCCEEDED / 21050001 RUNNING / 21050002 QUEUEING ...
      if (statusText == 'SUCCESS' || statusText == 'SUCCEEDED') {
        return _parseResult(data['Result']);
      }
      if (statusText.contains('FAILED') ||
          statusText.contains('ERROR') ||
          statusText == 'TRANSCRIPTION_ERROR') {
        throw Exception('转写失败：${data['StatusText']}');
      }
      await Future<void>.delayed(interval);
    }
    throw TimeoutException('转写超时');
  }

  ({List<TranscriptSentence> sentences, String plain}) _parseResult(
    dynamic result,
  ) {
    if (result == null) {
      return (sentences: const [], plain: '');
    }
    final map = result is Map ? result : <String, dynamic>{};
    final sentencesJson = map['Sentences'] as List? ?? const [];
    final sentences = <TranscriptSentence>[];
    final buffer = StringBuffer();
    int? lastSpeaker;
    for (final raw in sentencesJson) {
      final s = raw as Map<String, dynamic>;
      int spk = 0;
      final v = s['SpeakerId'];
      if (v is num) {
        spk = v.toInt();
      } else if (v is String) {
        spk = int.tryParse(v) ?? 0;
      }
      final sentence = TranscriptSentence(
        beginTime: (s['BeginTime'] as num?)?.toInt() ?? 0,
        endTime: (s['EndTime'] as num?)?.toInt() ?? 0,
        text: (s['Text'] as String?) ?? '',
        speakerId: spk,
      );
      sentences.add(sentence);
      if (enableSpeakerDiarization && spk != lastSpeaker) {
        if (buffer.isNotEmpty) buffer.writeln();
        buffer.write('【发言人 $spk】');
        lastSpeaker = spk;
      }
      buffer.write(sentence.text);
    }
    return (sentences: sentences, plain: buffer.toString().trim());
  }

  // ---------------- 辅助 ----------------

  Map<String, dynamic> _parseJson(dynamic raw) {
    if (raw is Map) return raw.cast<String, dynamic>();
    if (raw is String) return jsonDecode(raw) as Map<String, dynamic>;
    throw Exception('阿里云返回格式异常：$raw');
  }
}
