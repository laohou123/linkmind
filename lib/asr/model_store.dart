import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../llm/llm_client.dart';
import 'asr_model.dart';

/// 离线模型的下载、解压、删除。
///
/// 模型不进 APK：安装包只带识别引擎（原生库），模型在用户点「下载」之后
/// 落到应用私有目录，卸载 App 时一起清掉。
class ModelStore {
  static final ModelStore instance = ModelStore._();
  ModelStore._();

  /// 正在下载的模型，避免重复触发
  final Set<String> _running = {};

  bool isDownloading(String id) => _running.contains(id);

  Future<Directory> rootDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, 'asr_models'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> modelDir(AsrModelSpec spec) async {
    final root = await rootDir();
    return Directory(p.join(root.path, spec.id));
  }

  /// 各文件的最小体积，用来识别"下载被截断"这种半成品
  static const _minBytes = {
    'encoder': 15 * 1024 * 1024,
    'decoder': 900 * 1024,
    'joiner': 900 * 1024,
    'tokens': 1024,
  };

  /// 需要的文件是否都在，且大小合理。
  /// 只判断"存在"不够：断网导致下载中断时，文件在但内容是半截，
  /// 之后加载会失败或解不出字，却一直显示"已就绪"。
  Future<bool> isReady(AsrModelSpec spec) async {
    final dir = await modelDir(spec);
    for (final entry in spec.files.entries) {
      final file = File(p.join(dir.path, entry.value));
      if (!await file.exists()) return false;
      final min = _minBytes[entry.key];
      if (min != null && await file.length() < min) return false;
    }
    return true;
  }

  /// 已占用空间（字节）
  Future<int> usedBytes(AsrModelSpec spec) async {
    final dir = await modelDir(spec);
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final e in dir.list(recursive: true)) {
      if (e is File) total += await e.length();
    }
    return total;
  }

  /// 下载并解压。进度回调给 0~1，解压阶段没有细粒度进度，用阶段文字代替。
  Future<void> download(
    AsrModelSpec spec, {
    void Function(double progress, String stage)? onProgress,
  }) async {
    if (_running.contains(spec.id)) {
      throw const LlmException('这个模型正在下载，稍等。');
    }
    _running.add(spec.id);

    final dir = await modelDir(spec);
    final tmp = File(p.join(dir.path, 'download.tar.bz2'));

    try {
      if (!await dir.exists()) await dir.create(recursive: true);

      // 1) 下载，多个源依次尝试（GitHub 在国内经常很慢）
      Object? lastError;
      var ok = false;
      for (final url in spec.sources) {
        try {
          await _fetch(url, tmp, spec.archiveBytes,
              (received, total) => onProgress?.call(
                    total <= 0 ? 0 : (received / total).clamp(0, 1),
                    '正在下载 ${_mb(received)} / ${_mb(total)}',
                  ));
          ok = true;
          break;
        } catch (e) {
          lastError = e;
          try {
            if (await tmp.exists()) await tmp.delete();
          } catch (_) {}
        }
      }
      if (!ok) {
        throw LlmException('下载失败：$lastError\n换个网络再试，或用电脑下载后放进手机。');
      }

      // 2) 解压，只留需要的几个文件
      onProgress?.call(1, '正在解压…');
      await _extract(spec, tmp, dir);

      // 3) 校验
      if (!await isReady(spec)) {
        throw const LlmException('解压后文件不全，可能下载被截断了。请重试。');
      }
      onProgress?.call(1, '完成');
    } finally {
      _running.remove(spec.id);
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  Future<void> _fetch(
    String url,
    File target,
    int expected, [
    void Function(int received, int total)? onProgress,
  ]) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final resp = await client.send(req).timeout(const Duration(seconds: 30));

      if (resp.statusCode != 200) {
        throw LlmException('HTTP ${resp.statusCode}');
      }
      final total = resp.contentLength ?? expected;
      var received = 0;

      final sink = target.openWrite();
      try {
        await for (final chunk in resp.stream) {
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(received, total);
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      // 长度对不上说明没下完
      if (total > 0 && received < total * 0.99) {
        throw const LlmException('下载不完整');
      }
    } finally {
      client.close();
    }
  }

  Future<void> _extract(AsrModelSpec spec, File archive, Directory target) async {
    // 整个包要在内存里解开：bz2 是块压缩，没法只取局部。
    // 压缩 71MB → 解开约 130MB，现代手机扛得住。
    final raw = await archive.readAsBytes();
    final unpacked = BZip2Decoder().decodeBytes(raw);
    final tar = TarDecoder().decodeBytes(unpacked);

    final wanted = spec.files.values.toSet();
    final written = <String>{};
    for (final entry in tar) {
      if (!entry.isFile) continue;
      final name = p.basename(entry.name);
      if (!wanted.contains(name)) continue;

      final out = File(p.join(target.path, name));
      final sink = out.openWrite();
      try {
        sink.add(entry.content as List<int>);
      } finally {
        await sink.flush();
        await sink.close();
      }
      written.add(name);
    }

    final missing = wanted.difference(written);
    if (missing.isNotEmpty) {
      throw LlmException('压缩包里没找到这些文件：${missing.join('、')}');
    }
  }

  Future<void> remove(AsrModelSpec spec) async {
    final dir = await modelDir(spec);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
}
