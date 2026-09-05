import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/device.dart';

/// 局域网设备发现。
///
/// 两条腿走路,互为兜底:
///  1. **UDP 公告**(主路):绑定 [port],加入组播组 [group],定时把自己的
///     信息发到组播地址 + 子网广播地址。收到别人的 `announce` 包时,单播回
///     一份自己的信息,这样新上线的设备能立刻被双方看到。
///  2. **HTTP 子网扫描**(兜底):并发探测本机 /24 网段每个 IP 的
///     `/api/v1/info`。iOS 14+ 对原始组播/广播需要 Apple 单独审批的
///     multicast entitlement,没有它时第 1 条腿可能收发失败,此时靠扫描
///     仍能找到设备。
class DiscoveryService {
  DiscoveryService({
    required this.self,
    required this.port,
    required this.group,
  });

  /// 本机设备信息(port 字段是 HTTP 传输端口,不是发现端口)
  Device self;
  final int port;
  final String group;

  RawDatagramSocket? _socket;
  Timer? _announceTimer;
  final _found = StreamController<Device>.broadcast();

  /// 发现 / 更新到设备时推送
  Stream<Device> get onDevice => _found.stream;

  /// 关闭后不再回应别人的公告,也不再主动公告
  bool discoverable = true;

  bool get running => _socket != null;

  /// 最近一次 UDP 收发是否成功,用于在界面上提示「组播不可用,已用扫描兜底」
  bool udpWorking = false;

