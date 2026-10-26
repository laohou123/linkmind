/// 数据模型：实体、事实、审计日志、节点位置。
/// 命名与数据库列一一对应，方便直接 toMap / fromMap。

class EntityRec {
  final String id;
  final String name;

  /// 规范化名称（去空格、全角转半角、小写），用于模糊检索
  final String normalizedName;
  final String type;

  /// JSON 数组字符串，例如 ["33#湿矿","33号湿矿设备箱"]
  final String aliases;
  final String description;
  final int createdAt;
  final int updatedAt;

  /// 非空表示已软删除
  final int? deletedAt;

  const EntityRec({
    required this.id,
    required this.name,
    required this.normalizedName,
    required this.type,
    this.aliases = '[]',
    this.description = '',
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'normalizedName': normalizedName,
        'type': type,
        'aliases': aliases,
        'description': description,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'deletedAt': deletedAt,
      };

  factory EntityRec.fromMap(Map<String, Object?> m) => EntityRec(
        id: m['id'] as String,
        name: m['name'] as String,
        normalizedName: m['normalizedName'] as String,
        type: (m['type'] as String?) ?? EntityTypes.unknown,
        aliases: (m['aliases'] as String?) ?? '[]',
        description: (m['description'] as String?) ?? '',
        createdAt: (m['createdAt'] as int?) ?? 0,
        updatedAt: (m['updatedAt'] as int?) ?? 0,
        deletedAt: m['deletedAt'] as int?,
      );
}

class FactRec {
  final String id;
  final String subjectId;
  final String predicate;
  final String objectId;
  final String status;

  /// 用户原始输入，永远保留，作为可追溯的依据
  final String originalText;
  final String sourceType;
  final String? sourceNote;
  final int? validUntil;
  final int createdAt;
  final int updatedAt;

  /// 指向被本事实替代的旧事实
  final String? supersedesFactId;

  /// 扩展字段：如线缆 {"cable":"光纤"}
  final String? metadataJson;

  const FactRec({
    required this.id,
    required this.subjectId,
    required this.predicate,
    required this.objectId,
    required this.status,
    required this.originalText,
    this.sourceType = 'user_input',
    this.sourceNote,
    this.validUntil,
    required this.createdAt,
    required this.updatedAt,
    this.supersedesFactId,
    this.metadataJson,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'subjectId': subjectId,
        'predicate': predicate,
        'objectId': objectId,
        'status': status,
        'originalText': originalText,
        'sourceType': sourceType,
        'sourceNote': sourceNote,
        'validUntil': validUntil,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'supersedesFactId': supersedesFactId,
        'metadataJson': metadataJson,
      };

  factory FactRec.fromMap(Map<String, Object?> m) => FactRec(
        id: m['id'] as String,
        subjectId: m['subjectId'] as String,
        predicate: m['predicate'] as String,
        objectId: m['objectId'] as String,
        status: (m['status'] as String?) ?? FactStatus.confirmed,
        originalText: (m['originalText'] as String?) ?? '',
        sourceType: (m['sourceType'] as String?) ?? 'user_input',
        sourceNote: m['sourceNote'] as String?,
        validUntil: m['validUntil'] as int?,
        createdAt: (m['createdAt'] as int?) ?? 0,
        updatedAt: (m['updatedAt'] as int?) ?? 0,
        supersedesFactId: m['supersedesFactId'] as String?,
        metadataJson: m['metadataJson'] as String?,
      );
}

class FactStatus {
  static const confirmed = 'confirmed';
  static const proposed = 'proposed';
  static const superseded = 'superseded';
  static const rejected = 'rejected';
}

class EntityTypes {
  static const unknown = '未分类';
  static const cable = '线缆';

