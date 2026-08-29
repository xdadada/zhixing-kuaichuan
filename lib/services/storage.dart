import 'dart:convert';
import 'dart:io';

/// 零插件依赖的 JSON 文件存储(与 VPN 项目同一套思路)。
/// 各平台数据目录:
///  - macOS:   ~/Library/Application Support/LanDrop
///  - Windows: %APPDATA%\LanDrop
///  - iOS:     $HOME/Documents/LanDrop(HOME 即应用沙盒容器)
class Storage {
  Storage._(this._file, this.dir);

  final File _file;

  /// 数据目录,接收目录默认值也基于它推导
  final Directory dir;

  /// 依次尝试各候选目录,第一个能创建成功的即为数据目录。
  /// iOS 真机上 HOME 可能为空(拼出 'null/...' 会导致启动崩溃),
  /// 因此额外从 TMPDIR(沙盒内必然存在)反推容器根目录兜底。
  static Future<Storage> init() async {
    for (final d in _candidateDirs()) {
      try {
        await d.create(recursive: true);
        return Storage._(
            File('${d.path}${Platform.pathSeparator}state.json'), d);
      } catch (_) {
        // 该候选不可写,试下一个
      }
    }
    final tmp = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}landrop');
    await tmp.create(recursive: true);
    return Storage._(
        File('${tmp.path}${Platform.pathSeparator}state.json'), tmp);
  }

  static Iterable<Directory> _candidateDirs() sync* {
    final env = Platform.environment;
    final home = env['HOME'];
    if (Platform.isMacOS) {
      if (home != null && home.isNotEmpty) {
        yield Directory('$home/Library/Application Support/LanDrop');
      }
    } else if (Platform.isWindows) {
      final base = env['APPDATA'] ?? env['USERPROFILE'];
      if (base != null && base.isNotEmpty) {
        yield Directory('$base\\LanDrop');
      }
    } else if (Platform.isLinux) {
      final base = env['XDG_CONFIG_HOME'] ??
          (home == null || home.isEmpty ? null : '$home/.config');
      if (base != null) yield Directory('$base/landrop');
    } else if (Platform.isIOS) {
      if (home != null && home.isNotEmpty) {
        yield Directory('$home/Documents/LanDrop');
      }
      final container = _containerRootFromTmp();
      if (container != null) {
        yield Directory('$container/Documents/LanDrop');
        yield Directory('$container/Library/Application Support/LanDrop');
      }
    }
    yield Directory('${Directory.systemTemp.path}/landrop');
  }

  /// 从 TMPDIR 反推 iOS 沙盒容器根目录(去掉末尾的 /tmp)
  static String? _containerRootFromTmp() {
    var t = Directory.systemTemp.path;
    while (t.endsWith('/')) {
      t = t.substring(0, t.length - 1);
    }
    final cut = t.lastIndexOf('/');
    if (cut <= 0) return null;
    return t.substring(0, cut);
  }

  Future<Map<String, dynamic>?> load() async {
    try {
      if (!await _file.exists()) return null;
      final text = await _file.readAsString();
      if (text.trim().isEmpty) return null;
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return null; // 损坏的存档不阻塞启动
    }
  }

  /// 原子写入:先写临时文件再改名
  Future<void> save(Map<String, dynamic> data) async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    try {
      await tmp.rename(_file.path);
    } on FileSystemException {
      // Windows 上目标存在时 rename 可能失败,退回覆盖写
      await _file.writeAsString(jsonEncode(data), flush: true);
    }
  }

  String get path => _file.path;
}
