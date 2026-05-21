import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// 腾讯云 COS 对象存储上传客户端（PUT Object + 预签名 GET URL）
///
/// 签名规范：https://cloud.tencent.com/document/product/436/7778
class CosService {
  final String secretId;
  final String secretKey;
  final String region; // 例：ap-chengdu
  final String bucket; // 例：openear-1324711438

  final Dio _dio = Dio();

  CosService({
    required this.secretId,
    required this.secretKey,
    required this.region,
    required this.bucket,
  });

  String get _host => '$bucket.cos.$region.myqcloud.com';
  String get endpoint => 'https://$_host';

  /// 上传文件，返回预签名 GET URL（默认 24 小时有效）
  Future<String> uploadFile({
    required File file,
    required String key,
    String contentType = 'audio/mp4',
    Duration urlValidFor = const Duration(hours: 24),
    void Function(int sent, int total)? onProgress,
  }) async {
    if (key.startsWith('/')) key = key.substring(1);
    final url = '$endpoint/$key';

    final auth = _buildAuthHeader(httpMethod: 'put', key: key);
    final length = await file.length();
    final bytes = await file.readAsBytes();

    final res = await _dio.put<String>(
      url,
      data: bytes,
      onSendProgress: onProgress,
      options: Options(
        contentType: contentType,
        headers: {
          HttpHeaders.contentLengthHeader: length,
          'Authorization': auth,
        },
        responseType: ResponseType.plain,
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    if (res.statusCode != 200) {
      throw Exception('COS 上传失败 ${res.statusCode}: ${res.data}');
    }
    return presignGetUrl(key: key, validFor: urlValidFor);
  }

  /// 生成预签名 GET URL（用于 ASR 读取音频）
  String presignGetUrl({
    required String key,
    Duration validFor = const Duration(hours: 24),
  }) {
    if (key.startsWith('/')) key = key.substring(1);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expire = now + validFor.inSeconds;
    final keyTime = '$now;$expire';
    final signKey = _hmacSha1Hex(secretKey, keyTime);

    // GET 请求不带 body，不签任何 header
    final httpString = 'get\n/$key\n\n\n';
    final stringToSign =
        'sha1\n$keyTime\n${sha1.convert(utf8.encode(httpString)).toString()}\n';
    final signature = _hmacSha1Hex(signKey, stringToSign);

    final params = {
      'q-sign-algorithm': 'sha1',
      'q-ak': secretId,
      'q-sign-time': keyTime,
      'q-key-time': keyTime,
      'q-header-list': '',
      'q-url-param-list': '',
      'q-signature': signature,
    };
    final qs = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '$endpoint/$key?$qs';
  }

  /// 删除对象
  Future<void> deleteObject(String key) async {
    if (key.startsWith('/')) key = key.substring(1);
    final url = '$endpoint/$key';
    final auth = _buildAuthHeader(httpMethod: 'delete', key: key);
    await _dio.delete(
      url,
      options: Options(
        headers: {'Authorization': auth},
        validateStatus: (s) => s != null && s < 500,
      ),
    );
  }

  /// 构造 COS Authorization header，只签 host（最稳健）
  String _buildAuthHeader({
    required String httpMethod,
    required String key,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final expire = now + 3600;
    final keyTime = '$now;$expire';
    final signKey = _hmacSha1Hex(secretKey, keyTime);

    final method = httpMethod.toLowerCase();

    // 只签 host，避免 content-type / date 被 Dio 或网络层修改
    final headers = <String, String>{'host': _host};
    final headerKeys = headers.keys.toList()..sort();
    final headerStr =
        headerKeys.map((k) => '$k=${_uriEncode(headers[k]!)}').join('&');
    final headerList = headerKeys.join(';');

    // URI path：按 RFC 3986 对非保留字符外的字符编码，/ 不编码
    final uriPath = '/${_encodeKey(key)}';

    final httpString = '$method\n$uriPath\n\n$headerStr\n';
    final stringToSign =
        'sha1\n$keyTime\n${sha1.convert(utf8.encode(httpString)).toString()}\n';
    final signature = _hmacSha1Hex(signKey, stringToSign);

    return 'q-sign-algorithm=sha1'
        '&q-ak=$secretId'
        '&q-sign-time=$keyTime'
        '&q-key-time=$keyTime'
        '&q-header-list=$headerList'
        '&q-url-param-list='
        '&q-signature=$signature';
  }

  /// RFC 3986 编码，保留 /（用于对象 key 路径）
  static String _encodeKey(String key) {
    return key.split('/').map((seg) => _uriEncode(seg)).join('/');
  }

  /// RFC 3986 percent-encode（与 Uri.encodeComponent 基本一致）
  static String _uriEncode(String s) => Uri.encodeComponent(s);

  static String _hmacSha1Hex(String key, String data) {
    final hmac = Hmac(sha1, utf8.encode(key));
    return hmac.convert(utf8.encode(data)).toString();
  }
}
