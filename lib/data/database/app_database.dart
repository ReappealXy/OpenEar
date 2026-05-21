import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/recording.dart';

/// 应用本地数据库（单例）
///
/// 表结构：
///   recordings
///   ├── id           TEXT PRIMARY KEY
///   ├── title        TEXT
///   ├── file_path    TEXT
///   ├── duration_ms  INTEGER
///   ├── file_size    INTEGER
///   ├── created_at   INTEGER (毫秒时间戳)
///   ├── status       TEXT
///   ├── error_msg    TEXT
///   ├── oss_url      TEXT
///   ├── task_id      TEXT
///   ├── sentences    TEXT (JSON 数组)
///   ├── plain_text   TEXT
///   ├── summary      TEXT
///   ├── todos        TEXT
///   ├── minutes      TEXT
///   └── qa           TEXT
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  late final Database _db;
  bool _initialized = false;

  static const _dbName = 'openear.db';
  static const _dbVersion = 1;

  Future<void> init() async {
    if (_initialized) return;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _dbName);
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE recordings (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            file_path TEXT NOT NULL,
            duration_ms INTEGER NOT NULL DEFAULT 0,
            file_size INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            status TEXT NOT NULL DEFAULT 'ready',
            error_msg TEXT,
            oss_url TEXT,
            task_id TEXT,
            sentences TEXT,
            plain_text TEXT,
            summary TEXT,
            todos TEXT,
            minutes TEXT,
            qa TEXT
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_recordings_created ON recordings(created_at DESC)',
        );
      },
    );
    _initialized = true;
  }

  Database get raw => _db;

  // ------------------ Recording CRUD ------------------

  Future<List<Recording>> listRecordings({String? keyword}) async {
    final where = <String>[];
    final args = <Object?>[];
    if (keyword != null && keyword.trim().isNotEmpty) {
      where.add(
        '(title LIKE ? OR plain_text LIKE ? OR summary LIKE ? OR todos LIKE ? OR minutes LIKE ? OR qa LIKE ?)',
      );
      final k = '%${keyword.trim()}%';
      args.addAll([k, k, k, k, k, k]);
    }
    final rows = await _db.query(
      'recordings',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'created_at DESC',
    );
    return rows.map(_fromRow).toList();
  }

  Future<Recording?> getById(String id) async {
    final rows = await _db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<void> upsert(Recording r) async {
    await _db.insert(
      'recordings',
      _toRow(r),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> delete(String id) async {
    final row = await _db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    await _db.delete('recordings', where: 'id = ?', whereArgs: [id]);
    if (row.isNotEmpty) {
      final path = row.first['file_path'] as String?;
      if (path != null) {
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  // ------------------ 序列化 ------------------

  Map<String, Object?> _toRow(Recording r) => {
        'id': r.id,
        'title': r.title,
        'file_path': r.filePath,
        'duration_ms': r.durationMs,
        'file_size': r.fileSize,
        'created_at': r.createdAt.millisecondsSinceEpoch,
        'status': r.status.name,
        'error_msg': r.errorMessage,
        'oss_url': r.ossUrl,
        'task_id': r.taskId,
        'sentences': jsonEncode(r.sentences.map((s) => s.toJson()).toList()),
        'plain_text': r.plainTranscript,
        'summary': r.summary,
        'todos': r.todos,
        'minutes': r.minutes,
        'qa': r.qa,
      };

  Recording _fromRow(Map<String, Object?> row) {
    final sentencesStr = row['sentences'] as String?;
    final sentences = <TranscriptSentence>[];
    if (sentencesStr != null && sentencesStr.isNotEmpty) {
      try {
        final list = jsonDecode(sentencesStr) as List;
        for (final e in list) {
          sentences.add(TranscriptSentence.fromJson(e as Map<String, dynamic>));
        }
      } catch (_) {}
    }
    return Recording(
      id: row['id'] as String,
      title: row['title'] as String,
      filePath: row['file_path'] as String,
      durationMs: (row['duration_ms'] as int?) ?? 0,
      fileSize: (row['file_size'] as int?) ?? 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as int?) ?? 0,
      ),
      status: RecordingStatus.values.firstWhere(
        (s) => s.name == row['status'],
        orElse: () => RecordingStatus.ready,
      ),
      errorMessage: row['error_msg'] as String?,
      ossUrl: row['oss_url'] as String?,
      taskId: row['task_id'] as String?,
      sentences: sentences,
      plainTranscript: row['plain_text'] as String?,
      summary: row['summary'] as String?,
      todos: row['todos'] as String?,
      minutes: row['minutes'] as String?,
      qa: row['qa'] as String?,
    );
  }
}
