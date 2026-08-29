import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/device.dart';
import '../../services/file_service.dart';
import '../../state/app_state.dart';
import '../../utils/formats.dart';
import '../file_icon.dart';
import '../solar_icons.dart';
import '../theme.dart';
import '../widgets.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: const [
        _SelfCard(),
        SizedBox(height: 4),
        _OutboxCard(),
        SizedBox(height: 4),
        _DeviceListHeader(),
        _DeviceList(),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('知行快传'),
        actions: [
          IconButton(
            tooltip: '重新搜索',
            icon: const Icon(SolarIcons.refresh),
            onPressed: () {
              context.read<AppState>().refreshDiscovery();
              showToast(context, '已重新广播,正在等待设备回应');
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        bottom: false,
        // 桌面端支持把文件直接拖进窗口
        child: _isDesktop ? _DropTarget(child: list) : list,
      ),
    );
  }
}

class _DropTarget extends StatefulWidget {
  const _DropTarget({required this.child});

  final Widget child;

  @override
  State<_DropTarget> createState() => _DropTargetState();
}

class _DropTargetState extends State<_DropTarget> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _hover = true),
      onDragExited: (_) => setState(() => _hover = false),
      onDragDone: (detail) async {
        setState(() => _hover = false);
        final paths = detail.files.map((f) => f.path).toList();
        final items = await FileService.fromPaths(paths);
        if (!context.mounted) return;
        if (items.isEmpty) {
          showToast(context, '没能读取拖入的内容', error: true);
          return;
        }
        context.read<AppState>().addToOutbox(items);
        showToast(context, '已添加 ${items.length} 个文件');
      },
      child: Stack(
        children: [
          widget.child,
          if (_hover)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 26, vertical: 18),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardTheme.color,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                          color: AppColors.primary, width: 2),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(SolarIcons.send,
                            color: AppColors.primary, size: 26),
                        SizedBox(width: 10),
                        Text('松手即添加到待发送',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ 本机信息

class _SelfCard extends StatelessWidget {
  const _SelfCard();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final self = app.selfDevice;
    final ok = app.serverRunning;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
            child: Row(
              children: [
                DeviceIcon(type: self.deviceType, size: 52),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(self.alias,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 19, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(ok ? SolarIcons.check : SolarIcons.warn,
                              size: 15,
                              color: ok ? AppColors.green : AppColors.orange),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              ok
                                  ? '${app.localIp ?? "未联网"} · 端口 ${self.port}'
                                  : (app.serverError ?? '接收服务未运行'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: ok
                                    ? AppColors.subtextLight
                                    : AppColors.orange,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!app.settings.discoverable)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.orange.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Text('已隐身',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.orange)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- 待发送文件区

class _OutboxCard extends StatelessWidget {
  const _OutboxCard();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final files = app.outbox;
    final canPickFolder = FileService.supportsFolderPick;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text('待发送',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                if (files.isNotEmpty)
                  TextButton(
                    onPressed: app.clearOutbox,
                    style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      foregroundColor: AppColors.subtextLight,
                    ),
                    child: const Text('清空'),
                  ),
              ],
            ),
          ),
          if (files.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
              child: Text(
                Platform.isIOS
                    ? '先选文件,再点下面的设备发送'
                    : '先选文件或文件夹(也可直接拖进窗口),再点下面的设备发送',
                style: const TextStyle(
                    fontSize: 12.5, color: AppColors.subtextLight),
              ),
            )
          else ...[
            // 文件多时只列前 4 个,其余折叠成一行说明
            for (final f in files.take(4))
              SettingRow(
                icon: FileTypeIcon.iconFor(f.ext),
                iconColor: AppColors.forExtension(f.ext),
                title: f.relativePath ?? f.name,
                subtitle: formatBytes(f.size),
                trailing: IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(SolarIcons.close,
                      size: 22, color: AppColors.subtextLight),
                  onPressed: () => app.removeFromOutbox(f.id),
                ),
              ),
            if (files.length > 4)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                child: Text('还有 ${files.length - 4} 个文件…',
                    style: const TextStyle(
                        fontSize: 12.5, color: AppColors.subtextLight)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 4),
              child: Row(
                children: [
                  const Icon(SolarIcons.archive,
                      size: 17, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text('${files.length} 个文件 · ${formatBytes(app.outboxBytes)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ],
              ),
            ),
          ],
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: _PickButton(
                    icon: SolarIcons.file,
                    label: '选择文件',
                    onTap: () async {
                      final items = await FileService.pickFiles();
                      if (!context.mounted || items.isEmpty) return;
                      app.addToOutbox(items);
                    },
                  ),
                ),
                if (canPickFolder) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: _PickButton(
                      icon: SolarIcons.folder,
                      label: '选择文件夹',
                      onTap: () async {
                        final items = await FileService.pickFolder();
                        if (!context.mounted) return;
                        if (items.isEmpty) {
                          showToast(context, '这个文件夹里没有文件');
                          return;
                        }
                        app.addToOutbox(items);
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PickButton extends StatelessWidget {
  const _PickButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: dark ? const Color(0xFF22262D) : const Color(0xFFF4F6F9),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(label,
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- 设备列表

class _DeviceListHeader extends StatelessWidget {
  const _DeviceListHeader();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 20, 6),
      child: Row(
        children: [
          const Text('附近的设备',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.subtextLight)),
          const SizedBox(width: 8),
          if (app.scanning)
            const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2)),
          const Spacer(),
          _HeaderAction(
            icon: SolarIcons.scan,
            label: '扫描网段',
            onTap: app.scanning
                ? null
                : () async {
                    final n = await app.scanSubnet();
                    if (context.mounted) {
                      showToast(context, n > 0 ? '扫描到 $n 台设备' : '网段里没找到其他设备');
                    }
                  },
          ),
          const SizedBox(width: 4),
          _HeaderAction(
            icon: SolarIcons.add,
            label: '按 IP 添加',
            onTap: () => _showAddDialog(context, app),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog(BuildContext context, AppState app) async {
    final ip = await showTextPrompt(
      context,
      title: '按 IP 添加设备',
      hint: '例如 192.168.1.23',
      confirmText: '连接',
    );
    if (ip == null || ip.isEmpty || !context.mounted) return;
    final err = await app.addManualDevice(ip);
    if (!context.mounted) return;
    showToast(context, err ?? '已添加设备', error: err != null);
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            children: [
              Icon(icon,
                  size: 18,
                  color: onTap == null
                      ? AppColors.subtextLight.withValues(alpha: 0.5)
                      : AppColors.primary),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: onTap == null
                        ? AppColors.subtextLight.withValues(alpha: 0.5)
                        : AppColors.primary,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceList extends StatelessWidget {
  const _DeviceList();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final devices = app.visibleDevices;
    if (devices.isEmpty) return const _EmptyDevices();

    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < devices.length; i++)
            _DeviceRow(
              device: devices[i],
              showDivider: i != devices.length - 1,
            ),
        ],
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.showDivider});

  final Device device;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final online = app.isOnline(device);
    final fav = app.favorites.contains(device.fingerprint);
    final hasFiles = app.outbox.isNotEmpty;

    return SettingRow(
      showDivider: showDivider,
      icon: DeviceIcon.iconFor(device.deviceType),
      iconColor: online
          ? DeviceIcon.colorFor(device.deviceType)
          : AppColors.subtextLight,
      title: device.alias,
      subtitle: online
          ? '${device.ip}${device.model != null ? " · ${device.model}" : ""}'
          : '离线 · ${device.ip}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: fav ? '取消收藏' : '收藏',
            icon: Icon(fav ? SolarIcons.starOn : SolarIcons.starOff,
                size: 21,
                color: fav ? AppColors.orange : AppColors.subtextLight),
            onPressed: () => app.toggleFavorite(device.fingerprint),
          ),
          Icon(
            hasFiles ? SolarIcons.send : SolarIcons.chevronRight,
            size: hasFiles ? 24 : 20,
            color: hasFiles ? AppColors.primary : AppColors.subtextLight,
          ),
        ],
      ),
      onTap: () => _onTap(context, app),
    );
  }

  Future<void> _onTap(BuildContext context, AppState app) async {
    if (app.outbox.isEmpty) {
      // 没选文件时,点设备等于「选文件后发给它」
      final items = await FileService.pickFiles();
      if (!context.mounted || items.isEmpty) return;
      app.addToOutbox(items);
      if (!context.mounted) return;
    }
    if (!app.isOnline(device)) {
      // 手动添加的设备可能已经离线,先探一次再决定
      final err = await app.addManualDevice(device.ip, port: device.port);
      if (!context.mounted) return;
      if (err != null) {
        showToast(context, '${device.alias} 当前不在线', error: true);
        return;
      }
    }
    if (!context.mounted) return;
    final err = await app.sendOutboxTo(device);
    if (!context.mounted) return;
    if (err != null) showToast(context, err, error: true);
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 26),
      child: Column(
        children: [
          TintedIcon(SolarIcons.router, color: AppColors.primary, size: 54),
          const SizedBox(height: 14),
          const Text('还没发现其他设备',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          const Text(
            '确认两台设备连在同一个 Wi-Fi 或局域网,\n并且都打开了这个 App。',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, height: 1.6, color: AppColors.subtextLight),
          ),
          if (!app.udpWorking) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(SolarIcons.info, size: 17, color: AppColors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '自动广播暂无回应。部分网络会拦截组播,'
                      '可用上方「扫描网段」或「按 IP 添加」。',
                      style: TextStyle(
                          fontSize: 12, height: 1.5, color: AppColors.orange),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: 200,
            child: FilledButton(
              onPressed: app.scanning
                  ? null
                  : () async {
                      final n = await app.scanSubnet();
                      if (context.mounted) {
                        showToast(
                            context, n > 0 ? '扫描到 $n 台设备' : '网段里没找到其他设备');
                      }
                    },
              child: Text(app.scanning ? '扫描中…' : '扫描局域网'),
            ),
          ),
        ],
      ),
    );
  }
}
