import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// LLM 配置。任何 OpenAI 兼容服务都能接：
/// DeepSeek / 通义 / Kimi / 智谱 / 本地 vLLM / Ollama 的 /v1 接口。
class LlmSettings {
  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;

  const LlmSettings({
    this.baseUrl = 'https://api.deepseek.com/v1',
    this.apiKey = '',
    this.model = 'deepseek-chat',
    this.temperature = 0.1,
  });

  bool get isReady =>
      apiKey.trim().isNotEmpty && baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  String get chatCompletionsUrl => _endpoint('chat/completions');

  /// 兼容用户把 .../v1、.../v1/ 或整条接口地址粘进来的情况
  String _endpoint(String path) {
    var base = baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (base.endsWith('/$path')) return base;
    if (!base.endsWith('/v1') && !base.contains('/v1/')) base = '$base/v1';
    return '$base/$path';
  }

  LlmSettings copyWith({String? baseUrl, String? apiKey, String? model, double? temperature}) {
    return LlmSettings(
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
    );
  }
}

/// 语音合成配置
class TtsSettings {
  final String baseUrl;
  final String apiKey;
  final String model;
  final String voice;
  final VoiceProtocol protocol;

  /// 用手机自带语音引擎（Android TextToSpeech），不联网、不要 Key
  final bool useSystem;

  /// 系统语音的语言，例如 zh-CN / en-US
  final String systemLocale;

  const TtsSettings({
    this.baseUrl = 'https://api.openai.com/v1',
    this.apiKey = '',
    this.model = 'tts-1',
    this.voice = 'alloy',
    this.protocol = VoiceProtocol.auto,
    this.useSystem = true,
    this.systemLocale = 'zh-CN',
  });

  bool get isReady => useSystem || _configured(baseUrl, apiKey, model);

  bool get useChatFormat =>
      protocol == VoiceProtocol.chat ||
      (protocol == VoiceProtocol.auto && _looksLikeChatFormat(baseUrl, model));

  /// OpenAI 标准的候选地址
  List<String> get speechUrls =>
      endpointsFor(baseUrl, const ['audio/speech', 'audio/tts', 'tts', 'speech']);

  /// Chat 格式（MiMo 等）统一打到 /chat/completions
  String get chatUrl => chatCompletionsUrlOf(baseUrl);

  TtsSettings copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    String? voice,
    VoiceProtocol? protocol,
    bool? useSystem,
    String? systemLocale,
  }) =>
      TtsSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        voice: voice ?? this.voice,
        protocol: protocol ?? this.protocol,
        useSystem: useSystem ?? this.useSystem,
        systemLocale: systemLocale ?? this.systemLocale,
      );
}

/// 语音识别的三条路
enum AsrEngine {
  /// 手机自带的识别服务（SpeechRecognizer），有没有得看 ROM
  system('手机内置'),

  /// App 自己带模型跑，真正的离线
  offline('离线模型'),

  /// 走 OpenAI 兼容接口
  online('在线接口');

  const AsrEngine(this.label);
  final String label;
}

/// 语音识别配置
class AsrSettings {
  final String baseUrl;
  final String apiKey;
  final String model;

  /// 留空表示由模型自动判断语种
  final String language;
  final VoiceProtocol protocol;

  /// 识别方式。默认走手机内置，其次离线模型，再次在线接口。
  final AsrEngine engine;

  /// 系统识别的语言，例如 zh-CN
  final String systemLocale;

  /// 系统识别时强制本机完成，不把音频送到云端
  final bool onDeviceOnly;

  const AsrSettings({
    this.baseUrl = 'https://api.openai.com/v1',
    this.apiKey = '',
    this.model = 'whisper-1',
    this.language = 'zh',
    this.protocol = VoiceProtocol.auto,
    this.engine = AsrEngine.system,
    this.systemLocale = 'zh-CN',
    this.onDeviceOnly = false,
  });

  /// 手机自带识别
  bool get useSystem => engine == AsrEngine.system;

  /// 自带模型离线识别
  bool get useOffline => engine == AsrEngine.offline;

  /// 不需要联网填 Key 的两种方式都算配好了
  bool get isReady =>
      engine != AsrEngine.online || _configured(baseUrl, apiKey, model);

  bool get useChatFormat =>
      protocol == VoiceProtocol.chat ||
      (protocol == VoiceProtocol.auto && _looksLikeChatFormat(baseUrl, model));

  List<String> get transcriptionUrls =>
      endpointsFor(baseUrl, const ['audio/transcriptions', 'audio/transcribe', 'audio/asr', 'asr']);

  String get chatUrl => chatCompletionsUrlOf(baseUrl);

  AsrSettings copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    String? language,
    VoiceProtocol? protocol,
    AsrEngine? engine,
    String? systemLocale,
    bool? onDeviceOnly,
  }) =>
      AsrSettings(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        language: language ?? this.language,
        protocol: protocol ?? this.protocol,
        engine: engine ?? this.engine,
        systemLocale: systemLocale ?? this.systemLocale,
        onDeviceOnly: onDeviceOnly ?? this.onDeviceOnly,
      );
}

