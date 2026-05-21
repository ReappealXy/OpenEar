import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../data/models/recording.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordingsAsync = ref.watch(recordingsProvider);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (ctx, inner) => [
          SliverAppBar.large(
            title: const Text('OpenEar'),
            actions: [
              IconButton(
                tooltip: '搜索',
                icon: const Icon(Icons.search_rounded),
                onPressed: () => context.pushNamed('search'),
              ),
              IconButton(
                tooltip: '设置',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.pushNamed('settings'),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ],
        body: RefreshIndicator(
          onRefresh: () =>
              ref.read(recordingsProvider.notifier).refresh(),
          child: recordingsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => EmptyState(
              icon: Icons.error_outline,
              title: '加载失败',
              message: '$e',
            ),
            data: (list) => list.isEmpty
                ? const _Empty()
                : _List(list: list),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.mic_rounded),
        label: const Text('开始录音'),
        onPressed: () => context.pushNamed('recorder'),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return ListView(
      // 让 RefreshIndicator 可下拉
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: EmptyState(
            icon: Icons.graphic_eq_rounded,
            title: '还没有录音',
            message: '点击下方按钮开始录音，\n或先到设置完成阿里云与 LLM 配置。',
            action: FilledButton.tonalIcon(
              icon: const Icon(Icons.settings_outlined),
              label: const Text('打开设置'),
              onPressed: () => context.pushNamed('settings'),
            ),
          ),
        ),
      ],
    );
  }
}

class _List extends ConsumerWidget {
  final List<Recording> list;
  const _List({required this.list});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      itemCount: list.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (ctx, i) {
        final r = list[i];
        return _RecordingCard(r: r);
      },
    );
  }
}

class _RecordingCard extends ConsumerWidget {
  final Recording r;
  const _RecordingCard({required this.r});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final hasSummary = (r.summary ?? '').isNotEmpty;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.pushNamed('detail', pathParameters: {'id': r.id}),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      r.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (v) async {
                      switch (v) {
                        case 'delete':
                          await ref
                              .read(recordingsProvider.notifier)
                              .delete(r.id);
                          break;
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [
                            Icon(Icons.delete_outline,
                                size: 18, color: Colors.red),
                            SizedBox(width: 10),
                            Text('删除'),
                          ])),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  StatusBadge(status: r.status),
                  const SizedBox(width: 8),
                  Text(
                    '${formatDateShort(r.createdAt)} · ${formatDuration(r.duration)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (hasSummary) ...[
                const SizedBox(height: 10),
                Text(
                  r.summary!.replaceAll(RegExp(r'[#*`>\-]'), '').trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ] else if (r.status == RecordingStatus.failed &&
                  r.errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  '错误：${r.errorMessage}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.error, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
