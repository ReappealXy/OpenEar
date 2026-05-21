import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../core/utils.dart';
import '../../data/models/recording.dart';
import '../../data/services/export_service.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';

class DetailPage extends ConsumerStatefulWidget {
  final String recordingId;
  const DetailPage({super.key, required this.recordingId});

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  String _processingMessage = '';
  int _elapsedSeconds = 0;
  int _totalProcessingSeconds = 0; // 完成后保留总耗时
  Timer? _timer;
  RecordingStatus? _lastStatus;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _timer?.cancel();
    super.dispose();
  }

  void _syncTimer(RecordingStatus status) {
    final processing = status == RecordingStatus.uploading ||
        status == RecordingStatus.transcribing ||
        status == RecordingStatus.analyzing;

    if (status != _lastStatus) {
      if (_lastStatus != null && !processing) {
        // 从处理中 → 完成/失败，保存总耗时
        _totalProcessingSeconds = _elapsedSeconds;
      }
      if (processing && _lastStatus != null && !_isProcessing(_lastStatus!)) {
        // 新一轮处理开始，重置
        _elapsedSeconds = 0;
        _totalProcessingSeconds = 0;
      }
      _lastStatus = status;
    }

    if (processing && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _elapsedSeconds++);
      });
    } else if (!processing) {
      _timer?.cancel();
      _timer = null;
    }
  }

  bool _isProcessing(RecordingStatus s) =>
      s == RecordingStatus.uploading ||
      s == RecordingStatus.transcribing ||
      s == RecordingStatus.analyzing;

  Future<void> _reprocess(Recording r) async {
    setState(() => _processingMessage = '检查配置…');
    // 等待 settings 从磁盘加载完成
    final settings = await ref.read(settingsProvider.future);
    if (!settings.cloudReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在设置页填写腾讯云 SecretId / SecretKey / Bucket / AppID')));
      setState(() => _processingMessage = '');
      return;
    }
    setState(() {
      _processingMessage = '准备重试…';
      _elapsedSeconds = 0;
      _totalProcessingSeconds = 0;
    });
    try {
      await ref.read(processingPipelineProvider).run(
            r,
            onProgress: (m) {
              if (mounted) setState(() => _processingMessage = m);
            },
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('处理失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _processingMessage = '');
    }
  }

  Future<void> _editTitle(Recording r) async {
    final ctrl = TextEditingController(text: r.title);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑标题'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('保存')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty && v != r.title) {
      await ref
          .read(recordingsProvider.notifier)
          .upsert(r.copyWith(title: v));
    }
  }

  Future<void> _export(Recording r, ExportFormat fmt) async {
    final exp = ref.read(exportServiceProvider);
    try {
      await exp.exportAndShare(r, fmt);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('导出失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncR = ref.watch(recordingByIdProvider(widget.recordingId));
    return asyncR.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.error_outline,
          title: '加载失败',
          message: '$e',
        ),
      ),
      data: (r) {
        if (r == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
                icon: Icons.search_off, title: '该录音不存在'),
          );
        }
        return _build(r);
      },
    );
  }

  Widget _build(Recording r) {
    final scheme = Theme.of(context).colorScheme;
    final processing = r.status == RecordingStatus.uploading ||
        r.status == RecordingStatus.transcribing ||
        r.status == RecordingStatus.analyzing;
    _syncTimer(r.status);

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () => _editTitle(r),
          child: Text(r.title, overflow: TextOverflow.ellipsis),
        ),
        actions: [
          PopupMenuButton<ExportFormat>(
            tooltip: '导出',
            icon: const Icon(Icons.ios_share_outlined),
            enabled: r.status == RecordingStatus.done,
            onSelected: (f) => _export(r, f),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: ExportFormat.markdown,
                  child: ListTile(
                      leading: Icon(Icons.description_outlined),
                      title: Text('Markdown'),
                      contentPadding: EdgeInsets.zero)),
              PopupMenuItem(
                  value: ExportFormat.docx,
                  child: ListTile(
                      leading: Icon(Icons.article_outlined),
                      title: Text('Word (.docx)'),
                      contentPadding: EdgeInsets.zero)),
              PopupMenuItem(
                  value: ExportFormat.pdf,
                  child: ListTile(
                      leading: Icon(Icons.picture_as_pdf_outlined),
                      title: Text('PDF'),
                      contentPadding: EdgeInsets.zero)),
            ],
          ),
          if (r.status == RecordingStatus.failed ||
              r.status == RecordingStatus.ready)
            IconButton(
              tooltip: '重新处理',
              icon: const Icon(Icons.refresh),
              onPressed: () => _reprocess(r),
            ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: '概览'),
            Tab(text: '摘要'),
            Tab(text: '待办'),
            Tab(text: '纪要'),
            Tab(text: '问答'),
          ],
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: scheme.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge(status: r.status),
                    const SizedBox(width: 10),
                    Text(
                      '${formatDateTime(r.createdAt)} · '
                      '${formatDuration(r.duration)} · '
                      '${formatFileSize(r.fileSize)}',
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
                if (processing || _processingMessage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _processingMessage.isNotEmpty
                              ? _processingMessage
                              : _stepLabel(r.status),
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant),
                        ),
                      ),
                      if (_elapsedSeconds > 0)
                        Text(
                          '${_elapsedSeconds}s',
                          style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _StepBar(status: r.status),
                ],
                // 完成后显示总耗时
                if (!processing &&
                    r.status == RecordingStatus.done &&
                    _totalProcessingSeconds > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '处理完成，共耗时 ${_totalProcessingSeconds}s',
                    style: TextStyle(
                        fontSize: 11,
                        color: scheme.primary),
                  ),
                ],
                if (r.status == RecordingStatus.failed &&
                    r.errorMessage != null) ...[
                  const SizedBox(height: 6),
                  Text('错误：${r.errorMessage}',
                      style: TextStyle(
                          fontSize: 12, color: scheme.error)),
                ],
              ],
            ),
          ),
          _Player(filePath: r.filePath),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _Overview(r: r),
                _MarkdownTab(content: r.summary, emptyHint: '尚未生成摘要'),
                _MarkdownTab(content: r.todos, emptyHint: '尚未生成待办'),
                _MarkdownTab(content: r.minutes, emptyHint: '尚未生成会议纪要'),
                _MarkdownTab(content: r.qa, emptyHint: '尚未生成 Q&A'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Player extends ConsumerStatefulWidget {
  final String filePath;
  const _Player({required this.filePath});

  @override
  ConsumerState<_Player> createState() => _PlayerState();
}

class _PlayerState extends ConsumerState<_Player> {
  late final _player = ref.read(audioPlayerProvider).player;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        await _player.setFilePath(widget.filePath);
        if (mounted) setState(() => _loaded = true);
      } catch (_) {}
    }();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SizedBox(
        height: 56,
        child: Center(child: LinearProgressIndicator()),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (ctx, snap) {
              final playing = snap.data?.playing ?? false;
              return IconButton.filled(
                onPressed: () => playing ? _player.pause() : _player.play(),
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
              );
            },
          ),
          Expanded(
            child: StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (ctx, snap) {
                final pos = snap.data ?? Duration.zero;
                final dur = _player.duration ?? Duration.zero;
                final max = dur.inMilliseconds.toDouble().clamp(1.0, 1e12);
                return Column(
                  children: [
                    Slider(
                      value: pos.inMilliseconds
                          .toDouble()
                          .clamp(0.0, max),
                      max: max,
                      onChanged: (v) => _player
                          .seek(Duration(milliseconds: v.toInt())),
                    ),
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Text(formatDuration(pos),
                              style: const TextStyle(fontSize: 11)),
                          Text(formatDuration(dur),
                              style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  final Recording r;
  const _Overview({required this.r});

  @override
  Widget build(BuildContext context) {
    if (r.sentences.isEmpty) {
      return const EmptyState(
        icon: Icons.text_snippet_outlined,
        title: '暂无转写内容',
        message: '转写完成后将显示带说话人标签的逐字稿。',
      );
    }
    int? lastSpeaker;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: r.sentences.length,
      itemBuilder: (ctx, i) {
        final s = r.sentences[i];
        final showSpeaker = s.speakerId != lastSpeaker;
        lastSpeaker = s.speakerId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSpeaker)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _speakerColor(s.speakerId)
                              .withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '发言人 ${s.speakerId}',
                          style: TextStyle(
                            color: _speakerColor(s.speakerId),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${formatDuration(Duration(milliseconds: s.beginTime))} → '
                        '${formatDuration(Duration(milliseconds: s.endTime))}',
                        style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              Text(s.text, style: const TextStyle(height: 1.6)),
            ],
          ),
        );
      },
    );
  }

  Color _speakerColor(int id) {
    const colors = [
      Color(0xFF4F46E5),
      Color(0xFFEC4899),
      Color(0xFF06B6D4),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
      Color(0xFF8B5CF6),
    ];
    return colors[id.abs() % colors.length];
  }
}

