import '../util/text_match.dart';

/// 实体名校验：模型返回的名字必须能在用户原话里找到。
///
/// 为什么要这一层：模型时不时会把用户说的「8#炉9米设备箱」替换成库里
/// 已有的「38#39#炉9米设备箱」——它觉得自己在帮忙，实际是把两台不同设备
/// 说成了一台，用户确认时看到的名字根本不是自己说的那个。
///
/// 判定只看一个硬指标：**编号**。
/// 「8#炉9米」和「38#39#炉9米」差的就是编号，是现场区分设备的唯一依据，
/// 模型改了编号就是错，不能信。名字里没有编号时无法校验，原样放行。
class NameGuard {
  /// 把模型给的 [modelName] 对齐到用户原话 [input]。
  /// 能对上就返回原名，对不上就返回原话里那段，两者都不成立时返回原名。
  static String restore(String modelName, String input) {
    final name = modelName.trim();
    if (name.isEmpty) return modelName;
    final text = input.trim();
    if (text.isEmpty) return modelName;

    final normName = TextMatch.normalize(name);
    final normText = TextMatch.normalize(text);
    if (normName.isEmpty || normText.isEmpty) return modelName;

    // 原话里原封不动就有这个名字，没问题
    if (normText.contains(normName)) {
      return _withCode(name, text) ?? modelName;
    }

    // 名字没有编号，无从校验（「B区立磨设备箱」这类），不碰
    final nameDigits = _digits(normName);
    if (nameDigits.isEmpty) return modelName;

    // 编号在原话里确实出现过：模型只是补了 # 号之类，属于正常归一化
    if (_digits(normText).contains(nameDigits)) return modelName;

    // 编号对不上 —— 模型换了名字，用原话里「核心词 + 紧挨着的编号」还原
    final rest = _stripLeadingCode(name);
    if (rest.length < 3) return modelName;

    var from = 0;
    while (true) {
      final idx = text.indexOf(rest, from);
      if (idx < 0) return modelName;

      // 原话里「核心词」前面紧挨着编号：连编号一起取回来
      final extended = _extendLeft(text, idx, rest.length);
      if (extended != null) return extended;

      // 原话里这段核心词前面干干净净（用户本来就没说编号）：
      // 那模型补出来的那个编号就是它自己编的，退回原话这段
      if (_startsClean(text, idx)) {
        final normRest = TextMatch.normalize(rest);
        if (_digits(normRest).isNotEmpty && TextMatch.similarity(rest, name) >= 0.4) {
          return rest;
        }
      }
      from = idx + 1;
    }
  }

  /// 这段文字前面不是编号的一部分，可以当作名字的开头
  static bool _startsClean(String text, int idx) {
    if (idx == 0) return true;
    final prev = text[idx - 1];
    if (_isCodeChar(prev)) return false;
    if (prev.trim().isEmpty) return false;
    return true;
  }

  /// 名字在原话里出现、但开头被漏掉了编号时补回来。
  /// 原话「8#炉9米设备箱」+ 模型给「炉9米设备箱」→ 补成「8#炉9米设备箱」。
  static String? _withCode(String name, String text) {
    // 名字自己就以编号开头，说明没漏
    if (_stripLeadingCode(name) != name) return null;
    if (name.length < 2) return null;
    final idx = text.indexOf(name);
    if (idx < 0) return null;
    return _extendLeft(text, idx, name.length);
  }

  /// 从 [start] 往前吃掉紧邻的编号（#、号、数字），
  /// 只有紧挨着一个 # / 号 才算，避免把上一句话尾的数字粘进来。
  static String? _extendLeft(String text, int start, int length) {
    if (start <= 0) return null;
    final prev = text[start - 1];
    if (prev != '#' && prev != '＃' && prev != '号') return null;

    var i = start - 1;
    while (i >= 0 && _isCodeChar(text[i])) {
      i--;
    }
    final begin = i + 1;
    if (begin == start) return null;          // 只有 # 没有数字，不算补全

    final candidate = text.substring(begin, start + length).trim();
    if (candidate.isEmpty || candidate.length > length + 8) return null;
    if (_digits(TextMatch.normalize(candidate)).isEmpty) return null;
    return candidate;
  }

  static bool _isCodeChar(String c) {
    if (c == '#' || c == '＃' || c == '号') return true;
    final code = c.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  /// 去掉开头的编号：「38#39#炉9米设备箱」→「炉9米设备箱」
  static String _stripLeadingCode(String name) {
    var i = 0;
    while (i < name.length && _isCodeChar(name[i])) {
      i++;
    }
    return i == 0 ? name : name.substring(i).trim();
  }

  /// 名字里的数字串（归一化后，中文数字已转阿拉伯）
  static String _digits(String normalized) {
    final sb = StringBuffer();
    for (final c in normalized.split('')) {
      final code = c.codeUnitAt(0);
      if (code >= 48 && code <= 57) sb.write(c);
    }
    return sb.toString();
  }
}
