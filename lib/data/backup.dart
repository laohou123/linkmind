import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../llm/llm_client.dart';
import 'repository.dart';
import 'settings.dart';

/// 备份文件的读写。
///
/// 一个文件同时装两类东西：
/// 1. 节点和关系（实体、事实、坐标）—— 这是真正不能丢的
/// 2. 各项配置（模型地址、音色、识别方式）—— 换手机不用重填
///
/// API Key 默认不写进去：备份文件会在微信/云盘里传来传去，
/// 明文存 Key 风险太大。要带 Key 得用户明确勾选。
class BackupService {
  static const formatId = 'linkmind-backup';
  static const formatVersion = 1;

  /// 生成备份并写入临时文件，返回文件
  static Future<File> create({bool includeSecrets = false}) async {
    final data = await GraphRepository.instance.exportAll();
    final store = SettingsStore.instance;
    final llm = await store.load();
    final tts = store.ttsCached;
    final asr = store.asrCached;

    final payload = <String, Object?>{
      'format': formatId,
      'version': formatVersion,
      'exportedAt': DateTime.now().millisecondsSinceEpoch,
      'includeSecrets': includeSecrets,
      'counts': {
        'entities': (data['entities'] as List).length,
        'facts': (data['facts'] as List).length,
        'positions': (data['positions'] as List).length,
      },
      'data': data,
      'settings': {
        'llm': {
          'baseUrl': llm.baseUrl,
          'model': llm.model,
          'temperature': llm.temperature,
          if (includeSecrets) 'apiKey': llm.apiKey,
        },
        'tts': {
          'baseUrl': tts.baseUrl,
          'model': tts.model,
          'voice': tts.voice,
          'protocol': tts.protocol.name,
          'useSystem': tts.useSystem,
          'systemLocale': tts.systemLocale,
          if (includeSecrets) 'apiKey': tts.apiKey,
        },
        'asr': {
          'baseUrl': asr.baseUrl,
          'model': asr.model,
          'language': asr.language,
          'protocol': asr.protocol.name,
          'engine': asr.engine.name,
          'systemLocale': asr.systemLocale,
          'onDeviceOnly': asr.onDeviceOnly,
          if (includeSecrets) 'apiKey': asr.apiKey,
        },
      },
    };

    final dir = await getTemporaryDirectory();
    final stamp = _stamp(DateTime.now());
    final file = File(p.join(dir.path, 'LinkMind备份-$stamp.json'));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    return file;
  }

  /// 解析备份文件，先不落库 —— 让用户看清楚里面有多少东西再决定
  static BackupPreview inspect(String text) {
    final Map<String, Object?> json;
    try {
      final raw = jsonDecode(text);
      if (raw is! Map) {
        throw const LlmException('不是有效的备份文件');
      }
      json = raw.map((k, v) => MapEntry(k.toString(), v));
    } on FormatException {
      throw const LlmException('文件内容不是 JSON，可能选错了文件');
    }

    if (json['format'] != formatId) {
      throw const LlmException('这不是 LinkMind 的备份文件');
    }
    final version = (json['version'] as num?)?.toInt() ?? 0;
    if (version > formatVersion) {
      throw LlmException('备份来自更新版本的 App（v$version），当前版本读不了');
    }

    final data = json['data'];
    final counts = json['counts'];
    int countOf(String key) {
      if (counts is Map) {
        final v = counts[key];
        if (v is num) return v.toInt();
      }
      if (data is Map && data[key] is List) {
        return (data[key] as List).length;
      }
      return 0;
    }

    final exportedAt = (json['exportedAt'] as num?)?.toInt();

    return BackupPreview(
      payload: json,
      entities: countOf('entities'),
      facts: countOf('facts'),
      positions: countOf('positions'),
      exportedAt: exportedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(exportedAt),
      hasSecrets: json['includeSecrets'] == true,
      hasSettings: json['settings'] is Map,
    );
  }

  /// 真正写入。数据是整体替换，配置按备份里的值覆盖（Key 有才覆盖）
  static Future<BackupResult> restore(BackupPreview preview) async {
    final json = preview.payload;
    final data = json['data'];
    if (data is! Map) throw const LlmException('备份里没有数据部分');

    final count = await GraphRepository.instance
        .importAll(data.map((k, v) => MapEntry(k.toString(), v)));

    var settingsApplied = false;
    final settings = json['settings'];
    if (settings is Map) {
      settingsApplied = await _restoreSettings(settings);
    }

    return BackupResult(
      entities: count,
      settingsApplied: settingsApplied,
      keysRestored: preview.hasSecrets,
    );
  }

  static Future<bool> _restoreSettings(Map settings) async {
    final store = SettingsStore.instance;
    final current = await store.load();

    final llm = settings['llm'];
    if (llm is Map) {
      await store.save(LlmSettings(
        baseUrl: (llm['baseUrl'] as String?)?.trim().isNotEmpty == true
            ? llm['baseUrl'] as String
            : current.baseUrl,
        apiKey: (llm['apiKey'] as String?) ?? current.apiKey,
        model: (llm['model'] as String?)?.trim().isNotEmpty == true
            ? llm['model'] as String
            : current.model,
        temperature: (llm['temperature'] as num?)?.toDouble() ?? current.temperature,
      ));
    }

    final tts = settings['tts'];
    if (tts is Map) {
      final cur = store.ttsCached;
      await store.saveTts(cur.copyWith(
        baseUrl: (tts['baseUrl'] as String?) ?? cur.baseUrl,
        model: (tts['model'] as String?) ?? cur.model,
        voice: (tts['voice'] as String?) ?? cur.voice,
        useSystem: (tts['useSystem'] as bool?) ?? cur.useSystem,
        systemLocale: (tts['systemLocale'] as String?) ?? cur.systemLocale,
        apiKey: (tts['apiKey'] as String?) ?? cur.apiKey,
      ));
    }

    final asr = settings['asr'];
    if (asr is Map) {
      final cur = store.asrCached;
      await store.saveAsr(cur.copyWith(
        baseUrl: (asr['baseUrl'] as String?) ?? cur.baseUrl,
        model: (asr['model'] as String?) ?? cur.model,
        language: (asr['language'] as String?) ?? cur.language,
        engine: _engineOf(asr['engine']) ?? cur.engine,
        systemLocale: (asr['systemLocale'] as String?) ?? cur.systemLocale,
        onDeviceOnly: (asr['onDeviceOnly'] as bool?) ?? cur.onDeviceOnly,
        apiKey: (asr['apiKey'] as String?) ?? cur.apiKey,
      ));
    }

    return true;
  }

  static AsrEngine? _engineOf(Object? raw) {
    switch (raw) {
      case 'system':
        return AsrEngine.system;
      case 'offline':
        return AsrEngine.offline;
      case 'online':
        return AsrEngine.online;
      default:
        return null;
    }
  }

  static String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}';
  }
}

/// 备份文件里有什么
class BackupPreview {
  final Map<String, Object?> payload;
  final int entities;
  final int facts;
  final int positions;
  final DateTime? exportedAt;
  final bool hasSecrets;
  final bool hasSettings;

  const BackupPreview({
    required this.payload,
    required this.entities,
    required this.facts,
    required this.positions,
    required this.exportedAt,
    required this.hasSecrets,
    required this.hasSettings,
  });
}

class BackupResult {
  final int entities;
  final bool settingsApplied;
  final bool keysRestored;

  const BackupResult({
    required this.entities,
    required this.settingsApplied,
    required this.keysRestored,
  });
}
