import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/app_settings.dart';
import '../../providers.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _secretId;
  late TextEditingController _secretKey;
  late TextEditingController _cosRegion;
  late TextEditingController _cosBucket;
  late TextEditingController _cosPrefix;
  late TextEditingController _appId;
  late TextEditingController _llmBaseUrl;
  late TextEditingController _llmApiKey;
  late TextEditingController _llmModel;
  late TextEditingController _llmTemp;

  bool _enableSpeaker = true;
  int _speakerCount = 0;
  bool _initialized = false;

  // 密码可见性
  final Map<String, bool> _obscureState = {};

  void _ensureInit(AppSettings s) {
    if (_initialized) return;
    _initialized = true;
    _secretId = TextEditingController(text: s.secretId);
    _secretKey = TextEditingController(text: s.secretKey);
    _cosRegion = TextEditingController(text: s.cosRegion);
    _cosBucket = TextEditingController(text: s.cosBucket);
    _cosPrefix = TextEditingController(text: s.cosPrefix);
    _appId = TextEditingController(
        text: s.appId > 0 ? s.appId.toString() : '');
    _llmBaseUrl = TextEditingController(text: s.llmBaseUrl);
    _llmApiKey = TextEditingController(text: s.llmApiKey);
    _llmModel = TextEditingController(text: s.llmModel);
    _llmTemp = TextEditingController(text: s.llmTemperature.toString());
    _enableSpeaker = s.enableSpeakerDiarization;
    _speakerCount = s.speakerCount;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final next = AppSettings(
      secretId: _secretId.text.trim(),
      secretKey: _secretKey.text.trim(),
      cosRegion: _cosRegion.text.trim(),
      cosBucket: _cosBucket.text.trim(),
      cosPrefix: _cosPrefix.text.trim().isEmpty ? 'openear/' : _cosPrefix.text.trim(),
      appId: int.tryParse(_appId.text.trim()) ?? 0,
      llmBaseUrl: _llmBaseUrl.text.trim(),
      llmApiKey: _llmApiKey.text.trim(),
      llmModel: _llmModel.text.trim(),
      llmTemperature: double.tryParse(_llmTemp.text.trim()) ?? 0.3,
      enableSpeakerDiarization: _enableSpeaker,
      speakerCount: _speakerCount,
    );
    await ref.read(settingsProvider.notifier).save(next);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('已保存')));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (s) {
          _ensureInit(s);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              children: [
                _SectionHeader(
                  title: '腾讯云',
                  subtitle:
                      '用于把录音上传到 COS 并通过"录音文件识别"获取转写。\n'
                      '需要：SecretId / SecretKey + COS Bucket + AppID。',
                ),
                _field(label: 'SecretId', ctrl: _secretId, required: true),
                _field(
                    label: 'SecretKey',
                    ctrl: _secretKey,
                    obscure: true,
                    required: true),
                _field(
                    label: 'COS Region',
                    ctrl: _cosRegion,
                    helper: '例：ap-chengdu / ap-shanghai / ap-beijing',
                    required: true),
                _field(
                    label: 'COS Bucket',
                    ctrl: _cosBucket,
                    helper: '例：openear-1324711438',
                    required: true),
                _field(
                    label: 'COS 对象前缀',
                    ctrl: _cosPrefix,
                    helper: '上传的录音放在该前缀下，默认 openear/'),
                _field(
                    label: 'AppID',
                    ctrl: _appId,
                    helper: '腾讯云控制台右上角账号信息里的 AppID（纯数字）',
                    required: true,
                    keyboardType: TextInputType.number),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用说话人分离'),
                  subtitle: const Text('识别多个发言人并标注 A/B/C…'),
                  value: _enableSpeaker,
                  onChanged: (v) => setState(() => _enableSpeaker = v),
                ),
                if (_enableSpeaker)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const Text('说话人数：'),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _speakerCount,
                            items: const [
                              DropdownMenuItem(value: 0, child: Text('自动')),
                              DropdownMenuItem(value: 2, child: Text('2')),
                              DropdownMenuItem(value: 3, child: Text('3')),
                              DropdownMenuItem(value: 4, child: Text('4')),
                              DropdownMenuItem(value: 5, child: Text('5')),
                              DropdownMenuItem(value: 6, child: Text('6')),
                            ],
                            onChanged: (v) =>
                                setState(() => _speakerCount = v ?? 0),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                _SectionHeader(
                  title: '大模型 (LLM)',
                  subtitle:
                      'OpenAI Chat Completions 兼容协议；'
                      'DeepSeek / 通义 / 智谱 / Kimi / SiliconFlow 皆可。',
                ),
                _PresetChips(onPick: (p) => setState(() {
                      _llmBaseUrl.text = p.baseUrl;
                      _llmModel.text = p.model;
                    })),
                const SizedBox(height: 12),
                _field(
                    label: 'Base URL',
                    ctrl: _llmBaseUrl,
                    helper: '例：https://api.deepseek.com/v1',
                    required: true),
                _field(
                    label: 'API Key',
                    ctrl: _llmApiKey,
                    obscure: true,
                    required: true),
                _field(
                    label: '模型',
                    ctrl: _llmModel,
                    helper: '例：deepseek-chat / qwen-max / glm-4-flash',
                    required: true),
                _field(
                    label: 'Temperature',
                    ctrl: _llmTemp,
                    helper: '0.0 - 1.0，越低越稳定，推荐 0.3',
                    keyboardType: TextInputType.number),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController ctrl,
    String? helper,
    bool obscure = false,
    bool required = false,
    TextInputType? keyboardType,
  }) {
    // 第一次渲染时初始化可见性状态
    _obscureState.putIfAbsent(label, () => obscure);
    final isObscured = _obscureState[label]!;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextFormField(
        controller: ctrl,
        obscureText: isObscured,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          helperText: helper,
          border: const OutlineInputBorder(),
          suffixIcon: obscure
              ? IconButton(
                  icon: Icon(
                    isObscured ? Icons.visibility_off : Icons.visibility,
                  ),
                  tooltip: isObscured ? '显示' : '隐藏',
                  onPressed: () => setState(
                    () => _obscureState[label] = !isObscured,
                  ),
                )
              : null,
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? '请填写 $label' : null
            : null,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: scheme.primary)),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                    height: 1.5)),
          ],
        ],
      ),
    );
  }
}

class _LlmPreset {
  final String label;
  final String baseUrl;
  final String model;
  const _LlmPreset(this.label, this.baseUrl, this.model);
}

class _PresetChips extends StatelessWidget {
  final void Function(_LlmPreset) onPick;
  const _PresetChips({required this.onPick});

  static const _presets = [
    _LlmPreset('DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
    _LlmPreset('通义千问',
        'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-plus'),
    _LlmPreset(
        '智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4-flash'),
    _LlmPreset('Kimi', 'https://api.moonshot.cn/v1', 'moonshot-v1-8k'),
    _LlmPreset('SiliconFlow', 'https://api.siliconflow.cn/v1',
        'Qwen/Qwen2.5-7B-Instruct'),
    _LlmPreset('OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini'),
  ];

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 4,
        children: _presets
            .map((p) => ActionChip(
                  label: Text(p.label),
                  onPressed: () => onPick(p),
                ))
            .toList(),
      );
}
