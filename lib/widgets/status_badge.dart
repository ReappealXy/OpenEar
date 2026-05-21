import 'package:flutter/material.dart';

import '../data/models/recording.dart';

class StatusBadge extends StatelessWidget {
  final RecordingStatus status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg, dot) = switch (status) {
      RecordingStatus.ready =>
        (scheme.surfaceContainerHigh, scheme.onSurfaceVariant, Colors.grey),
      RecordingStatus.uploading =>
        (scheme.tertiaryContainer, scheme.onTertiaryContainer, Colors.orange),
      RecordingStatus.transcribing =>
        (scheme.secondaryContainer, scheme.onSecondaryContainer, Colors.cyan),
      RecordingStatus.analyzing =>
        (scheme.primaryContainer, scheme.onPrimaryContainer, Colors.indigo),
      RecordingStatus.done =>
        (Colors.green.withOpacity(0.15), Colors.green.shade800, Colors.green),
      RecordingStatus.failed =>
        (scheme.errorContainer, scheme.onErrorContainer, scheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: TextStyle(
                color: fg, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
