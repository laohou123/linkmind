import 'dart:io';

import 'package:path/path.dart' as p;

/// 从已记录的设备名生成 ASR 热词表。
///
/// 为什么要过滤：
/// 模型词表 (tokens.txt) 里只有 5000 多个汉字，**没有阿拉伯数字**，
/// 也没有 `#`。库里存的「7#炉9米设备箱」直接写进去根本编码不了。
/// 所以这里只保留纯中文片段（「湿矿设备箱」「电除尘」这类），
/// 编号交给 TextMatch 的中文数字归一化去对。
class HotwordsBuilder {
  /// 热词太多会拖慢解码、也可能压过真实发音，80 个够覆盖常用设备
  static const maxWords = 80;

  /// 少于 2 个字的片段（如「炉」）信息量太低，不加热词
  static const minLength = 2;

  /// 生成热词文件，返回路径；没有可用热词时返回 null
  static Future<String?> build({
    required String tokensPath,
    required String outputPath,
    required List<String> entityNames,
  }) async {
    final vocab = await _loadVocab(tokensPath);
    if (vocab.isEmpty) return null;

    final words = <String>[];
    final seen = <String>{};

    for (final name in entityNames) {
      for (final segment in _chineseSegments(name)) {
        if (segment.length < minLength) continue;
        // 每一个字都必须在词表里，否则整行编码失败
        if (!segment.split('').every(vocab.contains)) continue;
        if (!seen.add(segment)) continue;
        words.add(segment);
        if (words.length >= maxWords) break;
      }
      if (words.length >= maxWords) break;
    }

    if (words.isEmpty) return null;

    // 格式按官方文档：一行一个热词，中文连着写，字之间不加空格。
    // 空格是留给「中英混排短语」的（如 SPEECH 识别），
    // 把单个中文词拆成「湿 矿 设 备 箱」反而无法编码。
    final file = File(outputPath);
    await file.writeAsString(words.join('\n'), flush: true);
    return file.path;
  }

  /// 去掉重复和变化频繁的编号后，用「数量 + 最新更新时间」判断要不要重建
  static Future<String> fingerprint(List<String> entityNames) async {
    return '${entityNames.length}:${entityNames.join('|').hashCode}';
  }

  static Future<Set<String>> _loadVocab(String tokensPath) async {
    final file = File(tokensPath);
    if (!await file.exists()) return {};
    final out = <String>{};
    try {
      for (final line in await file.readAsLines()) {
        final idx = line.lastIndexOf(' ');
        if (idx <= 0) continue;
        final token = line.substring(0, idx);
        // <blk> <sos/eos> <unk> 这类特殊标记不能当热词
        if (token.startsWith('<')) continue;
        out.add(token);
      }
    } catch (_) {
      return {};
    }
    return out;
  }

  /// 按非汉字切开，只留连续的中文段
  static List<String> _chineseSegments(String raw) {
    final out = <String>[];
    final buf = StringBuffer();
    for (final ch in raw.split('')) {
      final code = ch.codeUnitAt(0);
      final isCjk = code >= 0x4E00 && code <= 0x9FFF;
      if (isCjk) {
        buf.write(ch);
      } else if (buf.isNotEmpty) {
        out.add(buf.toString());
        buf.clear();
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  static String hotwordsPath(String modelDir) => p.join(modelDir, 'hotwords.txt');
}
