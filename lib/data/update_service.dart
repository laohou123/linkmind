import 'dart:convert';

import 'package:http/http.dart' as http;

/// 版本更新检查：问 GitHub 要最新的 Release，和当前版本比一比。
class UpdateService {
  /// 源码和安装包都放这里
  static const repo = 'laohou123/linkmind';
  static const releasesUrl = 'https://github.com/$repo/releases';
  static const latestApi = 'https://api.github.com/repos/$repo/releases/latest';

  /// 检查结果。没网、没发布过版本、限流都归到 [error] 里，
  /// 调用方据此决定是提示还是直接打开网页。
  static Future<UpdateInfo> check({required String currentVersion}) async {
    http.Response resp;
    try {
      resp = await http.get(
        Uri.parse(latestApi),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'LinkMind-Android',
        },
      ).timeout(const Duration(seconds: 15));
    } catch (e) {
      return UpdateInfo(
        status: UpdateStatus.networkError,
        currentVersion: currentVersion,
        error: '连不上 GitHub（$e）',
      );
    }

    // 仓库还没发过 Release 时 GitHub 返回 404
    if (resp.statusCode == 404) {
      return UpdateInfo(
        status: UpdateStatus.noRelease,
        currentVersion: currentVersion,
        error: '仓库里还没有发布版本',
      );
    }
    if (resp.statusCode == 403) {
      return UpdateInfo(
        status: UpdateStatus.networkError,
        currentVersion: currentVersion,
        error: 'GitHub 接口被限流了，稍后再试，或直接去 Releases 页面看',
      );
    }
    if (resp.statusCode != 200) {
      return UpdateInfo(
        status: UpdateStatus.networkError,
        currentVersion: currentVersion,
        error: 'GitHub 返回 ${resp.statusCode}',
      );
    }

    try {
      final body = jsonDecode(utf8.decode(resp.bodyBytes));
      if (body is! Map) throw const FormatException('返回内容不是对象');

      final tag = (body['tag_name'] as String?)?.trim() ?? '';
      final name = (body['name'] as String?)?.trim();
      final notes = (body['body'] as String?)?.trim() ?? '';
      final pageUrl = (body['html_url'] as String?)?.trim();

      // 优先找 apk 资产，找不到就让用户去页面里点
      String? apkUrl;
      String? apkName;
      final assets = body['assets'];
      if (assets is List) {
        for (final a in assets) {
          if (a is! Map) continue;
          final n = (a['name'] as String?) ?? '';
          if (n.toLowerCase().endsWith('.apk')) {
            apkUrl = (a['browser_download_url'] as String?)?.trim();
            apkName = n;
            break;
          }
        }
      }

      final latest = _normalize(tag.isEmpty ? (name ?? '') : tag);
      if (latest.isEmpty) {
        return UpdateInfo(
          status: UpdateStatus.noRelease,
          currentVersion: currentVersion,
          error: '最新 Release 没有版本号',
        );
      }

      final hasNew = _isNewer(latest, currentVersion);

      return UpdateInfo(
        status: hasNew ? UpdateStatus.available : UpdateStatus.upToDate,
        currentVersion: currentVersion,
        latestVersion: latest,
        releaseName: name ?? tag,
        notes: notes,
        pageUrl: pageUrl ?? releasesUrl,
        apkUrl: apkUrl,
        apkName: apkName,
      );
    } catch (e) {
      return UpdateInfo(
        status: UpdateStatus.networkError,
        currentVersion: currentVersion,
        error: '解析返回内容失败：$e',
      );
    }
  }

  /// v1.13.0 / 1.13.0 / release-1.13 → 1.13.0
  static String _normalize(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.startsWith('v')) s = s.substring(1);
    s = s.replaceAll(RegExp(r'^[^0-9]*'), '');
    return s;
  }

  /// 逐段比较，1.13.0 > 1.12.9
  static bool _isNewer(String latest, String current) {
    List<int> parse(String v) {
      final core = v.split('-').first.split('+').first;
      return core.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    }

    final a = parse(latest);
    final b = parse(current);
    final len = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}

enum UpdateStatus {
  /// 有新版本
  available,

  /// 已是最新
  upToDate,

  /// 仓库还没有 Release
  noRelease,

  /// 网络或接口问题
  networkError,
}

class UpdateInfo {
  final UpdateStatus status;
  final String currentVersion;
  final String? latestVersion;
  final String? releaseName;
  final String? notes;
  final String? pageUrl;
  final String? apkUrl;
  final String? apkName;
  final String? error;

  const UpdateInfo({
    required this.status,
    required this.currentVersion,
    this.latestVersion,
    this.releaseName,
    this.notes,
    this.pageUrl,
    this.apkUrl,
    this.apkName,
    this.error,
  });
}
