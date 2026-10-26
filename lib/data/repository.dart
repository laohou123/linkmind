import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../util/ids.dart';
import '../util/text_match.dart';
import 'database.dart';
import 'models.dart';

class MatchCandidate {
  final EntityRec entity;
  final double score;
  const MatchCandidate(this.entity, this.score);
}

class CommitResult {
  final String factId;
  final List<String> supersededIds;
  final bool alreadyExists;

  /// 两端被解析成了同一个实体，这条关系被拒绝写入
  final bool selfLoop;

  const CommitResult({
    required this.factId,
    required this.supersededIds,
    required this.alreadyExists,
    this.selfLoop = false,
  });
}

/// 所有数据读写都在这里。UI 与模型层都不直接碰 SQL。
class GraphRepository {
  static final GraphRepository instance = GraphRepository._();
  GraphRepository._();

  // ------------------------------------------------------------------ 读图

  /// 生成给 WebView 的图数据。只画有关系的实体，孤立实体不进图。
  Future<Map<String, Object?>> graphPayload() async {
    final db = await AppDatabase.instance();
    final entityRows = await db.query('entities', where: 'deletedAt IS NULL');
    // 只画仍然有效的事实；被替换(superseded)的旧关系留在库里做历史，但不进图
    final facts = await db.query('facts', where: "status = 'confirmed'");
    final posRows = await db.query('node_positions');

    final entities = {for (final r in entityRows) r['id'] as String: EntityRec.fromMap(r)};
    // 注意：node_positions 的主键列名是 entityId，不是 id
    final positions = {for (final r in posRows) r['entityId'] as String: r};

    final connected = <String>{};
    for (final f in facts) {
      final s = f['subjectId'] as String;
      final o = f['objectId'] as String;
      if (entities.containsKey(s) && entities.containsKey(o)) {
        connected..add(s)..add(o);
      }
    }

    final nodes = <Map<String, Object?>>[];
    for (final id in connected) {
      final e = entities[id]!;
      final p = positions[id];
      nodes.add(GraphNode(
        e.id,
        e.name,
        e.type,
        FactStatus.confirmed,
        x: (p?['x'] as num?)?.toDouble(),
        y: (p?['y'] as num?)?.toDouble(),
      ).toJson());
    }

    final edges = <Map<String, Object?>>[];
    for (final f in facts) {
      final s = f['subjectId'] as String;
      final o = f['objectId'] as String;
      if (!connected.contains(s) || !connected.contains(o)) continue;
      // 自己连自己的边画出来就是个圈，没有任何信息量
      if (s == o) continue;

      final predicate = Predicate.fromCode(f['predicate'] as String);
      var from = s;
      var to = o;
      var label = Predicate.labelOf(f['predicate'] as String);

      // 箭头永远指向"流向的下游"：
      // "湿矿 电源来自 电除尘" → 画成 电除尘 --向其供电--> 湿矿
      if (predicate != null && predicate.isReverseFlow) {
        from = o;
        to = s;
        label = predicate.inverseLabel;
      }

      // 线缆是边的属性，不是节点：标签直接写"光纤连接""C-012 电源线连接"
      final cable = _cableOf(f['metadataJson'] as String?);
      if (cable.isNotEmpty) {
        label = cable;   // 箭头上的字就是线缆本身：A --光纤→ B
      }

      edges.add(GraphEdge(
        f['id'] as String,
        from,
        to,
        label,
        (f['status'] as String?) ?? FactStatus.confirmed,
      ).toJson());
    }

    return {'nodes': nodes, 'edges': edges};
  }

