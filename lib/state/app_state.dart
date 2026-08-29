import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/discovery.dart';
import '../core/receive_server.dart';
import '../core/send_client.dart';
import '../models/device.dart';
import '../models/settings.dart';
import '../models/transfer.dart';
import '../services/file_service.dart';
import '../services/storage.dart';

/// 等待用户确认的接收请求
class PendingApproval {
  PendingApproval(this.task, this._completer);

  final TransferTask task;
  final Completer<bool> _completer;

  bool get settled => _completer.isCompleted;

  void resolve(bool accept) {
    if (!_completer.isCompleted) _completer.complete(accept);
  }
}

class AppState extends ChangeNotifier {
  AppState(this._storage);

  final Storage _storage;

  AppSettings settings = AppSettings();

  /// 本机设备指纹,首次启动生成后持久化
  late String fingerprint;

  /// 在线设备(按发现时间排序),key = fingerprint
  final Map<String, Device> devices = {};

  /// 收藏设备指纹 —— 收藏的排在列表前面,还能配合「仅收藏自动接收」
  final Set<String> favorites = {};

  /// 手动添加的设备(IP 直连),掉线也不从列表移除
  final List<Device> manualDevices = [];

  /// 进行中的任务(发送 + 接收)
  final List<TransferTask> active = [];

  /// 已结束的任务,最新在前;上限 200 条
  final List<TransferTask> history = [];

  /// 待确认的接收请求
  final List<PendingApproval> pendingApprovals = [];

  /// 已选择、待发送的文件
  final List<FileItem> outbox = [];

  String? localIp;
  String? saveDirResolved;

  /// 发现服务是否收到过 UDP 包 —— 界面据此提示是否需要手动扫描
  bool get udpWorking => _discovery?.udpWorking ?? false;

  bool get scanning => _discovery?.scanning ?? false;

  ValueNotifier<double> get scanProgress =>
      _discovery?.scanProgress ?? ValueNotifier(1);

  bool serverRunning = false;

  /// 服务启动失败原因(端口占用等)
  String? serverError;

  DiscoveryService? _discovery;
  ReceiveServer? _server;
  final _sendClients = <String, SendClient>{};

  Timer? _persistDebounce;
  Timer? _ticker;
  Timer? _pruneTimer;
  StreamSubscription<Device>? _deviceSub;

  /// 上一秒的已传字节数,用于算速度
  final _lastBytes = <String, int>{};

  // ------------------------------------------------------------------ 初始化

