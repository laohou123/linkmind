import 'dart:convert';

import '../data/models.dart';
import 'llm_client.dart';
import 'prompts.dart';
import '../data/settings.dart';

/// 模型解析结果
class ParsedInput {
  final String intent; // add / query / retire / rename / unclear
  final List<FactDraft> facts;
  final String? queryEntity;
  final String? queryPredicate;

  /// retire 专用：要作废哪一条关系
  final String? retireSubject;
  final String? retirePredicate;
  final String? retireObject;

  /// rename 专用：把哪个设备改成什么名字
  final String? renameFrom;
  final String? renameTo;
  final String reason;

  const ParsedInput({
    required this.intent,
    this.facts = const [],
    this.queryEntity,
    this.queryPredicate,
    this.retireSubject,
    this.retirePredicate,
    this.retireObject,
    this.renameFrom,
    this.renameTo,
    this.reason = '',
  });
}

class FactParser {
  /// 把一句话解析成结构化结果。
  /// 解析失败会抛 LlmException，由上层展示中文错误，不会写入任何数据。
  static Future<ParsedInput> parse({
    required String input,
    required List<String> knownEntities,
    required LlmSettings settings,
  }) async {
    final raw = await LlmClient.instance.chat(
      settings: settings,
      messages: Prompts.parseMessages(input, knownEntities),
    );
    final json = _extractJson(raw);
    if (json == null) {
      throw const LlmException('模型没有按格式返回，再试一次通常就好了。', retryable: true);
    }
    final result = _fromJson(json, input);

    // 模型偶尔把「改名」判成提问（"修改A为B" 看着像在问什么）。
    // 这种句式很固定，本地认一次兜底，不依赖模型这次的判断。
    if (result.intent == 'query' || result.intent == 'unclear') {
      final renamed = _renameFromText(input);
      if (renamed != null) {
        return ParsedInput(
          intent: 'rename',
          renameFrom: renamed[0],
          renameTo: renamed[1],
          reason: '按改名句式识别',
        );
      }
    }
    return result;
  }

  /// 像「把 A 改名为 B」「修改 A 为 B」这类句式
  static final List<RegExp> _renamePatterns = [
    RegExp(r'^把\s*(.+?)\s*(?:改名为|改叫|改成|改为|修改为|更名为)\s*(.+?)\s*[。！？!?]?$'),
    RegExp(r'^将\s*(.+?)\s*(?:改名为|改叫|改成|改为|修改为|更名为)\s*(.+?)\s*[。！？!?]?$'),
    RegExp(r'^修改\s*(.+?)\s*为\s*(.+?)\s*[。！？!?]?$'),
    RegExp(r'^(.+?)\s*(?:改名为|改名叫|改叫|更名为)\s*(.+?)\s*[。！？!?]?$'),
    RegExp(r'^(.+?)\s*的名字\s*(?:改成|改为|修改为)\s*(.+?)\s*[。！？!?]?$'),
  ];

  /// 出现这些词，说的是改关系（"电源改到别处"），不是改名字
  static const List<String> _relationHints = [
    '电源', '供电', '网线', '光纤', '电缆', '线缆', '来自', '接到', '连到',
    '连接', '上联', '位于', '属于', '控制', '信号', '改到', '改接',
  ];

  /// 命中改名句式就返回 [原名, 新名]，否则 null
  static List<String>? _renameFromText(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    // 提到关系词，说的是"改关系"，交给 retire / add 处理
    for (final hint in _relationHints) {
      if (text.contains(hint)) return null;
    }

    for (final p in _renamePatterns) {
      final m = p.firstMatch(text);
      if (m == null) continue;
      final from = m.group(1)?.trim() ?? '';
      final to = m.group(2)?.trim() ?? '';
      if (from.isEmpty || to.isEmpty || from == to) continue;
      // 名字正常不会这么长，太长说明整句话被吞进来了，不靠谱
      if (from.length > 30 || to.length > 30) continue;
      return [from, to];
    }
    return null;
  }