/// 是否配置完整。
/// 本地跑的服务（Ollama / GPT-SoVITS / faster-whisper）通常不要 Key，
/// 所以只要地址是内网/本机，Key 留空也算配好，否则会被误判成"未配置"。
bool _configured(String baseUrl, String apiKey, String model) {
  final url = baseUrl.trim();
  if (url.isEmpty || model.trim().isEmpty) return false;
  if (apiKey.trim().isNotEmpty) return true;
  final lower = url.toLowerCase();
  return lower.contains('127.0.0.1') ||
      lower.contains('localhost') ||
      lower.contains('0.0.0.0') ||
      lower.contains('192.168.') ||
      lower.contains('10.') ||
      lower.contains('172.16.') ||
      lower.startsWith('http://');
}



String chatCompletionsUrlOf(String baseUrl) {
  var base = baseUrl.trim();
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  if (base.endsWith('/chat/completions')) return base;
  if (!RegExp(r'/v\d+(/|$)').hasMatch(base)) base = '$base/v1';
  return '$base/chat/completions';
}

/// 生成候选接口地址。
///
/// 不能无脑给 Base URL 补 /v1：服务商路径五花八门
/// （/v1、/api/paas/v4、/compatible-mode/v1、/audio/tts…），补错就 404。
/// 所以这里把几种常见路径都列出来，让调用方逐个试，最后把试过的地址告诉用户。
List<String> endpointsFor(String baseUrl, List<String> paths) {
  final raw = baseUrl.trim();
  if (raw.isEmpty) return const [];
  var base = raw;
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  // 用户直接把完整接口地址粘进来了，就只用它，不再拼接
  if (base.contains('/audio/') || base.endsWith('/tts') || base.endsWith('/asr')) {
    return [base];
  }
  final hasVersion = RegExp(r'/v\d+(/|$)').hasMatch(base);
  final out = <String>[];
  for (final path in paths) {
    out.add('$base/$path');
    if (!hasVersion) out.add('$base/v1/$path');
  }
  return out;
}


/// 语音接口协议。
/// OpenAI 用 /audio/speech 与 /audio/transcriptions；
/// 小米 MiMo、通义等把音频塞进 /chat/completions，字段完全不同。
enum VoiceProtocol {
  auto('自动'),
  openai('OpenAI 标准'),
  chat('Chat 格式');

  const VoiceProtocol(this.label);
  final String label;
}

bool _looksLikeChatFormat(String baseUrl, String model) {
  final b = baseUrl.toLowerCase();
  final m = model.toLowerCase();
  return b.contains('xiaomimimo') ||
      b.contains('dashscope') ||
      m.startsWith('mimo') ||
      m.contains('cosyvoice') ||
      m.contains('sensevoice');
}

AsrEngine _parseAsrEngine(String? raw, bool? legacyUseSystem) {
  switch (raw) {
    case 'system':
      return AsrEngine.system;
    case 'offline':
      return AsrEngine.offline;
    case 'online':
      return AsrEngine.online;
    default:
      // 老版本只存了「是否用系统识别」这一个布尔
      return (legacyUseSystem ?? true) ? AsrEngine.system : AsrEngine.online;
  }
}

VoiceProtocol _parseProtocol(String? raw) {
  switch (raw) {
    case 'openai':
      return VoiceProtocol.openai;
    case 'chat':
      return VoiceProtocol.chat;
    default:
      return VoiceProtocol.auto;
  }
}

class SettingsStore {
  static final SettingsStore instance = SettingsStore._();
  SettingsStore._();

  static const _kBaseUrl = 'llm_base_url';
  static const _kModel = 'llm_model';
  static const _kTemperature = 'llm_temperature';
  static const _kApiKey = 'llm_api_key';

  static const _kTtsBaseUrl = 'tts_base_url';
  static const _kTtsModel = 'tts_model';
  static const _kTtsVoice = 'tts_voice';
  static const _kTtsProtocol = 'tts_protocol';
  static const _kTtsUseSystem = 'tts_use_system';
  static const _kTtsSystemLocale = 'tts_system_locale';
  static const _kTtsKey = 'tts_api_key';

  static const _kAsrBaseUrl = 'asr_base_url';
  static const _kAsrModel = 'asr_model';
  static const _kAsrLanguage = 'asr_language';
  static const _kAsrProtocol = 'asr_protocol';
  static const _kAsrUseSystem = 'asr_use_system';
  static const _kAsrEngine = 'asr_engine';
  static const _kAsrSystemLocale = 'asr_system_locale';
  static const _kAsrOnDevice = 'asr_on_device';

  /// v1.10.1 起默认改用手机内置语音，老配置做一次迁移
  static const _kVoiceDefaultMigrated = 'voice_default_migrated';
  static const _kAsrKey = 'asr_api_key';

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  LlmSettings _cached = const LlmSettings();
  TtsSettings _ttsCached = const TtsSettings();
  AsrSettings _asrCached = const AsrSettings();

