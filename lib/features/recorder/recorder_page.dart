import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils.dart';
import '../../data/models/recording.dart';
import '../../providers.dart';

class RecorderPage extends ConsumerStatefulWidget {
  const RecorderPage({super.key});

  @override
  ConsumerState<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends ConsumerState<RecorderPage>
    with SingleTickerProviderStateMixin {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  double _amp = -160;
  bool _isRecording = false;
  bool _isPaused = false;
  StreamSubscription? _ampSub;

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ampSub?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final svc = ref.read(audioRecorderProvider);
    try {
      await svc.start();
      setState(() {
        _isRecording = true;
        _isPaused = false;
      });
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!mounted) return;
        if (!_isPaused) setState(() => _elapsed = svc.elapsed);
      });
      _ampSub?.cancel();
      _ampSub = svc.amplitudeStream.listen((Amplitude a) {
        if (!mounted) return;
        setState(() => _amp = a.current);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('录音启动失败：$e')));
    }
  }

  Future<void> _pause() async {
    await ref.read(audioRecorderProvider).pause();
    setState(() => _isPaused = true);
  }

  Future<void> _resume() async {
    await ref.read(audioRecorderProvider).resume();
    setState(() => _isPaused = false);
  }

  Future<void> _stop({bool process = true}) async {
    final svc = ref.read(audioRecorderProvider);
    final result = await svc.stop();
    _ticker?.cancel();
    _ampSub?.cancel();
    setState(() {
      _isRecording = false;
      _isPaused = false;
    });
    if (result == null) return;
    final r = Recording(
      id: const Uuid().v4(),
      title: '录音 ${formatDateTime(DateTime.now())}',
      filePath: result.path,
      durationMs: result.duration.inMilliseconds,
      fileSize: result.size,
      createdAt: DateTime.now(),
      status: RecordingStatus.ready,
    );
    await ref.read(recordingsProvider.notifier).upsert(r);
    if (!mounted) return;
    if (process) {
      _kickoffProcessing(r);
    }
    context.goNamed('detail', pathParameters: {'id': r.id});
  }

  Future<void> _importFile() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: false,
    );
    if (res == null || res.files.isEmpty) return;
    final file = res.files.first;
    if (file.path == null) return;
    final f = File(file.path!);
    final size = await f.length();
    final r = Recording(
      id: const Uuid().v4(),
      title: file.name.split('.').first,
      filePath: file.path!,
      durationMs: 0,
      fileSize: size,
      createdAt: DateTime.now(),
      status: RecordingStatus.ready,
    );
    await ref.read(recordingsProvider.notifier).upsert(r);
    if (!mounted) return;
    _kickoffProcessing(r);
    context.goNamed('detail', pathParameters: {'id': r.id});
  }

  void _kickoffProcessing(Recording r) {
    final pipeline = ref.read(processingPipelineProvider);
    // 不等待，后台执行
    unawaited(pipeline.run(r));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final cloudReady = settings?.cloudReady ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('新录音'),
        actions: [
          IconButton(
            tooltip: '导入音频',
            icon: const Icon(Icons.upload_file_outlined),
            onPressed: _isRecording ? null : _importFile,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (!cloudReady)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: scheme.error, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('腾讯云配置未完成，录音后将无法自动转写。',
                          style: TextStyle(fontSize: 13)),
                    ),
                    TextButton(
                      onPressed: () => context.pushNamed('settings'),
                      child: const Text('去配置'),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            _WaveRing(
              amplitude: _amp,
              active: _isRecording && !_isPaused,
              controller: _pulse,
            ),
            const SizedBox(height: 24),
            Text(
              formatDuration(_elapsed),
              style: const TextStyle(
                fontSize: 40,
                fontFeatures: [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w300,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isRecording
                  ? (_isPaused ? '已暂停' : '正在录音…')
                  : '准备就绪',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const Spacer(),
            _Controls(
              isRecording: _isRecording,
              isPaused: _isPaused,
              onStart: _start,
              onPause: _pause,
              onResume: _resume,
              onStop: () => _stop(),
              onCancel: () async {
                await ref.read(audioRecorderProvider).cancel();
                _ticker?.cancel();
                _ampSub?.cancel();
                setState(() {
                  _isRecording = false;
                  _isPaused = false;
                  _elapsed = Duration.zero;
                });
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  final bool isRecording;
  final bool isPaused;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onCancel;

  const _Controls({
    required this.isRecording,
    required this.isPaused,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    if (!isRecording) {
      return FilledButton.icon(
        style: FilledButton.styleFrom(
          minimumSize: const Size(double.infinity, 64),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
        icon: const Icon(Icons.fiber_manual_record),
        label: const Text('开始录音', style: TextStyle(fontSize: 16)),
        onPressed: onStart,
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _CircleBtn(
          icon: Icons.close,
          color: Colors.grey,
          onTap: onCancel,
          tooltip: '取消',
        ),
        _CircleBtn(
          icon: isPaused ? Icons.play_arrow : Icons.pause,
          color: Theme.of(context).colorScheme.secondary,
          onTap: isPaused ? onResume : onPause,
          size: 76,
          tooltip: isPaused ? '继续' : '暂停',
        ),
        _CircleBtn(
          icon: Icons.stop,
          color: Theme.of(context).colorScheme.primary,
          onTap: onStop,
          tooltip: '保存',
        ),
      ],
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double size;
  final String? tooltip;

  const _CircleBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    this.size = 60,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final w = Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(icon, color: Colors.white, size: size * 0.4),
        ),
      ),
    );
    return tooltip == null ? w : Tooltip(message: tooltip!, child: w);
  }
}

/// 跟随录音音量呼吸的圆形指示器
class _WaveRing extends StatelessWidget {
  final double amplitude; // dBFS（-160 静音 ~ 0 最大）
  final bool active;
  final AnimationController controller;

  const _WaveRing({
    required this.amplitude,
    required this.active,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = ((amplitude + 60) / 60).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: controller,
      builder: (ctx, _) {
        final scale = active ? 1 + (level * 0.35) : 1.0;
        return Stack(
          alignment: Alignment.center,
          children: [
            for (int i = 2; i >= 0; i--)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 180.0 + i * 30 * (active ? (0.3 + level) : 0.1),
                height: 180.0 + i * 30 * (active ? (0.3 + level) : 0.1),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary
                      .withOpacity(active ? (0.06 + i * 0.04) : 0.04),
                ),
              ),
            AnimatedScale(
              scale: scale.toDouble(),
              duration: const Duration(milliseconds: 200),
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary,
                      scheme.secondary,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withOpacity(0.3),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.mic, color: Colors.white, size: 52),
              ),
            ),
          ],
        );
      },
    );
  }
}
