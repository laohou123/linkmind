import 'dart:async';
import '../data/apk_installer.dart';
import '../data/update_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:file_selector/file_selector.dart';
import 'package:share_plus/share_plus.dart';
import '../data/backup.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../asr/asr_model.dart';
import '../asr/local_asr.dart';
import '../asr/model_store.dart';
import '../data/settings.dart';
import '../llm/llm_client.dart';
import '../voice/asr_service.dart';
import '../voice/speech_diagnostics.dart';
import '../voice/system_asr.dart';
import '../voice/tts_service.dart';
import 'theme.dart';

enum ModelKind {
  llm('大语言模型', 'LLM · 理解你说的话、抽出关系'),
  tts('语音合成', 'TTS · 把回答读出来'),
  asr('语音识别', 'ASR · 说话代替打字');

  const ModelKind(this.title, this.subtitle);
  final String title;
  final String subtitle;
}

/// 设置首页：三类模型各一个入口，点进去单独配
/// 一处维护，别再出现「设置页写 1.3.1、安装包是 1.12.x」这种事
const appVersion = '1.13.7';

class SettingsScreen extends StatelessWidget {
  final AppState state;
  const SettingsScreen({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('设置',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      // 监听状态：保存完返回时，列表上的"未配置/已配置"要立刻变
      body: AnimatedBuilder(
        animation: state,
        builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          _sectionLabel('模型配置'),
          _modelTile(
            context,
            ModelKind.llm,
            state.settings.isReady ? state.settings.model : '未配置',
            state.settings.isReady,
          ),
          const SizedBox(height: 10),
          _modelTile(
            context,
            ModelKind.tts,
            state.tts.useSystem
                ? '手机内置语音 · ${state.tts.systemLocale}'
                : (state.tts.isReady ? '${state.tts.model} · ${state.tts.voice}' : '未配置'),
            state.tts.isReady,
          ),
          const SizedBox(height: 10),
          _modelTile(
            context,
            ModelKind.asr,
            switch (state.asr.engine) {
              AsrEngine.system => '手机内置识别 · ${state.asr.systemLocale}',
              AsrEngine.offline => '离线模型 · 本地推理',
              AsrEngine.online =>
                state.asr.isReady ? state.asr.model : '未配置',
            },
            state.asr.isReady,
          ),
          const SizedBox(height: 12),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '三个模型互相独立，可以填不同的服务商。LLM 是必填项；TTS 和 ASR 用于语音播报与语音输入，先配好即可。',
              style: TextStyle(fontSize: 11, color: AppColors.textFaint, height: 1.6),
            ),
          ),
          const SizedBox(height: 32),
          _sectionLabel('数据'),
          const SizedBox(height: 6),
          const Text(
            '所有关系都只存在这台手机上，不上传服务器。卸载 App 会连数据一起删除，重要数据请另外留底。',
            style: TextStyle(fontSize: 12, color: AppColors.textFaint, height: 1.6),
          ),
          const SizedBox(height: 14),
          _infoRow('设备数', '${(state.graph['nodes'] as List?)?.length ?? 0} 个'),
          _infoRow('版本', appVersion),
          const SizedBox(height: 16),
          _BackupPanel(state: state),
          const SizedBox(height: 28),
          _sectionLabel('关于'),
          const SizedBox(height: 4),
          const _UpdatePanel(),
        ],
        ),
      ),
    );
  }

  Widget _modelTile(BuildContext context, ModelKind kind, String summary, bool ready) {
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ModelConfigScreen(kind: kind, state: state)),
      ),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                switch (kind) {
                  ModelKind.llm => Icons.psychology_outlined,
                  ModelKind.tts => Icons.record_voice_over_outlined,
                  ModelKind.asr => Icons.mic_none_outlined,
                },
                size: 19,
                color: ready ? AppColors.accent : AppColors.textFaint,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kind.title,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.text, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 3),
                  Text(
                    ready ? summary : kind.subtitle,
                    style: const TextStyle(fontSize: 11, color: AppColors.textFaint),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: ready ? AppColors.success : AppColors.border,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textFaint),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 11, color: AppColors.accent, letterSpacing: 1.2)),
      );

  Widget _infoRow(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(k, style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
            Text(v, style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
          ],
        ),
      );
}

/// 单个模型的配置页
class ModelConfigScreen extends StatefulWidget {
  final ModelKind kind;
  final AppState state;

  const ModelConfigScreen({super.key, required this.kind, required this.state});

  @override
  State<ModelConfigScreen> createState() => _ModelConfigScreenState();
}

class _ModelConfigScreenState extends State<ModelConfigScreen> {
  late final TextEditingController _baseUrl;
  late final TextEditingController _apiKey;
  late final TextEditingController _model;
  late final TextEditingController _extra; // TTS: 音色；ASR: 语种
  late final TextEditingController _systemLocale; // 本地语音的语言
  double _temperature = 0.1;

  bool _testing = false;
  String? _testResult;
  bool _testOk = false;
  bool _obscure = true;

  // 音色列表
  bool _fetchingVoices = false;
  List<String> _voices = const [];
  bool _voicesFromServer = false;
  String? _voiceNote;

  // 语音自检
  bool _speechTesting = false;
  String? _ttsResult;
  bool _ttsOk = false;

  VoiceProtocol _protocol = VoiceProtocol.auto;
  bool _useSystem = false; // TTS 用
  AsrEngine _engine = AsrEngine.system; // ASR 用
  bool _onDeviceOnly = false;
  bool _diagBusy = false;

  // 离线模型
  bool _dlBusy = false;
  double _dlProgress = 0;
  String _dlStage = '';
  bool _modelReady = false;
  int _modelBytes = 0;
  String? _diagText;
  bool _diagOk = false;

