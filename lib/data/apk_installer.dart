import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 应用内升级：下载 APK → 调起系统安装界面，全程不离开 App。
class ApkInstaller {
  static const _channel = MethodChannel('linkmind/installer');

  /// 用户有没有给「允许安装未知应用」。没给要先去设置页开。
  static Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// 跳到「允许安装未知应用」的设置页
  static Future<bool> openInstallSetting() async {
    try {
      return await _channel.invokeMethod<bool>('openInstallPermissionSetting') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 唤起系统安装界面。返回 null 表示已成功唤起，否则是给用户看的原因。
  static Future<String?> install(String path) async {
    try {
      await _channel.invokeMethod<void>('install', {'path': path});
      return null;
    } on PlatformException catch (e) {
      return e.message ?? e.code;
    } catch (e) {
      return '唤起安装界面失败：$e';
    }
  }

  /// 下载到应用私有的 Download 目录，返回文件路径
  static Future<String> download(
    String url, {
    required String fileName,
    void Function(double progress, String stage)? onProgress,
  }) async {
    final dir = await _apkDir();
    final target = File(p.join(dir.path, fileName));
    if (await target.exists()) {
      try {
        await target.delete();
      } catch (_) {}
    }

    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url))..followRedirects = true;
      final resp = await client.send(req).timeout(const Duration(seconds: 30));

      if (resp.statusCode != 200) {
        throw '下载失败：HTTP ${resp.statusCode}';
      }
      // GitHub 上 APK 走对象存储重定向，contentLength 可能拿不到
      final total = resp.contentLength ?? 0;
      var received = 0;

      final sink = target.openWrite();
      try {
        await for (final chunk in resp.stream) {
          received += chunk.length;
          sink.add(chunk);
          onProgress?.call(
            total <= 0 ? 0 : (received / total).clamp(0, 1),
            total <= 0
                ? '正在下载 ${_mb(received)}'
                : '正在下载 ${_mb(received)} / ${_mb(total)}',
          );
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      if (total > 0 && received < total * 0.99) {
        throw '下载不完整（只拿到 ${_mb(received)} / ${_mb(total)}）';
      }
      if (!await target.exists() || await target.length() < 1024) {
        throw '下载到的文件是空的';
      }
      return target.path;
    } finally {
      client.close();
    }
  }

  /// 清掉装完的安装包，别一直占着空间
  static Future<void> cleanup(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  static Future<Directory> _apkDir() async {
    final base = await getExternalStorageDirectory();
    final dir = Directory(p.join(base?.path ?? '', 'Download'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static String _mb(int bytes) => '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
}