  Future<void> init() async {
    final saved = await _storage.load();
    if (saved != null) _hydrate(saved);

    fingerprint = (saved?['fingerprint'] as String?) ?? _newFingerprint();
    if (settings.alias.isEmpty) settings.alias = await _defaultAlias();

    saveDirResolved =
        settings.saveDir ?? await FileService.defaultSaveDir(_storage.dir.path);
    localIp = await DiscoveryService.primaryIp();

    await _startNetworking();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _sampleSpeed());
    // 15 秒没公告的设备视为离线
    _pruneTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _pruneDevices());

    notifyListeners();
    _persist();
  }

  Device get selfDevice => Device(
        fingerprint: fingerprint,
        alias: settings.alias,
        deviceType: DeviceType.current(),
        ip: localIp ?? '0.0.0.0',
        port: settings.port,
        model: _osDescription(),
      );

  Future<void> _startNetworking() async {
    serverError = null;
    final server = ReceiveServer(
      selfInfo: () => selfDevice,
      onApproval: _requestApproval,
      onTaskUpdate: _onTaskUpdate,
      resolveSaveDir: _resolveSaveDir,
      overwriteExisting: () => settings.overwriteExisting,
    );
    try {
      await server.start(settings.port);
      _server = server;
      serverRunning = true;
    } catch (e) {
      serverRunning = false;
      serverError = '端口 ${settings.port} 无法监听:$e';
      debugPrint('[app] server start failed: $e');
    }

    final disc = DiscoveryService(
      self: selfDevice,
      port: settings.discoveryPort,
      group: settings.multicastGroup,
    );
    disc.discoverable = settings.discoverable;
    await disc.refreshInterfaces();
    _deviceSub = disc.onDevice.listen(_onDeviceFound);
    await disc.start();
    _discovery = disc;
  }

  /// 端口/设备名等改动后重启网络层
  Future<void> restartNetworking() async {
    await _deviceSub?.cancel();
    _deviceSub = null;
    _discovery?.dispose();
    _discovery = null;
    await _server?.stop();
    _server = null;
    serverRunning = false;
    devices.clear();
    localIp = await DiscoveryService.primaryIp();
    await _startNetworking();
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _pruneTimer?.cancel();
    _persistDebounce?.cancel();
    _deviceSub?.cancel();
    _discovery?.dispose();
    _server?.stop();
    super.dispose();
  }

  // -------------------------------------------------------------------- 设备

  void _onDeviceFound(Device d) {
    final existing = devices[d.fingerprint];
    if (existing == null) {
      devices[d.fingerprint] = d;
    } else {
      existing.lastSeen = DateTime.now();
      // IP 可能因换网变化,别名可能被改
      if (existing.ip != d.ip || existing.alias != d.alias) {
        devices[d.fingerprint] = d;
      }
    }
    notifyListeners();
  }

  void _pruneDevices() {
    final now = DateTime.now();
    final before = devices.length;
    devices.removeWhere(
        (_, d) => now.difference(d.lastSeen) > const Duration(seconds: 16));
    if (devices.length != before) notifyListeners();
  }

  /// 界面上展示的设备列表:收藏优先,其余按名字排序
  List<Device> get visibleDevices {
    final all = <String, Device>{};
    for (final m in manualDevices) {
      all[m.fingerprint] = m;
    }
    all.addAll(devices); // 在线信息覆盖手动记录
    final list = all.values.toList();
    list.sort((a, b) {
      final fa = favorites.contains(a.fingerprint) ? 0 : 1;
      final fb = favorites.contains(b.fingerprint) ? 0 : 1;
      if (fa != fb) return fa.compareTo(fb);
      return a.alias.toLowerCase().compareTo(b.alias.toLowerCase());
    });
    return list;
  }

  bool isOnline(Device d) => devices.containsKey(d.fingerprint);

  void toggleFavorite(String fp) {
    if (!favorites.remove(fp)) favorites.add(fp);
    notifyListeners();
    _persist();
  }

  /// 主动重新公告,催促对方回应
  void refreshDiscovery() {
    _discovery?.refreshInterfaces().then((_) => _discovery?.announce());
    _discovery?.announce();
    notifyListeners();
  }

  /// 子网扫描兜底
  Future<int> scanSubnet() async {
    final d = _discovery;
    if (d == null) return 0;
    notifyListeners();
    final found = await d.scanSubnet(httpPort: settings.port);
    notifyListeners();
    return found.length;
  }

  /// 手动按 IP 添加设备
  Future<String?> addManualDevice(String ip, {int? port}) async {
    final p = port ?? settings.port;
    final dev = await DiscoveryService.probe(ip, p,
        timeout: const Duration(seconds: 4));
    if (dev == null) return '在 $ip:$p 上没找到设备';
    if (dev.fingerprint == fingerprint) return '这是本机地址';
    manualDevices.removeWhere((m) => m.fingerprint == dev.fingerprint);
    manualDevices.add(dev);
    devices[dev.fingerprint] = dev;
    notifyListeners();
    _persist();
    return null;
  }

  void removeManualDevice(String fp) {
    manualDevices.removeWhere((m) => m.fingerprint == fp);
    notifyListeners();
    _persist();
  }

  // ------------------------------------------------------------- 待发送列表

  void addToOutbox(List<FileItem> items) {
    if (items.isEmpty) return;
    outbox.addAll(items);
    notifyListeners();
  }

  void removeFromOutbox(String id) {
    outbox.removeWhere((f) => f.id == id);
    notifyListeners();
  }

  void clearOutbox() {
    outbox.clear();
    notifyListeners();
  }

  int get outboxBytes => outbox.fold(0, (s, f) => s + f.size);

  // -------------------------------------------------------------------- 发送

  /// 把 outbox 里的文件发给 [target]。返回错误信息,成功为 null。
  Future<String?> sendOutboxTo(Device target) async {
    if (outbox.isEmpty) return '还没有选择文件';
    final files = List<FileItem>.from(outbox);
    outbox.clear();
    return sendFiles(target, files);
  }

  Future<String?> sendFiles(Device target, List<FileItem> files) async {
    if (files.isEmpty) return '还没有选择文件';
    final task = TransferTask(
      id: _newSessionId(),
      direction: TransferDirection.send,
      device: target,
      files: files,
    );
    active.insert(0, task);
    notifyListeners();

    final client = SendClient(
      self: selfDevice,
      target: target,
      task: task,
      onProgress: (_) => _markDirty(),
    );
    _sendClients[task.id] = client;
    try {
      await client.run();
      _finishTask(task);
      return null;
    } catch (e) {
      _finishTask(task);
      return e is SendException ? e.message : '$e';
    } finally {
      _sendClients.remove(task.id);
    }
  }

  Future<void> cancelTask(TransferTask task) async {
    if (task.direction == TransferDirection.send) {
      await _sendClients[task.id]?.cancel();
    } else {
      await _server?.cancelSession(task.id);
    }
    _finishTask(task);
  }

  // -------------------------------------------------------------------- 接收

  Future<bool> _requestApproval(TransferTask task) async {
    final auto = switch (settings.receiveMode) {
      ReceiveMode.auto => true,
      ReceiveMode.favoritesOnly =>
        favorites.contains(task.device.fingerprint),
      ReceiveMode.ask => false,
    };
    if (auto) return true;

    final completer = Completer<bool>();
    final pending = PendingApproval(task, completer);
    pendingApprovals.add(pending);
    notifyListeners();
    final accepted = await completer.future;
    pendingApprovals.remove(pending);
    notifyListeners();
    return accepted;
  }

  void resolveApproval(PendingApproval p, bool accept) {
    p.resolve(accept);
    notifyListeners();
  }

  Future<String> _resolveSaveDir() async {
    final dir = settings.saveDir ??
        saveDirResolved ??
        await FileService.defaultSaveDir(_storage.dir.path);
    if (await FileService.ensureDir(dir)) {
      saveDirResolved = dir;
      return dir;
    }
    // 用户设的目录不可写时退回默认目录,别让接收整批失败
    final fallback = await FileService.defaultSaveDir(_storage.dir.path);
    saveDirResolved = fallback;
    return fallback;
  }

  void _onTaskUpdate(TransferTask task) {
    if (!active.any((t) => t.id == task.id) &&
        !history.any((t) => t.id == task.id)) {
      active.insert(0, task);
    }
    if (task.status.isFinished) {
      _finishTask(task);
    } else {
      _markDirty();
    }
  }

  void _finishTask(TransferTask task) {
    task.bytesPerSecond = 0;
    _lastBytes.remove(task.id);
    active.removeWhere((t) => t.id == task.id);
    if (!history.any((t) => t.id == task.id)) {
      task.finishedAt ??= DateTime.now();
      history.insert(0, task);
      if (history.length > 200) history.removeRange(200, history.length);
    }
    notifyListeners();
    _persist();

    if (task.direction == TransferDirection.receive &&
        task.status == TransferStatus.done &&
        settings.autoOpenOnDone) {
      final first = task.savedPaths.values.firstOrNull;
      if (first != null) FileService.revealInFolder(first);
    }
  }

  void clearHistory() {
    history.clear();
    notifyListeners();
    _persist();
  }

  void removeHistory(String id) {
    history.removeWhere((t) => t.id == id);
    notifyListeners();
    _persist();
  }

  // ------------------------------------------------------------------ 速度

  /// 进度回调很密集,直接 notifyListeners 会把 UI 冲垮。
  /// 这里只打脏标记,由每秒的 ticker 统一刷新。
  bool _dirty = false;

  void _markDirty() {
    _dirty = true;
  }

  void _sampleSpeed() {
    for (final t in active) {
      final now = t.transferredBytes;
      final last = _lastBytes[t.id] ?? now;
      t.bytesPerSecond = (now - last).toDouble().clamp(0, double.infinity);
      _lastBytes[t.id] = now;
    }
    if (_dirty || active.isNotEmpty) {
      _dirty = false;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------ 设置

  Future<void> setAlias(String alias) async {
    final v = alias.trim();
    if (v.isEmpty || v == settings.alias) return;
    settings.alias = v;
    final d = _discovery;
    if (d != null) {
      d.self = selfDevice;
      d.announce();
    }
    notifyListeners();
    _persist();
  }

  void setThemeMode(AppThemeMode m) {
    settings.themeMode = m;
    notifyListeners();
    _persist();
  }

  void setReceiveMode(ReceiveMode m) {
    settings.receiveMode = m;
    notifyListeners();
    _persist();
  }

  Future<void> setSaveDir(String? dir) async {
    settings.saveDir = dir;
    saveDirResolved =
        dir ?? await FileService.defaultSaveDir(_storage.dir.path);
    notifyListeners();
    _persist();
  }

  void setDiscoverable(bool v) {
    settings.discoverable = v;
    _discovery?.discoverable = v;
    if (v) _discovery?.announce();
    notifyListeners();
    _persist();
  }

  void setOverwrite(bool v) {
    settings.overwriteExisting = v;
    notifyListeners();
    _persist();
  }

  void setAutoOpen(bool v) {
    settings.autoOpenOnDone = v;
    notifyListeners();
    _persist();
  }

  /// 改端口后必须重启监听
  Future<String?> setPort(int port) async {
    if (port < 1024 || port > 65535) return '端口需在 1024–65535 之间';
    if (port == settings.port) return null;
    final old = settings.port;
    settings.port = port;
    await restartNetworking();
    if (!serverRunning) {
      settings.port = old;
      await restartNetworking();
      return '端口 $port 不可用,已恢复为 $old';
    }
    _persist();
    return null;
  }

  // ---------------------------------------------------------------- 持久化

  void _persist() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 400), () {
      _storage.save({
        'fingerprint': fingerprint,
        'settings': settings.toJson(),
        'favorites': favorites.toList(),
        'manualDevices': manualDevices.map((d) => d.toJson()).toList(),
        'history': history.take(200).map((t) => t.toJson()).toList(),
      });
    });
  }

  void _hydrate(Map<String, dynamic> j) {
    final s = j['settings'];
    if (s is Map<String, dynamic>) settings = AppSettings.fromJson(s);
    final fav = j['favorites'];
    if (fav is List) favorites.addAll(fav.whereType<String>());
    final man = j['manualDevices'];
    if (man is List) {
      for (final m in man.whereType<Map<String, dynamic>>()) {
        final d = Device.fromJson(m);
        if (d != null) manualDevices.add(d);
      }
    }
    final h = j['history'];
    if (h is List) {
      for (final t in h.whereType<Map<String, dynamic>>()) {
        final task = TransferTask.fromJson(t);
        if (task != null) history.add(task);
      }
    }
  }

  // ------------------------------------------------------------------ 杂项

  static String _newFingerprint() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _newSessionId() {
    final r = Random.secure();
    return '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '-${r.nextInt(1 << 32).toRadixString(36)}';
  }

  /// 默认设备名:桌面用主机名,移动端用平台名
  static Future<String> _defaultAlias() async {
    try {
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        var h = Platform.localHostname;
        // macOS 主机名常带 .local 后缀
        if (h.endsWith('.local')) h = h.substring(0, h.length - 6);
        if (h.isNotEmpty) return h;
      }
    } catch (_) {}
    if (Platform.isIOS) {
      return DeviceType.current() == DeviceType.tablet ? 'iPad' : 'iPhone';
    }
    if (Platform.isMacOS) return 'Mac';
    if (Platform.isWindows) return 'Windows PC';
    return '未命名设备';
  }

  static String _osDescription() {
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    return Platform.operatingSystem;
  }
}
