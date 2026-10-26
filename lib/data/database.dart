import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 本地 SQLite。整个 App 只有这一个库，事实是唯一权威数据源。
class AppDatabase {
  static Database? _db;

  static Future<Database> instance() async {
    final cached = _db;
    if (cached != null) return cached;
    final dir = await getDatabasesPath();
    final db = await openDatabase(
      p.join(dir, 'relation_graph.db'),
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    _db = db;
    return db;
  }

  /// v2：facts 增加 metadataJson（存线缆等附加信息），老库补齐这一列
  /// v3：清掉自己指向自己的关系（老版本把两端误判成同一实体时会写进去）
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE facts ADD COLUMN metadataJson TEXT');
    }
    if (oldVersion < 3) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final fixed = await db.update(
        'facts',
        {
          'status': 'superseded',
          'validUntil': now,
          'updatedAt': now,
        },
        where: "subjectId = objectId AND status = 'confirmed'",
      );
      if (fixed > 0) {
        // 这些记录本身没有意义，标记失效而不是删除，历史仍然可查
        await db.insert('audit_log', {
          'id': 'mig_${now}_selfloop',
          'targetType': 'fact',
          'targetId': '*',
          'action': 'fix_self_loop',
          'beforeJson': null,
          'afterJson': '作废 $fixed 条自环关系',
          'at': now,
          'source': 'migration_v3',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE entities (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        normalizedName TEXT NOT NULL,
        type TEXT NOT NULL,
        aliases TEXT NOT NULL DEFAULT '[]',
        description TEXT NOT NULL DEFAULT '',
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        deletedAt INTEGER
      )
    ''');
    await db.execute('CREATE INDEX idx_entity_norm ON entities(normalizedName)');

    await db.execute('''
      CREATE TABLE facts (
        id TEXT PRIMARY KEY,
        subjectId TEXT NOT NULL,
        predicate TEXT NOT NULL,
        objectId TEXT NOT NULL,
        status TEXT NOT NULL,
        originalText TEXT NOT NULL,
        sourceType TEXT NOT NULL DEFAULT 'user_input',
        sourceNote TEXT,
        validUntil INTEGER,
        createdAt INTEGER NOT NULL,
        updatedAt INTEGER NOT NULL,
        supersedesFactId TEXT,
        metadataJson TEXT
      )
    ''');
    await db.execute('CREATE INDEX idx_fact_subject ON facts(subjectId)');
    await db.execute('CREATE INDEX idx_fact_object ON facts(objectId)');
    await db.execute('CREATE INDEX idx_fact_predicate ON facts(predicate)');

    await db.execute('''
      CREATE TABLE audit_log (
        id TEXT PRIMARY KEY,
        targetType TEXT NOT NULL,
        targetId TEXT NOT NULL,
        action TEXT NOT NULL,
        beforeJson TEXT,
        afterJson TEXT,
        at INTEGER NOT NULL,
        source TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE node_positions (
        entityId TEXT PRIMARY KEY,
        x REAL NOT NULL,
        y REAL NOT NULL,
        updatedAt INTEGER NOT NULL
      )
    ''');
  }
}