  LlmSettings get cached => _cached;
  TtsSettings get ttsCached => _ttsCached;
  AsrSettings get asrCached => _asrCached;

  Future<String> _readKey(String key) async {
    try {
      return await _secure.read(key: key) ?? '';
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key) ?? '';
    }
  }

  Future<void> _writeKey(String key, String value) async {
    try {
      await _secure.write(key: key, value: value);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    }
  }

  Future<LlmSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    _cached = LlmSettings(
      baseUrl: prefs.getString(_kBaseUrl) ?? 'https://api.deepseek.com/v1',
      apiKey: await _readKey(_kApiKey),
      model: prefs.getString(_kModel) ?? 'deepseek-chat',
      temperature: prefs.getDouble(_kTemperature) ?? 0.1,
    );
    _ttsCached = TtsSettings(
      baseUrl: prefs.getString(_kTtsBaseUrl) ?? 'https://api.openai.com/v1',
      apiKey: await _readKey(_kTtsKey),
      model: prefs.getString(_kTtsModel) ?? 'tts-1',
      voice: prefs.getString(_kTtsVoice) ?? 'alloy',
      protocol: _parseProtocol(prefs.getString(_kTtsProtocol)),
      useSystem: prefs.getBool(_kTtsUseSystem) ?? true,
      systemLocale: prefs.getString(_kTtsSystemLocale) ?? 'zh-CN',
    );
    _asrCached = AsrSettings(
      baseUrl: prefs.getString(_kAsrBaseUrl) ?? 'https://api.openai.com/v1',
      apiKey: await _readKey(_kAsrKey),
      model: prefs.getString(_kAsrModel) ?? 'whisper-1',
      language: prefs.getString(_kAsrLanguage) ?? 'zh',
      protocol: _parseProtocol(prefs.getString(_kAsrProtocol)),
      engine: _parseAsrEngine(
        prefs.getString(_kAsrEngine),
        prefs.getBool(_kAsrUseSystem),
      ),
      systemLocale: prefs.getString(_kAsrSystemLocale) ?? 'zh-CN',
      onDeviceOnly: prefs.getBool(_kAsrOnDevice) ?? false,
    );
    await _migrateVoiceDefault(prefs);
    return _cached;
  }

  /// 老版本默认走在线接口，升级后把「用手机内置」打开一次。
  ///
  /// 只做一次：用户之后再手动关掉就不会被反复改回来。
  /// 在线接口的地址、Key、模型都不动，随时能在设置里切回去。
  Future<void> _migrateVoiceDefault(SharedPreferences prefs) async {
    if (prefs.getBool(_kVoiceDefaultMigrated) ?? false) return;

    final ttsLocale = _ttsCached.systemLocale.trim().isEmpty
        ? 'zh-CN'
        : _ttsCached.systemLocale;
    final asrLocale = _asrCached.systemLocale.trim().isEmpty
        ? 'zh-CN'
        : _asrCached.systemLocale;

    _ttsCached = _ttsCached.copyWith(useSystem: true, systemLocale: ttsLocale);
    _asrCached = _asrCached.copyWith(engine: AsrEngine.system, systemLocale: asrLocale);

    await prefs.setBool(_kTtsUseSystem, true);
    await prefs.setBool(_kAsrUseSystem, true);
    await prefs.setString(_kAsrEngine, AsrEngine.system.name);
    await prefs.setBool(_kVoiceDefaultMigrated, true);
  }

  Future<void> save(LlmSettings value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, value.baseUrl.trim());
    await prefs.setString(_kModel, value.model.trim());
    await prefs.setDouble(_kTemperature, value.temperature);
    await _writeKey(_kApiKey, value.apiKey);
    _cached = value;
  }

  Future<void> saveTts(TtsSettings value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTtsBaseUrl, value.baseUrl.trim());
    await prefs.setString(_kTtsModel, value.model.trim());
    await prefs.setString(_kTtsVoice, value.voice.trim());
    await prefs.setString(_kTtsProtocol, value.protocol.name);
    await prefs.setBool(_kTtsUseSystem, value.useSystem);
    await prefs.setString(_kTtsSystemLocale, value.systemLocale.trim().isEmpty ? 'zh-CN' : value.systemLocale.trim());
    await _writeKey(_kTtsKey, value.apiKey);
    _ttsCached = value;
  }

  Future<void> saveAsr(AsrSettings value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAsrBaseUrl, value.baseUrl.trim());
    await prefs.setString(_kAsrModel, value.model.trim());
    await prefs.setString(_kAsrLanguage, value.language.trim());
    await prefs.setString(_kAsrProtocol, value.protocol.name);
    await prefs.setString(_kAsrEngine, value.engine.name);
    await prefs.setBool(_kAsrUseSystem, value.useSystem);
    await prefs.setString(
        _kAsrSystemLocale,
        value.systemLocale.trim().isEmpty ? 'zh-CN' : value.systemLocale.trim());
    await prefs.setBool(_kAsrOnDevice, value.onDeviceOnly);
    await _writeKey(_kAsrKey, value.apiKey);
    _asrCached = value;
  }
}
