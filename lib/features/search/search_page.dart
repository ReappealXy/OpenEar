import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils.dart';
import '../../data/models/recording.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/status_badge.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Recording> _results = const [];
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(v));
  }

  Future<void> _search(String v) async {
    if (v.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
      });
      return;
    }
    setState(() => _loading = true);
    final list =
        await ref.read(databaseProvider).listRecordings(keyword: v.trim());
    if (!mounted) return;
    setState(() {
      _results = list;
      _loading = false;
      _searched = true;
    });
  }

  String _excerpt(Recording r, String kw) {
    final pool = [
      r.title,
      r.plainTranscript ?? '',
      r.summary ?? '',
      r.todos ?? '',
      r.minutes ?? '',
      r.qa ?? '',
    ].join('\n');
    final idx = pool.toLowerCase().indexOf(kw.toLowerCase());
    if (idx < 0) return '';
    final start = (idx - 20).clamp(0, pool.length);
    final end = (idx + kw.length + 60).clamp(0, pool.length);
    var s = pool.substring(start, end).replaceAll('\n', ' ');
    if (start > 0) s = '… $s';
    if (end < pool.length) s = '$s …';
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索标题、转写或 AI 结果…',
            border: InputBorder.none,
          ),
          onChanged: _onChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: _search,
        ),
        actions: [
          if (_ctrl.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                _ctrl.clear();
                _onChanged('');
              },
            )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_searched
              ? const EmptyState(
                  icon: Icons.search,
                  title: '在所有录音中搜索',
                  message: '关键词将在标题、转写、摘要、待办、纪要、Q&A 中匹配。',
                )
              : _results.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off,
                      title: '未找到结果',
                    )
                  : ListView.builder(
                      itemCount: _results.length,
                      itemBuilder: (ctx, i) {
                        final r = _results[i];
                        final excerpt = _excerpt(r, _ctrl.text.trim());
                        return ListTile(
                          onTap: () => context.pushNamed(
                            'detail',
                            pathParameters: {'id': r.id},
                          ),
                          title: Text(r.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Row(children: [
                                StatusBadge(status: r.status),
                                const SizedBox(width: 8),
                                Text(
                                    '${formatDateShort(r.createdAt)} · ${formatDuration(r.duration)}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.onSurfaceVariant)),
                              ]),
                              if (excerpt.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(excerpt,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                      height: 1.5,
                                    )),
                              ]
                            ],
                          ),
                        );
                      },
                    ),
    );
  }
}
