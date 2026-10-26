import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../data/settings.dart';
import '../llm/llm_client.dart';

/// 语音输入：录一段 → 上传到 OpenAI 兼容的 /audio/transcriptions → 拿回文字。
///
/// 用 m4a/AAC 而不是 wav：同样音质体积小一半，弱网现场更稳。
class AsrService {
  static final AsrService instance = AsrService._();
  AsrService._();

  final AudioRecorder _recorder = AudioRecorder();
  String? _currentPath;
  DateTime? _startedAt;

  bool get isRecording => _currentPath != null;

  /// 已经开始录了多久，用于 UI 上显示秒数
  Duration get elapsed => _startedAt == null
      ? Duration.zero
      : DateTime.now().difference(_startedAt!);

  Future<bool> hasPermission() async {
    try {
      return await _recorder.hasPermission();
    } catch (_) {
      return false;
    }
  }

  Future<void> start() async {
    if (isRecording) return;
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'rg_voice_${DateTime.now().millisecondsSinceEpoch}.wav');
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    _currentPath = path;
    _startedAt = DateTime.now();
  }

  /// 停止并转文字。失败抛 LlmException，文案直接给用户看。
  Future<String> stopAndTranscribe(AsrSettings settings) async {
    final path = _currentPath;
    _currentPath = null;
    _startedAt = null;
    if (path == null) return '';

    String? recorded;
    try {
      recorded = await _recorder.stop();
    } catch (e) {
      throw LlmException('录音停止失败：$e');
    }
    final file = File(recorded ?? path);
    if (!await file.exists() || await file.length() < 2000) {
      throw const LlmException('没录到声音，靠近手机再说一次。');
    }
    // 本地服务允许不带 Key，这里不再拦；真需要 Key 的服务会返回 401，提示更准确

    try {
      return await _upload(file, settings);
    } finally {
      // 临时文件用完就删，不在手机上留录音
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<String> _upload(File file, AsrSettings settings) async {
    if (settings.useChatFormat) return _uploadChat(file, settings);
    final urls = settings.transcriptionUrls;
    if (urls.isEmpty) throw const LlmException('语音识别的 Base URL 没填。');

    final tried = <String>[];
    for (final url in urls) {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme) {
        throw LlmException('语音识别的地址格式不对：$url');
      }

      http.Response resp;
      try {
        final req = http.MultipartRequest('POST', uri)
          ..headers['Authorization'] = 'Bearer ${settings.apiKey.trim()}'
          ..fields['model'] = settings.model.trim();
        if (settings.language.trim().isNotEmpty) {
          req.fields['language'] = settings.language.trim();
        }
        req.files.add(await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: 'audio.wav',
        ));
        final streamed = await req.send().timeout(const Duration(seconds: 60));
        resp = await http.Response.fromStream(streamed);
      } on TimeoutException {
        throw const LlmException('语音识别超时了，网络不好时可以先打字。');
      } catch (e) {
        throw LlmException('连不上语音识别服务：$e');
      }

      // 路径不存在，换下一个候选
      if (resp.statusCode == 404 || resp.statusCode == 405) {
        tried.add(url);
        continue;
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw const LlmException('ASR 的 API Key 无效或没有权限。');
      }
      if (resp.statusCode != 200) {
        throw LlmException('语音识别失败（${resp.statusCode}）：${_brief(resp.body)}');
      }

      try {
        final body = jsonDecode(utf8.decode(resp.bodyBytes));
        if (body is Map && body['text'] is String) {
          final text = (body['text'] as String).trim();
          if (text.isEmpty) throw const LlmException('没听清，再说一次试试。');
          return text;
        }
      } catch (e) {
        if (e is LlmException) rethrow;
      }
      throw const LlmException('语音服务返回的格式不对。');
    }

    throw LlmException(
      '这些地址都没有语音识别接口：\n${tried.join('\n')}\n\n'
      '如果服务商的路径不在这几个里，把完整接口地址（例如 https://你的域名/v1/audio/xxx）直接填到 Base URL。',
    );
  }


  /// MiMo / 通义这类：走 /chat/completions，音频以 data URL 放进 input_audio
  Future<String> _uploadChat(File file, AsrSettings settings) async {
    final bytes = await file.readAsBytes();
    // base64 后上限 10MB，换算成原始音频约 7.5MB，对应 16k 单声道 wav 约 4 分钟
    if (bytes.length > 7 * 1024 * 1024) {
      throw const LlmException('这段录音太长了，分成几句说。');
    }
    final dataUrl = 'data:audio/wav;base64,${base64Encode(bytes)}';

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
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'input_audio',
                      'input_audio': {'data': dataUrl},
                    }
                  ],
                }
              ],
              'asr_options': {
                'language': settings.language.trim().isEmpty ? 'auto' : settings.language.trim(),
              },
            }),
          )
          .timeout(const Duration(seconds: 60));
    } on TimeoutException {
      throw const LlmException('语音识别超时了，网络不好时可以先打字。');
    } catch (e) {
      throw LlmException('连不上语音识别服务：$e');
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw const LlmException('ASR 的 API Key 无效或没有权限。');
    }
    if (resp.statusCode != 200) {
      throw LlmException('语音识别失败（${resp.statusCode}）：${_brief(resp.body)}');
    }

    try {
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      final choices = body['choices'];
      if (choices is List && choices.isNotEmpty) {
        final content = (choices.first as Map)['message']?['content'];
        if (content is String && content.trim().isNotEmpty) return content.trim();
        if (content is List) {
          final text = content
              .map((e) => (e is Map ? (e['text'] ?? '') : '').toString())
              .join()
              .trim();
          if (text.isNotEmpty) return text;
        }
      }
    } catch (e) {
      if (e is LlmException) rethrow;
    }
    throw const LlmException('模型没有返回文字。确认模型名是 ASR 模型（例如 mimo-v2.5-asr）。');
  }

  String _brief(String body) {
    final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length > 120 ? '${t.substring(0, 120)}…' : t;
  }

  Future<void> cancel() async {
    _currentPath = null;
    _startedAt = null;
    try {
      await _recorder.cancel();
    } catch (_) {}
  }

  void dispose() {
    _recorder.dispose();
  }
}
