import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../models/transfer.dart';

/// 接收端会话:一次 prepare 对应一批文件
class _Session {
  _Session({
    required this.id,
    required this.task,
    required this.tokens,
    required this.saveDir,
  });

  final String id;
  final TransferTask task;

  /// fileId -> 一次性上传令牌,防止别人猜到 sessionId 就能塞文件
  final Map<String, String> tokens;
  final String saveDir;

  /// 正在写的文件句柄,取消时要关掉
  final Map<String, IOSink> sinks = {};
  bool canceled = false;
}

/// 接收方决定是否接受这批文件
typedef ApprovalCallback = Future<bool> Function(TransferTask task);

/// 传输事件回调,交给 AppState 更新界面
typedef TaskCallback = void Function(TransferTask task);

/// 接收服务:一个极简 HTTP 服务器,实现自研传输协议。
///
/// ```
/// GET  /api/v1/info                    -> 本机设备信息(也被子网扫描使用)
/// POST /api/v1/prepare                 -> 请求发送一批文件,等待接收方确认
/// POST /api/v1/upload?session=&file=&token=  -> 上传单个文件正文
/// POST /api/v1/cancel?session=         -> 发送方取消
/// ```
class ReceiveServer {
  ReceiveServer({
    required this.selfInfo,
    required this.onApproval,
    required this.onTaskUpdate,
    required this.resolveSaveDir,
    required this.overwriteExisting,
  });

  /// 返回本机设备信息(端口等设置可能随时变,用回调而非快照)
  final Device Function() selfInfo;
  final ApprovalCallback onApproval;
  final TaskCallback onTaskUpdate;

  /// 每次接收前取一次保存目录(设置里可改)
  final Future<String> Function() resolveSaveDir;
  final bool Function() overwriteExisting;

  HttpServer? _server;
  final _sessions = <String, _Session>{};
  final _rand = Random.secure();

  bool get running => _server != null;
  int? get port => _server?.port;

