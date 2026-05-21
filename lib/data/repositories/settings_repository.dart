import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/app_settings.dart';

class SettingsRepository {
  static const _key = 'openear_settings_v2';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<AppSettings> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return const AppSettings();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return AppSettings(
        secretId: j['secretId'] as String? ?? '',
        secretKey: j['secretKey'] as String? ?? '',
        cosRegion: j['cosRegion'] as String? ?? 'ap-chengdu',
        cosBucket: j['cosBucket'] as String? ?? '',
        cosPrefix: j['cosPrefix'] as String? ?? 'openear/',
        appId: (j['appId'] as num?)?.toInt() ?? 0,
        llmBaseUrl: j['llmBaseUrl'] as String? ?? 'https://api.deepseek.com/v1',
        llmApiKey: j['llmApiKey'] as String? ?? '',
        llmModel: j['llmModel'] as String? ?? 'deepseek-chat',
        llmTemperature: (j['llmTemperature'] as num?)?.toDouble() ?? 0.3,
        enableSpeakerDiarization: j['enableSpeaker'] as bool? ?? true,
        speakerCount: (j['speakerCount'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings s) async {
    final j = <String, dynamic>{
      'secretId': s.secretId,
      'secretKey': s.secretKey,
      'cosRegion': s.cosRegion,
      'cosBucket': s.cosBucket,
      'cosPrefix': s.cosPrefix,
      'appId': s.appId,
      'llmBaseUrl': s.llmBaseUrl,
      'llmApiKey': s.llmApiKey,
      'llmModel': s.llmModel,
      'llmTemperature': s.llmTemperature,
      'enableSpeaker': s.enableSpeakerDiarization,
      'speakerCount': s.speakerCount,
    };
    await _storage.write(key: _key, value: jsonEncode(j));
  }

  Future<void> clear() => _storage.delete(key: _key);
}