  bool _recTesting = false;
  bool _asrBusy = false;
  String? _asrResult;
  bool _asrOk = false;

  static const _llmPresets = [
    _Preset('DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat'),
    _Preset('通义千问', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-plus'),
    _Preset('Kimi', 'https://api.moonshot.cn/v1', 'moonshot-v1-8k'),
    _Preset('智谱', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4-flash'),
    _Preset('本机 Ollama', 'http://127.0.0.1:11434/v1', 'qwen2.5:7b'),
  ];

  @override
  void initState() {
    super.initState();
    _systemLocale = TextEditingController(text: widget.state.tts.systemLocale);
    if (widget.kind == ModelKind.asr) {
      _refreshModel();
    }
    switch (widget.kind) {
      case ModelKind.llm:
        final s = widget.state.settings;
        _baseUrl = TextEditingController(text: s.baseUrl);
        _apiKey = TextEditingController(text: s.apiKey);
        _model = TextEditingController(text: s.model);
        _extra = TextEditingController();
        _temperature = s.temperature;
        break;
      case ModelKind.tts:
        final s = widget.state.tts;
        _baseUrl = TextEditingController(text: s.baseUrl);
        _apiKey = TextEditingController(text: s.apiKey);
        _model = TextEditingController(text: s.model);
        _extra = TextEditingController(text: s.voice);
        _protocol = s.protocol;
        _useSystem = s.useSystem;
        break;
      case ModelKind.asr:
        final s = widget.state.asr;
        _baseUrl = TextEditingController(text: s.baseUrl);
        _apiKey = TextEditingController(text: s.apiKey);
        _model = TextEditingController(text: s.model);
        _extra = TextEditingController(text: s.language);
        _protocol = s.protocol;
        _engine = s.engine;
        _onDeviceOnly = s.onDeviceOnly;
        break;
    }
  }

  @override
  void dispose() {
    // 离开页面时别把录音和播放留在后台
    if (_recTesting) AsrService.instance.cancel();
    TtsService.instance.stop();
    _baseUrl.dispose();
    _apiKey.dispose();
    _model.dispose();
    _extra.dispose();
    _systemLocale.dispose();
    super.dispose();
  }

  String get _extraLabel => switch (widget.kind) {
        ModelKind.llm => '',
        ModelKind.tts => '音色',
        ModelKind.asr => '语种',
      };

  String get _extraHint => switch (widget.kind) {
        ModelKind.llm => '',
        ModelKind.tts => 'alloy / echo / fable / onyx / nova / shimmer',
        ModelKind.asr => 'zh / en，留空自动判断',
      };


  /// 一键填好整组参数：地址、模型、协议（音色）
  Widget _audioPresets() {
    return Wrap(
      spacing: 8,
      children: [
        _presetChip('小米 MiMo', () {
          setState(() {
            _baseUrl.text = 'https://api.xiaomimimo.com/v1';
            _model.text = widget.kind == ModelKind.tts ? 'mimo-v2.5-tts' : 'mimo-v2.5-asr';
            _protocol = VoiceProtocol.chat;
            if (widget.kind == ModelKind.tts && _extra.text.trim().isEmpty) {
              _extra.text = '冰糖';
            }
          });
        }),
        _presetChip('OpenAI 官方', () {
          setState(() {
            _baseUrl.text = 'https://api.openai.com/v1';
            _model.text = widget.kind == ModelKind.tts ? 'tts-1' : 'whisper-1';
            _protocol = VoiceProtocol.openai;
            if (widget.kind == ModelKind.tts && _extra.text.trim().isEmpty) {
              _extra.text = 'alloy';
            }
          });
        }),
      ],
    );
  }

  Widget _presetChip(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
      ),
    );
  }

