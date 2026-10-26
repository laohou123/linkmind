import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import '../data/settings.dart';
import '../llm/llm_client.dart';

/// 语音合成。走 OpenAI 兼容的 /audio/speech，返回音频字节直接播。
class _AudioPayload {
  final Uint8List bytes;
  final String mime;
  const _AudioPayload(this.bytes, this.mime);
}

class TtsService {
  static final TtsService instance = TtsService._();
  TtsService._();

  final AudioPlayer _player = AudioPlayer();

  /// 系统语音引擎（Android TextToSpeech / iOS AVSpeechSynthesizer）
  final FlutterTts _system = FlutterTts();
  bool _systemConfigured = false;

  Completer<void>? _done;

  /// 服务端常见的音色列表接口，按顺序试探；
  /// 都不支持时返回空列表，由调用方回落到内置常用音色。
  static const _voicePaths = ['audio/voices', 'voices', 'audio/voice/list'];

  /// MiMo 预置音色（官方文档列表）
  static const chatVoices = <String>[
    'mimo_default', '冰糖', '茉莉', '苏打', '白桦', 'Mia', 'Chloe', 'Milo', 'Dean',
  ];

  static const builtinVoices = <String>[
    'alloy', 'echo', 'fable', 'onyx', 'nova', 'shimmer',
  ];

  /// 试一次服务端音色接口。返回 null 表示"服务端没有这个能力"，
  /// 返回空列表表示"接口存在但没解析出音色"。
  Future<List<String>?> fetchVoices(TtsSettings settings) async {
    if (settings.apiKey.trim().isEmpty) {
      throw const LlmException('先填好 API Key 再获取音色。');
    }
    var base = settings.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (!base.endsWith('/v1') && !base.contains('/v1/')) base = '$base/v1';

    for (final path in _voicePaths) {
      try {
        final resp = await http.get(
          Uri.parse('$base/$path'),
          headers: {'Authorization': 'Bearer ${settings.apiKey.trim()}'},
        ).timeout(const Duration(seconds: 12));

        if (resp.statusCode != 200) continue;
        final parsed = _parseVoices(utf8.decode(resp.bodyBytes));
        if (parsed.isNotEmpty) return parsed;
      } catch (_) {
        // 这个接口不存在或超时，继续试下一个
        continue;
      }
    }
    return null;
  }

  /// 容错解析：可能是 ["alloy"]、{"voices":[{"name":"alloy"}]}、{"data":[{"id":"alloy"}]}
  List<String> _parseVoices(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return const [];
    }
    final out = <String>[];
    void collect(dynamic node) {
      if (node is String) {
        if (node.trim().isNotEmpty) out.add(node.trim());
      } else if (node is List) {
        for (final e in node) {
          collect(e);
        }
      } else if (node is Map) {
        for (final key in ['name', 'id', 'voice', 'voice_id', 'short_name']) {
          final v = node[key];
          if (v is String && v.trim().isNotEmpty) {
            out.add(v.trim());
            return;
          }
        }
      }
    }

