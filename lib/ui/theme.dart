import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/color_registry.dart';

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

  /// 按名字/类型取颜色。
  ///
  /// 颜色不写死：由 ColorRegistry 学习分配 —— 第一次遇到某个类别时，
  /// 从调色板挑一个还没被占用的颜色记住，以后同类设备都用它。
  /// 这样新增设备类别不用改代码，颜色也会自动保持一致。
  static Color colorFor(String name, String type) =>
      Color(ColorRegistry.instance.colorOf(name, type));
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