  /// 两个类型能不能当成同一个实体自动合并。
  /// 线缆和非线缆不能自动并：「5#湿矿平台设备箱」和「5#湿矿平台设备箱光纤」
  /// 名字高度重合，但一个是设备一个是线，并了就丢信息。
  static bool compatible(String a, String b) {
    if (a == b) return true;
    if (a.isEmpty || b.isEmpty || a == unknown || b == unknown) return true;
    return (a == cable) == (b == cable);
  }
  static const List<String> all = [
    '设备', '电气设备', '配电柜', '电源', '设备箱',
    '网络设备', '线缆', '端口', '区域', unknown,
  ];
}

/// 关系谓词白名单。code 存库，label 用于界面展示。
///
/// 方向约定：subject 是「下游/被描述方」，object 是「上游/来源方」。
/// 例：33#湿矿设备箱 --powered_by--> 电除尘，展示为「电源来自」。
enum Predicate {
  poweredBy('powered_by', '电源来自', '向其供电'),
  connectedTo('connected_to', '连接到', '接入'),
  cableConnects('cable_connects', '线缆连接', '线缆连接'),
  locatedIn('located_in', '位于', '区域内含'),
  uplinkTo('uplink_to', '上联至', '下联至'),
  belongsTo('belongs_to', '属于', '包含'),
  controls('controls', '控制', '受控于'),
  signalFrom('signal_from', '信号来自', '信号去往'),
  derivedFrom('derived_from', '来源于', '派生出'),
  relatedTo('related_to', '相关', '相关');

  const Predicate(this.code, this.label, this.inverseLabel);

  final String code;
  final String label;
  final String inverseLabel;

  /// 语义流向和句子主语相反的关系。
  /// "33#湿矿 电源来自 电除尘"：主语是下游，能源从"电除尘"流向"湿矿"，
  /// 所以画箭头要把方向反过来，否则箭头看起来像是湿矿在给电除尘供电。
  bool get isReverseFlow =>
      this == Predicate.poweredBy ||
      this == Predicate.signalFrom ||
      this == Predicate.derivedFrom;

  static Predicate? fromCode(String? code) {
    if (code == null) return null;
    for (final p in Predicate.values) {
      if (p.code == code) return p;
    }
    return null;
  }

  static String labelOf(String code) => fromCode(code)?.label ?? code;

  /// 可视为「供电路径」的谓词，用于多跳溯源
  static const List<String> powerChain = ['powered_by', 'uplink_to', 'cable_connects'];
}

/// 送给图谱渲染层的数据结构
class GraphNode {
  final String id;
  final String label;
  final String type;
  final String status;
  final double? x;
  final double? y;

  const GraphNode(this.id, this.label, this.type, this.status, {this.x, this.y});

  Map<String, Object?> toJson() => {
        'id': id, 'label': label, 'type': type, 'status': status,
        if (x != null) 'x': x, if (y != null) 'y': y,
      };
}

class GraphEdge {
  final String id;
  final String source;
  final String target;
  final String label;
  final String status;

  const GraphEdge(this.id, this.source, this.target, this.label, this.status);

  Map<String, Object?> toJson() => {
        'id': id, 'source': source, 'target': target,
        'label': label, 'status': status,
      };
}

/// 待确认的一条关系（模型解析出来，尚未入库）
class FactDraft {
  final String subjectName;
  final String subjectType;
  final Predicate predicate;
  final String objectName;
  final String objectType;

  /// 中间用的是什么线（光纤 / 网线 / C-012 电源线）。空表示没提到。
  final String cableNote;
  final double confidence;

  const FactDraft({
    required this.subjectName,
    required this.subjectType,
    required this.predicate,
    required this.objectName,
    required this.objectType,
    this.cableNote = '',
    this.confidence = 0.9,
  });
}

class FactView {
  final String id;
  final String subjectName;
  final String objectName;
  final String predicateLabel;
  final String status;
  final String originalText;
  final int createdAt;

  /// 中间经过的线缆（光纤 / C-012 电源线…），空表示没说
  final String cableNote;

  const FactView({
    required this.id,
    required this.subjectName,
    required this.objectName,
    required this.predicateLabel,
    required this.status,
    required this.originalText,
    required this.createdAt,
    this.cableNote = '',
  });
}

class AnswerResult {
  final String text;
  final List<String> highlightIds;
  final List<FactView> evidence;

  /// true 表示数据库里没有依据，回答是「没找到」
  final bool isEmpty;

  const AnswerResult({
    required this.text,
    this.highlightIds = const [],
    this.evidence = const [],
    this.isEmpty = false,
  });
}
