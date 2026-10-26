import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../data/settings.dart';

class LlmException implements Exception {
  final String message;
  final bool retryable;
  const LlmException(this.message, {this.retryable = false});
  @override
  String toString() => message;
}

/// OpenAI 兼容的 Chat Completions 客户端。
///
/// 只做三件事：发请求、拿文本、把错误翻译成人话。
/// 不在这里做任何业务判断，避免模型层和业务层纠缠。
class LlmClient {
  static final LlmClient instance = LlmClient._();
  LlmClient._();

  final http.Client _http = http.Client();

  Future<String> chat({
    required LlmSettings settings,
    required List<Map<String, String>> messages,
    bool jsonMode = true,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (settings.apiKey.trim().isEmpty) {
      throw const LlmException('还没有填 API Key，去右上角设置里填一下。');
    }

    final payload = <String, dynamic>{
      'model': settings.model,
      'temperature': settings.temperature,
      'messages': messages,
      if (jsonMode) 'response_format': {'type': 'json_object'},
    };

    var text = await _post(settings, payload, timeout);

    // 有些服务商不认 response_format，被拒后去掉重发一次
    if (text == null) {
      payload.remove('response_format');
      text = await _post(settings, payload, timeout);
    }
    if (text == null) {
      throw const LlmException('模型服务返回了空内容，请稍后重试。', retryable: true);
    }
    return text;
  }

  /// 返回 null 表示「可能是不支持 response_format」，调用方可以降级重试
  Future<String?> _post(LlmSettings settings, Map<String, dynamic> payload, Duration timeout) async {
    final uri = Uri.tryParse(settings.chatCompletionsUrl);
    if (uri == null || !uri.hasScheme) {
      throw const LlmException('Base URL 格式不对，示例：https://api.deepseek.com/v1');
    }

    http.Response resp;
    try {
      resp = await _http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${settings.apiKey.trim()}',
            },
            body: jsonEncode(payload),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const LlmException('请求超时。网络慢或模型服务卡住了，稍后再试。', retryable: true);
    } catch (e) {
      throw LlmException('连不上模型服务：$e', retryable: true);
    }

    if (resp.statusCode == 400 && payload.containsKey('response_format')) {
      final body = utf8.decode(resp.bodyBytes);
      if (body.contains('response_format')) return null;
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw const LlmException('API Key 无效或没有权限，检查一下设置里的 Key。');
    }
    if (resp.statusCode == 404) {
      throw const LlmException('接口地址不存在。Base URL 一般填到 /v1 为止，例如 https://api.deepseek.com/v1');
    }
    if (resp.statusCode == 429) {
      throw const LlmException('调用太频繁或额度用完了，等一下再试。', retryable: true);
    }
    if (resp.statusCode >= 500) {
      throw LlmException('模型服务出错（${resp.statusCode}），稍后再试。', retryable: true);
    }
    if (resp.statusCode != 200) {
      throw LlmException('调用失败（${resp.statusCode}）：${_brief(resp.body)}');
    }

    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final choices = decoded['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw const LlmException('模型没有返回内容。');
      }
      final msg = (choices.first as Map)['message'] as Map?;
      final content = msg?['content'];
      if (content is String) return content;
      if (content is List) {
        // 少数实现会把 content 拆成多段
        return content
            .map((e) => (e is Map ? (e['text'] ?? '') : '').toString())
            .join();
      }
      return null;
    } on LlmException {
      rethrow;
    } catch (_) {
      throw const LlmException('模型返回的内容无法解析，稍后再试。', retryable: true);
    }
  }

  String _brief(String body) {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 160 ? '${t.substring(0, 160)}…' : t;
  }

  /// 设置页的「测试连接」：发一句最短的话，确认地址、Key、模型名都对
  Future<String> testConnection(LlmSettings settings) async {
    final reply = await chat(
      settings: settings,
      jsonMode: false,
      timeout: const Duration(seconds: 30),
      messages: [
        {'role': 'user', 'content': '只回复两个字：正常'}
      ],
    );
    return reply.trim();
  }
}