  Widget _protocolRow() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: VoiceProtocol.values.map((p) {
        final selected = _protocol == p;
        return GestureDetector(
          onTap: () => setState(() => _protocol = p),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? AppColors.accent.withAlpha(30) : AppColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: selected ? AppColors.accent : AppColors.border),
            ),
            child: Text(
              p.label,
              style: TextStyle(
                fontSize: 12,
                color: selected ? AppColors.accent : AppColors.textSub,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// 很多 OpenAI 兼容服务并没有"列音色"接口，所以先试探，
  /// 探不到就把通用音色摆出来，同时如实告诉用户是本地兜底。
  Future<void> _fetchVoices() async {
    setState(() {
      _fetchingVoices = true;
      _voiceNote = null;
    });

    final probe = TtsSettings(
      baseUrl: _baseUrl.text,
      apiKey: _apiKey.text,
      model: _model.text,
      voice: _extra.text,
      protocol: _protocol,
    );
    if (probe.useChatFormat) {
      setState(() {
        _voices = TtsService.chatVoices;
        _voicesFromServer = false;
        _fetchingVoices = false;
        _voiceNote = 'Chat 格式没有统一的音色接口，下面是小米 MiMo 的预置音色';
      });
      return;
    }

    try {
      final list = await TtsService.instance.fetchVoices(probe);
      setState(() {
        if (list != null && list.isNotEmpty) {
          _voices = list;
          _voicesFromServer = true;
          _voiceNote = '已从服务端读到 ${list.length} 个音色';
        } else {
          _voices = TtsService.builtinVoices;
          _voicesFromServer = false;
          _voiceNote = '这个服务没有提供音色列表，下面是通用音色，音色名也可以直接手填';
        }
      });
    } on LlmException catch (e) {
      setState(() {
        _voices = TtsService.builtinVoices;
        _voicesFromServer = false;
        _voiceNote = '${e.message}（下面是通用音色）';
      });
    } catch (e) {
      setState(() {
        _voices = TtsService.builtinVoices;
        _voicesFromServer = false;
        _voiceNote = '获取失败：$e（下面是通用音色）';
      });
    } finally {
      if (mounted) setState(() => _fetchingVoices = false);
    }
  }

  Widget _voicePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _fetchingVoices ? null : _fetchVoices,
          icon: _fetchingVoices
              ? const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textFaint),
                )
              : const Icon(Icons.download_outlined, size: 15),
          label: Text(_fetchingVoices ? '正在获取…' : '一键获取可用音色'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.accent,
            side: BorderSide(color: AppColors.accent.withAlpha(90)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
        if (_voiceNote != null) ...[
          const SizedBox(height: 8),
          Text(
            _voiceNote!,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              color: _voicesFromServer ? AppColors.success : AppColors.textFaint,
            ),
          ),
        ],
        if (_voices.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _voices.map((v) {
              final selected = _extra.text.trim() == v;
              return GestureDetector(
                onTap: () => setState(() => _extra.text = v),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accent.withAlpha(30) : AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: selected ? AppColors.accent : AppColors.border),
                  ),
                  child: Text(
                    v,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: selected ? AppColors.accent : AppColors.textSub,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final reply = await LlmClient.instance.testConnection(LlmSettings(
        baseUrl: _baseUrl.text,
        apiKey: _apiKey.text,
        model: _model.text,
      ));
      setState(() {
        _testOk = true;
        _testResult = '连接正常，模型回了：「$reply」';
      });
    } on LlmException catch (e) {
      setState(() {
        _testOk = false;
        _testResult = e.message;
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = '连接失败：$e';
      });
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    switch (widget.kind) {
      case ModelKind.llm:
        await widget.state.saveSettings(LlmSettings(
          baseUrl: _baseUrl.text,
          apiKey: _apiKey.text,
          model: _model.text,
          temperature: _temperature,
        ));
        break;
      case ModelKind.tts:
        await widget.state.saveTts(TtsSettings(
          baseUrl: _baseUrl.text,
          apiKey: _apiKey.text,
          model: _model.text,
          voice: _extra.text.trim().isEmpty ? 'alloy' : _extra.text.trim(),
          protocol: _protocol,
          useSystem: _useSystem,
          systemLocale: _systemLocale.text.trim().isEmpty ? 'zh-CN' : _systemLocale.text.trim(),
        ));
        break;
      case ModelKind.asr:
        await widget.state.saveAsr(AsrSettings(
          baseUrl: _baseUrl.text,
          apiKey: _apiKey.text,
          model: _model.text,
          language: _extra.text.trim(),
          protocol: _protocol,
          engine: _engine,
          systemLocale: _systemLocale.text.trim().isEmpty
              ? 'zh-CN'
              : _systemLocale.text.trim(),
          onDeviceOnly: _onDeviceOnly,
        ));
        break;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.kind.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Text(
            widget.kind.subtitle,
            style: const TextStyle(fontSize: 12, color: AppColors.textFaint, height: 1.6),
          ),
          const SizedBox(height: 16),
          if (widget.kind == ModelKind.llm) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _llmPresets
                  .map((p) => GestureDetector(
                        onTap: () => setState(() {
                          _baseUrl.text = p.baseUrl;
                          _model.text = p.model;
                        }),
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(p.name,
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSub)),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 18),
          ],
          if (widget.kind == ModelKind.asr) ...[
            _enginePicker(),
            const SizedBox(height: 18),
          ],
          if (widget.kind == ModelKind.tts) ...[
            _systemSwitch(),
            const SizedBox(height: 18),
          ],
          if (widget.kind == ModelKind.llm ||
              (widget.kind == ModelKind.tts && !_useSystem) ||
              (widget.kind == ModelKind.asr && _engine == AsrEngine.online)) ...[
          if (widget.kind != ModelKind.llm) ...[
            _audioPresets(),
            const SizedBox(height: 16),
          ],
          _field('Base URL', _baseUrl, _baseUrlHint),
          if (widget.kind != ModelKind.llm) ...[
            const SizedBox(height: 12),
            const Text('接口协议',
                style: TextStyle(fontSize: 12, color: AppColors.textSub)),
            const SizedBox(height: 8),
            _protocolRow(),
            const SizedBox(height: 6),
            Text(
              _protocol == VoiceProtocol.chat
                  ? '走 /chat/completions，音频放在 audio / input_audio 字段里（小米 MiMo、通义等）。'
                  : _protocol == VoiceProtocol.openai
                      ? '走标准音频接口：合成 /audio/speech，识别 /audio/transcriptions。'
                      : '自动判断：模型名带 mimo 或地址是小米/通义时走 Chat 格式，其余走标准接口。',
              style: const TextStyle(fontSize: 10, color: AppColors.textFaint, height: 1.5),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _apiKey,
            obscureText: _obscure,
            style: const TextStyle(fontSize: 13, color: AppColors.text),
            decoration: _decoration('API Key', hint: 'sk-…').copyWith(
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility,
                    size: 17, color: AppColors.textFaint),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text('Key 存在手机系统加密存储里，不写日志、不进备份。',
                style: TextStyle(fontSize: 10, color: AppColors.textFaint)),
          ),
          const SizedBox(height: 14),
          _field('模型名', _model, _modelHint),
          if (widget.kind == ModelKind.tts) ...[
            const SizedBox(height: 14),
            _field(_extraLabel, _extra, _extraHint),
            const SizedBox(height: 10),
            _voicePicker(),
            const SizedBox(height: 14),
            _testAction(
              label: _speechTesting ? '正在合成并播放…' : '试听一句',
              icon: _speechTesting ? null : Icons.play_circle_outline,
              busy: _speechTesting,
              onTap: _speechTesting ? null : _testTts,
            ),
            if (_ttsResult != null) _testBanner(_ttsResult!, _ttsOk),
          ] else if (widget.kind == ModelKind.asr) ...[
            const SizedBox(height: 14),
            _field(_extraLabel, _extra, _extraHint),
            const SizedBox(height: 14),
            _testAction(
              label: _recTesting
                  ? '录音中，点一下结束并识别'
                  : (_asrBusy ? '正在识别…' : '试说一句'),
              icon: _recTesting
                  ? Icons.stop_circle_outlined
                  : (_asrBusy ? null : Icons.mic_none),
              busy: _asrBusy,
              danger: _recTesting,
              onTap: _asrBusy ? null : _testAsr,
            ),
            if (_asrResult != null) _testBanner(_asrResult!, _asrOk),
          ],
          ] else if (widget.kind == ModelKind.asr && _engine == AsrEngine.offline) ...[
            const SizedBox(height: 4),
            _offlineModelCard(),
          ] else ...[
            const SizedBox(height: 4),
            _field('语言', _systemLocale,
                widget.kind == ModelKind.tts ? 'zh-CN / en-US' : 'zh-CN / yue-HK'),
            const SizedBox(height: 6),
            Text(
              widget.kind == ModelKind.tts
                  ? '用手机自带的语音引擎：离线、不耗流量、不花钱。中文一般填 zh-CN。'
                      '没声音时，去 系统设置 → 语言与输入 → 文字转语音，装一个中文语音引擎。'
                  : '用手机里已装的语音识别服务，不经过本 App 的服务器，也不填 Key。'
                      '中文一般填 zh-CN。识别准不准取决于手机自带的语音服务。',
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textFaint, height: 1.5),
            ),
            if (widget.kind == ModelKind.asr) ...[
              const SizedBox(height: 12),
              _onDeviceSwitch(),
              const SizedBox(height: 10),
              _diagnoseRow(),
              if (_diagText != null) _diagBanner(),
            ],
            const SizedBox(height: 16),
            _testAction(
              label: widget.kind == ModelKind.tts
                  ? (_speechTesting ? '正在播放…' : '试听一句')
                  : (_recTesting
                      ? '录音中，点一下结束并识别'
                      : (_asrBusy ? '正在识别…' : '试说一句')),
              icon: widget.kind == ModelKind.tts
                  ? (_speechTesting ? null : Icons.play_circle_outline)
                  : (_recTesting
                      ? Icons.stop_circle_outlined
                      : (_asrBusy ? null : Icons.mic_none)),
              busy: widget.kind == ModelKind.tts ? _speechTesting : _asrBusy,
              danger: widget.kind == ModelKind.asr && _recTesting,
              onTap: widget.kind == ModelKind.tts
                  ? (_speechTesting ? null : _testTts)
                  : (_asrBusy ? null : _testAsr),
            ),
            if (widget.kind == ModelKind.tts && _ttsResult != null)
              _testBanner(_ttsResult!, _ttsOk),
            if (widget.kind == ModelKind.asr && _asrResult != null)
              _testBanner(_asrResult!, _asrOk),
          ],
          if (widget.kind == ModelKind.llm) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                const Text('温度', style: TextStyle(fontSize: 12, color: AppColors.textSub)),
                const SizedBox(width: 10),
                Text(_temperature.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 12, color: AppColors.accent)),
                Expanded(
                  child: Slider(
                    value: _temperature,
                    min: 0,
                    max: 1,
                    divisions: 10,
                    activeColor: AppColors.accent,
                    inactiveColor: AppColors.border,
                    onChanged: (v) => setState(() => _temperature = v),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text('抽取关系建议保持 0～0.2，高了模型容易自由发挥。',
                  style: TextStyle(fontSize: 10, color: AppColors.textFaint)),
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              if (widget.kind == ModelKind.llm) ...[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _testing ? null : _test,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSub,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _testing
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.textFaint),
                          )
                        : const Text('测试连接'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: widget.kind == ModelKind.llm ? 2 : 1,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: const Color(0xFF04202E),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('保存',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_testOk ? AppColors.success : AppColors.danger).withAlpha(20),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: (_testOk ? AppColors.success : AppColors.danger).withAlpha(70)),
              ),
              child: Text(
                _testResult!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: _testOk ? AppColors.success : AppColors.danger,
                ),
              ),
            ),
          ],
          if (widget.kind != ModelKind.llm) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                widget.kind == ModelKind.tts
                    ? '配好后，每次回答会自动语音播报；回答面板右上角的喇叭可以随时静音或重播。'
                    : '配好后，输入框右边的麦克风可以录一句话直接识别成文字并发送。',
                style: const TextStyle(fontSize: 11, color: AppColors.textFaint, height: 1.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------- 语音自检（就地验证）

  /// 用当前表单里的值直接合成一句，验证地址/Key/模型/音色是否都对
  Future<void> _testTts() async {
    setState(() {
      _speechTesting = true;
      _ttsResult = null;
    });
    try {
      await TtsService.instance.speak(
        '关系图谱语音已就绪。',
        TtsSettings(
          baseUrl: _baseUrl.text,
          apiKey: _apiKey.text,
          model: _model.text,
          voice: _extra.text.trim().isEmpty ? 'alloy' : _extra.text.trim(),
          protocol: _protocol,
          useSystem: _useSystem,
          systemLocale: _systemLocale.text.trim().isEmpty ? 'zh-CN' : _systemLocale.text.trim(),
        ),
      );
      setState(() {
        _ttsOk = true;
        _ttsResult = '播放完成。地址、Key、模型和音色都对。';
      });
    } on LlmException catch (e) {
      setState(() {
        _ttsOk = false;
        _ttsResult = e.message;
      });
    } catch (e) {
      setState(() {
        _ttsOk = false;
        _ttsResult = '播放失败：$e';
      });
    } finally {
      if (mounted) setState(() => _speechTesting = false);
    }
  }

  /// 点一下开始录，再点一下结束并识别，结果直接显示在页面上
  Future<void> _testAsr() async {
    if (!_recTesting) {
      final ok = await AsrService.instance.hasPermission();
      if (!ok) {
        setState(() {
          _asrOk = false;
          _asrResult = '没有麦克风权限。到手机设置 → 应用 → 关系图谱 → 权限，允许录音。';
        });
        return;
      }
      try {
        switch (_engine) {
          case AsrEngine.system:
            await SystemAsrService.instance.start(
              _systemLocale.text.trim().isEmpty ? 'zh-CN' : _systemLocale.text.trim(),
              onDeviceOnly: _onDeviceOnly,
            );
          case AsrEngine.offline:
            await LocalAsrService.instance.start();
          case AsrEngine.online:
            await AsrService.instance.start();
        }
        setState(() {
          _recTesting = true;
          _asrResult = null;
        });
      } on LlmException catch (e) {
        setState(() {
          _asrOk = false;
          _asrResult = e.message;
        });
      } catch (e) {
        setState(() {
          _asrOk = false;
          _asrResult = '开始录音失败：$e';
        });
      }
      return;
    }

    setState(() {
      _recTesting = false;
      _asrBusy = true;
    });
    try {
      final text = switch (_engine) {
        AsrEngine.system => await SystemAsrService.instance.stop(),
        AsrEngine.offline => await LocalAsrService.instance.stop(),
        AsrEngine.online => await AsrService.instance.stopAndTranscribe(AsrSettings(
              baseUrl: _baseUrl.text,
              apiKey: _apiKey.text,
              model: _model.text,
              language: _extra.text.trim(),
              protocol: _protocol,
            )),
      };
      setState(() {
        _asrOk = true;
        _asrResult = '识别结果：$text';
      });
    } on LlmException catch (e) {
      setState(() {
        _asrOk = false;
        _asrResult = e.message;
      });
    } catch (e) {
      setState(() {
        _asrOk = false;
        _asrResult = '识别失败：$e';
      });
    } finally {
      if (mounted) setState(() => _asrBusy = false);
    }
  }



  /// 是否强制本机识别。关掉时由系统自己决定走本地还是云端。

  /// 检测本机识别能力的入口。国产 ROM 上出错时常需要它来定性。
  Widget _diagnoseRow() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: _diagBusy ? null : _runDiagnose,
        icon: _diagBusy
            ? const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.textFaint),
              )
            : const Icon(Icons.troubleshoot, size: 15),
        label: Text(_diagBusy ? '正在检测…' : '检测本机识别能力'),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSub,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          textStyle: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _diagBanner() {
    final color = _diagOk ? AppColors.accent : AppColors.warning;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(
        _diagText!,
        style: TextStyle(fontSize: 10.5, height: 1.6, color: color),
      ),
    );
  }

  Future<void> _runDiagnose() async {
    setState(() {
      _diagBusy = true;
      _diagText = null;
    });
    final support = await SpeechDiagnostics.check();
    if (!mounted) return;
    final steps = support.nextSteps;
    final buffer = StringBuffer()
      ..write(support.describe())
      ..write('\n\n')
      ..write(support.verdict);
    if (steps.isNotEmpty) {
      buffer
        ..write('\n\n可以这样做：')
        ..write('\n${steps.map((e) => '· $e').join('\n')}');
    }
    setState(() {
      _diagBusy = false;
      _diagOk = support.usable;
      _diagText = buffer.toString();
    });
  }

  Widget _onDeviceSwitch() {
    return GestureDetector(
      onTap: () => setState(() => _onDeviceOnly = !_onDeviceOnly),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('仅本机识别',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: _onDeviceOnly ? AppColors.accent : AppColors.text)),
                  const SizedBox(height: 2),
                  const Text('录音不离开手机。系统没装离线包时会识别失败。',
                      style: TextStyle(fontSize: 10, color: AppColors.textFaint)),
                ],
              ),
            ),
            Switch(
              value: _onDeviceOnly,
              activeThumbColor: AppColors.accent,
              onChanged: (v) => setState(() => _onDeviceOnly = v),
            ),
          ],
        ),
      ),
    );
  }


  // ---------------------------------------------------- 识别方式（三选一）

  Widget _enginePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('识别方式',
            style: TextStyle(fontSize: 12, color: AppColors.textSub)),
        const SizedBox(height: 8),
        Row(
          children: AsrEngine.values.map((e) {
            final selected = _engine == e;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _engine = e),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.accent.withAlpha(28)
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: selected ? AppColors.accent : AppColors.border),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        switch (e) {
                          AsrEngine.system => Icons.phone_android,
                          AsrEngine.offline => Icons.memory,
                          AsrEngine.online => Icons.cloud_outlined,
                        },
                        size: 17,
                        color: selected ? AppColors.accent : AppColors.textFaint,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        e.label,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: selected ? AppColors.accent : AppColors.textSub,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        Text(
          switch (_engine) {
            AsrEngine.system => '用手机自带的识别服务。不联网、不用填 Key，但要有系统识别服务（部分 ROM 没开放）。',
            AsrEngine.offline => 'App 自己带模型跑，真正离线。首次要下载一次，之后完全不用网。',
            AsrEngine.online => '走 OpenAI 兼容接口，识别质量最好，但需要联网。',
          },
          style: const TextStyle(fontSize: 10, color: AppColors.textFaint, height: 1.5),
        ),
      ],
    );
  }

  // ---------------------------------------------------- 离线模型管理

  Widget _offlineModelCard() {
    final spec = AsrModels.zhStreaming;
    final ready = _modelReady;
    final pct = (_dlProgress * 100).clamp(0, 100).toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: ready ? AppColors.accent.withAlpha(110) : AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ready ? Icons.check_circle : Icons.download_for_offline,
                  size: 16,
                  color: ready ? AppColors.accent : AppColors.textFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${spec.title}（${spec.sizeLabel}）',
                    style: const TextStyle(fontSize: 13, color: AppColors.text)),
              ),
              Text(
                _dlBusy ? '$pct%' : (ready ? '已就绪' : '未下载'),
                style: TextStyle(
                  fontSize: 11,
                  color: _dlBusy
                      ? AppColors.accent
                      : (ready ? AppColors.accent : AppColors.textFaint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(spec.subtitle,
              style: const TextStyle(
                  fontSize: 10.5, color: AppColors.textFaint, height: 1.4)),
          if (_dlBusy) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _dlProgress,
                minHeight: 4,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation(AppColors.accent),
              ),
            ),
            const SizedBox(height: 6),
            Text(_dlStage,
                style: const TextStyle(fontSize: 10, color: AppColors.textSub)),
          ],
          if (!_dlBusy) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (!ready)
                  GestureDetector(
                    onTap: _downloadModel,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text('下载模型',
                          style: TextStyle(
                              fontSize: 12, color: Color(0xFF04202E))),
                    ),
                  ),
                if (ready) ...[
                  const Text('已占用 ',
                      style: TextStyle(fontSize: 10, color: AppColors.textFaint)),
                  Text('${(_modelBytes / 1024 / 1024).toStringAsFixed(1)}MB',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textSub)),
                  const Spacer(),
                  GestureDetector(
                    onTap: _deleteModel,
                    child: const Text('删除',
                        style:
                            TextStyle(fontSize: 11, color: AppColors.danger)),
                  ),
                ],
                if (!ready)
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: 10),
                      child: Text('下载后可离线识别，卸载 App 会一并清除',
                          style: TextStyle(
                              fontSize: 9.5,
                              color: AppColors.textFaint,
                              height: 1.3)),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _refreshModel() async {
    final spec = AsrModels.zhStreaming;
    final ready = await ModelStore.instance.isReady(spec);
    final bytes = await ModelStore.instance.usedBytes(spec);
    if (!mounted) return;
    setState(() {
      _modelReady = ready;
      _modelBytes = bytes;
    });
  }

  Future<void> _downloadModel() async {
    final spec = AsrModels.zhStreaming;
    setState(() {
      _dlBusy = true;
      _dlProgress = 0;
      _dlStage = '正在连接…';
    });
    try {
      await ModelStore.instance.download(spec, onProgress: (v, stage) {
        if (!mounted) return;
        setState(() {
          _dlProgress = v;
          _dlStage = stage;
        });
      });
      await _refreshModel();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('模型下载完成，可以在「离线模型」方式下说话了')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _dlBusy = false);
      showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: AppColors.surfaceAlt,
          title: const Text('下载失败', style: TextStyle(fontSize: 15)),
          content:
              Text('$e', style: const TextStyle(fontSize: 12, height: 1.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    } finally {
      if (mounted) setState(() => _dlBusy = false);
    }
  }

  Future<void> _deleteModel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('删除离线模型？', style: TextStyle(fontSize: 15)),
        content: const Text('删掉后不能离线识别，需要重新下载。已经记录的关系不受影响。',
            style: TextStyle(fontSize: 12, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('删除',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ModelStore.instance.remove(AsrModels.zhStreaming);
    LocalAsrService.instance.reset();
    await _refreshModel();
  }

  // ---------------------------------------------------- 手机内置语音（TTS）

  Widget _systemSwitch() {
    return GestureDetector(
      onTap: () => setState(() => _useSystem = !_useSystem),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: _useSystem ? AppColors.accent.withAlpha(22) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _useSystem ? AppColors.accent.withAlpha(120) : AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.phone_android,
                size: 18, color: _useSystem ? AppColors.accent : AppColors.textFaint),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      widget.kind == ModelKind.tts ? '使用手机内置语音' : '使用手机内置识别',
                      style: TextStyle(
                          fontSize: 13,
                          color: _useSystem ? AppColors.accent : AppColors.text)),
                  const SizedBox(height: 2),
                  Text(
                      widget.kind == ModelKind.tts
                          ? '离线播报，不联网、不用填 Key'
                          : '调系统识别，不联网、不用填 Key',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.textFaint)),
                ],
              ),
            ),
            Switch(
              value: _useSystem,
              activeThumbColor: AppColors.accent,
              onChanged: (v) => setState(() => _useSystem = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _testAction({
    required String label,
    IconData? icon,
    required bool busy,
    bool danger = false,
    VoidCallback? onTap,
  }) {
    final color = danger ? AppColors.danger : AppColors.accent;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: danger ? AppColors.danger.withAlpha(22) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: danger ? AppColors.danger.withAlpha(90) : AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else if (icon != null)
              Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _testBanner(String text, bool ok) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: (ok ? AppColors.success : AppColors.danger).withAlpha(18),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: (ok ? AppColors.success : AppColors.danger).withAlpha(70)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            height: 1.5,
            color: ok ? AppColors.success : AppColors.danger,
          ),
        ),
      );

  String get _baseUrlHint => switch (widget.kind) {
        ModelKind.llm => 'https://api.deepseek.com/v1',
        ModelKind.tts => 'https://api.openai.com/v1',
        ModelKind.asr => 'https://api.openai.com/v1',
      };

  String get _modelHint => switch (widget.kind) {
        ModelKind.llm => 'deepseek-chat',
        ModelKind.tts => 'tts-1 / tts-1-hd',
        ModelKind.asr => 'whisper-1',
      };

  Widget _field(String label, TextEditingController c, String hint) => TextField(
        controller: c,
        style: const TextStyle(fontSize: 13, color: AppColors.text),
        decoration: _decoration(label, hint: hint),
      );

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 12, color: AppColors.textFaint),
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFF2F4560)),
      );
}

