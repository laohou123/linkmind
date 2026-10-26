import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/models.dart';
import 'theme.dart';

/// 底部浮层容器：圆角、半透明、最高占屏 46%，内容可滚动，不长期遮挡图谱
class BottomPanel extends StatelessWidget {
  final Widget child;
  final VoidCallback? onClose;
  final Color? accent;

  const BottomPanel({super.key, required this.child, this.onClose, this.accent});

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.46;
    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.surface.withAlpha(246),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent?.withAlpha(90) ?? AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(120),
            blurRadius: 24,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 3,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// 回答面板：只显示数据库里有依据的结论，并列出依据原文
class AnswerPanel extends StatelessWidget {
  final AnswerResult answer;
  final VoidCallback onClose;
  final void Function(String factId) onOpenFact;

  /// 语音播报状态：正在念 / 已静音
  final bool isSpeaking;
  final bool muted;
  final VoidCallback? onToggleSpeech;
  final String? speechError;

  const AnswerPanel({
    super.key,
    required this.answer,
    required this.onClose,
    required this.onOpenFact,
    this.isSpeaking = false,
    this.muted = false,
    this.onToggleSpeech,
    this.speechError,
  });

  @override
  Widget build(BuildContext context) {
    final accent = answer.isEmpty ? AppColors.warning : AppColors.accent;
    return BottomPanel(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(answer.isEmpty ? Icons.help_outline : Icons.auto_awesome,
                  size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                answer.isEmpty ? '没有找到依据' : '根据已记录的事实',
                style: TextStyle(fontSize: 12, color: accent, letterSpacing: .5),
              ),
              const Spacer(),
              if (onToggleSpeech != null)
                GestureDetector(
                  onTap: onToggleSpeech,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Icon(
                      isSpeaking
                          ? Icons.volume_up
                          : (muted ? Icons.volume_off : Icons.volume_up_outlined),
                      size: 18,
                      color: isSpeaking ? accent : AppColors.textFaint,
                    ),
                  ),
                ),
              GestureDetector(
                onTap: onClose,
                child: const Icon(Icons.close, size: 18, color: AppColors.textFaint),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            answer.text,
            style: const TextStyle(
              fontSize: 15,
              height: 1.55,
              color: AppColors.text,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (speechError != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.volume_off, size: 12, color: AppColors.danger),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(speechError!,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.danger)),
                ),
              ],
            ),
          ],
          if (answer.evidence.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text('依据',
                style: TextStyle(fontSize: 11, color: AppColors.textFaint, letterSpacing: 1)),
            const SizedBox(height: 6),
            ...answer.evidence.take(4).map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GestureDetector(
                    onTap: () => onOpenFact(f.id),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${f.subjectName} ${f.predicateLabel} ${f.objectName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.textSub),
                            ),
                          ),
                          const Icon(Icons.chevron_right,
                              size: 14, color: AppColors.textFaint),
                        ],
                      ),
                    ),
                  ),
                )),
          ],
        ],
      ),
    );
  }
}

