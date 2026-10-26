import 'dart:async';

import 'package:flutter/foundation.dart';

import 'asr/local_asr.dart';
import 'data/models.dart';
import 'data/repository.dart';
import 'data/settings.dart';
import 'llm/llm_client.dart';
import 'llm/parser.dart';
import 'voice/asr_service.dart';
import 'voice/system_asr.dart';
import 'voice/tts_service.dart';

/// 一条待确认关系 + 它可能对应的已有实体 + 它将要顶掉的旧记录
class DraftResolution {
  final FactDraft draft;
  final MatchCandidate? subjectMatch;
  final MatchCandidate? objectMatch;

  /// 同主语、同关系、不同去向的已有记录 —— 确认后会被置为失效
  final List<FactView> replaces;

  const DraftResolution(this.draft, this.subjectMatch, this.objectMatch, this.replaces);
}

/// 全局状态。刻意保持扁平：一个图谱、一个输入流程、一份配置。
class AppState extends ChangeNotifier {
  final GraphRepository repo = GraphRepository.instance;

  LlmSettings settings = const LlmSettings();
  TtsSettings tts = const TtsSettings();
  AsrSettings asr = const AsrSettings();
  bool settingsLoaded = false;

  Map<String, Object?> graph = const {'nodes': [], 'edges': []};
  int graphRevision = 0;
  bool graphLoading = true;

  bool busy = false;
  String? statusText;
  String? errorText;

  AnswerResult? answer;
  int answerRevision = 0;

  List<DraftResolution> pendingDrafts = const [];
  String pendingOriginal = '';
  bool showConfirm = false;

  /// 待确认作废的事实
  List<FactView> pendingRetire = const [];
  bool showRetireConfirm = false;

  List<String> highlightIds = const [];
  int highlightRevision = 0;
  String? focusNodeId;
  int focusRevision = 0;

  /// 底部面板内容：同一时刻只显示一个
  Map<String, Object?>? panelEntity;
  FactView? panelFact;
  int panelRevision = 0;

  // ------------------------------------------------------------------ 语音

  bool isRecording = false;
  bool isTranscribing = false;
  bool isSpeaking = false;

  /// 用户点了静音：后续回答不再自动念出来
  bool speechMuted = false;

  /// 语音识别出来的文字，交给界面填进输入框
  String? lastTranscript;
  int transcriptRevision = 0;

  /// 语音播报出错时的提示（不遮挡回答内容）
  String? speechError;

  /// 连续播报失败次数。默认走手机内置后，没装语音包的机器会每次失败，
  /// 提示两次就够了，再多就是噪音。
  int _speechFailures = 0;

  // ------------------------------------------------------------------ 初始化

  Future<void> init() async {
    settings = await SettingsStore.instance.load();
    tts = SettingsStore.instance.ttsCached;
    asr = SettingsStore.instance.asrCached;
    settingsLoaded = true;
    notifyListeners();
    await refreshGraph();
  }

  /// 导入备份后要重新读一遍配置，否则界面上还是旧值（虽然文件已经更新了）
  Future<void> reloadSettings() async {
    settings = await SettingsStore.instance.load();
    tts = SettingsStore.instance.ttsCached;
    asr = SettingsStore.instance.asrCached;
    notifyListeners();
  }

  Future<void> refreshGraph() async {
    try {
      graph = await repo.graphPayload();
      graphRevision++;
      graphLoading = false;
      notifyListeners();
    } catch (e) {
      graphLoading = false;
      errorText = '读取本地数据失败：$e';
      notifyListeners();
    }
  }

  Future<void> saveSettings(LlmSettings value) async {
    await SettingsStore.instance.save(value);
    settings = value;
    notifyListeners();
  }

  Future<void> saveTts(TtsSettings value) async {
    await SettingsStore.instance.saveTts(value);
    tts = value;
    notifyListeners();
  }

  Future<void> saveAsr(AsrSettings value) async {
    await SettingsStore.instance.saveAsr(value);
    asr = value;
    notifyListeners();
  }

  // ------------------------------------------------------------------ 输入

  /// 唯一的入口：记事实、提问、纠错、作废，都是这一条路
  Future<void> submit(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || busy) return;

    errorText = null;
    answer = null;
    pendingDrafts = const [];
    pendingRetire = const [];
    showConfirm = false;
    showRetireConfirm = false;

    if (!settings.isReady) {
      errorText = '还没配置模型。点右上角设置 → 大语言模型，填入 Base URL、API Key 和模型名。';
      notifyListeners();
      return;
    }

    busy = true;
    statusText = '正在理解…';
    notifyListeners();