  /// 模型偶尔会包 ```json 代码块，或者前后多说一句话，这里做容错
  static Map<String, dynamic>? _extractJson(String raw) {
    var text = raw.trim();
    if (text.startsWith('```')) {
      final firstNewline = text.indexOf('\n');
      if (firstNewline > 0) text = text.substring(firstNewline + 1);
      if (text.endsWith('```')) text = text.substring(0, text.length - 3);
      text = text.trim();
    }
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    try {
      final decoded = jsonDecode(text.substring(start, end + 1));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  static ParsedInput _fromJson(Map<String, dynamic> json, String input) {
    final intent = (json['intent'] as String?)?.toLowerCase().trim() ?? 'unclear';
    final reason = (json['reason'] as String?) ?? '';
    final list = json['facts'];

    if (intent == 'query') {
      final q = json['query'];
      String? entity;
      String? predicate;
      if (q is Map) {
        entity = (q['entity'] as String?)?.trim();
        predicate = (q['predicate'] as String?)?.trim();
      }
      return ParsedInput(
        intent: 'query',
        queryEntity: (entity == null || entity.isEmpty) ? input : entity,
        queryPredicate: (predicate == null || predicate.isEmpty) ? null : predicate,
        reason: reason,
      );
    }

    if (intent == 'retire') {
      final r = json['retire'];
      String? subject;
      String? predicate;
      String? object;
      if (r is Map) {
        subject = (r['subject'] as String?)?.trim();
        predicate = (r['predicate'] as String?)?.trim();
        object = (r['object'] as String?)?.trim();
      }
      // 模型可能把 retire 的信息放进了 facts 里
      if ((subject == null || subject.isEmpty) && list is List && list.isNotEmpty) {
        final first = list.first;
        if (first is Map) {
          subject = (first['subject'] as String?)?.trim();
          predicate = (first['predicate'] as String?)?.trim();
          object = (first['object'] as String?)?.trim();
        }
      }
      if (subject != null && subject.isNotEmpty) {
        return ParsedInput(
          intent: 'retire',
          retireSubject: subject,
          retirePredicate: (predicate == null || predicate.isEmpty) ? null : predicate,
          retireObject: (object == null || object.isEmpty) ? null : object,
          reason: reason,
        );
      }
    }

    // 改名：只改名字，不动关系，所以单独走一路，不进 facts
    if (intent == 'rename') {
      final r = json['rename'];
      String? from;
      String? to;
      if (r is Map) {
        from = (r['from'] as String?)?.trim();
        to = (r['to'] as String?)?.trim();
      }
      // 模型偶尔把改名塞进 facts：主宾填了名但没有谓词，多半是改名
      if ((from == null || from.isEmpty || to == null || to.isEmpty) &&
          list is List &&
          list.isNotEmpty) {
        final first = list.first;
        if (first is Map) {
          from ??= (first['subject'] as String?)?.trim();
          to ??= (first['object'] as String?)?.trim();
        }
      }
      if (from != null && from.isNotEmpty && to != null && to.isNotEmpty) {
        return ParsedInput(
          intent: 'rename',
          renameFrom: from,
          renameTo: to,
          reason: reason,
        );
      }
      // 名字没拿全，退回按提问处理，至少能给点反馈
      return ParsedInput(
        intent: 'query',
        queryEntity: from ?? input,
        queryPredicate: null,
        reason: reason.isEmpty ? '没识别出要改成什么名字，按提问处理' : reason,
      );
    }

    final drafts = <FactDraft>[];
    if (list is List) {
      for (final item in list) {
        if (item is! Map) continue;
        final subject = (item['subject'] as String?)?.trim() ?? '';
        final object = (item['object'] as String?)?.trim() ?? '';
        if (subject.isEmpty || object.isEmpty) continue;
        if (subject == object) continue;
        final code = (item['predicate'] as String?)?.trim() ?? '';
        var predicate = Predicate.fromCode(code);
        predicate ??= _guessPredicate(code, input);
        drafts.add(FactDraft(
          subjectName: subject,
          subjectType: _cleanType((item['subject_type'] as String?) ?? ''),
          predicate: predicate,
          objectName: object,
          objectType: _cleanType((item['object_type'] as String?) ?? ''),
          cableNote: (item['cable'] as String?)?.trim() ?? (item['cable_note'] as String?)?.trim() ?? '',
        ));
      }
    }

    final cleaned = drafts.map(_extractCable).toList();

    if (intent == 'add' && cleaned.isNotEmpty) {
      return ParsedInput(intent: 'add', facts: cleaned, reason: reason);
    }
    if (cleaned.isNotEmpty) {
      // 模型说 unclear 但确实抽出了关系，按 add 处理，让用户确认
      return ParsedInput(intent: 'add', facts: cleaned, reason: reason);
    }
    // 没抽出关系，也没说 query —— 尝试当作提问兜底
    return ParsedInput(
      intent: 'query',
      queryEntity: input,
      queryPredicate: null,
      reason: reason.isEmpty ? '没识别出明确关系，按提问处理' : reason,
    );
  }


  /// 模型经常把线缆写进实体名里（"5#湿矿平台设备箱光纤"）。
  /// 这里本地兜一次：名字末尾是线缆词的，把它拆出来当边的属性，
  /// 同时把关系改成"线缆连接"，不让它多建一个节点。
  static const _cableWords = [
    '光纤', '网线', '电源线', '电缆', '信号线', '控制线', '通讯线', '跳线', '数据线',
  ];

  static FactDraft _extractCable(FactDraft d) {
    var subject = d.subjectName;
    var object = d.objectName;
    var cable = d.cableNote;
    var predicate = d.predicate;

    if (cable.isEmpty) {
      for (final w in _cableWords) {
        if (subject.endsWith(w) && subject.length > w.length + 1) {
          subject = subject.substring(0, subject.length - w.length).trim();
          cable = w;
          break;
        }
        if (object.endsWith(w) && object.length > w.length + 1) {
          object = object.substring(0, object.length - w.length).trim();
          cable = w;
          break;
        }
      }
    }

    // 提到了线缆，关系就该是"线缆连接"，而不是笼统的"连接到"
    if (cable.isNotEmpty &&
        (predicate == Predicate.connectedTo || predicate == Predicate.relatedTo)) {
      predicate = Predicate.cableConnects;
    }

    if (subject == d.subjectName && object == d.objectName && cable == d.cableNote) {
      return d;
    }
    return FactDraft(
      subjectName: subject,
      subjectType: d.subjectType,
      predicate: predicate,
      objectName: object,
      objectType: d.objectType,
      cableNote: cable,
      confidence: d.confidence,
    );
  }

  /// 模型偶尔会返回中文谓词或自造 code，这里做一次宽松映射
  static Predicate _guessPredicate(String code, String input) {
    final c = code.toLowerCase();
    if (c.contains('power') || c.contains('供电') || c.contains('电源')) return Predicate.poweredBy;
    if (c.contains('cable') || c.contains('线缆') || c.contains('网线')) return Predicate.cableConnects;
    if (c.contains('uplink') || c.contains('上联')) return Predicate.uplinkTo;
    if (c.contains('connect') || c.contains('连接')) return Predicate.connectedTo;
    if (c.contains('locat') || c.contains('位置') || c.contains('位于')) return Predicate.locatedIn;
    if (c.contains('belong') || c.contains('属于')) return Predicate.belongsTo;
    if (c.contains('control') || c.contains('控制')) return Predicate.controls;
    if (c.contains('signal') || c.contains('信号')) return Predicate.signalFrom;

    if (input.contains('供电') || input.contains('电源')) return Predicate.poweredBy;
    return Predicate.relatedTo;
  }

  static String _cleanType(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return EntityTypes.unknown;
    for (final known in EntityTypes.all) {
      if (known == t) return t;
    }
    if (t.contains('箱')) return '设备箱';
    if (t.contains('柜')) return '配电柜';
    if (t.contains('电源')) return '电源';
    if (t.contains('缆') || t.contains('线')) return '线缆';
    if (t.contains('端口')) return '端口';
    if (t.contains('区') || t.contains('层') || t.contains('房')) return '区域';
    if (t.contains('网络') || t.contains('交换') || t.contains('路由')) return '网络设备';
    if (t.contains('设备')) return '设备';
    return EntityTypes.unknown;
  }
}
