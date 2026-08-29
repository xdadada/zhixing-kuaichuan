import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/device.dart';
import '../models/transfer.dart';

/// 发送方拿到的拒绝/失败原因,界面按类型给不同提示
class SendException implements Exception {
  SendException(this.message, {this.rejected = false});

  final String message;

  /// true = 对方点了「拒绝」,不是网络错误
  final bool rejected;

  @override
  String toString() => message;
}

/// 文件发送客户端。一个实例负责一次会话,支持中途取消。
class SendClient {
  SendClient({
    required this.self,
    required this.target,
    required this.task,
    required this.onProgress,
  });

  final Device self;
  final Device target;
  final TransferTask task;

  /// 每收到一次进度变化就回调(节流交给 AppState)
  final void Function(TransferTask task) onProgress;

  final _client = HttpClient()
    // 局域网内连接建立很快,超过 8 秒基本是对方不在线
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 30);

  String? _sessionId;
  bool _canceled = false;
  HttpClientRequest? _current;

  Uri _uri(String path, [Map<String, String>? q]) => Uri(
        scheme: 'http',
        host: target.ip,
        port: target.port,
        path: path,
        queryParameters: q,
      );

  /// 走完整个流程:prepare -> 逐个 upload。
  /// 抛 [SendException] 表示失败,task.status 也会同步更新。
  Future<void> run() async {
    try {
      final tokens = await _prepare();
      task.status = TransferStatus.transferring;
      onProgress(task);

      for (final f in task.files) {
        if (_canceled) throw SendException('已取消');
        final token = tokens[f.id];
        if (token == null) {
          throw SendException('对方未接受文件 ${f.name}');
        }
        await _uploadOne(f, token);
      }

      task.status = TransferStatus.done;
      task.currentFileId = null;
      task.finishedAt = DateTime.now();
      onProgress(task);
    } catch (e) {
      if (task.status.isFinished) return; // 已被 cancel() 处理过
      task.status =
          _canceled ? TransferStatus.canceled : TransferStatus.failed;
      if (e is SendException && e.rejected) {
        task.status = TransferStatus.rejected;
      }
      task.error = e is SendException ? e.message : '$e';
      task.finishedAt = DateTime.now();
      onProgress(task);
      rethrow;
    } finally {
      _client.close(force: true);
    }
  }

  /// 询问对方是否接收。对方在弹窗上纠结的时间可能很长,这里不设超时上限,
  /// 只靠用户点「取消」来中断。
  Future<Map<String, String>> _prepare() async {
    final body = jsonEncode({
      'device': self.toJson(),
      'files': task.files.map((f) => f.toJson()).toList(),
    });
    late HttpClientResponse resp;
    try {
      final req = await _client.postUrl(_uri('/api/v1/prepare'));
      req.headers.contentType = ContentType.json;
      req.write(body);
      _current = req;
      resp = await req.close();
    } on SocketException catch (e) {
      throw SendException('连不上 ${target.alias}(${target.ip}):${e.message}');
    } finally {
      _current = null;
    }

    final text = await utf8.decoder.bind(resp).join();
    if (resp.statusCode == 403) {
      throw SendException('${target.alias} 拒绝了本次传输', rejected: true);
    }
    if (resp.statusCode != 200) {
      throw SendException('对方返回 ${resp.statusCode}:${_briefError(text)}');
    }
    final j = jsonDecode(text);
    if (j is! Map<String, dynamic>) throw SendException('对方响应格式异常');
    final sid = j['sessionId'];
    final tk = j['tokens'];
    if (sid is! String || tk is! Map) throw SendException('对方响应缺少会话信息');
    _sessionId = sid;
    task.id;
    return {
      for (final e in tk.entries)
        if (e.key is String && e.value is String)
          e.key as String: e.value as String,
    };
  }

  Future<void> _uploadOne(FileItem item, String token) async {
    final path = item.path;
    if (path == null) throw SendException('${item.name} 缺少本地路径');
    final file = File(path);
    if (!await file.exists()) throw SendException('文件已不存在:${item.name}');

    task.currentFileId = item.id;
    onProgress(task);

    late HttpClientResponse resp;
    try {
      final req = await _client.postUrl(_uri('/api/v1/upload', {
        'session': _sessionId!,
        'file': item.id,
        'token': token,
      }));
      req.headers.contentType = ContentType.binary;
      // 设置 Content-Length,避免走 chunked 编码
      req.contentLength = item.size;
      _current = req;

      var sent = 0;
      // 64KB 一块:局域网吞吐够用,进度更新也不至于过密
      await for (final chunk in file.openRead()) {
        if (_canceled) throw SendException('已取消');
        req.add(chunk);
        // 等 socket 排空再读下一块,否则大文件会全部堆进内存
        await req.flush();
        sent += chunk.length;
        task.progress[item.id] = sent;
        onProgress(task);
      }
      resp = await req.close();
    } on SocketException catch (e) {
      throw SendException('传输中断:${e.message}');
    } finally {
      _current = null;
    }

    if (resp.statusCode == 409) {
      throw SendException('对方已取消接收');
    }
    final text = await utf8.decoder.bind(resp).join();
    if (resp.statusCode != 200) {
      throw SendException('${item.name} 上传失败:${_briefError(text)}');
    }
    task.progress[item.id] = item.size;
    onProgress(task);
  }

  /// 取消:中断当前请求,并通知对方清理会话
  Future<void> cancel() async {
    _canceled = true;
    try {
      _current?.abort();
    } catch (_) {}
    final sid = _sessionId;
    if (sid != null) {
      try {
        final c = HttpClient()..connectionTimeout = const Duration(seconds: 3);
        final req = await c.postUrl(_uri('/api/v1/cancel', {'session': sid}));
        await req.close();
        c.close(force: true);
      } catch (_) {
        // 对方可能已经断了,取消通知失败无所谓
      }
    }
    if (!task.status.isFinished) {
      task.status = TransferStatus.canceled;
      task.error = '已取消发送';
      task.finishedAt = DateTime.now();
      onProgress(task);
    }
  }

  /// 从对方返回的 JSON 里挑出 error 字段,失败则截断原文
  static String _briefError(String text) {
    try {
      final j = jsonDecode(text);
      if (j is Map && j['error'] is String) return j['error'] as String;
    } catch (_) {}
    final t = text.trim();
    return t.length > 120 ? '${t.substring(0, 120)}…' : t;
  }

  static void debugLog(String m) => debugPrint('[send] $m');
}
