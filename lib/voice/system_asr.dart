import 'dart:async';

import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../llm/llm_client.dart';
import 'speech_diagnostics.dart';

/// 系统语音识别：直接调 Android 的 SpeechRecognizer（iOS 上对应
/// SFSpeechRecognizer），用的是手机里已经装好的识别服务，不经过本 App 的服务器。
///
/// 和在线识别最大的不同：它不是"录一段音频再上传"，而是边听边转。
/// 所以这里的接口是 start / stop 两段式，中间靠 partial 结果累积。
class SystemAsrService {
  static final SystemAsrService instance = SystemAsrService._();
  SystemAsrService._();

  final SpeechToText _speech = SpeechToText();

  bool _ready = false;
  bool _active = false;
  String _partial = '';
  String _error = '';
  Completer<String>? _done;

  bool get isActive => _active;

  /// 手机里有没有可用的识别服务。
  /// 国产 ROM 上如果被厂商裁掉了识别服务，这里会返回 false。
  Future<bool> available() async {
    if (_ready) return true;
    try {
      _ready = await _speech.initialize(
        onError: (e) {
          _error = e.errorMsg;
        },
        onStatus: (status) {
          // 系统自己判定说完了，也要当结束处理，否则会一直挂着
          if (status == 'done' || status == 'notListening') {
            _finish();
          }
        },
      );
      return _ready;
    } catch (e) {
      _error = '$e';
      return false;
    }
  }


  /// 失败原因。先问原生通道，拿不到再退回笼统说法。
  ///
  /// 之前这里只报「没有可用语音识别服务」，但真实原因可能是权限被拒、
  /// 厂商没注册标准服务、或识别器正被别的 App 占用，提示太笼统会误导。
  Future<String> failureReason() async {
    final raw = _error;
    final support = await SpeechDiagnostics.check();

    if (!support.usable) {
      return '系统里没有可用的语音识别服务。\n\n'
          '${support.describe()}\n\n'
          '${support.verdict}';
    }

    if (raw.contains('permission') || raw.contains('not_allowed')) {
      return '没有录音权限。到 系统设置 → 应用 → LinkMind → 权限，允许麦克风后重试。';
    }
    if (raw.isNotEmpty) {
      return '系统识别启动失败：$raw\n\n${support.describe()}';
    }
    return '系统识别没能启动。\n\n${support.describe()}';
  }

  /// 系统里有哪些识别语言，用于设置页提示
  Future<List<String>> locales() async {
    try {
      final list = await _speech.locales();
      return list.map((l) => l.localeId).toList()..sort();
    } catch (_) {
      return const [];
    }
  }

  /// 开始听。[onDeviceOnly] 为真时强制本机识别，不走云端。
  Future<void> start(String localeId, {bool onDeviceOnly = false}) async {
    if (_active) return;

    if (!await available()) {
      throw LlmException(await failureReason());
    }

    _partial = '';
    _error = '';
    _done = Completer<String>();
    _active = true;

    try {
      await _speech.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          partialResults: true,
          cancelOnError: true,
          onDevice: onDeviceOnly,
          // 说一句停一下的场景用 dictation，比 confirmation 宽松
          listenMode: ListenMode.dictation,
          // 最长 2 分钟，防止误触后一直占着麦克风
          listenFor: const Duration(seconds: 120),
          // 静音 3 秒算说完
          pauseFor: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      _active = false;
      throw LlmException('启动系统识别失败：$e');
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    _partial = result.recognizedWords;
    if (result.finalResult) _finish();
  }

  /// 结束并拿文字。系统已经自己结束时也能直接取到结果。
  Future<String> stop() async {
    if (!_active) {
      final t = _partial.trim();
      _partial = '';
      return t;
    }

    try {
      await _speech.stop();
    } catch (_) {}

    // 停之后系统还要回调最终结果，给它一点时间；拿不到就用最后的 partial
    final text = await _awaitDone();
    _active = false;
    _partial = '';
    _done = null;

    if (text.isEmpty) {
      throw LlmException(
        _error.isEmpty
            ? '没听到内容，靠近手机再说一次。'
            : '没听到内容（$_error）。靠近手机再说一次。',
      );
    }
    return text;
  }

  Future<String> _awaitDone() async {
    final done = _done;
    if (done == null) return _partial.trim();
    if (done.isCompleted) {
      try {
        return await done.future;
      } catch (_) {
        return _partial.trim();
      }
    }
    try {
      return await done.future.timeout(const Duration(seconds: 4));
    } on TimeoutException {
      return _partial.trim();
    }
  }

  void _finish() {
    final done = _done;
    if (done != null && !done.isCompleted) {
      done.complete(_partial.trim());
    }
  }

  Future<void> cancel() async {
    _active = false;
    _partial = '';
    final done = _done;
    if (done != null && !done.isCompleted) done.complete('');
    _done = null;
    try {
      await _speech.cancel();
    } catch (_) {}
  }
}