  Future<void> savePositions(List<Map<String, Object?>> positions) async {
    final db = await AppDatabase.instance();
    final now = nowMs();
    final batch = db.batch();
    for (final p in positions) {
      batch.insert(
        'node_positions',
        {
          'entityId': p['id'],
          'x': (p['x'] as num).toDouble(),
          'y': (p['y'] as num).toDouble(),
          'updatedAt': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  // -------------------------------------------------------------- 实体匹配

  // ------------------------------------------------------------ 备份导出/导入

  /// 全量导出：实体、关系、节点坐标都要，一个不落。
  /// 已失效的关系和软删除的实体也一起带走 —— 那是历史，恢复后还要能查。
  Future<Map<String, Object?>> exportAll() async {
    final db = await AppDatabase.instance();
    return {
      'entities': await db.query('entities'),
      'facts': await db.query('facts'),
      'positions': await db.query('node_positions'),
    };
  }

  /// 导入前先看看备份里有什么，好让用户确认
  Future<Map<String, int>> countAll() async {
    final db = await AppDatabase.instance();
    Future<int> count(String sql) async {
      final r = await db.rawQuery(sql);
      return (r.first.values.first as num).toInt();
    }

    return {
      'entities': await count('SELECT COUNT(*) FROM entities WHERE deletedAt IS NULL'),
      'facts': await count("SELECT COUNT(*) FROM facts WHERE status = 'confirmed'"),
      'superseded': await count("SELECT COUNT(*) FROM facts WHERE status != 'confirmed'"),
    };
  }

  /// 用备份替换当前数据。
  ///
  /// 是「替换」不是「合并」：备份恢复的场景（换手机、重装）里，
  /// 合并会把旧设备的同名实体掺进来，反而更难理清。
  Future<int> importAll(Map<String, Object?> data) async {
    final entities = _asRows(data['entities']);
    final facts = _asRows(data['facts']);
    final positions = _asRows(data['positions']);

    final db = await AppDatabase.instance();
    return db.transaction<int>((txn) async {
      await txn.delete('facts');
      await txn.delete('node_positions');
      await txn.delete('entities');

      // 按当前表结构过滤字段：老备份可能少列，新备份可能多列，
      // 直接 insert 会因为列不存在整批失败。
      final entityCols = await _columns(txn, 'entities');
      final factCols = await _columns(txn, 'facts');
      final posCols = await _columns(txn, 'node_positions');

      for (final row in entities) {
        await txn.insert('entities', _pick(row, entityCols),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in facts) {
        await txn.insert('facts', _pick(row, factCols),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final row in positions) {
        await txn.insert('node_positions', _pick(row, posCols),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }

      return entities.length;
    });
  }

  List<Map<String, Object?>> _asRows(Object? raw) {
    if (raw is! List) return const [];
    final out = <Map<String, Object?>>[];
    for (final item in raw) {
      if (item is Map) {
        out.add(item.map((k, v) => MapEntry(k.toString(), v)));
      }
    }
    return out;
  }

  Future<Set<String>> _columns(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return rows.map((r) => r['name'].toString()).toSet();
  }

  Map<String, Object?> _pick(Map<String, Object?> row, Set<String> allowed) {
    final out = <String, Object?>{};
    for (final entry in row.entries) {
      if (allowed.contains(entry.key)) out[entry.key] = entry.value;
    }
    return out;
  }

  /// 只取名字（含别名），用于生成 ASR 热词。比 allEntities 轻。
  Future<List<String>> allEntityNames() async {
    final db = await AppDatabase.instance();
    final rows = await db.query(
      'entities',
      columns: ['name', 'aliases'],
      where: 'deletedAt IS NULL',
    );
    final out = <String>[];
    for (final r in rows) {
      final name = r['name'] as String?;
      if (name != null && name.trim().isNotEmpty) out.add(name);
      final raw = r['aliases'] as String?;
      if (raw != null && raw.isNotEmpty) out.addAll(_aliases(raw));
    }
    return out;
  }

  Future<List<EntityRec>> allEntities() async {
    final db = await AppDatabase.instance();
    final rows = await db.query('entities', where: 'deletedAt IS NULL');
    return rows.map(EntityRec.fromMap).toList();
  }

  Future<List<MatchCandidate>> candidatesFor(String mention, {int limit = 5}) async {
    final db = await AppDatabase.instance();
    return _candidates(db, mention, limit: limit);
  }

  Future<MatchCandidate?> bestMatch(String mention) async {
    final list = await candidatesFor(mention, limit: 1);
    if (list.isEmpty || list.first.score < 0.55) return null;
    return list.first;
  }

  Future<List<MatchCandidate>> _candidates(
    DatabaseExecutor db,
    String mention, {
    int limit = 5,
  }) async {
    final rows = await db.query('entities', where: 'deletedAt IS NULL');
    final scored = <MatchCandidate>[];
    for (final row in rows) {
      final e = EntityRec.fromMap(row);
      var best = TextMatch.similarityWithCode(mention, e.name);
      for (final alias in _aliases(e.aliases)) {
        final s = TextMatch.similarityWithCode(mention, alias) * 0.98;
        if (s > best) best = s;
      }
      if (best >= 0.42) scored.add(MatchCandidate(e, best));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList();
  }

  List<String> _aliases(String json) {
    try {
      final list = jsonDecode(json);
      if (list is List) return list.map((e) => e.toString()).toList();
    } catch (_) {}
    return const [];
  }

  // ---------------------------------------------------------------- 写入

  /// 确认后写入。整段在一个事务里，任何一步失败都不留半条数据。
  /// 冲突策略：同主语 + 同谓词下若已有不同的宾语，旧事实置为 superseded 并留档。
  Future<CommitResult> commitDraft(
    FactDraft draft, {
    String? subjectId,
    String? objectId,
  }) async {
    final db = await AppDatabase.instance();
    return db.transaction<CommitResult>((txn) async {
      final now = nowMs();
      final subject = await _resolveOrCreate(txn, draft.subjectName, draft.subjectType, now, subjectId);
      final object = await _resolveOrCreate(txn, draft.objectName, draft.objectType, now, objectId);

      // 自己指向自己的关系没有意义，只会让图上多一个绕圈的箭头。
      // 出现这种情况一定是两端被合并到了同一个实体（多半是名字太像），
      // 直接拒绝，让上层提示用户改名重说，而不是把脏数据写进去。
      if (subject.id == object.id) {
        return CommitResult(
          factId: '',
          supersededIds: const [],
          alreadyExists: false,
          selfLoop: true,
        );
      }

      final existingRows = await txn.query(
        'facts',
        where: "subjectId = ? AND predicate = ? AND status = 'confirmed'",
        whereArgs: [subject.id, draft.predicate.code],
      );
      final existing = existingRows.map(FactRec.fromMap).toList();

      final dup = existing.where((f) => f.objectId == object.id).toList();
      if (dup.isNotEmpty) {
        return CommitResult(factId: dup.first.id, supersededIds: const [], alreadyExists: true);
      }

      final superseded = existing.where((f) => f.objectId != object.id).toList();
      for (final old in superseded) {
        await txn.update(
          'facts',
          {'status': FactStatus.superseded, 'validUntil': now, 'updatedAt': now},
          where: 'id = ?',
          whereArgs: [old.id],
        );
        await _audit(txn, 'fact', old.id, 'supersede', old.originalText,
            '被新记录替代：${draft.subjectName} ${draft.predicate.label} ${draft.objectName}', now);
      }

      final factId = newId();
      await txn.insert('facts', {
        'id': factId,
        'subjectId': subject.id,
        'predicate': draft.predicate.code,
        'objectId': object.id,
        'status': FactStatus.confirmed,
        'originalText': '${draft.subjectName}${draft.predicate.label}${draft.objectName}',
        'sourceType': 'user_input',
        'createdAt': now,
        'updatedAt': now,
        'supersedesFactId': superseded.isEmpty ? null : superseded.first.id,
        'metadataJson': draft.cableNote.trim().isEmpty
            ? null
            : jsonEncode({'cable': draft.cableNote.trim()}),
      });
      await _audit(txn, 'fact', factId, 'create', null,
          '${subject.name} -[${draft.predicate.code}]-> ${object.name}', now);

      return CommitResult(
        factId: factId,
        supersededIds: superseded.map((e) => e.id).toList(),
        alreadyExists: false,
      );
    });
  }

  Future<EntityRec> _resolveOrCreate(
    DatabaseExecutor db,
    String name,
    String type,
    int now, [
    String? forcedId,
  ]) async {
    if (forcedId != null) {
      final rows = await db.query('entities', where: 'id = ?', whereArgs: [forcedId]);
      if (rows.isNotEmpty) return EntityRec.fromMap(rows.first);
    }
    final candidates = await _candidates(db, name, limit: 1);
    if (candidates.isNotEmpty &&
        candidates.first.score >= 0.86 &&
        EntityTypes.compatible(candidates.first.entity.type, type)) {
      return candidates.first.entity;
    }
    final created = EntityRec(
      id: newId(),
      name: name.trim(),
      normalizedName: TextMatch.normalize(name),
      type: type.trim().isEmpty ? EntityTypes.unknown : type.trim(),
      createdAt: now,
      updatedAt: now,
    );
    await db.insert('entities', created.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    await _audit(db, 'entity', created.id, 'create', null, created.name, now);
    return created;
  }

  Future<void> _audit(
    DatabaseExecutor db,
    String targetType,
    String targetId,
    String action,
    String? before,
    String? after,
    int at,
  ) async {
    await db.insert('audit_log', {
      'id': newId(),
      'targetType': targetType,
      'targetId': targetId,
      'action': action,
      'beforeJson': before,
      'afterJson': after,
      'at': at,
      'source': 'user_input',
    });
  }

  /// 把 source 并进 target：
  /// 事实改指向 target、旧名变成 target 的别名、源实体软删除。
  /// 合并后产生的重复事实只留最早一条，其余置为已失效；自环（自己连自己）直接作废。
  Future<int> mergeEntities(String sourceId, String targetId) async {
    if (sourceId == targetId) return 0;
    final db = await AppDatabase.instance();
    return db.transaction<int>((txn) async {
      final now = nowMs();
      final rows = await txn.query('entities',
          where: 'id IN (?, ?)', whereArgs: [sourceId, targetId]);
      final byId = {for (final r in rows) r['id'] as String: EntityRec.fromMap(r)};
      final source = byId[sourceId];
      final target = byId[targetId];
      if (source == null || target == null) return 0;

      // 旧名记进别名，以后用户说旧名字也能对上
      final aliases = <String>{};
      aliases.addAll(_aliases(target.aliases));
      aliases.addAll(_aliases(source.aliases));
      aliases.add(source.name);
      aliases.remove(target.name);
      await txn.update(
        'entities',
        {'aliases': jsonEncode(aliases.toList()), 'updatedAt': now},
        where: 'id = ?',
        whereArgs: [targetId],
      );

      final movedFrom = await txn.update('facts', {'subjectId': targetId},
          where: 'subjectId = ?', whereArgs: [sourceId]);
      final movedTo = await txn.update('facts', {'objectId': targetId},
          where: 'objectId = ?', whereArgs: [sourceId]);

      // 合并后自己连自己的边没有意义
      await txn.update(
        'facts',
        {'status': FactStatus.superseded, 'validUntil': now, 'updatedAt': now},
        where: "status = 'confirmed' AND subjectId = ? AND objectId = ?",
        whereArgs: [targetId, targetId],
      );

      // 合并后可能撞出重复事实：同主语同谓词同宾语，只留最早一条
      final groups = await txn.rawQuery("""
        SELECT subjectId, predicate, objectId, COUNT(*) AS c, MIN(createdAt) AS firstAt
        FROM facts WHERE status = 'confirmed'
        GROUP BY subjectId, predicate, objectId HAVING c > 1
      """);
      for (final g in groups) {
        final extras = await txn.query(
          'facts',
          where: "status = 'confirmed' AND subjectId = ? AND predicate = ? "
              "AND objectId = ? AND createdAt > ?",
          whereArgs: [g['subjectId'], g['predicate'], g['objectId'], g['firstAt']],
        );
        for (final e in extras) {
          await txn.update(
            'facts',
            {'status': FactStatus.superseded, 'validUntil': now, 'updatedAt': now},
            where: 'id = ?',
            whereArgs: [e['id']],
          );
        }
      }

      await txn.update('entities', {'deletedAt': now, 'updatedAt': now},
          where: 'id = ?', whereArgs: [sourceId]);
      await txn.delete('node_positions', where: 'entityId = ?', whereArgs: [sourceId]);
      await _audit(txn, 'entity', targetId, 'merge', source.name, target.name, now);

      return movedFrom + movedTo;
    });
  }

  /// 废弃一条事实（软删除，保留历史）
  Future<void> retireFact(String factId) async {
    final db = await AppDatabase.instance();
    await db.transaction((txn) async {
      final now = nowMs();
      final rows = await txn.query('facts', where: 'id = ?', whereArgs: [factId]);
      if (rows.isEmpty) return;
      final fact = FactRec.fromMap(rows.first);
      await txn.update(
        'facts',
        {'status': FactStatus.superseded, 'validUntil': now, 'updatedAt': now},
        where: 'id = ?',
        whereArgs: [factId],
      );
      await _audit(txn, 'fact', factId, 'retire', fact.originalText, null, now);
    });
  }

  // ---------------------------------------------------------------- 查询

  Future<FactView?> factView(String factId) async {
    final db = await AppDatabase.instance();
    final rows = await db.query('facts', where: 'id = ?', whereArgs: [factId]);
    if (rows.isEmpty) return null;
    final names = await _nameMap(db);
    return _toView(FactRec.fromMap(rows.first), names);
  }

  Future<Map<String, Object?>> entityDetail(String entityId) async {
    final db = await AppDatabase.instance();
    final rows = await db.query('entities', where: 'id = ?', whereArgs: [entityId]);
    if (rows.isEmpty) return {'entity': null, 'facts': []};
    final entity = EntityRec.fromMap(rows.first);
    final names = await _nameMap(db);

    final outgoing = await db.query('facts',
        where: "subjectId = ? AND status IN ('confirmed','superseded')", whereArgs: [entityId]);
    final incoming = await db.query('facts',
        where: "objectId = ? AND status IN ('confirmed','superseded')", whereArgs: [entityId]);

    final views = <FactView>[];
    final seen = <String>{};
    for (final r in [...outgoing, ...incoming]) {
      final f = FactRec.fromMap(r);
      if (!seen.add(f.id)) continue;
      final v = _toView(f, names);
      if (v != null) views.add(v);
    }
    // 有效的排前面，已失效的沉底但保留，方便追溯"以前接的是谁"
    views.sort((a, b) {
      final aok = a.status == FactStatus.confirmed ? 0 : 1;
      final bok = b.status == FactStatus.confirmed ? 0 : 1;
      if (aok != bok) return aok - bok;
      return b.createdAt.compareTo(a.createdAt);
    });

    return {
      'entity': {
        'id': entity.id,
        'name': entity.name,
        'type': entity.type,
        'description': entity.description,
      },
      'facts': views
          .map((v) => {
                'id': v.id,
                'subject': v.subjectName,
                'object': v.objectName,
                'predicate': v.predicateLabel,
                'original': v.originalText,
                'date': shortDate(v.createdAt),
                'status': v.status,
              })
          .toList(),
    };
  }

  /// 找出这条新关系会顶掉哪些旧记录（同主语、同谓词、不同宾语）
  /// 用于确认卡片上提前告知"将替换 XXX"
  Future<List<FactView>> conflictsFor(FactDraft draft) async {
    final db = await AppDatabase.instance();
    final candidates = await _candidates(db, draft.subjectName, limit: 1);
    if (candidates.isEmpty || candidates.first.score < 0.55) return const [];
    final subject = candidates.first.entity;

    final rows = await db.query(
      'facts',
      where: "subjectId = ? AND predicate = ? AND status = 'confirmed'",
      whereArgs: [subject.id, draft.predicate.code],
    );
    final names = await _nameMap(db);
    final out = <FactView>[];
    for (final r in rows) {
      final f = FactRec.fromMap(r);
      final oldObject = names[f.objectId]?.name;
      // 宾语本质相同 = 重复记录，不算冲突
      if (oldObject != null && TextMatch.similarity(oldObject, draft.objectName) >= 0.86) {
        continue;
      }
      final v = _toView(f, names);
      if (v != null) out.add(v);
    }
    return out;
  }

  /// 找出现有的、需要被作废的事实（用于"XX 不再来自 YY"这类指令）
  Future<List<FactView>> factsToRetire({
    required String subjectName,
    String? predicateCode,
    String? objectName,
  }) async {
    final db = await AppDatabase.instance();
    final match = await bestMatch(subjectName);
    if (match == null) return const [];

    final rows = await db.query(
      'facts',
      where: "subjectId = ? AND status = 'confirmed'",
      whereArgs: [match.entity.id],
    );
    final names = await _nameMap(db);
    final out = <FactView>[];
    for (final r in rows) {
      final f = FactRec.fromMap(r);
      if (predicateCode != null && predicateCode.isNotEmpty && f.predicate != predicateCode) {
        continue;
      }
      if (objectName != null && objectName.trim().isNotEmpty) {
        final objName = names[f.objectId]?.name;
        if (objName == null || TextMatch.similarity(objName, objectName) < 0.55) continue;
      }
      final v = _toView(f, names);
      if (v != null) out.add(v);
    }
    return out;
  }

  Future<Map<String, EntityRec>> _nameMap(DatabaseExecutor db) async {
    final rows = await db.query('entities');
    return {for (final r in rows) r['id'] as String: EntityRec.fromMap(r)};
  }

  /// "线缆连接"和"连接到"对用户来说是同一件事，查询时互相认
  bool _sameRelation(String stored, Predicate asked) {
    if (stored == asked.code) return true;
    const cableFamily = { 'cable_connects', 'connected_to' };
    return cableFamily.contains(stored) && cableFamily.contains(asked.code);
  }

  String _cableOf(String? metadataJson) {
    if (metadataJson == null || metadataJson.isEmpty) return '';
    try {
      final m = jsonDecode(metadataJson);
      if (m is Map && m['cable'] is String) return (m['cable'] as String).trim();
    } catch (_) {}
    return '';
  }

  FactView? _toView(FactRec fact, Map<String, EntityRec> names) {
    final s = names[fact.subjectId];
    final o = names[fact.objectId];
    if (s == null || o == null) return null;
    return FactView(
      id: fact.id,
      subjectName: s.name,
      objectName: o.name,
      predicateLabel: Predicate.labelOf(fact.predicate),
      status: fact.status,
      originalText: fact.originalText,
      createdAt: fact.createdAt,
      cableNote: _cableOf(fact.metadataJson),
    );
  }

  /// 回答用户的问题。
  ///
  /// 关键设计：答案只由数据库里的事实拼出来，模型不参与措辞。
  /// 这样即使模型被诱导，也不可能「编造」一条不存在的线路。
  Future<AnswerResult> answer(String mention, String? predicateCode) async {
    final db = await AppDatabase.instance();
    final match = await bestMatch(mention);
    if (match == null) {
      return AnswerResult(
        text: '当前记录里没有找到「$mention」这个设备。\n如果是新设备，直接说一句关系就能记下来。',
        isEmpty: true,
      );
    }

    final entity = match.entity;
    final names = await _nameMap(db);
    final outgoing = (await db.query('facts',
            where: "subjectId = ? AND status = 'confirmed'", whereArgs: [entity.id]))
        .map(FactRec.fromMap)
        .toList();
    final incoming = (await db.query('facts',
            where: "objectId = ? AND status = 'confirmed'", whereArgs: [entity.id]))
        .map(FactRec.fromMap)
        .toList();

    final predicate = Predicate.fromCode(predicateCode);
    final wanted = predicate == null
        ? [...outgoing, ...incoming]
        : [...outgoing, ...incoming].where((f) => _sameRelation(f.predicate, predicate)).toList();

    if (wanted.isNotEmpty) {
      final views = wanted.map((f) => _toView(f, names)).whereType<FactView>().toList();
      // 高亮要覆盖：边本身 + 它两端的节点，缺一端就会出现"只亮一半"
      final highlight = <String>[];
      for (final f in wanted) {
        highlight
          ..add(f.id)
          ..add(f.subjectId)
          ..add(f.objectId);
      }
      return AnswerResult(
        text: _composeDirect(entity.name, views),
        highlightIds: highlight.toSet().toList(),
        evidence: views,
      );
    }

    // 指定的那种关系没有，但这个实体还有别的记录：先把已有记录摊给用户，
    // 别一句"没有记录"把人打发了
    final all = [...outgoing, ...incoming];
    if (predicate != null && all.isNotEmpty) {
      final views = all.map((f) => _toView(f, names)).whereType<FactView>().toList();
      return AnswerResult(
        text: '没有「${predicate.label}」这类记录，但「${entity.name}」还有这些：\n'
            '${_composeDirect(entity.name, views)}',
        highlightIds: [...all.map((f) => f.id), entity.id],
        evidence: views,
      );
    }

    // 直接没有 → 尝试顺着供电链路上游追溯
    final chain = await _powerChain(db, entity.id, names);
    if (chain.isNotEmpty) {
      final pathText = [entity.name, ...chain.map((c) => c.name)].join(' ← ');
      return AnswerResult(
        text: '记录里没有「${entity.name}」的直接来源，但顺着已记录的关系可以追到：\n'
            '$pathText\n共 ${chain.length} 跳，最终来源是「${chain.last.name}」。',
        highlightIds: [...chain.map((c) => c.fact.id), entity.id],
        evidence: chain
            .map((c) => _toView(c.fact, names))
            .whereType<FactView>()
            .toList(),
      );
    }

    return AnswerResult(
      text: '当前记录里没有「${entity.name}」的相关依据。\n'
          '我不会替你猜——需要的话，补一句「${entity.name} 电源来自 XXX」我就记住了。',
      highlightIds: [entity.id],
      isEmpty: true,
    );
  }

  Future<List<_ChainHop>> _powerChain(
    DatabaseExecutor db,
    String startId,
    Map<String, EntityRec> names,
  ) async {
    final chain = <_ChainHop>[];
    final visited = <String>{startId};
    var cursor = startId;
    const maxDepth = 4;

    for (var i = 0; i < maxDepth; i++) {
      final rows = await db.query(
        'facts',
        where: "subjectId = ? AND status = 'confirmed'",
        whereArgs: [cursor],
      );
      final next = rows
          .map(FactRec.fromMap)
          .where((f) =>
              Predicate.powerChain.contains(f.predicate) && !visited.contains(f.objectId))
          .toList();
      if (next.isEmpty) break;
      final fact = next.first;
      final target = names[fact.objectId];
      if (target == null) break;
      chain.add(_ChainHop(target.name, fact));
      visited.add(fact.objectId);
      cursor = fact.objectId;
    }
    return chain;
  }

  String _composeDirect(String subject, List<FactView> views) {
    if (views.isEmpty) return '';
    if (views.length == 1) {
      final v = views.first;
      final cable = v.cableNote.isEmpty ? '' : '（经${v.cableNote}）';
      final sentence = v.subjectName == subject
          ? '$subject ${v.predicateLabel}「${v.objectName}」$cable。'
          : '$subject 被「${v.subjectName}」${v.predicateLabel}$cable。';
      return '$sentence\n依据：${shortDate(v.createdAt)} 你记录的原文「${v.originalText}」';
    }
    final lines = views.take(5).map((v) {
      final cable = v.cableNote.isEmpty ? '' : '（经${v.cableNote}）';
      final body = v.subjectName == subject
          ? '${v.predicateLabel}「${v.objectName}」$cable'
          : '被「${v.subjectName}」${v.predicateLabel}$cable';
      return '· $body　（${shortDate(v.createdAt)} 记录）';
    }).join('\n');
    return '$subject 共有 ${views.length} 条相关记录：\n$lines';
  }

  Future<int> entityCount() async {
    final db = await AppDatabase.instance();
    final r = await db.rawQuery('SELECT COUNT(*) AS c FROM entities WHERE deletedAt IS NULL');
    return (r.first['c'] as int?) ?? 0;
  }

  Future<List<Map<String, Object?>>> searchEntities(String query, {int limit = 12}) async {
    final list = await candidatesFor(query, limit: limit);
    return list
        .map((c) => {'id': c.entity.id, 'name': c.entity.name, 'type': c.entity.type})
        .toList();
  }
}

class _ChainHop {
  final String name;
  final FactRec fact;
  const _ChainHop(this.name, this.fact);
}
