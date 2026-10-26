/// 离线语音模型的规格描述。
///
/// 模型不打进安装包：APK 里只有识别引擎（约 15MB 的原生库），
/// 真正的模型在用户点「下载」之后落到手机存储里。
class AsrModelSpec {
  /// 内部标识，也是落盘目录名
  final String id;

  /// 显示名
  final String title;

  /// 一句话说明
  final String subtitle;

  /// 主下载地址（tar.bz2）
  final String url;

  /// 备用地址。GitHub 在国内经常几十 KB/s，前一个超时就换下一个。
  final List<String> mirrors;

  /// 压缩包大小，用于进度条和空间预估
  final int archiveBytes;

  /// 解压后目录名（压缩包内的顶层目录）
  final String folder;

  /// 需要从包里提取的文件：用途 → 包内相对文件名
  final Map<String, String> files;

  const AsrModelSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.url,
    this.mirrors = const [],
    required this.archiveBytes,
    required this.folder,
    required this.files,
  });

  String get sizeLabel => '${(archiveBytes / 1024 / 1024).round()} MB';

  /// 解压后大约占多少（压缩比的粗略估计，给用户看个量级）
  String get unpackedLabel =>
      '约 ${(archiveBytes / 1024 / 1024 * 2.1).round()} MB';

  /// 依次尝试的下载地址
  List<String> get sources => [url, ...mirrors];

  /// 模型文件路径（相对模型根目录）
  String pathOf(String key, String root) => '$root/${files[key] ?? ''}';
}

/// 目前提供的模型。只放一个，避免选择困难；要换随时加。
class AsrModels {
  static const zhStreaming = AsrModelSpec(
    id: 'zipformer-zh-14m',
    title: '中文流式识别',
    subtitle: '边说边出字，14M 参数，日常口语够用',
    url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/'
        'sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23.tar.bz2',
    mirrors: [
      'https://ghfast.top/https://github.com/k2-fsa/sherpa-onnx/releases/'
          'download/asr-models/'
          'sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23.tar.bz2',
      'https://gh-proxy.com/https://github.com/k2-fsa/sherpa-onnx/releases/'
          'download/asr-models/'
          'sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23.tar.bz2',
      'https://ghproxy.net/https://github.com/k2-fsa/sherpa-onnx/releases/'
          'download/asr-models/'
          'sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23.tar.bz2',
    ],
    archiveBytes: 74004050,
    folder: 'sherpa-onnx-streaming-zipformer-zh-14M-2023-02-23',
    files: {
      'encoder': 'encoder-epoch-99-avg-1.int8.onnx',
      'decoder': 'decoder-epoch-99-avg-1.int8.onnx',
      'joiner': 'joiner-epoch-99-avg-1.int8.onnx',
      'tokens': 'tokens.txt',
    },
  );

  static const all = <AsrModelSpec>[zhStreaming];

  static AsrModelSpec? byId(String id) {
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }
}
