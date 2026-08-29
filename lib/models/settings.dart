enum AppThemeMode { system, light, dark }

/// 接收策略
enum ReceiveMode {
  /// 每次弹窗询问
  ask,
  /// 自动接收所有设备
  auto,
  /// 只自动接收收藏设备,其余询问
  favoritesOnly;

  String get label => switch (this) {
        ReceiveMode.ask => '每次询问',
        ReceiveMode.auto => '全部自动接收',
        ReceiveMode.favoritesOnly => '仅收藏设备自动',
      };
}

class AppSettings {
  AppSettings({
    this.alias = '',
    this.themeMode = AppThemeMode.system,
    this.receiveMode = ReceiveMode.ask,
    this.saveDir,
    this.port = 54322,
    this.discoveryPort = 54321,
    this.multicastGroup = '224.0.0.180',
    this.discoverable = true,
    this.autoOpenOnDone = false,
    this.overwriteExisting = false,
  });

  /// 对外显示的设备名
  String alias;
  AppThemeMode themeMode;
  ReceiveMode receiveMode;

  /// 接收文件保存目录;null = 使用平台默认下载目录
  String? saveDir;

  /// HTTP 传输端口
  int port;

  /// UDP 发现端口
  int discoveryPort;
  String multicastGroup;

  /// 关闭后不响应组播、不被别人发现(仍可主动发给别人)
  bool discoverable;

  /// 接收完成后自动打开所在文件夹(仅桌面)
  bool autoOpenOnDone;

  /// 同名文件直接覆盖;false 时自动改名 a(1).txt
  bool overwriteExisting;

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'themeMode': themeMode.name,
        'receiveMode': receiveMode.name,
        'saveDir': saveDir,
        'port': port,
        'discoveryPort': discoveryPort,
        'multicastGroup': multicastGroup,
        'discoverable': discoverable,
        'autoOpenOnDone': autoOpenOnDone,
        'overwriteExisting': overwriteExisting,
      };

  static AppSettings fromJson(Map<String, dynamic> j) => AppSettings(
        alias: (j['alias'] as String?) ?? '',
        themeMode: AppThemeMode.values.firstWhere(
          (m) => m.name == j['themeMode'],
          orElse: () => AppThemeMode.system,
        ),
        receiveMode: ReceiveMode.values.firstWhere(
          (m) => m.name == j['receiveMode'],
          orElse: () => ReceiveMode.ask,
        ),
        saveDir: j['saveDir'] as String?,
        port: j['port'] is int ? j['port'] as int : 54322,
        discoveryPort:
            j['discoveryPort'] is int ? j['discoveryPort'] as int : 54321,
        multicastGroup:
            (j['multicastGroup'] as String?) ?? '224.0.0.180',
        discoverable: j['discoverable'] as bool? ?? true,
        autoOpenOnDone: j['autoOpenOnDone'] as bool? ?? false,
        overwriteExisting: j['overwriteExisting'] as bool? ?? false,
      );
}
