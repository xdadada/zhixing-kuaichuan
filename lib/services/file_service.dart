import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../models/transfer.dart';

/// 文件选择、目录解析、打开所在文件夹
class FileService {
  static final _rand = Random();

  static String _id() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_rand.nextInt(1 << 20).toRadixString(36)}';

  /// 选择多个文件。用户取消时返回空列表。
  static Future<List<FileItem>> pickFiles() async {
    final picked = await FilePicker.pickFiles();
    final out = <FileItem>[];
    for (final f in picked) {
      // path 为 null 表示不在本地磁盘上(web/云端占位),发不了
      final path = f.path;
      if (path == null) continue;
      var size = 0;
      try {
        size = await f.length();
      } catch (_) {
        size = await _sizeOf(path);
      }
      out.add(FileItem(
        id: _id(),
        name: f.name,
        size: size,
        path: path,
      ));
    }
    return out;
  }

  /// 选择一个文件夹并递归展开其中所有文件,relativePath 保留目录结构。
  /// iOS 上目录选择不可用,调用方需先判断 [supportsFolderPick]。
  static Future<List<FileItem>> pickFolder() async {
    final dir = await FilePicker.getDirectoryPath();
    if (dir == null) return const [];
    return expandDirectory(dir);
  }

  static bool get supportsFolderPick =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// 递归展开目录为文件列表
  static Future<List<FileItem>> expandDirectory(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return const [];
    final rootName = _basename(dirPath);
    final out = <FileItem>[];
    try {
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final name = _basename(e.path);
        // 跳过 macOS/Windows 的目录元数据文件
        if (name == '.DS_Store' || name == 'Thumbs.db') continue;
        final rel = e.path.substring(dirPath.length).replaceAll('\\', '/');
        final relative = '$rootName${rel.startsWith('/') ? '' : '/'}$rel';
        out.add(FileItem(
          id: _id(),
          name: name,
          size: await _sizeOf(e.path),
          path: e.path,
          relativePath: relative,
        ));
      }
    } catch (e) {
      debugPrint('[files] 展开目录失败: $e');
    }
    return out;
  }

  /// 桌面端拖拽投放的路径可能混着文件和文件夹,统一展开
  static Future<List<FileItem>> fromPaths(List<String> paths) async {
    final out = <FileItem>[];
    for (final p in paths) {
      if (await Directory(p).exists()) {
        out.addAll(await expandDirectory(p));
      } else if (await File(p).exists()) {
        out.add(FileItem(
          id: _id(),
          name: _basename(p),
          size: await _sizeOf(p),
          path: p,
        ));
      }
    }
    return out;
  }

  /// 让用户挑选接收目录;iOS 不支持,返回 null
  static Future<String?> pickSaveDir() => FilePicker.getDirectoryPath();

  static Future<int> _sizeOf(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return 0;
    }
  }

  static String _basename(String p) {
    final norm = p.replaceAll('\\', '/');
    final cut = norm.lastIndexOf('/');
    return cut < 0 ? norm : norm.substring(cut + 1);
  }

  /// 默认接收目录:
  ///  - macOS/Windows/Linux: 用户下载目录下的 LanDrop 子目录
  ///  - iOS: 沙盒 Documents/LanDrop(可通过「文件」App 访问)
  ///
  /// [fallback] 为存储服务的数据目录,取不到系统目录时兜底。
  static Future<String> defaultSaveDir(String fallback) async {
    final env = Platform.environment;
    final home = env['HOME'];
    final candidates = <String>[];
    if (Platform.isMacOS || Platform.isLinux) {
      if (home != null && home.isNotEmpty) {
        candidates.add('$home/Downloads/LanDrop');
      }
    } else if (Platform.isWindows) {
      final profile = env['USERPROFILE'];
      if (profile != null && profile.isNotEmpty) {
        candidates.add('$profile\\Downloads\\LanDrop');
      }
    } else if (Platform.isIOS) {
      if (home != null && home.isNotEmpty) {
        candidates.add('$home/Documents/LanDrop');
      }
    }
    candidates.add('$fallback${Platform.pathSeparator}Received');

    for (final c in candidates) {
      try {
        final d = Directory(c);
        await d.create(recursive: true);
        return d.path;
      } catch (_) {
        // 试下一个
      }
    }
    return fallback;
  }

  /// 确保目录存在;不存在且创建失败时返回 false
  static Future<bool> ensureDir(String path) async {
    try {
      await Directory(path).create(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 在系统文件管理器里打开(桌面端)。iOS 无此概念,直接返回 false。
  static Future<bool> revealInFolder(String path) async {
    try {
      if (Platform.isMacOS) {
        // -R 选中文件本身而不是只打开目录
        await Process.run('open', ['-R', path]);
        return true;
      }
      if (Platform.isWindows) {
        await Process.run('explorer', ['/select,', path]);
        return true;
      }
      if (Platform.isLinux) {
        await Process.run('xdg-open', [_dirOf(path)]);
        return true;
      }
    } catch (e) {
      debugPrint('[files] 打开目录失败: $e');
    }
    return false;
  }

  /// 打开一个目录本身
  static Future<bool> openDir(String path) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [path]);
        return true;
      }
      if (Platform.isWindows) {
        await Process.run('explorer', [path]);
        return true;
      }
      if (Platform.isLinux) {
        await Process.run('xdg-open', [path]);
        return true;
      }
    } catch (e) {
      debugPrint('[files] 打开目录失败: $e');
    }
    return false;
  }

  static String _dirOf(String p) {
    final norm = p.replaceAll('\\', '/');
    final cut = norm.lastIndexOf('/');
    return cut <= 0 ? norm : norm.substring(0, cut);
  }
}
