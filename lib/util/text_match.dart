/// 轻量文本匹配，不依赖分词库。
///
/// 为什么不用向量检索：实体名通常是「33#湿矿设备箱」这类短编号，
/// 向量模型容易把不同编号的相似设备判成同一个；字符级匹配更可控、可解释。
class TextMatch {
  /// 归一化：全角转半角 + 去掉空白和分隔符号 + 小写。
  ///
  /// 为什么连 # - _ / 这些符号也要去掉：
  /// 现场记录里「33湿矿」「33#湿矿」「33 号湿矿」指的是同一台设备，
  /// 保留符号会让相似度从 0.9 掉到 0.25，程序就会当成两台设备，进而
  /// 漏掉"改接"应该替换的旧记录。
  static String normalize(String raw) {
    final sb = StringBuffer();
    for (final rune in raw.runes) {
      var c = String.fromCharCode(rune);
      if (rune == 0x3000) continue; // 全角空格
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        c = String.fromCharCode(rune - 0xFEE0);
      }
      if (c.trim().isEmpty) continue;
      if (_separators.contains(c)) continue;
      sb.write(c.toLowerCase());
    }
    return _digitsToArabic(sb.toString());
  }

  /// 中文数字转阿拉伯数字，并去掉数字后面的「号」。
  ///
  /// 离线模型（以及多数中文 ASR）词表里只有汉字，没有阿拉伯数字，
  /// 所以「7#炉9米设备箱」会被听成「七号炉九米设备箱」。
  /// 不归一化的话，两条记录会变成两台设备。
  ///
  /// 只处理「七号」这种数字+号，不动「信号线」里的那个号。
  static String _digitsToArabic(String input) {
    final converted = input.replaceAllMapped(
      RegExp(r'[零一二三四五六七八九十百千两]+'),
      (m) {
        final cn = m[0]!;
        final n = _cnToInt(cn);
        return n == null ? cn : n.toString();
      },
    );
    return converted.replaceAllMapped(RegExp(r'(\d)号'), (m) => m[1]!);
  }

  static const _cnDigit = {
    '零': 0, '一': 1, '二': 2, '两': 2, '三': 3, '四': 4,
    '五': 5, '六': 6, '七': 7, '八': 8, '九': 9,
  };
  static const _cnUnit = {'十': 10, '百': 100, '千': 1000};

  /// 「三十三」→ 33、「十二」→ 12、「九」→ 9。超出千位或含杂字返回 null
  static int? _cnToInt(String cn) {
    var section = 0;
    var number = 0;
    var seenAny = false;
    for (final ch in cn.split('')) {
      if (_cnDigit.containsKey(ch)) {
        number = _cnDigit[ch]!;
        seenAny = true;
      } else if (_cnUnit.containsKey(ch)) {
        final unit = _cnUnit[ch]!;
        section += (number == 0 ? 1 : number) * unit;
        number = 0;
        seenAny = true;
      } else {
        return null;
      }
    }
    if (!seenAny) return null;
    return section + number;
  }

  static const _separators = {
    '#', '-', '_', '/', '\\', '.', '·', '•', '、', ',', ';', ':', '(', ')',
    '[', ']', '【', '】', '（', '）', '"', "'", '“', '”', '‘', '’',
  };

  /// 相似度 0.0 ~ 1.0
  /// 1.0 完全相同；0.80+ 一方包含另一方；其余用字符二元组 Jaccard
  static double similarity(String a, String b) {
    final x = normalize(a);
    final y = normalize(b);
    if (x.isEmpty || y.isEmpty) return 0;
    if (x == y) return 1.0;
    if (x.contains(y) || y.contains(x)) {
      final ratio =
          (x.length < y.length ? x.length : y.length) / (x.length > y.length ? x.length : y.length);
      return 0.80 + 0.14 * ratio;
    }
    return _jaccard(_bigrams(x), _bigrams(y));
  }


  /// 现场设备的命名规律：编号 + 核心词 + 后缀。
  /// 「8#炉布袋除尘设备箱」和「8#布袋除尘光纤」在字符层面只有 0.27，
  /// 但编号相同、核心词（布袋除尘）重叠，实际指的是同一套设备。
  /// 这种情况给 0.62~0.87 的分数：高到会出现在确认卡片上让你选，
  /// 低到不会自动合并（0.86 以上才自动并）。
  static double similarityWithCode(String a, String b) {
    final base = similarity(a, b);
    final codeA = _codeToken(a);
    final codeB = _codeToken(b);
    if (codeA == null) return base;
    if (codeA != codeB) return base;

    // 名字里的数字必须逐个一致。
    // 「7#炉0米设备箱」和「7#炉9米设备箱」只差一个楼层数字，字符相似度高达 0.73，
    // 但它们在现场是两台完全不同的设备 —— 楼层/编号/尺寸这类数字就是区分符，
    // 差一个数就不该往一起并。这条比相似度更硬，放在最前面挡。
    if (!_sameDigits(normalize(a), normalize(b))) return base;

    final x = normalize(a);
    final y = normalize(b);
    final restA = x.length > codeA.length ? x.substring(codeA.length) : '';
    final restB = y.length > codeA.length ? y.substring(codeA.length) : '';
    if (restA.isEmpty || restB.isEmpty) return base;

    // 简称通常是被包含的字符子序列：
    // "5#湿矿光纤" ⊂ "5#湿矿平台设备箱光纤"（湿→矿→光→纤 顺序一致）
    if (_isSubsequence(restA, restB) || _isSubsequence(restB, restA)) {
      final shorter = restA.length < restB.length ? restA : restB;
      if (shorter.length >= 3) return base > 0.80 ? base : 0.80;
    }

    // 公共前缀兜底：
    // 「湿矿电源」和「湿矿平台设备箱」既不是包含也不是子序列（"电源"是关系
    // 干扰词），但去掉编号后都以「湿矿」开头，指的还是同一台设备。
    // 给一个能进候选、但不足以自动合并的分（0.60~0.80）。
    final prefixLen = _commonPrefixLen(restA, restB);
    if (prefixLen >= 2) {
      final minLen = restA.length < restB.length ? restA.length : restB.length;
      final prefScore = 0.60 + 0.20 * (prefixLen / minLen);
      if (prefScore > base) return prefScore;
    }

    final overlap = _jaccard(_bigrams(restA), _bigrams(restB));
    if (overlap < 0.22) return base;      // 核心词几乎不重合，当作不同设备
    final boosted = 0.62 + 0.25 * overlap;
    return boosted > base ? boosted : base;
  }


  /// 两串里的数字序列是否逐个相同
  static bool _sameDigits(String a, String b) {
    final da = _digitGroups(a);
    final db = _digitGroups(b);
    if (da.length != db.length) return false;
    for (var i = 0; i < da.length; i++) {
      if (da[i] != db[i]) return false;
    }
    return true;
  }

  static List<String> _digitGroups(String s) {
    final out = <String>[];
    final buf = StringBuffer();
    for (final c in s.split('')) {
      final code = c.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        buf.write(c);
      } else if (buf.isNotEmpty) {
        out.add(buf.toString());
        buf.clear();
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }


  /// 两个字符串从开头连续相同的字符数
  static int _commonPrefixLen(String a, String b) {
    final n = a.length < b.length ? a.length : b.length;
    var i = 0;
    while (i < n && a[i] == b[i]) {
      i++;
    }
    return i;
  }

  /// a 的字符是否按顺序全部出现在 b 里
  static bool _isSubsequence(String a, String b) {
    if (a.isEmpty || a.length > b.length) return false;
    var i = 0;
    for (var j = 0; j < b.length && i < a.length; j++) {
      if (b[j] == a[i]) i++;
    }
    return i == a.length;
  }

  /// 取开头的编号部分："8#" → "8"、"33#湿矿" → "33"、"c-012" → "c012"
  static String? _codeToken(String raw) {
    final n = normalize(raw);
    var i = 0;
    while (i < n.length && (n[i].codeUnitAt(0) >= 48 && n[i].codeUnitAt(0) <= 57)) {
      i++;
    }
    if (i == 0) {
      // 字母开头（如 C-012）取字母 + 紧随的数字
      if (n.isNotEmpty && n[0].codeUnitAt(0) >= 97 && n[0].codeUnitAt(0) <= 122) {
        var j = 1;
        while (j < n.length && n[j].codeUnitAt(0) >= 48 && n[j].codeUnitAt(0) <= 57) {
          j++;
        }
        return j > 1 ? n.substring(0, j) : null;
      }
      return null;
    }
    return n.substring(0, i);
  }

  static Set<String> _bigrams(String s) {
    if (s.length == 1) return {s};
    final out = <String>{};
    for (var i = 0; i < s.length - 1; i++) {
      out.add(s.substring(i, i + 2));
    }
    return out;
  }

  static double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    var inter = 0;
    for (final item in a) {
      if (b.contains(item)) inter++;
    }
    final union = a.length + b.length - inter;
    return union == 0 ? 0 : inter / union;
  }
}
