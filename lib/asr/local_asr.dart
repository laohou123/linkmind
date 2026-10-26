import 'dart:async';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../data/repository.dart';
import '../llm/llm_client.dart';
import 'asr_model.dart';
import 'hotwords.dart';
import 'model_store.dart';

/// 完全离线的语音识别：手机自己跑模型，不联网、不依赖厂商的识别服务。
///
/// 和系统识别的区别：系统识别由手机厂商实现，本机有没有得看 ROM；
/// 这条路把引擎和模型都攥在自己手里，代价是安装包变大、首次要下模型。
class LocalAsrService {
  static final LocalAsrService instance = LocalAsrService._();
  LocalAsrService._();

  final AudioRecorder _recorder = AudioRecorder();

  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _audioSub;

  bool _active = false;
  String _partial = '';

  // 诊断用：拿不到文字时必须能说清楚卡在哪一步
  int _chunks = 0;
  int _bytes = 0;
  String? _firstError;

  /// 生成热词时的实体指纹，变了就重建识别器
  String? _hotwordKey;

  /// 热词是否真的被引擎接受了（加载失败时会被降级成 false）
  bool _hotwordsApplied = false;
  bool get hotwordsApplied => _hotwordsApplied;

  /// 最近一次识别出的中间结果，可以边录边显示
  String get partial => _partial;
  bool get isActive => _active;

  /// 模型是否已经下载好
  Future<bool> isModelReady() =>
      ModelStore.instance.isReady(AsrModels.zhStreaming);

  /// 库里加了新设备，热词表就过期了。重建识别器比较贵（几秒），
  /// 但只在实体有变化后第一次说话时发生。
  Future<void> _refreshHotwordsIfNeeded() async {
    if (_recognizer == null) return;
    try {
      final names = await GraphRepository.instance.allEntityNames();
      final fp = await HotwordsBuilder.fingerprint(names);
      if (fp != _hotwordKey) reset();
    } catch (_) {
      // 读库失败不影响识别，继续用旧热词
    }
  }

