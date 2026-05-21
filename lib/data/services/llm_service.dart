import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// OpenAI Chat Completions 兼容协议的 LLM 客户端
///
/// 支持 OpenAI / DeepSeek / 通义千问（DashScope 兼容模式）/ 智谱 / Kimi /
/// 硅基流动 SiliconFlow / 任意自部署的兼容服务。
class LlmService {
  final String baseUrl; // 例：https://api.deepseek.com/v1
  final String apiKey;
  final String model;
  final double temperature;

  final Dio _dio;

  LlmService({
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.temperature = 0.3,
  }) : _dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(minutes: 5),
            responseType: ResponseType.json,
            validateStatus: (s) => s != null && s < 500,
          ),
        );

  Future<String> chat({
    required String system,
    required String user,
    int maxTokens = 4096,
  }) async {
    final url = '${baseUrl.replaceAll(RegExp(r'/+$'), '')}/chat/completions';
    final body = <String, dynamic>{
      'model': model,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'stream': false,
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': user},
      ],
    };
    final res = await _dio.post<dynamic>(
      url,
      data: body,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
    );
    final data = res.data is String
        ? jsonDecode(res.data as String) as Map<String, dynamic>
        : (res.data as Map).cast<String, dynamic>();
    if (res.statusCode != 200) {
      throw Exception('LLM 请求失败 ${res.statusCode}：${data['error'] ?? data}');
    }
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('LLM 未返回 choices：$data');
    }
    final message = choices.first['message'] as Map?;
    final content = message?['content'];
    if (content is String) return content.trim();
    throw Exception('LLM 返回内容格式异常：$data');
  }

  // ---------------- 业务级 Prompt ----------------

  /// 并行生成四类分析结果
  Future<({String summary, String todos, String minutes, String qa})>
      analyzeAll(
    String transcript, {
    void Function(String step)? onStepDone,
  }) async {
    Future<String> wrap(String label, Future<String> f) async {
      final r = await f;
      onStepDone?.call(label);
      return r;
    }

    final results = await Future.wait([
      wrap('摘要', summarize(transcript)),
      wrap('待办', extractTodos(transcript)),
      wrap('纪要', generateMinutes(transcript)),
      wrap('Q&A', generateQA(transcript)),
    ]);
    return (
      summary: results[0],
      todos: results[1],
      minutes: results[2],
      qa: results[3],
    );
  }

  Future<String> summarize(String transcript) {
    return chat(
      system: '''你是一位资深的会议秘书，擅长从录音转写文本中提炼关键信息。
请用清晰简洁的中文撰写摘要，使用 Markdown 排版。
要求：
- 控制在 300 字以内
- 输出三段：核心议题、关键结论、后续行动
- 用 **加粗** 突出重点
- 不要重复转写原文''',
      user: '请阅读以下转写文本并生成摘要：\n\n$transcript',
    );
  }

  Future<String> extractTodos(String transcript) {
    return chat(
      system: '''你是一位专业的项目管理助理，擅长从对话中识别待办事项。
请用 Markdown 任务列表格式输出，每条包含：
- [ ] **任务内容**（负责人：xxx，截止：xxx）
若负责人或截止时间未提及，则写"未指定"。
若文本中没有任何明确的待办，请回复："本段录音未提取到明确的待办事项。"''',
      user: '请从以下转写文本中提取待办事项：\n\n$transcript',
    );
  }

  Future<String> generateMinutes(String transcript) {
    return chat(
      system: '''你是一名经验丰富的会议纪要撰写者。请将转写文本整理为结构化的会议纪要，
使用 Markdown 排版，包含以下章节（缺失则跳过）：

## 一、会议概况
- 时间 / 参会人（基于发言人编号）/ 主题

## 二、讨论要点
按议题分点列出，每点 1-3 句概括。

## 三、决议与结论
明确达成的共识。

## 四、待办与负责人
表格形式：| 任务 | 负责人 | 截止 |

## 五、其他备注
未归类的重要信息。

注意：不要编造文本中不存在的信息。''',
      user: '请基于以下转写整理会议纪要：\n\n$transcript',
    );
  }

  Future<String> generateQA(String transcript) {
    return chat(
      system: '''你是一名内容分析助手，需要从录音转写中提取最具价值的问答对，
帮助用户快速回顾内容要点。

输出 Markdown 格式，5-10 组 Q&A，每组形如：

**Q1：xxx？**
A1：xxx

回答要简洁但信息完整，必要时引用原文关键句。''',
      user: '请基于以下转写文本生成 Q&A：\n\n$transcript',
    );
  }
}