    if (decoded is Map) {
      for (final key in ['voices', 'data', 'items', 'list']) {
        if (decoded.containsKey(key)) collect(decoded[key]);
      }
    } else {
      collect(decoded);
    }
    return out.toSet().toList()..sort();
  }

  /// 合成并播放。返回的 Future 在播完或被打断时结束。
  Future<void> speak(String text, TtsSettings settings) async {
    final clean = _prepare(text);
    if (clean.isEmpty) return;
    await stop();

    if (settings.useSystem) {
      await _speakSystem(clean, settings);
      return;
    }

    final payload = await _synthesize(clean, settings);
    _done = Completer<void>();
    _player.onPlayerComplete.first.then((_) {
      if (_done != null && !_done!.isCompleted) _done!.complete();
    });
    try {
      await _player.play(BytesSource(payload.bytes, mimeType: payload.mime));
      await _done!.future;
    } finally {
      _done = null;
    }
  }


  /// 本地播报：直接调系统引擎，全程不联网。
  Future<void> _speakSystem(String text, TtsSettings settings) async {
    if (!_systemConfigured) {
      await _system.awaitSpeakCompletion(true);
      await _system.setSpeechRate(0.5);
      await _system.setPitch(1.0);
      await _system.setVolume(1.0);
      _systemConfigured = true;
    }

    final locale = settings.systemLocale.trim().isEmpty ? 'zh-CN' : settings.systemLocale.trim();
    try {
      final ok = await _system.setLanguage(locale);
      if (ok == 0) {
        throw LlmException(
          '这台手机没有装「$locale」的语音包。\n'
          '到 系统设置 → 语言与输入 → 文字转语音，选一个中文引擎（如 Google 文字转语音 / 手机自带）并下载中文语音数据。',
        );
      }
    } catch (e) {
      if (e is LlmException) rethrow;
      throw LlmException('系统语音初始化失败：$e');
    }

    await _system.speak(text);
  }

  /// 有哪些语言可选（用于设置页提示，不同手机差别很大）
  Future<List<String>> systemLanguages() async {
    try {
      final langs = await _system.getLanguages;
      if (langs is List) return langs.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }

  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
    try {
      await _system.stop();
    } catch (_) {}
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
    _done = null;
  }

  /// 念之前先做点清理：去掉 Markdown 符号、把路径箭头读成"来自"
  String _prepare(String raw) {
    var t = raw;
    t = t.replaceAll('←', '，来自');
    t = t.replaceAll('→', '，指向');
    t = t.replaceAll(RegExp(r'^\s*[·•\-]\s*', multiLine: true), '');
    t = t.replaceAll('「', '').replaceAll('」', '');
    t = t.replaceAll('（', '，').replaceAll('）', '。');
    t = t.replaceAll('*', '');
    return t.trim();
  }

  Future<_AudioPayload> _synthesize(String text, TtsSettings settings) async {
    if (settings.useChatFormat) return _synthesizeChat(text, settings);
    final urls = settings.speechUrls;
    if (urls.isEmpty) throw const LlmException('还没填 Base URL。');

    final tried = <String>[];
    for (final url in urls) {
      http.Response resp;
      try {
        resp = await http
            .post(
              Uri.parse(url),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${settings.apiKey.trim()}',
              },
              body: jsonEncode({
                'model': settings.model.trim(),
                'input': text,
                'voice': settings.voice.trim().isEmpty ? 'alloy' : settings.voice.trim(),
                'response_format': 'mp3',
              }),
            )
            .timeout(const Duration(seconds: 40));
      } on TimeoutException {
        throw const LlmException('语音合成超时了。');
      } catch (e) {
        throw LlmException('连不上语音服务：$e');
      }

      // 404/405 说明这个路径不存在，换下一个候选
      if (resp.statusCode == 404 || resp.statusCode == 405) {
        tried.add(url);
        continue;
      }

      final contentType = resp.headers['content-type'] ?? '';
      if (resp.statusCode != 200 || contentType.contains('application/json')) {
        // 地址通了但被拒（Key、模型、参数问题），直接把服务端的话给用户
        throw LlmException(_errorMessage(resp));
      }
      if (resp.bodyBytes.isEmpty) throw const LlmException('语音服务返回了空音频。');
      final mime = contentType.contains('wav')
          ? 'audio/wav'
          : (contentType.contains('mpeg') || contentType.contains('mp3') ? 'audio/mpeg' : 'audio/mpeg');
      return _AudioPayload(resp.bodyBytes, mime);
    }

    throw LlmException(
      '这些地址都没有语音合成接口：\n${tried.join('\n')}\n\n'
      '如果服务商的路径不在这几个里，把完整接口地址（例如 https://你的域名/v1/audio/xxx）直接填到 Base URL。',
    );
  }

  /// 让用户自己确认一次：当前会依次尝试哪些地址
  List<String> debugUrls(TtsSettings settings) => settings.speechUrls;


  /// MiMo / 通义这类：走 /chat/completions，音频在 choices[0].message.audio.data（base64）
  Future<_AudioPayload> _synthesizeChat(String text, TtsSettings settings) async {
    http.Response resp;
    try {
      resp = await http
          .post(
            Uri.parse(settings.chatUrl),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${settings.apiKey.trim()}',
            },
            body: jsonEncode({
              'model': settings.model.trim(),
              'messages': [
                {'role': 'assistant', 'content': text},
              ],
              'audio': {
                'format': 'wav',
                'voice': settings.voice.trim().isEmpty ? '冰糖' : settings.voice.trim(),
              },
            }),
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw const LlmException('语音合成超时了。');
    } catch (e) {
      throw LlmException('连不上语音服务：$e');
    }

    if (resp.statusCode != 200) throw LlmException(_errorMessage(resp));

    try {
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      final choices = body['choices'];
      if (choices is List && choices.isNotEmpty) {
        final message = (choices.first as Map)['message'];
        final audio = message is Map ? message['audio'] : null;
        final data = audio is Map ? audio['data'] : null;
        if (data is String && data.isNotEmpty) {
          return _AudioPayload(base64Decode(data), 'audio/wav');
        }
      }
    } catch (e) {
      if (e is LlmException) rethrow;
    }
    throw const LlmException('模型没有返回音频。确认模型名是 TTS 模型（例如 mimo-v2.5-tts）。');
  }

  String _errorMessage(http.Response resp) {
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      return 'TTS 的 API Key 无效或没有权限。';
    }
    if (resp.statusCode == 404) {
      return '这个地址没有语音合成接口，检查 Base URL（一般到 /v1 为止）。';
    }
    try {
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is Map) {
        final err = body['error'];
        if (err is Map && err['message'] is String) return '语音合成失败：${err['message']}';
        if (err is String) return '语音合成失败：$err';
      }
    } catch (_) {}
    return '语音合成失败（${resp.statusCode}）。';
  }

  void dispose() {
    _player.dispose();
  }
}