    try {
      final entities = await repo.allEntities();
      final names = entities.map((e) => e.name).toList();
      final parsed = await FactParser.parse(input: text, knownEntities: names, settings: settings);

      switch (parsed.intent) {
        case 'query':
          statusText = '正在查记录…';
          notifyListeners();
          final result = await repo.answer(parsed.queryEntity ?? text, parsed.queryPredicate);
          answer = result;
          answerRevision++;
          _maybeSpeak(result.text);
          highlightIds = result.highlightIds;
          highlightRevision++;
          statusText = null;
          break;

        case 'retire':
          statusText = '正在找要作废的记录…';
          notifyListeners();
          final facts = await repo.factsToRetire(
            subjectName: parsed.retireSubject ?? text,
            predicateCode: parsed.retirePredicate,
            objectName: parsed.retireObject,
          );
          statusText = null;
          if (facts.isEmpty) {
            answer = AnswerResult(
              text: '没找到符合条件的记录，没有可作废的内容。\n'
                  '如果是想改成别的去处，直接说「${parsed.retireSubject ?? '某设备'} 电源改到 XXX」。',
              isEmpty: true,
            );
            answerRevision++;
            _maybeSpeak(answer!.text);
          } else {
            pendingRetire = facts;
            showRetireConfirm = true;
          }
          break;

        default:
          // add：先查候选实体和会被顶掉的旧记录，一起放到确认卡片上
          final resolutions = <DraftResolution>[];
          for (final d in parsed.facts) {
            final sub = await repo.bestMatch(d.subjectName);
            final obj = await repo.bestMatch(d.objectName);
            final replaces = await repo.conflictsFor(d);
            resolutions.add(DraftResolution(
              d,
              (sub != null && sub.score >= 0.60) ? sub : null,
              (obj != null && obj.score >= 0.60) ? obj : null,
              replaces,
            ));
          }
          pendingDrafts = resolutions;
          pendingOriginal = text;
          showConfirm = true;
          statusText = null;
      }
    } on LlmException catch (e) {
      errorText = e.message;
      statusText = null;
    } catch (e) {
      errorText = '出了点问题：$e';
      statusText = null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // -------------------------------------------------------------- 确认写入

  /// useExistingSubject/Object 决定同名实体是合并到旧实体还是新建
  Future<void> confirmDrafts({
    required List<bool> useExistingSubject,
    required List<bool> useExistingObject,
  }) async {
    if (pendingDrafts.isEmpty) return;
    // 防御：勾选数组长度必须与关系条数一致
    final useSub = List<bool>.generate(
        pendingDrafts.length, (i) => i < useExistingSubject.length ? useExistingSubject[i] : false);
    final useObj = List<bool>.generate(
        pendingDrafts.length, (i) => i < useExistingObject.length ? useExistingObject[i] : false);

    // 两端勾到同一个已有实体，写进去就是自己连自己。
    // 这种情况一定有问题（多半是名字太像被误判），先拦住，别让用户白点一次。
    for (var i = 0; i < pendingDrafts.length; i++) {
      final r = pendingDrafts[i];
      final sid = useSub[i] ? r.subjectMatch?.entity.id : null;
      final oid = useObj[i] ? r.objectMatch?.entity.id : null;
      if (sid != null && sid == oid) {
        errorText = '「${r.draft.subjectName}」和「${r.draft.objectName}」被当成了同一个设备，'
            '保存后会变成"自己连自己"。\n'
            '把其中一个的勾选去掉（当作新设备）再试。';
        notifyListeners();
        return;
      }
    }

    busy = true;
    statusText = '正在保存…';
    notifyListeners();

    try {
      final results = <CommitResult>[];
      for (var i = 0; i < pendingDrafts.length; i++) {
        final r = pendingDrafts[i];
        results.add(await repo.commitDraft(
          r.draft,
          subjectId: useSub[i] ? r.subjectMatch?.entity.id : null,
          objectId: useObj[i] ? r.objectMatch?.entity.id : null,
        ));
      }

      final rejected = results.where((r) => r.selfLoop).length;
      if (rejected > 0) {
        showConfirm = false;
        pendingDrafts = const [];
        errorText = '有 $rejected 条关系的两端是同一个设备，没有保存。'
            '检查一下名字，把两端写清楚再录一次。';
        notifyListeners();
        return;
      }

      final savedCount = results.where((r) => !r.alreadyExists).length;
      final duplicate = results.where((r) => r.alreadyExists).length;
      final supersededIds = results.expand((r) => r.supersededIds).toList();
      final lastFactId = results.isEmpty ? null : results.last.factId;

      showConfirm = false;
      pendingDrafts = const [];
      await refreshGraph();

      if (lastFactId != null) {
        highlightIds = [lastFactId];
        highlightRevision++;
      }

      final buffer = StringBuffer();
      if (savedCount == 0 && duplicate > 0) {
        buffer.write('这条记录之前就有了，没有重复写入。');
      } else {
        buffer.write('已记住${savedCount > 1 ? ' $savedCount 条关系' : ''}。');
        if (supersededIds.isNotEmpty) {
          buffer.write('\n原来那条记录已自动失效'
              '${supersededIds.length > 1 ? '（共 ${supersededIds.length} 条）' : ''}，'
              '图上不会再显示，历史保留在设备详情里。');
        } else {
          buffer.write('\n以后直接问「${pendingOriginal.isEmpty ? '它' : _shortQuery(pendingOriginal)}」我就能答。');
        }
      }
      answer = AnswerResult(text: buffer.toString());
      answerRevision++;
      _maybeSpeak(answer!.text);
    } catch (e) {
      errorText = '保存失败：$e';
    } finally {
      busy = false;
      statusText = null;
      notifyListeners();
    }
  }

  /// 确认作废
  Future<void> confirmRetire() async {
    if (pendingRetire.isEmpty) return;
    busy = true;
    statusText = '正在作废…';
    notifyListeners();
    try {
      final count = pendingRetire.length;
      for (final f in pendingRetire) {
        await repo.retireFact(f.id);
      }
      showRetireConfirm = false;
      pendingRetire = const [];
      await refreshGraph();
      highlightIds = const [];
      highlightRevision++;
      answer = AnswerResult(
        text: '已作废 $count 条记录，图上对应连线已经移除。\n'
            '原始记录没有删除，在设备详情里还能看到「已失效」的历史。',
      );
      answerRevision++;
      _maybeSpeak(answer!.text);
    } catch (e) {
      errorText = '作废失败：$e';
    } finally {
      busy = false;
      statusText = null;
      notifyListeners();
    }
  }

  void cancelDrafts() {
    showConfirm = false;
    pendingDrafts = const [];
    notifyListeners();
  }

  void cancelRetire() {
    showRetireConfirm = false;
    pendingRetire = const [];
    notifyListeners();
  }

  /// 从"已记住"的提示里截一段能当问句的短句
  String _shortQuery(String original) {
    final t = original.replaceAll(RegExp(r'[。！？!?]'), '');
    return t.length <= 12 ? t : '${t.substring(0, 12)}…';
  }

  // -------------------------------------------------------------- 语音输入输出

  /// 点麦克风：第一次开始录，第二次停止并识别
  Future<void> toggleRecording() async {
    if (isTranscribing || busy) return;

    if (!isRecording) {
      if (!asr.isReady) {
        errorText = '还没配置语音识别。设置 → 语音识别，填好后再用麦克风。';
        notifyListeners();
        return;
      }
      final ok = await AsrService.instance.hasPermission();
      if (!ok) {
        errorText = '没有麦克风权限。到手机设置 → 应用 → 关系图谱 → 权限，允许录音。';
        notifyListeners();
        return;
      }
      try {
        await TtsService.instance.stop();
        isSpeaking = false;
        answer = null;
        errorText = null;
        switch (asr.engine) {
          case AsrEngine.system:
            await SystemAsrService.instance
                .start(asr.systemLocale, onDeviceOnly: asr.onDeviceOnly);
          case AsrEngine.offline:
            // 首次要加载 25MB 模型，可能卡几秒，先给个提示
            statusText = '正在准备离线模型…';
            notifyListeners();
            await LocalAsrService.instance.start();
          case AsrEngine.online:
            await AsrService.instance.start();
        }
        statusText = null;
        isRecording = true;
      } on LlmException catch (e) {
        statusText = null;
        errorText = e.message;
      } catch (e) {
        statusText = null;
        errorText = '开始录音失败：$e';
      }
      notifyListeners();
      return;
    }

    // 停止录音 → 上传识别
    isRecording = false;
    isTranscribing = true;
    notifyListeners();
    try {
      final text = switch (asr.engine) {
        AsrEngine.system => await SystemAsrService.instance.stop(),
        AsrEngine.offline => await LocalAsrService.instance.stop(),
        AsrEngine.online => await AsrService.instance.stopAndTranscribe(asr),
      };
      if (text.isNotEmpty) {
        lastTranscript = text;
        transcriptRevision++;
      }
    } on LlmException catch (e) {
      errorText = e.message;
    } catch (e) {
      errorText = '语音识别失败：$e';
    } finally {
      isTranscribing = false;
      notifyListeners();
    }
  }

  Future<void> cancelRecording() async {
    if (!isRecording) return;
    isRecording = false;
    switch (asr.engine) {
      case AsrEngine.system:
        await SystemAsrService.instance.cancel();
      case AsrEngine.offline:
        await LocalAsrService.instance.cancel();
      case AsrEngine.online:
        await AsrService.instance.cancel();
    }
    notifyListeners();
  }

  /// 回答面板右上角的喇叭：正在念就停并静音；已静音就解除并重念
  Future<void> toggleSpeech() async {
    if (isSpeaking) {
      await TtsService.instance.stop();
      isSpeaking = false;
      speechMuted = true;
      notifyListeners();
      return;
    }
    if (!tts.isReady) {
      errorText = '还没配置语音合成。设置 → 语音合成，填好后再点喇叭。';
      notifyListeners();
      return;
    }
    speechMuted = false;
    final text = answer?.text;
    if (text == null || text.isEmpty) {
      notifyListeners();
      return;
    }
    await _speak(text);
  }

  Future<void> _speak(String text) async {
    if (!tts.isReady) return;
    isSpeaking = true;
    speechError = null;
    notifyListeners();
    try {
      await TtsService.instance.speak(text, tts);
      // 播放成功才清零，否则「连续失败 3 次就闭嘴」永远不成立
      _speechFailures = 0;
    } on LlmException catch (e) {
      // 只提示，不自动静音：静音一次就再也不出声，用户会以为配置没生效
      _speechFailures++;
      if (_speechFailures <= 2) speechError = e.message;
    } catch (_) {
      _speechFailures++;
      if (_speechFailures <= 2) speechError = '语音播放失败';
    } finally {
      isSpeaking = false;
      notifyListeners();
    }
  }

  /// 收起面板时把正在念的语音一起停掉，别让它在后台继续说话
  Future<void> _stopSpeech() async {
    if (!isSpeaking) return;
    await TtsService.instance.stop();
    isSpeaking = false;
    notifyListeners();
  }

  /// 新回答是否要自动念出来
  void _maybeSpeak(String text) {
    if (!tts.isReady || speechMuted) return;
    unawaited(_speak(text));
  }

  // -------------------------------------------------------------- 其它操作

  Future<void> retireFact(String factId) async {
    await repo.retireFact(factId);
    await refreshGraph();
    highlightRevision++;
    highlightIds = const [];
    notifyListeners();
  }

  void focusNode(String id) {
    focusNodeId = id;
    focusRevision++;
    notifyListeners();
  }

  void highlight(List<String> ids) {
    highlightIds = ids;
    highlightRevision++;
    notifyListeners();
  }

  void clearAnswer() {
    answer = null;
    errorText = null;
    highlightIds = const [];
    highlightRevision++;
    unawaited(_stopSpeech());
    notifyListeners();
  }

  /// 把两个节点并成一个（用于同一台设备被记成两个名字的情况）
  Future<void> mergeEntity(String sourceId, String targetId) async {
    if (sourceId == targetId) return;
    busy = true;
    statusText = '正在合并…';
    notifyListeners();
    try {
      final moved = await repo.mergeEntities(sourceId, targetId);
      await refreshGraph();
      panelEntity = null;
      panelFact = null;
      panelRevision++;
      answer = AnswerResult(
        text: '已合并到同一个节点。'
            '${moved > 0 ? '迁移了 $moved 条关系' : '没有需要迁移的关系'}，'
            '旧名字已存为别名，以后用哪个名字问都能对上。',
      );
      answerRevision++;
    } catch (e) {
      errorText = '合并失败：$e';
    } finally {
      busy = false;
      statusText = null;
      notifyListeners();
    }
  }

  // -------------------------------------------------------------- 底部面板

  Future<void> openEntity(String entityId) async {
    panelFact = null;
    answer = null;
    errorText = null;
    unawaited(_stopSpeech());
    panelEntity = await repo.entityDetail(entityId);
    panelRevision++;
    notifyListeners();
  }

  Future<void> openFact(String factId) async {
    panelEntity = null;
    answer = null;
    errorText = null;
    unawaited(_stopSpeech());
    panelFact = await repo.factView(factId);
    panelRevision++;
    notifyListeners();
  }

  /// 点空白处：把回答、错误、详情一起收掉（确认类面板不算，必须明确操作）
  void dismissTransientPanels() {
    panelEntity = null;
    panelFact = null;
    answer = null;
    errorText = null;
    panelRevision++;
    unawaited(_stopSpeech());
    notifyListeners();
  }

  void closePanel() {
    panelEntity = null;
    panelFact = null;
    panelRevision++;
    unawaited(_stopSpeech());
    notifyListeners();
  }
}
