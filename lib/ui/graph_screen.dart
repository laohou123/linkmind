import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/models.dart';
import 'graph_view.dart';
import 'panels.dart';
import 'search_delegate.dart';
import 'settings_screen.dart';
import 'theme.dart';

class GraphScreen extends StatefulWidget {
  final AppState state;
  const GraphScreen({super.key, required this.state});

  @override
  State<GraphScreen> createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();

  List<bool> _useSubject = const [];
  List<bool> _useObject = const [];
  bool _wasConfirming = false;
  int _lastTranscriptRevision = -1;

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    final s = widget.state;
    if (s.showConfirm && !_wasConfirming) {
      // 新一批待确认关系：默认勾选"合并到已有实体"（如果匹配到的话）
      // 类型冲突时默认不勾选：别把设备并到线缆上（或反过来）
      // 只有「基本确定是同一个」才默认勾选（0.86 以上）。
      // 之前是只要匹配到就勾，像「7#炉0米设备箱」和「7#炉9米设备箱」这种
      // 0.73 分的也会被默认勾上，用户直接点确认就把两台设备并了。
      _useSubject = s.pendingDrafts
          .map((d) =>
              d.subjectMatch != null &&
              d.subjectMatch!.score >= 0.86 &&
              EntityTypes.compatible(d.subjectMatch!.entity.type, d.draft.subjectType))
          .toList();
      _useObject = s.pendingDrafts
          .map((d) =>
              d.objectMatch != null &&
              d.objectMatch!.score >= 0.86 &&
              EntityTypes.compatible(d.objectMatch!.entity.type, d.draft.objectType))
          .toList();
    }
    _wasConfirming = s.showConfirm;

    // 语音识别出文字：填进输入框并直接发送
    if (s.transcriptRevision != _lastTranscriptRevision) {
      _lastTranscriptRevision = s.transcriptRevision;
      final text = s.lastTranscript;
      if (text != null && text.isNotEmpty) {
        _input.text = text;
        _input.selection = TextSelection.collapsed(offset: text.length);
        // 只填进输入框，不自动发送：识别偶尔会听错一两个字，
        // 直接发出去会多一张要取消的卡片，让人改一下再发更省事。
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _inputFocus.requestFocus();
        });
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _inputFocus.unfocus();
    // 发出即清空，别让输入框里挂着上一句
    _input.clear();
    await widget.state.submit(text);
    if (!mounted) return;
    // 没送出去（没配模型、网络失败）就把原话还回去，别让人白打一遍
    if (widget.state.errorText != null && _input.text.isEmpty) {
      _input.text = text;
      _input.selection = TextSelection.collapsed(offset: text.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        color: AppColors.bg,
        child: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              // 图谱铺满整个屏幕
              Positioned.fill(child: GraphView(state: s)),

              // 半透明挡板：面板打开时，点画面任意空白处收起，但不会误触图谱
              if (_hasTransientPanel(s))
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _dismissTransient,
                    child: const SizedBox.expand(),
                  ),
                ),