  /// 加载模型。第一次要读 25MB 的 onnx，会卡几秒，调用方应提示「正在准备」。
  Future<void> prepare() async {
    if (_recognizer != null) return;

    final spec = AsrModels.zhStreaming;
    if (!await ModelStore.instance.isReady(spec)) {
      throw const LlmException(
        '离线模型还没下载。设置 → 语音识别 → 离线模型，点「下载」后再用。',
      );
    }

    final dir = await ModelStore.instance.modelDir(spec);
    await sherpa.initBindingsAsync();

    // 把库里已有的设备名做成热词，让模型往这些词上靠。
    // 只保留纯中文片段：模型词表里没有阿拉伯数字和 #，
    // 带编号的整串写进去编码不了，反而整行失效。
    final names = await GraphRepository.instance.allEntityNames();
    final hotwordsFile = await HotwordsBuilder.build(
      tokensPath: p.join(dir.path, spec.files['tokens']!),
      outputPath: HotwordsBuilder.hotwordsPath(dir.path),
      entityNames: names,
    );
    _hotwordKey = await HotwordsBuilder.fingerprint(names);
    final useHotwords = hotwordsFile != null;

    final config = sherpa.OnlineRecognizerConfig(
      model: sherpa.OnlineModelConfig(
        transducer: sherpa.OnlineTransducerModelConfig(
          encoder: p.join(dir.path, spec.files['encoder']!),
          decoder: p.join(dir.path, spec.files['decoder']!),
          joiner: p.join(dir.path, spec.files['joiner']!),
        ),
        tokens: p.join(dir.path, spec.files['tokens']!),
        numThreads: 2,
        debug: false,
        provider: 'cpu',
        // 热词是按建模单元编码的，必须声明成 cjkchar（中文逐字），
        // 否则会按 bpe 去查，查不到就整个识别器创建失败。
        modelingUnit: useHotwords ? 'cjkchar' : '',
      ),
      feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
      // 热词只支持 modified_beam_search，greedy_search 下不生效
      decodingMethod: useHotwords ? 'modified_beam_search' : 'greedy_search',
      // 不自动断句：由用户点麦克风决定什么时候结束
      enableEndpoint: false,
      hotwordsFile: hotwordsFile ?? '',
      // 中文场景 1.5 偏弱，官方示例用 2.0；再高容易把无关的话也扭成热词
      hotwordsScore: 2.0,
    );

    try {
      _recognizer = sherpa.OnlineRecognizer(config);
    } catch (e) {
      // 热词只是锦上添花，格式一旦不被接受就会拖垮整个识别器。
      // 这里退回不带热词再试一次，宁可识别得差一点，也不能完全用不了。
      if (useHotwords) {
        try {
          _recognizer = sherpa.OnlineRecognizer(
            sherpa.OnlineRecognizerConfig(
              model: sherpa.OnlineModelConfig(
                transducer: sherpa.OnlineTransducerModelConfig(
                  encoder: p.join(dir.path, spec.files['encoder']!),
                  decoder: p.join(dir.path, spec.files['decoder']!),
                  joiner: p.join(dir.path, spec.files['joiner']!),
                ),
                tokens: p.join(dir.path, spec.files['tokens']!),
                numThreads: 2,
                debug: false,
                provider: 'cpu',
              ),
              feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 80),
              decodingMethod: 'greedy_search',
              enableEndpoint: false,
            ),
          );
          _hotwordsApplied = false;
          return;
        } catch (_) {
          // 去掉热词还是失败，说明是模型本身的问题，走下面的统一报错
        }
      }
      _recognizer = null;
      throw LlmException(
        '离线模型加载失败：$e\n\n'
        '如果是刚下载完，删掉模型重新下一次（可能下载不完整）。',
      );
    }
    _hotwordsApplied = useHotwords;
  }

  Future<void> start() async {
    if (_active) return;
    await _refreshHotwordsIfNeeded();
    await prepare();

    _partial = '';
    _chunks = 0;
    _bytes = 0;
    _firstError = null;
    _stream = _recognizer!.createStream();

    final audio = await _recorder.startStream(
      const RecordConfig(
        // sherpa 要裸 PCM，不能是压缩过的 aac/wav 容器
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
    );

    _active = true;
    _audioSub = audio.listen(_onAudio, onError: (_) {}, cancelOnError: false);
  }

  void _onAudio(Uint8List chunk) {
    final stream = _stream;
    final recognizer = _recognizer;
    if (stream == null || recognizer == null) return;

    _chunks++;
    _bytes += chunk.length;

    try {
      stream.acceptWaveform(samples: _toFloat32(chunk), sampleRate: 16000);
      while (recognizer.isReady(stream)) {
        recognizer.decode(stream);
      }
      _partial = recognizer.getResult(stream).text.trim();
    } catch (e) {
      // 单块失败不中断整段录音，但要留证据，否则最后只能说"没听到"
      _firstError ??= e.toString();
    }
  }

  /// 结束并取最终文字
  Future<String> stop() async {
    if (!_active) {
      final leftover = _partial.trim();
      _partial = '';
      return leftover;
    }

    _active = false;
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}

    final stream = _stream;
    final recognizer = _recognizer;
    var text = _partial.trim();

    if (stream != null && recognizer != null) {
      try {
        stream.inputFinished();
        while (recognizer.isReady(stream)) {
          recognizer.decode(stream);
        }
        final finalText = recognizer.getResult(stream).text.trim();
        if (finalText.isNotEmpty) text = finalText;
      } catch (_) {
        // 收尾失败就用已经解出来的部分
      }
      try {
        stream.free();
      } catch (_) {}
    }

    _stream = null;
    _partial = '';

    if (text.isEmpty) {
      throw LlmException(_explainEmpty());
    }
    return text;
  }

  /// 没解出文字时，区分是「没收到声音」还是「收到了但没认出来」
  String _explainEmpty() {
    if (_chunks == 0) {
      return '没有收到任何录音数据。\n\n'
          '可能原因：麦克风权限没给，或这台手机的录音器不支持 16kHz 单声道 PCM。\n'
          '先去系统设置里确认 LinkMind 有麦克风权限，再试一次。';
    }
    if (_bytes < 8000) {
      return '只收到 ${(_bytes / 1024).toStringAsFixed(1)}KB 音频，太短了（不到半秒）。\n'
          '说完一句再点停止，别一点就停。';
    }
    final buf = StringBuffer()
      ..write('收到了 ${(_bytes / 1024).toStringAsFixed(0)}KB 音频（$_chunks 段），但没有解出文字。');
    if (_firstError != null) {
      buf.write('\n\n解码报错：$_firstError');
    } else {
      buf.write('\n\n音频进来了、解码也没报错，说明模型没认出来。'
          '可能是模型和环境不匹配，把这段信息发我。');
    }
    return buf.toString();
  }

  Future<void> cancel() async {
    _active = false;
    _partial = '';
    await _audioSub?.cancel();
    _audioSub = null;
    try {
      await _recorder.stop();
    } catch (_) {}
    try {
      _stream?.free();
    } catch (_) {}
    _stream = null;
  }

  /// 换了模型或删了模型后要让识别器重新加载
  void reset() {
    try {
      _stream?.free();
    } catch (_) {}
    try {
      _recognizer?.free();
    } catch (_) {}
    _stream = null;
    _recognizer = null;
  }

  /// 16 位小端 PCM → [-1, 1] 的浮点采样
  Float32List _toFloat32(Uint8List bytes) {
    final count = bytes.length ~/ 2;
    if (count == 0) return Float32List(0);

    // 不能用 bytes.buffer.asInt16List(bytes.offsetInBytes, count)：
    // 录音插件推来的 chunk 是某个大 buffer 上的视图，offsetInBytes 可能是奇数，
    // 而 Int16List 要求 2 字节对齐，遇上奇数偏移直接抛 RangeError，一块都解不出来。
    // 这里按字节手工拼，顺便把字节序写死成小端（AudioRecord 就是这么给的），
    // 不依赖平台字节序。
    final out = Float32List(count);
    for (var i = 0; i < count; i++) {
      final lo = bytes[i * 2];
      final hi = bytes[i * 2 + 1];
      var v = (hi << 8) | lo;
      if (v >= 0x8000) v -= 0x10000;
      out[i] = v / 32768.0;
    }
    return out;
  }
}