  Future<void> start() async {
    await stop();
    try {
      final s = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
        reusePort: !Platform.isWindows, // Windows 不支持 SO_REUSEPORT
      );
      s.broadcastEnabled = true;
      s.multicastHops = 4; // 跨过一两级交换机/AP 仍能到达
      _socket = s;
      _joinMulticast(s);
      s.listen(_onEvent, onError: (Object e) {
        debugPrint('[discovery] socket error: $e');
      });
      // 立即公告一次,再转入周期公告
      announce();
      _announceTimer = Timer.periodic(
          const Duration(seconds: 5), (_) => announce());
    } catch (e) {
      debugPrint('[discovery] bind failed: $e');
      // 端口被占用等情况下不抛出:界面仍可用扫描 + 手动添加
    }
  }

  /// 在每块网卡上加入组播组。部分平台/网卡会失败,忽略即可。
  void _joinMulticast(RawDatagramSocket s) {
    try {
      s.joinMulticast(InternetAddress(group));
      return;
    } catch (_) {
      // 未指定网卡时失败,逐块网卡重试
    }
    NetworkInterface.list(type: InternetAddressType.IPv4).then((ifaces) {
      for (final i in ifaces) {
        try {
          s.joinMulticast(InternetAddress(group), i);
        } catch (_) {
          // 该网卡不支持组播
        }
      }
    }).catchError((Object e) {
      // 拿不到网卡列表(权限受限)时放弃组播,靠广播和扫描兜底
      debugPrint('[discovery] interface list failed: $e');
    });
  }

  Future<void> stop() async {
    _announceTimer?.cancel();
    _announceTimer = null;
    final s = _socket;
    _socket = null;
    if (s != null) {
      try {
        s.leaveMulticast(InternetAddress(group));
      } catch (_) {}
      s.close();
    }
  }

  void dispose() {
    stop();
    _found.close();
  }

  // ------------------------------------------------------------------ 收发

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final s = _socket;
    if (s == null) return;
    final dg = s.receive();
    if (dg == null) return;
    Map<String, dynamic> j;
    try {
      final decoded = jsonDecode(utf8.decode(dg.data));
      if (decoded is! Map<String, dynamic>) return;
      j = decoded;
    } catch (_) {
      return; // 不是我们的包,忽略
    }
    if (j['fingerprint'] == self.fingerprint) return; // 自己发的
    final dev = Device.fromJson(j, observedIp: dg.address.address);
    if (dev == null) return;
    udpWorking = true;
    _found.add(dev);
    // 对方在「宣告上线」,单播回一份自己的信息让它也能看到我们
    if (j['announce'] == true && discoverable) {
      _send(_payload(announce: false), dg.address, port);
    }
  }

  List<int> _payload({required bool announce}) => utf8.encode(jsonEncode({
        ...self.toJson(),
        'announce': announce,
      }));

  void _send(List<int> data, InternetAddress addr, int p) {
    try {
      _socket?.send(data, addr, p);
    } catch (_) {
      // 网卡切换瞬间可能失败,下个周期会重发
    }
  }

  /// 主动宣告上线:组播 + 各网卡子网广播(组播被网络设备拦掉时的兜底)
  void announce() {
    if (!discoverable || _socket == null) return;
    final data = _payload(announce: true);
    _send(data, InternetAddress(group), port);
    _send(data, InternetAddress('255.255.255.255'), port);
    for (final b in _broadcastAddresses) {
      _send(data, InternetAddress(b), port);
    }
  }

  /// 缓存的子网广播地址(如 192.168.1.255),网卡变化时刷新
  List<String> _broadcastAddresses = const [];

  Future<void> refreshInterfaces() async {
    final out = <String>[];
    try {
      for (final i in await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLoopback: false)) {
        for (final a in i.addresses) {
          final b = _broadcastOf24(a.address);
          if (b != null) out.add(b);
        }
      }
    } catch (_) {
      // 权限受限时拿不到网卡列表,保留旧值
      return;
    }
    _broadcastAddresses = out;
  }

  /// 按 /24 推导广播地址。局域网绝大多数是 /24,拿不到掩码时这个假设够用。
  static String? _broadcastOf24(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return null;
    return '${parts[0]}.${parts[1]}.${parts[2]}.255';
  }

  // ------------------------------------------------------- HTTP 子网扫描兜底

  /// 扫描进度 0..1
  final scanProgress = ValueNotifier<double>(1);

  bool _scanning = false;
  bool get scanning => _scanning;

  /// 并发探测本机所在 /24 网段的 `/api/v1/info`。
  /// [httpPort] 是对方的传输端口(默认与本机相同)。
  Future<List<Device>> scanSubnet({
    required int httpPort,
    Duration timeout = const Duration(milliseconds: 600),
    int concurrency = 48,
  }) async {
    if (_scanning) return const [];
    _scanning = true;
    scanProgress.value = 0;
    final results = <Device>[];
    try {
      final prefixes = <String>{};
      for (final ip in await localIps()) {
        final parts = ip.split('.');
        if (parts.length == 4) {
          prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
        }
      }
      if (prefixes.isEmpty) return const [];

      final targets = <String>[];
      for (final p in prefixes) {
        for (var i = 1; i < 255; i++) {
          targets.add('$p.$i');
        }
      }

      var done = 0;
      // 分批并发,避免一次性开几百个 socket 把系统 fd 打满
      for (var i = 0; i < targets.length; i += concurrency) {
        final batch = targets.skip(i).take(concurrency);
        final probes = batch.map((ip) async {
          final d = await probe(ip, httpPort, timeout: timeout);
          done++;
          scanProgress.value = done / targets.length;
          if (d != null && d.fingerprint != self.fingerprint) {
            results.add(d);
            _found.add(d);
          }
        });
        await Future.wait(probes);
      }
    } finally {
      _scanning = false;
      scanProgress.value = 1;
    }
    return results;
  }

  /// 探测单个地址是否跑着本 App;不是则返回 null
  static Future<Device?> probe(
    String ip,
    int httpPort, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = timeout;
    try {
      final req = await client
          .getUrl(Uri.parse('http://$ip:$httpPort/api/v1/info'))
          .timeout(timeout);
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) return null;
      final body = await resp
          .transform(utf8.decoder)
          .join()
          .timeout(timeout);
      final j = jsonDecode(body);
      if (j is! Map<String, dynamic>) return null;
      return Device.fromJson(j, observedIp: ip);
    } catch (_) {
      return null; // 绝大多数 IP 都是超时/拒绝,属正常
    } finally {
      client.close(force: true);
    }
  }

  /// 本机所有非回环 IPv4 地址,常用网卡(en/wl)优先
  static Future<List<String>> localIps() async {
    try {
      final ifaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      final out = <String>[];
      for (final i in ifaces) {
        for (final a in i.addresses) {
          // 169.254.x.x 是链路本地自分配地址,连不通任何人
          if (a.address.startsWith('169.254.')) continue;
          out.add(a.address);
        }
      }
      out.sort((a, b) {
        // 私有网段优先,让界面上显示的「本机 IP」是有意义的那个
        int rank(String ip) => _isPrivate(ip) ? 0 : 1;
        return rank(a).compareTo(rank(b));
      });
      return out;
    } catch (_) {
      return const [];
    }
  }

  static bool _isPrivate(String ip) =>
      ip.startsWith('192.168.') ||
      ip.startsWith('10.') ||
      RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(ip);

  /// 界面展示用的主 IP
  static Future<String?> primaryIp() async {
    final ips = await localIps();
    return ips.isEmpty ? null : ips.first;
  }
}