              // 顶部工具条
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _TopBar(state: s, onSearch: _openSearch),
              ),

              // 底部：面板 + 输入框
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (s.busy && s.statusText != null) _StatusPill(text: s.statusText!),
                    _buildPanel(s),
                    _InputBar(
                      controller: _input,
                      focusNode: _inputFocus,
                      busy: s.busy,
                      isRecording: s.isRecording,
                      isTranscribing: s.isTranscribing,
                      onSend: _send,
                      onMic: s.toggleRecording,
                    ),
                    SizedBox(
                      height: MediaQuery.of(context).viewInsets.bottom > 0
                          ? 6
                          : MediaQuery.of(context).viewPadding.bottom + 12,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasTransientPanel(AppState s) {
    if (s.showConfirm || s.showRetireConfirm || s.showRenameConfirm) return false;
    return s.answer != null ||
        s.errorText != null ||
        s.panelEntity != null ||
        s.panelFact != null;
  }

  void _dismissTransient() {
    widget.state.dismissTransientPanels();
    if (mounted) setState(() {});
  }

  Widget _buildPanel(AppState s) {
    if (s.showRenameConfirm) {
      return RenamePanel(
        fromName: s.pendingRenameFrom,
        toName: s.pendingRenameTo,
        factCount: s.pendingRenameFactCount,
        working: s.busy,
        onConfirm: s.confirmRename,
        onCancel: s.cancelRename,
      );
    }
    if (s.showRetireConfirm && s.pendingRetire.isNotEmpty) {
      return RetirePanel(
        facts: s.pendingRetire,
        working: s.busy,
        onConfirm: s.confirmRetire,
        onCancel: s.cancelRetire,
      );
    }
    if (s.showConfirm && s.pendingDrafts.isNotEmpty) {
      return ConfirmPanel(
        drafts: s.pendingDrafts,
        useExistingSubject: _useSubject,
        useExistingObject: _useObject,
        saving: s.busy,
        onToggle: (i, {bool? subject, bool? object}) {
          setState(() {
            if (subject != null) _useSubject[i] = subject;
            if (object != null) _useObject[i] = object;
          });
        },
        onConfirm: () {
          s.confirmDrafts(useExistingSubject: _useSubject, useExistingObject: _useObject);
        },
        onCancel: s.cancelDrafts,
      );
    }
    if (s.panelEntity != null) {
      final entity = s.panelEntity!['entity'];
      final entityId = entity is Map ? entity['id'] as String? : null;
      return EntityPanel(
        detail: s.panelEntity!,
        onClose: s.closePanel,
        onOpenFact: s.openFact,
        onMerge: entityId == null ? null : () => _mergeEntity(entityId),
      );
    }
    if (s.panelFact != null) {
      return FactPanel(
        fact: s.panelFact!,
        onClose: s.closePanel,
        onRetire: () async {
          await s.retireFact(s.panelFact!.id);
          s.closePanel();
        },
      );
    }
    if (s.errorText != null) {
      return ErrorPanel(
        message: s.errorText!,
        onClose: s.clearAnswer,
        onOpenSettings: _openSettings,
      );
    }
    if (s.answer != null) {
      return AnswerPanel(
        answer: s.answer!,
        onClose: s.clearAnswer,
        onOpenFact: s.openFact,
        isSpeaking: s.isSpeaking,
        muted: s.speechMuted,
        onToggleSpeech: s.toggleSpeech,
        speechError: s.speechError,
      );
    }
    return const SizedBox.shrink();
  }

  Future<void> _openSearch() async {
    final id = await showSearch<String?>(
      context: context,
      delegate: EntitySearchDelegate(widget.state),
    );
    if (id != null) {
      widget.state.focusNode(id);
    }
  }

  /// 选一个目标设备，把当前这个并过去
  Future<void> _mergeEntity(String sourceId) async {
    final targetId = await showSearch<String?>(
      context: context,
      delegate: EntitySearchDelegate(widget.state),
    );
    if (!mounted || targetId == null || targetId == sourceId) return;
    await widget.state.mergeEntity(sourceId, targetId);
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SettingsScreen(state: widget.state)),
    );
    if (mounted) setState(() {});
  }
}

class _TopBar extends StatelessWidget {
  final AppState state;
  final VoidCallback onSearch;

  const _TopBar({required this.state, required this.onSearch});

  @override
  Widget build(BuildContext context) {
    final count = (state.graph['nodes'] as List?)?.length ?? 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.bg.withAlpha(240), AppColors.bg.withAlpha(0)],
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'LinkMind',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                count == 0 ? '还没有记录' : '$count 个设备',
                style: const TextStyle(fontSize: 10, color: AppColors.textFaint),
              ),
            ],
          ),
          const Spacer(),
          _iconButton(Icons.search, onSearch),
          _iconButton(Icons.tune, () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SettingsScreen(state: state)),
            );
          }),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, VoidCallback onTap) => IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 20, color: AppColors.textSub),
        splashRadius: 22,
      );
}

class _StatusPill extends StatelessWidget {
  final String text;
  const _StatusPill({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.accent),
          ),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool isRecording;
  final bool isTranscribing;
  final VoidCallback onSend;
  final VoidCallback onMic;

  const _InputBar({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.isRecording,
    required this.isTranscribing,
    required this.onSend,
    required this.onMic,
  });

  @override
  Widget build(BuildContext context) {
    final hint = isTranscribing
        ? '正在识别…'
        : isRecording
            ? '正在录音，说完再点一次'
            : '记一句关系，或直接提问…';

    final borderColor = isRecording ? AppColors.danger : AppColors.border;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 1,
              maxLines: 4,
              readOnly: isRecording || isTranscribing,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(fontSize: 14, color: AppColors.text, height: 1.4),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: isRecording ? AppColors.danger : AppColors.textFaint,
                ),
                // 右边留出麦克风的位置，麦克风做成输入框的一部分
                contentPadding: const EdgeInsets.fromLTRB(16, 12, 48, 12),
                suffixIcon: _micButton(),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 46, minHeight: 40),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: borderColor),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: const BorderSide(color: AppColors.accentDim),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: busy ? null : onSend,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: busy ? AppColors.surfaceAlt : AppColors.accent,
                shape: BoxShape.circle,
              ),
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.textFaint),
                    )
                  : const Icon(Icons.arrow_upward, size: 20, color: Color(0xFF04202E)),
            ),
          ),
        ],
      ),
    );
  }

  /// 输入框里的麦克风：纯图标，点一下开始录，再点一下结束并识别
  Widget _micButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: busy ? null : onMic,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 30,
          height: 30,
          child: isTranscribing
              ? const Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.accent),
                )
              : Icon(
                  isRecording ? Icons.stop : Icons.mic_none,
                  size: 20,
                  color: isRecording
                      ? AppColors.danger
                      : (isTranscribing ? AppColors.accent : AppColors.textSub),
                ),
        ),
      ),
    );
  }
}
