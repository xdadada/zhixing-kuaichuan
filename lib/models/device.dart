import 'dart:io';

/// 设备类型 —— 决定列表里显示哪个图标
enum DeviceType {
  desktop,
  laptop,
  phone,
  tablet,
  unknown;

  String get wire => name;

  static DeviceType parse(String? s) => DeviceType.values.firstWhere(
        (t) => t.name == s,
        orElse: () => DeviceType.unknown,
      );

  /// 当前设备的类型:iPad 归 tablet,iPhone 归 phone,桌面平台按机型
  static DeviceType current() {
    if (Platform.isIOS) {
      // iPadOS 的 Platform.operatingSystemVersion 里带 "iPad"
      final v = Platform.operatingSystemVersion.toLowerCase();
      return v.contains('ipad') ? DeviceType.tablet : DeviceType.phone;
    }
    if (Platform.isAndroid) return DeviceType.phone;
    if (Platform.isMacOS) return DeviceType.laptop;
    return DeviceType.desktop;
  }
}

/// 局域网里的一台设备。
///
/// [fingerprint] 是设备的稳定标识(首次启动随机生成并持久化),用于
/// 去重、收藏、以及识别「自己发出的组播包」。IP 会变,指纹不会。
class Device {
  Device({
    required this.fingerprint,
    required this.alias,
    required this.deviceType,
    required this.ip,
    required this.port,
    this.model,
    DateTime? lastSeen,
  }) : lastSeen = lastSeen ?? DateTime.now();

  final String fingerprint;
  final String alias;
  final DeviceType deviceType;
  final String ip;
  final int port;

  /// 机型描述,如 "macOS 26.5"、"iOS 27.0"
  final String? model;

  /// 最后一次收到公告的时间,用于剔除离线设备
  DateTime lastSeen;

  String get baseUrl => 'http://$ip:$port';

  Device copyWith({String? ip, int? port, DateTime? lastSeen, String? alias}) =>
      Device(
        fingerprint: fingerprint,
        alias: alias ?? this.alias,
        deviceType: deviceType,
        ip: ip ?? this.ip,
        port: port ?? this.port,
        model: model,
        lastSeen: lastSeen ?? this.lastSeen,
      );

  Map<String, dynamic> toJson() => {
        'fingerprint': fingerprint,
        'alias': alias,
        'deviceType': deviceType.wire,
        'ip': ip,
        'port': port,
        if (model != null) 'model': model,
      };

  /// 从组播公告 / HTTP 响应解析。字段缺失或类型不对时返回 null,
  /// 不让畸形的广播包打断发现流程。
  ///
  /// [observedIp] 是「包的实际来源地址」或「实际连上的地址」。它优先于
  /// 包内自报的 ip:对方换网后本机 IP 变了,但 App 可能还在广播旧 IP,
  /// 自报值会过期,而来源地址永远是当下可达的。
  static Device? fromJson(Map<String, dynamic> j, {String? observedIp}) {
    final fp = j['fingerprint'];
    final alias = j['alias'];
    if (fp is! String || fp.isEmpty) return null;
    if (alias is! String || alias.isEmpty) return null;
    final port = j['port'];
    final ip = observedIp ?? (j['ip'] as String?);
    if (ip == null || ip.isEmpty) return null;
    return Device(
      fingerprint: fp,
      alias: alias,
      deviceType: DeviceType.parse(j['deviceType'] as String?),
      ip: ip,
      port: port is int ? port : int.tryParse('$port') ?? 54322,
      model: j['model'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Device && other.fingerprint == fingerprint;

  @override
  int get hashCode => fingerprint.hashCode;
}
