import 'dart:math';

final Random _random = Random.secure();

/// 生成 v4 UUID。不引第三方包，减少依赖面。
String newId() {
  const chars = '0123456789abcdef';
  final buf = StringBuffer();
  for (var i = 0; i < 36; i++) {
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      buf.write('-');
    } else if (i == 14) {
      buf.write('4');
    } else if (i == 19) {
      buf.write(chars[(_random.nextInt(16) & 0x3) | 0x8]);
    } else {
      buf.write(chars[_random.nextInt(16)]);
    }
  }
  return buf.toString();
}

/// 毫秒时间戳
int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// 2026-10-26 这种短日期
String shortDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}
