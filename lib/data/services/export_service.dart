import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils.dart';
import '../models/recording.dart';

enum ExportFormat { markdown, docx, pdf }

class ExportService {
  /// 生成 Markdown 文本
  String buildMarkdown(Recording r) {
    final buf = StringBuffer();
    buf.writeln('# ${r.title}');
    buf.writeln();
    buf.writeln('- 录制时间：${formatDateTime(r.createdAt)}');
    buf.writeln('- 时长：${formatDuration(r.duration)}');
    buf.writeln('- 文件大小：${formatFileSize(r.fileSize)}');
    buf.writeln();

    if (r.summary != null && r.summary!.trim().isNotEmpty) {
      buf.writeln('## 摘要');
      buf.writeln();
      buf.writeln(r.summary);
      buf.writeln();
    }

    if (r.todos != null && r.todos!.trim().isNotEmpty) {
      buf.writeln('## 待办事项');
      buf.writeln();
      buf.writeln(r.todos);
      buf.writeln();
    }

    if (r.minutes != null && r.minutes!.trim().isNotEmpty) {
      buf.writeln('## 会议纪要');
      buf.writeln();
      buf.writeln(r.minutes);
      buf.writeln();
    }

    if (r.qa != null && r.qa!.trim().isNotEmpty) {
      buf.writeln('## 问答');
      buf.writeln();
      buf.writeln(r.qa);
      buf.writeln();
    }

    if (r.plainTranscript != null && r.plainTranscript!.isNotEmpty) {
      buf.writeln('## 完整转写');
      buf.writeln();
      buf.writeln('```');
      buf.writeln(r.plainTranscript);
      buf.writeln('```');
    }
    return buf.toString();
  }

  /// 导出到本地文件并触发系统分享
  Future<File> exportAndShare(Recording r, ExportFormat format) async {
    final file = await export(r, format);
    await Share.shareXFiles([XFile(file.path)], text: r.title);
    return file;
  }

  Future<File> export(Recording r, ExportFormat format) async {
    final dir = await getTemporaryDirectory();
    final safeTitle = r.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    switch (format) {
      case ExportFormat.markdown:
        final f = File(p.join(dir.path, '$safeTitle.md'));
        await f.writeAsString(buildMarkdown(r), flush: true);
        return f;
      case ExportFormat.pdf:
        final pdfBytes = await _buildPdf(r);
        final f = File(p.join(dir.path, '$safeTitle.pdf'));
        await f.writeAsBytes(pdfBytes, flush: true);
        return f;
      case ExportFormat.docx:
        final docxBytes = _buildDocx(r);
        final f = File(p.join(dir.path, '$safeTitle.docx'));
        await f.writeAsBytes(docxBytes, flush: true);
        return f;
    }
  }

  // ------------ PDF ------------

  Future<Uint8List> _buildPdf(Recording r) async {
    final doc = pw.Document();
    // 中文需要嵌入字体，否则会出现 Tofu 方块
    final font = await PdfGoogleFonts.notoSansSCRegular();
    final fontBold = await PdfGoogleFonts.notoSansSCBold();
    final theme = pw.ThemeData.withFont(base: font, bold: fontBold);

    pw.Widget section(String title, String? body) {
      if (body == null || body.trim().isEmpty) return pw.SizedBox();
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 12),
          pw.Text(title,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Divider(height: 12, thickness: 0.5),
          pw.Text(body, style: const pw.TextStyle(fontSize: 11, lineSpacing: 4)),
        ],
      );
    }

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => [
          pw.Text(r.title,
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Text(
            '录制时间：${formatDateTime(r.createdAt)}    '
            '时长：${formatDuration(r.duration)}    '
            '大小：${formatFileSize(r.fileSize)}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          section('摘要', r.summary),
          section('待办事项', r.todos),
          section('会议纪要', r.minutes),
          section('问答', r.qa),
          section('完整转写', r.plainTranscript),
        ],
      ),
    );
    return doc.save();
  }

  // ------------ DOCX ------------
  //
  // .docx 本质是一个 zip，最少需要 3 个文件：
  //   [Content_Types].xml
  //   _rels/.rels
  //   word/document.xml
  // 这里手工拼装 OOXML，避免引入复杂的 docx 库。

  Uint8List _buildDocx(Recording r) {
    String para(String text, {bool bold = false, int size = 22}) {
      // OOXML size = half-points，22 => 11pt，36 => 18pt
      final boldXml = bold ? '<w:b/><w:bCs/>' : '';
      final escaped = _xmlEscape(text);
      return '''<w:p><w:pPr><w:spacing w:after="120"/></w:pPr>
<w:r><w:rPr>$boldXml<w:sz w:val="$size"/><w:szCs w:val="$size"/><w:rFonts w:ascii="Microsoft YaHei" w:hAnsi="Microsoft YaHei" w:eastAsia="Microsoft YaHei"/></w:rPr><w:t xml:space="preserve">$escaped</w:t></w:r></w:p>''';
    }

    String heading(String text, {int level = 1}) {
      final size = level == 1 ? 44 : 32; // 22pt / 16pt
      return para(text, bold: true, size: size);
    }

    String section(String title, String? body) {
      if (body == null || body.trim().isEmpty) return '';
      final lines = const LineSplitter().convert(body);
      final paras = lines.map(para).join();
      return heading(title, level: 2) + paras;
    }

    final body = StringBuffer()
      ..write(heading(r.title))
      ..write(para('录制时间：${formatDateTime(r.createdAt)}'))
      ..write(para('时长：${formatDuration(r.duration)}    '
          '大小：${formatFileSize(r.fileSize)}'))
      ..write(section('摘要', r.summary))
      ..write(section('待办事项', r.todos))
      ..write(section('会议纪要', r.minutes))
      ..write(section('问答', r.qa))
      ..write(section('完整转写', r.plainTranscript));

    final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>
$body
<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>
</w:body>
</w:document>''';

    final contentTypesXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
</Types>''';

    const relsXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    final archive = Archive()
      ..addFile(ArchiveFile('[Content_Types].xml',
          utf8.encode(contentTypesXml).length,
          utf8.encode(contentTypesXml)))
      ..addFile(ArchiveFile('_rels/.rels',
          utf8.encode(relsXml).length,
          utf8.encode(relsXml)))
      ..addFile(ArchiveFile('word/document.xml',
          utf8.encode(documentXml).length,
          utf8.encode(documentXml)));
    final bytes = ZipEncoder().encode(archive);
    if (bytes == null) {
      throw StateError('DOCX 打包失败：ZipEncoder 返回空');
    }
    return Uint8List.fromList(bytes);
  }

  String _xmlEscape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
