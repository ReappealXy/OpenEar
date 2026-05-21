import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// 阿里云 OSS 极简上传客户端（PUT Object + 预签名 URL）
///
/// 不依赖官方 SDK，纯 HTTP 实现，避免引入巨大依赖。
/// 文档：https://help.aliyun.com/zh/oss/developer-reference/put-object
class AliyunOssService {
  final String accessKeyId;
  final String accessKeySecret;
  final String region; // 例如 oss-cn-shanghai
  final String bucket;

  final Dio _dio = Dio();

  AliyunOssService({
    required this.accessKeyId,
    required this.accessKeySecret,
    required this.region,
    required this.bucket,
  });

  String get endpoint => 'https://$bucket.$region.aliyuncs.com';

  /// 上传文件并返回该对象的预签名 GET URL（默认 24 小时有效）。
  Future<String> uploadFile({
    required File file,
    required String key,
    String contentType = 'audio/mp4',
    Duration urlValidFor = const Duration(hours: 24),
    void Function(int sent, int total)? onProgress,
  }) async {
    if (key.startsWith('/')) key = key.substring(1);
    final url = '$endpoint/$key';
    final date = _gmtDate();
    final stringToSign = [
      'PUT',
      '', // Content-MD5
      contentType,
      date,
      '/$bucket/$key',
    ].join('\n');
    final signature = _hmacSha1Base64(accessKeySecret, stringToSign);

    final length = await file.length();
    final stream = file.openRead();

    final res = await _dio.put(
      url,
      data: stream,
      onSendProgress: onProgress,
      options: Options(
        headers: {
          HttpHeaders.contentTypeHeader: contentType,
          HttpHeaders.contentLengthHeader: length,
          'Date': date,
          HttpHeaders.authorizationHeader:
              'OSS $accessKeyId:$signature',
        },
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (res.statusCode != 200) {
      throw Exception('OSS 上传失败 ${res.statusCode}: ${res.data}');
    }
    return presignGetUrl(key: key, validFor: urlValidFor);
  }

  /// 生成预签名 GET URL（供阿里云 ASR 拉取音频）。
  String presignGetUrl({
    required String key,
    Duration validFor = const Duration(hours: 24),
  }) {
    if (key.startsWith('/')) key = key.substring(1);
    final expires =
        (DateTime.now().millisecondsSinceEpoch ~/ 1000) + validFor.inSeconds;
    final stringToSign = [
      'GET',
      '', // Content-MD5
      '', // Content-Type
      expires.toString(),
      '/$bucket/$key',
    ].join('\n');
    final signature = _hmacSha1Base64(accessKeySecret, stringToSign);
    final params = {
      'OSSAccessKeyId': accessKeyId,
      'Expires': expires.toString(),
      'Signature': signature,
    };
    final qs = params.entries
        .map((e) => '${Uri.encodeQueryComponent(e.key)}='
            '${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$endpoint/$key?$qs';
  }

  /// 删除对象（清理上传过的文件）。
  Future<void> deleteObject(String key) async {
    if (key.startsWith('/')) key = key.substring(1);
    final url = '$endpoint/$key';
    final date = _gmtDate();
    final stringToSign = [
      'DELETE',
      '',
      '',
      date,
      '/$bucket/$key',
    ].join('\n');
    final signature = _hmacSha1Base64(accessKeySecret, stringToSign);
    await _dio.delete(
      url,
      options: Options(
        headers: {
          'Date': date,
          HttpHeaders.authorizationHeader:
              'OSS $accessKeyId:$signature',
        },
        validateStatus: (s) => s != null && s < 500,
      ),
    );
  }

  static String _gmtDate() {
    // RFC 1123 GMT 时间
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final n = DateTime.now().toUtc();
    final wd = days[n.weekday - 1];
    final m = months[n.month - 1];
    final dd = n.day.toString().padLeft(2, '0');
    final hh = n.hour.toString().padLeft(2, '0');
    final mm = n.minute.toString().padLeft(2, '0');
    final ss = n.second.toString().padLeft(2, '0');
    return '$wd, $dd $m ${n.year} $hh:$mm:$ss GMT';
  }

  static String _hmacSha1Base64(String key, String data) {
    final hmac = Hmac(sha1, utf8.encode(key));
    final digest = hmac.convert(utf8.encode(data));
    return base64Encode(digest.bytes);
  }
}