/// 错误提示：说清楚下一步该干什么，不只是抛一句"失败"
class ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback onClose;
  final VoidCallback? onOpenSettings;

  const ErrorPanel({
    super.key,
    required this.message,
    required this.onClose,
    this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return BottomPanel(
      accent: AppColors.danger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline, size: 16, color: AppColors.danger),
              const SizedBox(width: 6),
              const Text('没成功',
                  style: TextStyle(fontSize: 12, color: AppColors.danger, letterSpacing: .5)),
              const Spacer(),
              GestureDetector(
                onTap: onClose,
                child: const Icon(Icons.close, size: 18, color: AppColors.textFaint),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(message,
              style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.text)),
          if (onOpenSettings != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onOpenSettings,
                child: const Text('打开设置'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 确认卡片：模型解析出的关系必须先给人看，点了"记住"才入库
class ConfirmPanel extends StatefulWidget {
  final List<DraftResolution> drafts;
  final List<bool> useExistingSubject;
  final List<bool> useExistingObject;
  final void Function(int index, {bool? subject, bool? object}) onToggle;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool saving;

  const ConfirmPanel({
    super.key,
    required this.drafts,
    required this.useExistingSubject,
    required this.useExistingObject,
    required this.onToggle,
    required this.onConfirm,
    required this.onCancel,
    this.saving = false,
  });

  @override
  State<ConfirmPanel> createState() => _ConfirmPanelState();
}

class _ConfirmPanelState extends State<ConfirmPanel> {
  @override
  Widget build(BuildContext context) {
    return BottomPanel(
      accent: AppColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist_rtl, size: 16, color: AppColors.accent),
              const SizedBox(width: 6),
              Text(
                '这样记，对吗？',
                style: TextStyle(fontSize: 13, color: AppColors.accent, letterSpacing: .5),
              ),
              const Spacer(),
              GestureDetector(
                onTap: widget.onCancel,
                child: const Icon(Icons.close, size: 18, color: AppColors.textFaint),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(widget.drafts.length, (i) => _draftCard(i)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.saving ? null : widget.onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSub,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: widget.saving ? null : widget.onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: const Color(0xFF04202E),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: widget.saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('记住这个关系',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _draftCard(int i) {
    final r = widget.drafts[i];
    final d = r.draft;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: _entityChip(d.subjectName, d.subjectType)),
              const SizedBox(width: 6),
              Text(d.predicate.label,
                  style: const TextStyle(fontSize: 11, color: AppColors.accent)),
              const SizedBox(width: 6),
              Flexible(child: _entityChip(d.objectName, d.objectType)),
            ],
          ),
          if (d.cableNote.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  const Icon(Icons.cable, size: 12, color: AppColors.textFaint),
                  const SizedBox(width: 4),
                  Text('经「${d.cableNote}」',
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textSub)),
                ],
              ),
            ),
          if (r.subjectMatch != null || r.objectMatch != null) ...[
            const SizedBox(height: 8),
            if (r.subjectMatch != null)
              _mergeRow(
                name: r.subjectMatch!.entity.name,
                score: r.subjectMatch!.score,
                value: widget.useExistingSubject[i],
                onChanged: (v) => widget.onToggle(i, subject: v),
                note: _typeNote(r.subjectMatch!.entity.type, d.subjectType),
              ),
            if (r.objectMatch != null)
              _mergeRow(
                name: r.objectMatch!.entity.name,
                score: r.objectMatch!.score,
                value: widget.useExistingObject[i],
                onChanged: (v) => widget.onToggle(i, object: v),
                note: _typeNote(r.objectMatch!.entity.type, d.objectType),
              ),
          ],
          if (r.replaces.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.warning.withAlpha(18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.warning.withAlpha(70)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.swap_horiz, size: 13, color: AppColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '将替换旧记录：${r.replaces.map((f) => '${f.predicateLabel}「${f.objectName}」').join('、')}'
                      '\n旧记录会失效但保留历史',
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.warning, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 类型对不上时提醒一句：可能是同一台设备的不同叫法，也可能真是不一样的东西
  String? _typeNote(String existingType, String newType) {
    if (existingType.isEmpty || newType.isEmpty) return null;
    if (existingType == newType) return null;
    if (existingType == EntityTypes.unknown || newType == EntityTypes.unknown) return null;
    return '类型不一样：已有「$existingType」，这次识别成「$newType」';
  }

  Widget _mergeRow({
    required String name,
    required double score,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? note,
  }) {
    final exact = score >= 0.86;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                side: const BorderSide(color: AppColors.textFaint),
                activeColor: AppColors.accent,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    exact ? '已有同名实体「$name」，合并到它' : '可能是指「$name」，合并到它',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSub),
                  ),
                  if (note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(note,
                          style: const TextStyle(
                              fontSize: 10, color: AppColors.warning, height: 1.4)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entityChip(String name, String type) {
    final color = AppColors.typeColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(110)),
      ),
      child: Text(
        name,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: AppColors.text),
      ),
    );
  }
}

/// 作废确认：动手前必须把"要作废哪几条"摆出来
class RetirePanel extends StatelessWidget {
  final List<FactView> facts;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final bool working;

  const RetirePanel({
    super.key,
    required this.facts,
    required this.onConfirm,
    required this.onCancel,
    this.working = false,
  });

  @override
  Widget build(BuildContext context) {
    return BottomPanel(
      accent: AppColors.danger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.link_off, size: 16, color: AppColors.danger),
              const SizedBox(width: 6),
              Text('要作废这 ${facts.length} 条记录？',
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.danger, letterSpacing: .5)),
              const Spacer(),
              GestureDetector(
                onTap: onCancel,
                child: const Icon(Icons.close, size: 18, color: AppColors.textFaint),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...facts.map((f) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${f.subjectName}  ${f.predicateLabel}  ${f.objectName}',
                        style: const TextStyle(fontSize: 13, color: AppColors.text),
                      ),
                    ),
                    Text(_date(f.createdAt),
                        style: const TextStyle(fontSize: 10, color: AppColors.textFaint)),
                  ],
                ),
              )),
          const SizedBox(height: 4),
          const Text(
            '作废后不再参与回答，图上连线消失；记录本身保留为历史，可追溯。',
            style: TextStyle(fontSize: 10.5, color: AppColors.textFaint, height: 1.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: working ? null : onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSub,
                    side: const BorderSide(color: AppColors.border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('再想想'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: working ? null : onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                    foregroundColor: const Color(0xFF2B0A0A),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: working
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('确认作废',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}

/// 实体详情
class EntityPanel extends StatelessWidget {
  final Map<String, Object?> detail;
  final VoidCallback onClose;
  final void Function(String factId) onOpenFact;
  final VoidCallback? onMerge;

  const EntityPanel({
    super.key,
    required this.detail,
    required this.onClose,
    required this.onOpenFact,
    this.onMerge,
  });

  @override
  Widget build(BuildContext context) {
    final entity = detail['entity'] as Map<String, Object?>?;
    final facts = (detail['facts'] as List?) ?? const [];
    if (entity == null) {
      return BottomPanel(child: const Text('实体不存在'));
    }
    final type = entity['type'] as String? ?? EntityTypes.unknown;
    final color = AppColors.typeColor(type);

    return BottomPanel(
      accent: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  entity['name'] as String? ?? '',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
                ),
              ),
              GestureDetector(
                onTap: onClose,
                child: const Icon(Icons.close, size: 18, color: AppColors.textFaint),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Text(type,
                style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
          ),
          const SizedBox(height: 14),
          if (facts.isEmpty)
            const Text('这个设备还没有记录任何关系。',
                style: TextStyle(fontSize: 13, color: AppColors.textSub))
          else
            ...facts.map((raw) {
              final f = raw as Map<String, Object?>;
              final isOutgoing = f['subject'] == entity['name'];
              final dead = f['status'] == 'superseded';
              return GestureDetector(
                onTap: () => onOpenFact(f['id'] as String),
                child: Opacity(
                  opacity: dead ? 0.55 : 1,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: dead ? AppColors.border : AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          dead
                              ? Icons.link_off
                              : (isOutgoing ? Icons.arrow_outward : Icons.arrow_downward),
                          size: 13,
                          color: dead ? AppColors.danger : AppColors.textFaint,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              style: TextStyle(
                                fontSize: 13,
                                color: dead ? AppColors.textFaint : AppColors.text,
                                decoration: dead ? TextDecoration.lineThrough : null,
                                decorationColor: AppColors.textFaint,
                              ),
                              children: [
                                TextSpan(
                                    text: isOutgoing
                                        ? '${f['predicate']}「${f['object']}」'
                                        : '被「${f['subject']}」${f['predicate']}'),
                              ],
                            ),
                          ),
                        ),
                        if (dead)
                          const Text('已失效',
                              style: TextStyle(fontSize: 9, color: AppColors.danger))
                        else
                          Text(f['date'] as String? ?? '',
                              style: const TextStyle(fontSize: 10, color: AppColors.textFaint)),
                      ],
                    ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// 关系详情
class FactPanel extends StatelessWidget {
  final FactView fact;
  final VoidCallback onClose;
  final VoidCallback onRetire;

  const FactPanel({
    super.key,
    required this.fact,
    required this.onClose,
    required this.onRetire,
  });

  @override
  Widget build(BuildContext context) {
    return BottomPanel(
      accent: AppColors.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Text('关系详情',
                  style: TextStyle(fontSize: 12, color: AppColors.accent, letterSpacing: .5)),
              const Spacer(),
              GestureDetector(
                onTap: onClose,
                child: const Icon(Icons.close, size: 18, color: AppColors.textFaint),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${fact.subjectName}  ${fact.predicateLabel}  ${fact.objectName}',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.text, height: 1.5),
          ),
          const SizedBox(height: 12),
          _kv('原始记录', fact.originalText),
          if (fact.cableNote.isNotEmpty) _kv('所用线缆', fact.cableNote),
          _kv('记录时间', _formatDate(fact.createdAt)),
          _kv('状态', fact.status == FactStatus.confirmed ? '已确认' : '已废弃'),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.info_outline, size: 12, color: AppColors.textFaint),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '废弃后这条关系不再参与回答，但历史记录会保留，可以追溯。',
                  style: const TextStyle(fontSize: 11, color: AppColors.textFaint, height: 1.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onRetire,
              icon: const Icon(Icons.link_off, size: 15),
              label: const Text('这条已失效'),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 70,
              child: Text(k,
                  style: const TextStyle(fontSize: 12, color: AppColors.textFaint)),
            ),
            Expanded(
              child: Text(v,
                  style: const TextStyle(fontSize: 12, color: AppColors.textSub, height: 1.5)),
            ),
          ],
        ),
      );

  String _formatDate(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.year}-$m-$day $hh:$mm';
  }
}
