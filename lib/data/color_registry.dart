import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 节点颜色注册表：按「设备类别」记颜色，第一次见到就分配，以后一直用。
///
/// 为什么这么做：
/// 设备类型是模型录入时自动打的标签，只有十来个固定值，像「摄像头」这种
/// 根本没有对应类型，模型每次猜的不一样，颜色就会乱跳。
/// 所以改成看**设备名**判断类别，颜色也不写死，而是第一次遇到时从调色板
/// 挑一个还没被占用的颜色记住 —— 设备箱第一次是绿，以后一直是绿；
/// 后来加了交换机，自动再拿一个没被用过的颜色，以后交换机也固定。
///
/// 老版本硬编码的那几个颜色保留成「种子」，保证升级后用户已经习惯的颜色
/// 不会突然变掉。
class ColorRegistry {
  static final ColorRegistry instance = ColorRegistry._();
  ColorRegistry._();

  static const _kPrefs = 'node_color_map_v1';

  /// 调色板：自动分配时按顺序挑第一个没用过的。
  /// 尽量让相邻颜色差异明显，避免两个类别看起来像同一个色。
  static const List<int> palette = [
    0xFF4C8DFF, // 蓝
    0xFF13C2C2, // 青绿
    0xFFFF7A45, // 橙
    0xFF9254DE, // 紫
    0xFF36CFC9, // 浅青
    0xFFFFB020, // 琥珀
    0xFFF759AB, // 粉
    0xFF5B8FF9, // 亮蓝
    0xFF52C41A, // 绿
    0xFFFA8C16, // 深橙
    0xFF722ED1, // 深紫
    0xFFEB2F96, // 洋红
    0xFF2F9E44, // 墨绿
    0xFF08979C, // 深青
    0xFFD4380D, // 砖红
    0xFF237804, // 深绿
    0xFF096DD9, // 深蓝
    0xFFAD6800, // 土黄
    0xFFC41D7F, // 玫红
    0xFF531DAB, // 靛紫
    0xFF5CDBD3, // 薄荷
    0xFFB37FEB, // 浅紫
  ];

  /// 类别定义：类别名 → 名字里出现这些词就算这一类。
  /// 顺序就是优先级，更「本质」的放前面。
  /// 注意「区域」放在「配电柜」之前，否则「配电室」会被「配电」抢走。
  static const List<MapEntry<String, List<String>>> categories = [
    MapEntry('线缆', ['光纤', '光缆', '网线', '跳线', '尾纤', '电缆', '线缆']),
    MapEntry('网络设备',
        ['交换机', '路由器', '防火墙', '收发器', '光端机', '无线ap', '录像机', 'nvr', 'dvr']),
    MapEntry('区域', ['弱电井', '机房', '机柜', '楼层', '区域', '配电室']),
    MapEntry('配电柜', ['配电', '电源', 'ups', '变压器', '开关柜', '断路器']),
    MapEntry('设备箱', ['设备箱', '控制箱', '接线箱', '端子箱', '弱电箱']),
    MapEntry('设备', ['服务器', '工控机', '主机', '电脑']),
    MapEntry('摄像头',
        ['摄像头', '摄像机', '球机', '枪机', '半球', '云台', '相机', 'ipc', 'camera']),
    MapEntry('端口', ['端口', '接口']),
  ];

  /// 种子色：老版本写死的颜色，原样保留，避免升级后颜色突变
  static const Map<String, int> seedColors = {
    '线缆': 0xFF9254DE,
    '网络设备': 0xFF36CFC9,
    '区域': 0xFF5B8FF9,
    '配电柜': 0xFFFF7A45,
    '设备箱': 0xFF13C2C2,
    '设备': 0xFF4C8DFF,
    '摄像头': 0xFF7C4DFF,
    '端口': 0xFF8B9DC3,
    '电气设备': 0xFFFFB020,
    '电源': 0xFFF759AB,
    '未分类': 0xFF6B7A99,
  };

  final Map<String, int> _colors = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kPrefs);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          decoded.forEach((k, v) {
            if (k is String && v is String) {
              // 存成 hex 字符串，避免 0xFFxxxxxx 超出 32 位有符号整数
              final parsed = int.tryParse(v, radix: 16);
              if (parsed != null) _colors[k] = parsed;
            }
          });
        }
      }
    } catch (_) {
      // 配置读坏了就当没学过，重新按种子色走
    }
    // 种子色补齐，保证老用户看到的颜色不变
    seedColors.forEach((k, v) => _colors.putIfAbsent(k, () => v));
    _loaded = true;
  }

  /// 判断一台设备属于哪个类别：
  /// 1) 先看名字里有没有关键词，命中就是对应类别（设备箱、交换机…）
  /// 2) 没命中就去掉开头的编号，剩下的当作类别 ——
  ///    「1#排风机」「2#排风机」都会归到「排风机」，各拿一个颜色
  /// 3) 名字里实在没内容，才退回按类型
  String categoryOf(String name, String type) {
    final n = name.toLowerCase();
    for (final rule in categories) {
      for (final kw in rule.value) {
        if (n.contains(kw)) return rule.key;
      }
    }
    final core = _stripCode(name);
    if (core.isNotEmpty) return core;
    final t = type.trim();
    return t.isEmpty ? '未分类' : t;
  }

  /// 去掉设备名开头的编号：8# / #8 / 8号 / 33# / A8 之类
  static String _stripCode(String name) {
    var s = name.trim();
    s = s.replaceFirst(RegExp(r'^[#＃]?\s*[A-Za-z]?\s*\d+\s*[#＃号]?\s*'), '');
    s = s.replaceAll(RegExp(r'[#＃]'), '').trim();
    return s;
  }

  /// 取颜色。没学过这个类别，就分配一个并记住。
  int colorOf(String name, String type) {
    final key = categoryOf(name, type);
    final existing = _colors[key];
    if (existing != null) return existing;

    final assigned = _nextColor();
    _colors[key] = assigned;
    _persist();
    return assigned;
  }

  /// 挑一个还没被任何类别用过的颜色；都用过了就轮着来
  int _nextColor() {
    final used = _colors.values.toSet();
    for (final c in palette) {
      if (!used.contains(c)) return c;
    }
    return palette[_colors.length % palette.length];
  }

  void _persist() {
    SharedPreferences.getInstance().then((prefs) {
      final map = _colors.map(
        (k, v) => MapEntry(k, v.toRadixString(16).toUpperCase().padLeft(8, '0')),
      );
      prefs.setString(_kPrefs, jsonEncode(map));
    }).catchError((_) {});
  }

  /// 清空学习记录，回到种子色。设置页「重置颜色」用。
  Future<void> reset() async {
    _colors
      ..clear()
      ..addAll(seedColors);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrefs);
    } catch (_) {}
  }

  /// 当前已学到的「类别 → 颜色」，给设置页展示用
  Map<String, int> get assignments => Map.unmodifiable(_colors);
}
