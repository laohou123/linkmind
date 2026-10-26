import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Hindsight 风格的深色配色：底色接近纯黑蓝，信息靠冷色发光凸显。
class AppColors {
  static const bg = Color(0xFF070B12);
  static const surface = Color(0xFF0E1626);
  static const surfaceAlt = Color(0xFF13203A);
  static const border = Color(0xFF1E2E45);
  static const accent = Color(0xFF4CC2FF);
  static const accentDim = Color(0xFF1B4F73);
  static const text = Color(0xFFE8F0FB);
  static const textSub = Color(0xFF7E97BA);
  static const textFaint = Color(0xFF4A6488);
  static const warning = Color(0xFFFFB020);
  static const danger = Color(0xFFFF6B6B);
  static const success = Color(0xFF35D07F);

  static Color typeColor(String type) {
    switch (type) {
      case '设备':
        return const Color(0xFF4C8DFF);
      case '电气设备':
        return const Color(0xFFFFB020);
      case '配电柜':
        return const Color(0xFFFF7A45);
      case '电源':
        return const Color(0xFFF759AB);
      case '设备箱':
        return const Color(0xFF13C2C2);
      case '网络设备':
        return const Color(0xFF36CFC9);
      case '线缆':
        return const Color(0xFF9254DE);
      case '端口':
        return const Color(0xFF8B9DC3);
      case '区域':
        return const Color(0xFF5B8FF9);
      default:
        return const Color(0xFF6B7A99);
    }
  }

  /// 先按设备名里的关键词归类，命中就给对应颜色；命中不了再退回按类型取色。
  ///
  /// 背景：类型是模型录入时自动打的标签，「摄像头」没有独立类型，
  /// 模型一会儿判「设备箱」一会儿判「设备」，同一批摄像头颜色就花了。
  /// 按名字归类后，只要名字里带「摄像头」，无论类型字段是什么，颜色都固定。
  ///
  /// 规则按「本质」排序：更具体的类放前面。比如「监控交换机」含「监控」也含
  /// 「交换机」，交换机在前，就归网络设备而不是摄像头，避免误判。
  static Color colorFor(String name, String type) {
    final n = name.toLowerCase();
    final rules = <MapEntry<List<String>, Color>>[
      MapEntry(const ['光纤', '光缆', '网线', '跳线', '尾纤', '电缆', '线缆'],
          const Color(0xFF9254DE)),
      MapEntry(const ['交换机', '路由器', '防火墙', '收发器', '光端机', '无线ap'],
          const Color(0xFF36CFC9)),
      MapEntry(const ['录像机', 'nvr', 'dvr', '硬盘录像机'],
          const Color(0xFF36CFC9)),
      MapEntry(const ['配电', '电源', 'ups', '变压器', '开关柜', '断路器'],
          const Color(0xFFFF7A45)),
      MapEntry(const ['服务器', '工控机', '主机', '电脑'],
          const Color(0xFF4C8DFF)),
      MapEntry(const ['摄像头', '摄像机', '球机', '枪机', '半球', '云台', '相机', 'ipc', 'camera'],
          const Color(0xFF7C4DFF)),
      MapEntry(const ['端口', '接口'], const Color(0xFF8B9DC3)),
      MapEntry(const ['弱电井', '机房', '机柜', '楼层', '区域', '配电室'],
          const Color(0xFF5B8FF9)),
    ];
    for (final rule in rules) {
      for (final kw in rule.key) {
        if (n.contains(kw)) return rule.value;
      }
    }
    return typeColor(type);
  }
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.accent,
      surface: AppColors.surface,
      onSurface: AppColors.text,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: const TextStyle(color: AppColors.textFaint, fontSize: 14),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.accentDim),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceAlt,
      contentTextStyle: TextStyle(color: AppColors.text),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
