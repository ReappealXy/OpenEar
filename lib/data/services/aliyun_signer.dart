import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// 阿里云 RPC 风格签名工具（v1.0 HMAC-SHA1）
///
/// 适用于 NLS Token / 录音文件识别 等使用 RPC 风格的服务。
/// 文档：https://help.aliyun.com/zh/sdk/product-overview/v3-request-structure-and-signature
class AliyunRpcSigner {
  /// 在 [params] 基础上补全公共参数，计算签名，返回最终的 query parameters。
  static Map<String, String> signedQuery({
    required String accessKeyId,
    required String accessKeySecret,
    required String httpMethod, // GET / POST
    required Map<String, String> params,
  }) {
    final all = <String, String>{
      ...params,
      'AccessKeyId': accessKeyId,
      'SignatureMethod': 'HMAC-SHA1',
      'SignatureVersion': '1.0',
      'SignatureNonce': _nonce(),
      'Timestamp': _isoTimestamp(),
      if (!params.containsKey('Format')) 'Format': 'JSON',
    };
    final sorted = all.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final canonicalQs = sorted
        .map((e) =>
            '${_percentEncode(e.key)}=${_percentEncode(e.value)}')
        .join('&');
    final stringToSign =
        '$httpMethod&${_percentEncode('/')}&${_percentEncode(canonicalQs)}';
    final hmac = Hmac(sha1, utf8.encode('$accessKeySecret&'));
    final signature = base64Encode(hmac.convert(utf8.encode(stringToSign)).bytes);
    return {...all, 'Signature': signature};
  }

  static String _nonce() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String _isoTimestamp() {
    final now = DateTime.now().toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}T'
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}Z';
  }

  /// 阿里云的 percent-encode：与 RFC 3986 一致；
  /// Dart 的 [Uri.encodeComponent] 已基本符合，但要把 '+' 替换成 '%20'、'*' 替换成 '%2A'、
  /// '%7E' 还原成 '~'。
  static String _percentEncode(String s) {
    return Uri.encodeComponent(s)
        .replaceAll('+', '%20')
        .replaceAll('*', '%2A')
        .replaceAll('%7E', '~');
  }
}
