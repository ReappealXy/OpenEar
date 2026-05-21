/// 录音状态机：
///   ready   - 已录制好等待转写
///   uploading - 上传 OSS 中
///   transcribing - ASR 转写中
///   analyzing - LLM 分析中
///   done    - 全部完成
///   failed  - 任意阶段失败
enum RecordingStatus {
  ready,
  uploading,
  transcribing,
  analyzing,
  done,
  failed;

  String get label => switch (this) {
        RecordingStatus.ready => '待处理',
        RecordingStatus.uploading => '上传中',
        RecordingStatus.transcribing => '转写中',
        RecordingStatus.analyzing => 'AI 分析中',
        RecordingStatus.done => '已完成',
        RecordingStatus.failed => '失败',
      };
}

/// 转写句子（带时间戳和说话人）
class TranscriptSentence {
  final int beginTime; // ms
  final int endTime;
  final String text;
  final int speakerId; // 0 表示未知

  const TranscriptSentence({
    required this.beginTime,
    required this.endTime,
    required this.text,
    this.speakerId = 0,
  });

  Map<String, dynamic> toJson() => {
        'b': beginTime,
        'e': endTime,
        't': text,
        's': speakerId,
      };

  factory TranscriptSentence.fromJson(Map<String, dynamic> j) =>
      TranscriptSentence(
        beginTime: (j['b'] as num?)?.toInt() ?? 0,
        endTime: (j['e'] as num?)?.toInt() ?? 0,
        text: j['t'] as String? ?? '',
        speakerId: (j['s'] as num?)?.toInt() ?? 0,
      );
}

/// 录音主对象
class Recording {
  final String id;
  final String title;
  final String filePath;
  final int durationMs;
  final int fileSize;
  final DateTime createdAt;
  final RecordingStatus status;
  final String? errorMessage;
  final String? ossUrl; // 上传到 OSS 之后的可访问 URL
  final String? taskId; // 阿里云 ASR 任务 ID

  // 转写结果
  final List<TranscriptSentence> sentences;
  final String? plainTranscript; // 拼接好的逐字稿

  // LLM 分析结果（Markdown 格式）
  final String? summary;
  final String? todos;
  final String? minutes;
  final String? qa;

  const Recording({
    required this.id,
    required this.title,
    required this.filePath,
    required this.durationMs,
    required this.fileSize,
    required this.createdAt,
    this.status = RecordingStatus.ready,
    this.errorMessage,
    this.ossUrl,
    this.taskId,
    this.sentences = const [],
    this.plainTranscript,
    this.summary,
    this.todos,
    this.minutes,
    this.qa,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  Recording copyWith({
    String? title,
    String? filePath,
    int? durationMs,
    int? fileSize,
    DateTime? createdAt,
    RecordingStatus? status,
    String? errorMessage,
    String? ossUrl,
    String? taskId,
    List<TranscriptSentence>? sentences,
    String? plainTranscript,
    String? summary,
    String? todos,
    String? minutes,
    String? qa,
  }) =>
      Recording(
        id: id,
        title: title ?? this.title,
        filePath: filePath ?? this.filePath,
        durationMs: durationMs ?? this.durationMs,
        fileSize: fileSize ?? this.fileSize,
        createdAt: createdAt ?? this.createdAt,
        status: status ?? this.status,
        errorMessage: errorMessage,
        ossUrl: ossUrl ?? this.ossUrl,
        taskId: taskId ?? this.taskId,
        sentences: sentences ?? this.sentences,
        plainTranscript: plainTranscript ?? this.plainTranscript,
        summary: summary ?? this.summary,
        todos: todos ?? this.todos,
        minutes: minutes ?? this.minutes,
        qa: qa ?? this.qa,
      );
}