String _stepLabel(RecordingStatus s) => switch (s) {
      RecordingStatus.uploading => '步骤 1/3：上传录音到云端…',
      RecordingStatus.transcribing => '步骤 2/3：语音转写中，请耐心等待…',
      RecordingStatus.analyzing => '步骤 3/3：AI 正在生成分析…',
      _ => s.label,
    };

class _StepBar extends StatelessWidget {
  final RecordingStatus status;
  const _StepBar({required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final steps = [
      (label: '上传', active: status == RecordingStatus.uploading,
       done: _isDoneOrAfter(status, RecordingStatus.uploading)),
      (label: '转写', active: status == RecordingStatus.transcribing,
       done: _isDoneOrAfter(status, RecordingStatus.transcribing)),
      (label: 'AI 分析', active: status == RecordingStatus.analyzing,
       done: status == RecordingStatus.done),
    ];

    return Row(
      children: [
        for (int i = 0; i < steps.length; i++) ...[
          _StepDot(
            label: steps[i].label,
            active: steps[i].active,
            done: steps[i].done,
            scheme: scheme,
          ),
          if (i < steps.length - 1)
            Expanded(
              child: Container(
                height: 2,
                color: steps[i].done
                    ? scheme.primary
                    : scheme.outlineVariant,
              ),
            ),
        ],
      ],
    );
  }

  bool _isDoneOrAfter(RecordingStatus current, RecordingStatus step) {
    const order = [
      RecordingStatus.uploading,
      RecordingStatus.transcribing,
      RecordingStatus.analyzing,
      RecordingStatus.done,
    ];
    final ci = order.indexOf(current);
    final si = order.indexOf(step);
    return ci > si;
  }
}

class _StepDot extends StatelessWidget {
  final String label;
  final bool active;
  final bool done;
  final ColorScheme scheme;
  const _StepDot(
      {required this.label,
      required this.active,
      required this.done,
      required this.scheme});

  @override
  Widget build(BuildContext context) {
    final color = done || active ? scheme.primary : scheme.outlineVariant;
    return Column(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: done ? scheme.primary : Colors.transparent,
            border: Border.all(color: color, width: 2),
            shape: BoxShape.circle,
          ),
          child: done
              ? Icon(Icons.check, size: 12, color: scheme.onPrimary)
              : active
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
        ),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: color,
                fontWeight:
                    active ? FontWeight.w600 : FontWeight.normal)),
      ],
    );
  }
}

class _MarkdownTab extends StatelessWidget {
  final String? content;
  final String emptyHint;
  const _MarkdownTab({required this.content, required this.emptyHint});

  @override
  Widget build(BuildContext context) {
    if (content == null || content!.trim().isEmpty) {
      return EmptyState(
        icon: Icons.auto_awesome_outlined,
        title: emptyHint,
        message: '当转写完成且 LLM 配置可用时会自动生成。',
      );
    }
    return Markdown(
      data: content!,
      padding: const EdgeInsets.all(20),
      selectable: true,
      styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
        p: const TextStyle(fontSize: 15, height: 1.7),
        h1: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        h2: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        h3: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        listBullet: const TextStyle(fontSize: 15, height: 1.7),
      ),
    );
  }
}
