import 'package:flutter/services.dart';

/// 本机语音识别能力检测结果
class SpeechSupport {
  /// 标准通道是否可用（SpeechRecognizer.isRecognitionAvailable）
  final bool available;

  /// 是否支持纯本机识别（Android 12+）
  final bool onDeviceAvailable;

  /// 系统里注册了 RecognitionService 的应用包名
  final List<String> services;

  final int sdkInt;
  final String model;

  /// 通道本身出错时的原始信息
  final String? error;

  const SpeechSupport({
    required this.available,
    required this.onDeviceAvailable,
    required this.services,
    required this.sdkInt,
    required this.model,
    this.error,
  });

  /// 有没有可用的识别服务
  bool get usable => available || onDeviceAvailable;

  String describe() {
    if (error != null) return '检测失败：$error';

    final sb = StringBuffer();
    sb.writeln('Android $sdkInt · $model');
    sb.writeln('标准识别通道：${available ? '可用' : '不可用'}');
    if (sdkInt >= 31) {
      sb.writeln('纯本机识别：${onDeviceAvailable ? '支持' : '不支持'}');
    }
    if (services.isEmpty) {
      sb.writeln('识别服务：系统里一个都没找到');
    } else {
      sb.writeln('识别服务（${services.length} 个）：${services.join('、')}');
    }
    return sb.toString().trim();
  }

  /// 检测结论。
  ///
  /// 这里只允许陈述「本次检测实际看到了什么」，不做品牌归因。
  /// 之前这里写过一句凭常识贴的品牌结论（形容某家 ROM 只做了自家助手），
  /// 却排在检测结果下面，看起来像是从手机读出来的 —— 那是误导。
  String get verdict {
    if (error != null) return '检测通道出错，无法判断。';

    if (usable) {
      return services.isEmpty
          ? '系统报告可用，但没查到具体服务名（可能被厂商隐藏）。直接试一次识别最准。'
          : '系统报告可用，且查到 ${services.length} 个识别服务。';
    }

    if (services.isEmpty) {
      return '系统报告不可用，并且没有查到任何注册了 RecognitionService 的应用。'
          '结论：这台设备上没有第三方 App 能调用的系统识别服务。';
    }

    return '系统里查到 ${services.length} 个识别服务，但当前报告不可用。'
        '可能原因：默认识别服务未设置、被停用，或录音权限被拒。'
        '建议先检查权限，再试一次。';
  }

  /// 下一步能做什么。和 [verdict] 分开显示，避免把建议混进检测事实里。
  List<String> get nextSteps {
    if (error != null) return const ['先重装一次 App 再检测；仍然出错说明诊断模块没加载。'];
    if (usable) return const [];

    return const [
      '关掉上面的「使用手机内置识别」，改回在线识别 —— 最快，原配置都还在',
      '或装一个真正注册了系统识别服务的应用（装了之后回来重新检测）',
      '两者都不行，就需要 App 自己内置离线模型，那是另一项工作',
    ];
  }
}

/// 调原生通道问清楚本机的识别能力，避免「没有可用服务」这种笼统提示
class SpeechDiagnostics {
  static const _channel = MethodChannel('linkmind/speech');

  static Future<SpeechSupport> check() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('diagnose');
      if (raw == null) {
        return const SpeechSupport(
          available: false,
          onDeviceAvailable: false,
          services: [],
          sdkInt: 0,
          model: '',
          error: '原生通道没有返回结果',
        );
      }
      final services = <String>[];
      final list = raw['services'];
      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final label = (item['label'] ?? '').toString().trim();
            final pkg = (item['package'] ?? '').toString().trim();
            services.add(label.isNotEmpty ? '$label（$pkg）' : pkg);
          }
        }
      }
      return SpeechSupport(
        available: raw['available'] == true,
        onDeviceAvailable: raw['onDeviceAvailable'] == true,
        services: services,
        sdkInt: (raw['sdkInt'] as num?)?.toInt() ?? 0,
        model: '${raw['manufacturer'] ?? ''} ${raw['model'] ?? ''}'.trim(),
        error: raw['queryError']?.toString(),
      );
    } on MissingPluginException {
      return const SpeechSupport(
        available: false,
        onDeviceAvailable: false,
        services: [],
        sdkInt: 0,
        model: '',
        error: '当前安装包没有带诊断模块',
      );
    } catch (e) {
      return SpeechSupport(
        available: false,
        onDeviceAvailable: false,
        services: const [],
        sdkInt: 0,
        model: '',
        error: '$e',
      );
    }
  }
}