class _Preset {
  final String name;
  final String baseUrl;
  final String model;
  const _Preset(this.name, this.baseUrl, this.model);
}

/// 数据备份：导出成一个 json 文件，通过系统分享面板存到微信/云盘/文件管理器
class _BackupPanel extends StatefulWidget {
  final AppState state;
  const _BackupPanel({required this.state});

  @override
  State<_BackupPanel> createState() => _BackupPanelState();
}

class _BackupPanelState extends State<_BackupPanel> {
  bool _busy = false;
  String? _status;
  bool _ok = true;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined,
                  size: 16, color: AppColors.textSub),
              const SizedBox(width: 6),
              const Text('备份与恢复',
                  style: TextStyle(fontSize: 13, color: AppColors.text)),
              const Spacer(),
              if (_busy)
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.textFaint),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '导出的文件包含全部设备、关系、节点位置和各项配置。'
            '恢复时会用备份内容替换当前数据，不会合并。',
            style: TextStyle(fontSize: 10.5, color: AppColors.textFaint, height: 1.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  label: '导出备份',
                  icon: Icons.upload_file,
                  primary: true,
                  onTap: _busy ? null : _export,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionButton(
                  label: '导入备份',
                  icon: Icons.download_for_offline_outlined,
                  primary: false,
                  onTap: _busy ? null : _import,
                ),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 10),
            Text(
              _status!,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.5,
                color: _ok ? AppColors.accent : AppColors.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required bool primary,
    required VoidCallback? onTap,
  }) {
    final color = primary ? AppColors.accent : AppColors.textSub;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: primary ? AppColors.accent.withAlpha(26) : AppColors.surfaceAlt,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: primary ? AppColors.accent.withAlpha(120) : AppColors.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: onTap == null ? AppColors.textFaint : color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: onTap == null ? AppColors.textFaint : color)),
          ],
        ),
      ),
    );
  }

  Future<void> _export() async {
    var withSecrets = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surfaceAlt,
          title: const Text('导出备份', style: TextStyle(fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '会导出 ${(widget.state.graph['nodes'] as List?)?.length ?? 0} 个设备、'
                '${(widget.state.graph['edges'] as List?)?.length ?? 0} 条关系，'
                '以及模型配置和节点位置。',
                style: const TextStyle(fontSize: 12, height: 1.6),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () => setDialogState(() => withSecrets = !withSecrets),
                child: Row(
                  children: [
                    Checkbox(
                      value: withSecrets,
                      onChanged: (v) => setDialogState(() => withSecrets = v ?? false),
                      activeColor: AppColors.accent,
                      visualDensity: VisualDensity.compact,
                    ),
                    const Expanded(
                      child: Text('同时导出 API Key',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ),
              const Text(
                '默认不导出。Key 会以明文写进文件，文件传出去就等于把 Key 给出去了。'
                '换手机想免填 Key 再勾。',
                style: TextStyle(fontSize: 10, color: AppColors.textFaint, height: 1.5),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('导出'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final file = await BackupService.create(includeSecrets: withSecrets);
      final size = (await file.length() / 1024).toStringAsFixed(0);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'LinkMind 备份',
        text: 'LinkMind 数据备份（$size KB）',
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = true;
        _status = '已生成备份文件（$size KB）。'
            '${withSecrets ? '包含 API Key，注意保管。' : '不含 API Key，恢复后需要重新填。'}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = false;
        _status = '导出失败：$e';
      });
    }
  }

  Future<void> _import() async {
    XFile? picked;
    try {
      picked = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'LinkMind 备份',
            extensions: ['json'],
            mimeTypes: ['application/json'],
          ),
        ],
      );
    } catch (e) {
      setState(() {
        _ok = false;
        _status = '打不开文件选择器：$e';
      });
      return;
    }
    if (picked == null) return;

    final String text;
    try {
      text = await picked.readAsString();
    } catch (e) {
      setState(() {
        _ok = false;
        _status = '读取文件失败：$e';
      });
      return;
    }

    BackupPreview preview;
    try {
      preview = BackupService.inspect(text);
    } on LlmException catch (e) {
      setState(() {
        _ok = false;
        _status = e.message;
      });
      return;
    }

    if (!mounted) return;
    final when = preview.exportedAt == null
        ? '时间未知'
        : '${preview.exportedAt!.year}-${preview.exportedAt!.month.toString().padLeft(2, '0')}'
            '-${preview.exportedAt!.day.toString().padLeft(2, '0')} '
            '${preview.exportedAt!.hour.toString().padLeft(2, '0')}:'
            '${preview.exportedAt!.minute.toString().padLeft(2, '0')}';

    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('导入备份', style: TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('备份时间：$when',
                style: const TextStyle(fontSize: 12, height: 1.6)),
            Text('包含 ${preview.entities} 个设备、${preview.facts} 条关系',
                style: const TextStyle(fontSize: 12, height: 1.6)),
            const SizedBox(height: 10),
            const Text(
              '导入会用这份备份替换当前全部数据，现在手机上的记录会被清掉。'
              '建议先导出一份再导入。',
              style: TextStyle(fontSize: 10.5, color: AppColors.danger, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('替换并导入',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (go != true) return;

    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final result = await BackupService.restore(preview);
      await widget.state.reloadSettings();
      await widget.state.refreshGraph();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = true;
        _status = '已恢复 ${result.entities} 个设备'
            '${result.settingsApplied ? '，模型配置也一并恢复了' : ''}'
            '${result.keysRestored ? '（含 API Key）' : '（API Key 需重新填写）'}。';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = false;
        _status = '导入失败：$e';
      });
    }
  }
}

/// 检查更新：问 GitHub 要最新 Release，和当前版本比。
/// 有新版就在 App 里下载 APK，再调起系统安装界面，不跳浏览器。
class _UpdatePanel extends StatefulWidget {
  const _UpdatePanel();

  @override
  State<_UpdatePanel> createState() => _UpdatePanelState();
}

class _UpdatePanelState extends State<_UpdatePanel> {
  bool _busy = false;
  double _progress = 0;
  String? _hint;
  bool _ok = true;

  bool get _downloading => _busy && _progress > 0;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_alt,
                  size: 16, color: AppColors.textSub),
              const SizedBox(width: 6),
              const Text('检查更新',
                  style: TextStyle(fontSize: 13, color: AppColors.text)),
              const Spacer(),
              Text('当前 $appVersion',
                  style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '新版本发布在 GitHub Releases。检测到新版会直接在 App 里下载并弹出安装界面。',
            style: TextStyle(fontSize: 10.5, color: AppColors.textFaint, height: 1.5),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: _busy ? null : _check,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.accent.withAlpha(26),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: AppColors.accent.withAlpha(120)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: _busy
                        ? const CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.accent)
                        : const Icon(Icons.refresh, size: 14, color: AppColors.accent),
                  ),
                  const SizedBox(width: 5),
                  Text(_busy ? '正在处理…' : '检查更新',
                      style: const TextStyle(fontSize: 12, color: AppColors.accent)),
                ],
              ),
            ),
          ),
          if (_downloading) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 4,
                backgroundColor: AppColors.border,
                valueColor: const AlwaysStoppedAnimation(AppColors.accent),
              ),
            ),
          ],
          if (_hint != null) ...[
            const SizedBox(height: 10),
            Text(
              _hint!,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.5,
                color: _ok ? AppColors.accent : AppColors.warning,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _check() async {
    setState(() {
      _busy = true;
      _progress = 0;
      _hint = null;
    });
    final info = await UpdateService.check(currentVersion: appVersion);
    if (!mounted) return;
    setState(() => _busy = false);

    switch (info.status) {
      case UpdateStatus.available:
        setState(() {
          _ok = true;
          _hint = '有新版本 ${info.latestVersion}';
        });
        await _askAndInstall(info);
      case UpdateStatus.upToDate:
        setState(() {
          _ok = true;
          _hint = '已经是最新版本（${info.currentVersion}）';
        });
      case UpdateStatus.noRelease:
        setState(() {
          _ok = false;
          _hint = '仓库里还没发布过版本。发布后这里就能直接装。';
        });
      case UpdateStatus.networkError:
        setState(() {
          _ok = false;
          _hint = info.error ?? '检查失败';
        });
    }
  }

  Future<void> _askAndInstall(UpdateInfo info) async {
    final hasApk = info.apkUrl != null;

    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: Text('发现新版本 ${info.latestVersion}',
            style: const TextStyle(fontSize: 15)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前版本 ${info.currentVersion}',
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textFaint)),
              if ((info.notes ?? '').isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(info.notes!,
                    style: const TextStyle(fontSize: 11.5, height: 1.6)),
              ],
              if (!hasApk) ...[
                const SizedBox(height: 12),
                const Text(
                  '这个版本没有附上可直接安装的 APK，只能去 Releases 页面手动下载。',
                  style: TextStyle(fontSize: 11, color: AppColors.warning, height: 1.5),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('稍后'),
          ),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: Text(hasApk ? '下载并安装' : '打开页面'),
          ),
        ],
      ),
    );
    if (go != true) return;

    if (!hasApk) {
      await _openPage(info.pageUrl ?? UpdateService.releasesUrl);
      return;
    }
    await _downloadAndInstall(info);
  }

  Future<void> _downloadAndInstall(UpdateInfo info) async {
    // Android 8+ 要单独授权「允许安装未知应用」，没授权直接装会被系统拦掉
    final can = await ApkInstaller.canInstall();
    if (!can) {
      setState(() {
        _ok = false;
        _hint = '需要允许「安装未知应用」。已为你打开设置页，'
            '找到 LinkMind 打开开关后，回来再点一次检查更新。';
      });
      await ApkInstaller.openInstallSetting();
      return;
    }

    setState(() {
      _busy = true;
      _progress = 0.001;
      _hint = '准备下载…';
      _ok = true;
    });

    String path;
    try {
      path = await ApkInstaller.download(
        info.apkUrl!,
        fileName: 'LinkMind-${info.latestVersion}.apk',
        onProgress: (v, stage) {
          if (!mounted) return;
          setState(() {
            _progress = v;
            _hint = stage;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = 0;
        _ok = false;
        _hint = '下载失败：$e';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _progress = 1;
      _hint = '下载完成，正在打开安装界面…';
    });

    final error = await ApkInstaller.install(path);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = 0;
      if (error == null) {
        _ok = true;
        _hint = '已唤起安装界面，按系统提示完成安装即可。';
        // 装完把安装包删掉，别一直占空间
      } else {
        _ok = false;
        _hint = error;
      }
    });
    unawaited(_cleanupLater(path));
  }

  /// 延迟清理：立刻删可能打断安装器读文件
  Future<void> _cleanupLater(String path) async {
    await Future<void>.delayed(const Duration(minutes: 2));
    await ApkInstaller.cleanup(path);
  }

  Future<void> _openPage(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
}
