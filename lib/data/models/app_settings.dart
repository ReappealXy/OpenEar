/// 应用设置：腾讯云 + LLM 配置
class AppSettings {
  // 腾讯云访问凭证
  final String secretId;
  final String secretKey;

  // COS（对象存储，用于上传录音供 ASR 拉取）
  final String cosRegion; // e.g. ap-chengdu
  final String cosBucket; // e.g. openear-1324711438
  final String cosPrefix; // 默认 openear/

  // 腾讯云 ASR
  final int appId; // 腾讯云 AppID（数字）

  // LLM（OpenAI 兼容）
  final String llmBaseUrl;
  final String llmApiKey;
  final String llmModel;
  final double llmTemperature;

  // 说话人分离
  final bool enableSpeakerDiarization;
  final int speakerCount; // 0 = 自动

  const AppSettings({
    this.secretId = '',
    this.secretKey = '',
    this.cosRegion = 'ap-chengdu',
    this.cosBucket = '',
    this.cosPrefix = 'openear/',
    this.appId = 0,
    this.llmBaseUrl = 'https://api.deepseek.com/v1',
    this.llmApiKey = '',
    this.llmModel = 'deepseek-chat',
    this.llmTemperature = 0.3,
    this.enableSpeakerDiarization = true,
    this.speakerCount = 0,
  });

  bool get cloudReady =>
      secretId.isNotEmpty &&
      secretKey.isNotEmpty &&
      cosBucket.isNotEmpty &&
      appId > 0;

  bool get llmReady =>
      llmBaseUrl.isNotEmpty && llmApiKey.isNotEmpty && llmModel.isNotEmpty;

  AppSettings copyWith({
    String? secretId,
    String? secretKey,
    String? cosRegion,
    String? cosBucket,
    String? cosPrefix,
    int? appId,
    String? llmBaseUrl,
    String? llmApiKey,
    String? llmModel,
    double? llmTemperature,
    bool? enableSpeakerDiarization,
    int? speakerCount,
  }) =>
      AppSettings(
        secretId: secretId ?? this.secretId,
        secretKey: secretKey ?? this.secretKey,
        cosRegion: cosRegion ?? this.cosRegion,
        cosBucket: cosBucket ?? this.cosBucket,
        cosPrefix: cosPrefix ?? this.cosPrefix,
        appId: appId ?? this.appId,
        llmBaseUrl: llmBaseUrl ?? this.llmBaseUrl,
        llmApiKey: llmApiKey ?? this.llmApiKey,
        llmModel: llmModel ?? this.llmModel,
        llmTemperature: llmTemperature ?? this.llmTemperature,
        enableSpeakerDiarization:
            enableSpeakerDiarization ?? this.enableSpeakerDiarization,
        speakerCount: speakerCount ?? this.speakerCount,
      );
}
