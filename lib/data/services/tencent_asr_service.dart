import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import '../models/recording.dart';

/// 腾讯云"录音文件识别"客户端
///
/// 1. CreateRecTask  提交任务（传 COS 预签名 URL）
/// 2. DescribeTaskStatus 轮询直到完成
/// 3. 解析 SentenceList（含说话人 ID、起止时间、文本）
///
/// 文档：https://cloud.tencent.com/document/product/1093/37823
class TencentAsrService {
  final String secretId;
  final String secretKey;
  final int appId;
  final bool enableSpeakerDiarization;
  final int speakerCount; // 0 = 自动

  static const _host = 'asr.tencentcloudapi.com';
  static const _service = 'asr';
  static const _version = '2019-06-14';
  static const _region = 'ap-guangzhou'; // ASR 服务不分地域，用广州即可

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://$_host',
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      responseType: ResponseType.json,
      validateStatus: (s) => s != null && s < 500,
    ),
  );

  TencentAsrService({
    required this.secretId,
    required this.secretKey,
    required this.appId,
    this.enableSpeakerDiarization = true,
    this.speakerCount = 0,
  });

  // ------------------- 提交任务 -------------------

  Future<int> submitTask({required String fileUrl}) async {
    final body = <String, dynamic>{
      'EngineModelType': '16k_zh',
      'ChannelNum': 1,
      'ResTextFormat': 3, // JSON 格式，含句子级时间戳和说话人 ID
      'SourceType': 0,
      'Url': fileUrl,
      'ConvertNumMode': 1,
      if (enableSpeakerDiarization) ...{
        'SpeakerDiarization': 1,
        'SpeakerNumber': speakerCount,
      },
    };
    final res = await _request(action: 'CreateRecTask', body: body);
    final data = res['Data'] as Map<String, dynamic>?;
    if (data == null) throw Exception('CreateRecTask 返回为空: $res');
    return (data['TaskId'] as num).toInt();
  }

  // ------------------- 轮询结果 -------------------

  Future<({List<TranscriptSentence> sentences, String plain})> waitForResult({
    required int taskId,
    Duration interval = const Duration(seconds: 8),
    Duration timeout = const Duration(minutes: 30),
    void Function(String status)? onProgress,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final res = await _request(
        action: 'DescribeTaskStatus',
        body: {'TaskId': taskId},
      );
      final data = res['Data'] as Map<String, dynamic>?;
      if (data == null) throw Exception('DescribeTaskStatus 返回为空: $res');

      final status = (data['Status'] as num).toInt();
      final statusStr = _statusLabel(status);
      // 打印原始返回，方便排查
      debugPrint('[ASR Poll] taskId=$taskId status=$status($statusStr) '
          'ErrorMsg=${data['ErrorMsg']} ResultLen=${(data['Result'] as String? ?? '').length}');
      onProgress?.call(statusStr);

      // 腾讯云 DescribeTaskStatus: 0=等待 1=执行中 2=成功 3=失败
      if (status == 2) {
        return _parseResult(data['Result'] as String? ?? '');
      }
      if (status == 3) {
        throw Exception('腾讯云 ASR 失败：${data['ErrorMsg'] ?? '未知错误'}');
      }
      await Future<void>.delayed(interval);
    }
    throw TimeoutException('转写超时');
  }

  ({List<TranscriptSentence> sentences, String plain}) _parseResult(
      String resultJson) {
    if (resultJson.trim().isEmpty) {
      return (sentences: const [], plain: '');
    }
    debugPrint('[ASR Parse] 前100字符: ${resultJson.substring(0, resultJson.length.clamp(0, 100))}');
    // 如果不是 JSON（以 { 或 [ 开头），直接当纯文本处理
    final trimmed = resultJson.trim();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      // 纯文本格式：去除时间戳 [x:x.xxx,x:x.xxx,x] 前缀
      final plain = trimmed
          .replaceAll(RegExp(r'\[\d+:\d+\.\d+,\d+:\d+\.\d+,\d+\]\s*'), '')
          .trim();
      return (sentences: const [], plain: plain);
    }
    final map = jsonDecode(resultJson) as Map<String, dynamic>;
    final sentenceList = map['sentence_list'] as List? ?? const [];
    final sentences = <TranscriptSentence>[];
    final buffer = StringBuffer();
    int? lastSpeaker;

    for (final raw in sentenceList) {
      final s = raw as Map<String, dynamic>;
      final spk = (s['speaker_id'] as num?)?.toInt() ?? 0;
      final sentence = TranscriptSentence(
        beginTime: (s['start_ms'] as num?)?.toInt() ?? 0,
        endTime: (s['end_ms'] as num?)?.toInt() ?? 0,
        text: (s['final_sentence'] as String?) ?? '',
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

  // ------------------- TC3-HMAC-SHA256 签名 -------------------

  Future<Map<String, dynamic>> _request({
    required String action,
    required Map<String, dynamic> body,
  }) async {
    final payload = jsonEncode(body);
    final now = DateTime.now().toUtc();
    final timestamp = (now.millisecondsSinceEpoch ~/ 1000).toString();
    final date =
        '${now.year}-${now.month.toString().padLeft(2,'0')}-${now.day.toString().padLeft(2,'0')}';

    // Step 1: CanonicalRequest
    final hashedPayload = _sha256Hex(payload);
    const canonicalHeaders =
        'content-type:application/json; charset=utf-8\nhost:$_host\n';
    const signedHeaders = 'content-type;host';
    final canonicalRequest =
        'POST\n/\n\n$canonicalHeaders\n$signedHeaders\n$hashedPayload';

    // Step 2: StringToSign
    final credentialScope = '$date/$_service/tc3_request';
    final hashedCanonical = _sha256Hex(canonicalRequest);
    final stringToSign =
        'TC3-HMAC-SHA256\n$timestamp\n$credentialScope\n$hashedCanonical';

    // Step 3: DerivedSigningKey
    final secretDate = _hmacSha256Bytes('TC3$secretKey', date);
    final secretService = _hmacSha256Bytes(secretDate, _service);
    final secretSigning = _hmacSha256Bytes(secretService, 'tc3_request');
    final signature = _hmacSha256Hex(secretSigning, stringToSign);

    // Step 4: Authorization
    final authorization =
        'TC3-HMAC-SHA256 Credential=$secretId/$credentialScope, '
        'SignedHeaders=$signedHeaders, Signature=$signature';

    final res = await _dio.post<dynamic>(
      '/',
      data: payload,
      options: Options(
        headers: {
          'Authorization': authorization,
          'Content-Type': 'application/json; charset=utf-8',
          'Host': _host,
          'X-TC-Action': action,
          'X-TC-Version': _version,
          'X-TC-Timestamp': timestamp,
          'X-TC-Region': _region,
        },
      ),
    );
    final resp = res.data is String
        ? jsonDecode(res.data as String) as Map<String, dynamic>
        : (res.data as Map).cast<String, dynamic>();
    final response = resp['Response'] as Map<String, dynamic>?;
    if (response == null) throw Exception('腾讯云返回格式异常: $resp');
    if (response.containsKey('Error')) {
      final err = response['Error'] as Map;
      throw Exception(
          '腾讯云 ASR 错误 ${err['Code']}: ${err['Message']}');
    }
    return response;
  }

  static String _statusLabel(int s) => switch (s) {
        0 => '等待中',
        1 => '转写中',
        2 => '已完成',
        3 => '失败',
        _ => '未知($s)',
      };

  static String _sha256Hex(String data) =>
      sha256.convert(utf8.encode(data)).toString();

  static String _hmacSha256Hex(List<int> key, String data) =>
      Hmac(sha256, key).convert(utf8.encode(data)).toString();

  static List<int> _hmacSha256Bytes(dynamic key, String data) {
    final k = key is String ? utf8.encode(key) : key as List<int>;
    return Hmac(sha256, k).convert(utf8.encode(data)).bytes;
  }
}