  Future<void> start(int port) async {
    await stop();
    // 绑定 anyIPv4 而非 loopback:必须能被局域网其他设备访问
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port,
        shared: false);
    _server!.listen(_handle, onError: (Object e) {
      debugPrint('[server] error: $e');
    });
    debugPrint('[server] listening on ${_server!.address.address}:$port');
  }

  Future<void> stop() async {
    final s = _server;
    _server = null;
    for (final sess in _sessions.values) {
      await _closeSession(sess, canceled: true);
    }
    _sessions.clear();
    await s?.close(force: true);
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      switch (req.uri.path) {
        case '/api/v1/info':
          await _info(req);
        case '/api/v1/prepare':
          await _prepare(req);
        case '/api/v1/upload':
          await _upload(req);
        case '/api/v1/cancel':
          await _cancel(req);
        default:
          await _json(req, 404, {'error': 'not found'});
      }
    } catch (e, st) {
      debugPrint('[server] handler failed: $e\n$st');
      try {
        await _json(req, 500, {'error': '$e'});
      } catch (_) {
        // 响应已开始发送,无法再改状态码
      }
    }
  }

  Future<void> _json(HttpRequest req, int status, Map<String, Object?> body) {
    req.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(body));
    return req.response.close();
  }

  // ------------------------------------------------------------------ info

  Future<void> _info(HttpRequest req) => _json(req, 200, selfInfo().toJson());

  // --------------------------------------------------------------- prepare

  /// 请求体:`{ device: {...}, files: [{id,name,size,relativePath}] }`
  /// 响应体:`{ sessionId, tokens: {fileId: token} }`
  Future<void> _prepare(HttpRequest req) async {
    if (req.method != 'POST') {
      return _json(req, 405, {'error': 'method not allowed'});
    }
    final body = await utf8.decoder.bind(req).join();
    final j = jsonDecode(body);
    if (j is! Map<String, dynamic>) {
      return _json(req, 400, {'error': 'bad body'});
    }
    final devJson = j['device'];
    final sender = devJson is Map<String, dynamic>
        ? Device.fromJson(devJson,
            fallbackIp: req.connectionInfo?.remoteAddress.address)
        : null;
    if (sender == null) return _json(req, 400, {'error': 'bad device'});

    final rawFiles = j['files'];
    if (rawFiles is! List || rawFiles.isEmpty) {
      return _json(req, 400, {'error': 'no files'});
    }
    final files = rawFiles
        .whereType<Map<String, dynamic>>()
        .map(FileItem.fromJson)
        .whereType<FileItem>()
        .toList();
    if (files.isEmpty) return _json(req, 400, {'error': 'bad files'});

    final sessionId = _token();
    final task = TransferTask(
      id: sessionId,
      direction: TransferDirection.receive,
      device: sender,
      files: files,
      status: TransferStatus.waiting,
    );
    onTaskUpdate(task);

    final accepted = await onApproval(task);
    if (!accepted) {
      task.status = TransferStatus.rejected;
      task.finishedAt = DateTime.now();
      onTaskUpdate(task);
      return _json(req, 403, {'error': 'rejected'});
    }

    final saveDir = await resolveSaveDir();
    final tokens = {for (final f in files) f.id: _token()};
    _sessions[sessionId] =
        _Session(id: sessionId, task: task, tokens: tokens, saveDir: saveDir);
    task.status = TransferStatus.transferring;
    onTaskUpdate(task);
    return _json(req, 200, {'sessionId': sessionId, 'tokens': tokens});
  }

  // ---------------------------------------------------------------- upload

  Future<void> _upload(HttpRequest req) async {
    if (req.method != 'POST') {
      return _json(req, 405, {'error': 'method not allowed'});
    }
    final q = req.uri.queryParameters;
    final sess = _sessions[q['session']];
    final fileId = q['file'];
    if (sess == null || fileId == null) {
      return _json(req, 404, {'error': 'no session'});
    }
    if (sess.tokens[fileId] != q['token']) {
      return _json(req, 403, {'error': 'bad token'});
    }
    if (sess.canceled) return _json(req, 409, {'error': 'canceled'});

    final item = sess.task.files.firstWhere((f) => f.id == fileId,
        orElse: () => FileItem(id: '', name: '', size: 0));
    if (item.id.isEmpty) return _json(req, 404, {'error': 'no file'});

    // 令牌一次性:防止重复上传把进度算乱
    sess.tokens.remove(fileId);
    sess.task.currentFileId = fileId;

    final target = await _resolveTarget(sess.saveDir, item);
    final sink = target.openWrite();
    sess.sinks[fileId] = sink;
    var written = 0;
    try {
      await for (final chunk in req) {
        if (sess.canceled) throw const _Canceled();
        sink.add(chunk);
        written += chunk.length;
        sess.task.progress[fileId] = written;
        onTaskUpdate(sess.task);
      }
      await sink.flush();
      await sink.close();
      sess.sinks.remove(fileId);
      sess.task.progress[fileId] = written;
      sess.task.savedPaths[fileId] = target.path;

      // 大小不符说明连接中断,别把半个文件当成功
      if (item.size > 0 && written != item.size) {
        throw FileSystemException(
            '接收不完整:期望 ${item.size} 字节,实到 $written 字节', target.path);
      }
      _maybeFinish(sess);
      return _json(req, 200, {'ok': true});
    } catch (e) {
      await _abortFile(sess, fileId, target);
      if (e is _Canceled) {
        return _json(req, 409, {'error': 'canceled'});
      }
      sess.task.status = TransferStatus.failed;
      sess.task.error = '$e';
      sess.task.finishedAt = DateTime.now();
      onTaskUpdate(sess.task);
      _sessions.remove(sess.id);
      return _json(req, 500, {'error': '$e'});
    }
  }

  Future<void> _abortFile(_Session sess, String fileId, File target) async {
    final sink = sess.sinks.remove(fileId);
    try {
      await sink?.close();
    } catch (_) {}
    // 删掉写坏的半个文件,避免用户拿到损坏数据
    try {
      if (await target.exists()) await target.delete();
    } catch (_) {}
  }

  /// 所有文件都收完 -> 会话完成
  void _maybeFinish(_Session sess) {
    final all = sess.task.files
        .every((f) => (sess.task.progress[f.id] ?? -1) >= f.size);
    if (!all) return;
    sess.task.status = TransferStatus.done;
    sess.task.currentFileId = null;
    sess.task.finishedAt = DateTime.now();
    onTaskUpdate(sess.task);
    _sessions.remove(sess.id);
  }

  // ---------------------------------------------------------------- cancel

  Future<void> _cancel(HttpRequest req) async {
    final sess = _sessions.remove(req.uri.queryParameters['session']);
    if (sess == null) return _json(req, 404, {'error': 'no session'});
    await _closeSession(sess, canceled: true);
    return _json(req, 200, {'ok': true});
  }

  Future<void> _closeSession(_Session sess, {required bool canceled}) async {
    sess.canceled = true;
    for (final sink in sess.sinks.values) {
      try {
        await sink.close();
      } catch (_) {}
    }
    sess.sinks.clear();
    if (canceled && !sess.task.status.isFinished) {
      sess.task.status = TransferStatus.canceled;
      sess.task.error = '发送方已取消';
      sess.task.finishedAt = DateTime.now();
      onTaskUpdate(sess.task);
    }
  }

  /// 本端主动取消某个接收会话
  Future<void> cancelSession(String sessionId) async {
    final sess = _sessions.remove(sessionId);
    if (sess != null) {
      sess.canceled = true;
      for (final sink in sess.sinks.values) {
        try {
          await sink.close();
        } catch (_) {}
      }
      sess.sinks.clear();
      sess.task.status = TransferStatus.canceled;
      sess.task.error = '已取消接收';
      sess.task.finishedAt = DateTime.now();
      onTaskUpdate(sess.task);
    }
  }

  // ------------------------------------------------------------- 落盘路径

  /// 计算文件保存路径。发送方提供的 relativePath 完全不可信,
  /// 必须逐段清洗,否则 `../../..` 能写到保存目录外面去。
  Future<File> _resolveTarget(String saveDir, FileItem item) async {
    final sep = Platform.pathSeparator;
    final segments = sanitizeRelativePath(item.relativePath ?? item.name);
    final name = segments.removeLast();
    var dir = Directory(saveDir);
    if (segments.isNotEmpty) {
      dir = Directory('$saveDir$sep${segments.join(sep)}');
    }
    await dir.create(recursive: true);

    var file = File('${dir.path}$sep$name');
    if (overwriteExisting()) return file;
    // 同名不覆盖:a.txt -> a(1).txt -> a(2).txt
    if (!await file.exists()) return file;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 1; i < 1000; i++) {
      file = File('${dir.path}$sep$stem($i)$ext');
      if (!await file.exists()) return file;
    }
    return File('${dir.path}$sep$stem-${_token().substring(0, 6)}$ext');
  }

  /// 把不可信的相对路径清洗成安全的路径分段。
  /// 至少返回一段(文件名),清洗到空则回退为 'file'。
  @visibleForTesting
  static List<String> sanitizeRelativePath(String raw) {
    final parts = raw
        .replaceAll('\\', '/')
        .split('/')
        .map(_sanitizeSegment)
        .where((s) => s.isNotEmpty && s != '.' && s != '..')
        .toList();
    if (parts.isEmpty) return ['file'];
    // 目录深度设上限,避免超长路径写失败
    if (parts.length > 16) {
      return [...parts.take(15), parts.last];
    }
    return parts;
  }

  /// 单段清洗:去掉盘符、非法字符、首尾空白与点
  static String _sanitizeSegment(String s) {
    var out = s.trim();
    // Windows 盘符 "C:" 以及各平台非法字符
    out = out.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '_');
    // 结尾的 '.' 和空格在 Windows 上会被静默去掉,提前处理
    while (out.endsWith('.') || out.endsWith(' ')) {
      out = out.substring(0, out.length - 1);
    }
    // Windows 保留设备名
    const reserved = {
      'CON', 'PRN', 'AUX', 'NUL',
      'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
      'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
    };
    final stem = out.contains('.') ? out.split('.').first : out;
    if (reserved.contains(stem.toUpperCase())) out = '_$out';
    // 单段长度上限,给去重后缀留余量
    if (out.length > 150) {
      final dot = out.lastIndexOf('.');
      if (dot > 0 && out.length - dot <= 12) {
        out = out.substring(0, 150 - (out.length - dot)) + out.substring(dot);
      } else {
        out = out.substring(0, 150);
      }
    }
    return out;
  }

  String _token() {
    final bytes = List<int>.generate(18, (_) => _rand.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}

class _Canceled implements Exception {
  const _Canceled();
}
