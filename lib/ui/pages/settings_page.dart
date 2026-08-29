import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/settings.dart';
import '../../services/file_service.dart';
import '../../state/app_state.dart';
import '../solar_icons.dart';
import '../theme.dart';
import '../widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 32),
          children: [
            // ------------------------------------------------------ 本机
            const _Label('本机'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SettingRow(
                    icon: SolarIcons.thisDevice,
                    iconColor: AppColors.primary,
                    title: '设备名称',
                    subtitle: '别人在列表里看到的名字',
                    trailing: ChevronValue(s.alias),
                    onTap: () async {
                      final v = await showTextPrompt(
                        context,
                        title: '设备名称',
                        initial: s.alias,
                        hint: '例如 我的 MacBook',
                      );
                      if (v != null && v.isNotEmpty) app.setAlias(v);
                    },
                  ),
                  SettingRow(
                    icon: SolarIcons.eye,
                    iconColor: AppColors.teal,
                    title: '允许被发现',
                    subtitle: '关闭后别人搜不到你,你仍能主动发给别人',
                    trailing: Switch(
                      value: s.discoverable,
                      onChanged: app.setDiscoverable,
                    ),
                  ),
                  SettingRow(
                    icon: SolarIcons.globe,
                    iconColor: AppColors.indigo,
                    title: '本机地址',
                    subtitle: app.serverRunning
                        ? '接收服务正常运行'
                        : (app.serverError ?? '接收服务未运行'),
                    showDivider: false,
                    trailing: _CopyValue(
                        value: '${app.localIp ?? "未联网"}:${s.port}'),
                  ),
                ],
              ),
            ),

            // ------------------------------------------------------ 接收
            const _Label('接收'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SettingRow(
                    icon: SolarIcons.shield,
                    iconColor: AppColors.green,
                    title: '接收方式',
                    subtitle: switch (s.receiveMode) {
                      ReceiveMode.ask => '每次都弹窗让你确认',
                      ReceiveMode.auto => '任何设备发来都直接接收',
                      ReceiveMode.favoritesOnly => '收藏设备直接收,其余询问',
                    },
                    trailing: ChevronValue(s.receiveMode.label),
                    onTap: () => _pickReceiveMode(context, app),
                  ),
                  SettingRow(
                    icon: SolarIcons.folderFiles,
                    iconColor: AppColors.orange,
                    title: '保存位置',
                    subtitle: app.saveDirResolved ?? '默认下载目录',
                    trailing: _isDesktop
                        ? const Icon(SolarIcons.chevronRight,
                            size: 20, color: AppColors.subtextLight)
                        : _CopyValue(value: app.saveDirResolved ?? '-'),
                    onTap: _isDesktop
                        ? () async {
                            final dir = await FileService.pickSaveDir();
                            if (dir == null || !context.mounted) return;
                            final ok = await FileService.ensureDir(dir);
                            if (!context.mounted) return;
                            if (!ok) {
                              showToast(context, '这个目录不可写', error: true);
                              return;
                            }
                            await app.setSaveDir(dir);
                            if (context.mounted) showToast(context, '保存位置已更新');
                          }
                        : null,
                  ),
                  SettingRow(
                    icon: SolarIcons.copy,
                    iconColor: AppColors.purple,
                    title: '同名文件覆盖',
                    subtitle: s.overwriteExisting
                        ? '直接覆盖已有文件'
                        : '自动改名为 文件(1).txt',
                    trailing: Switch(
                      value: s.overwriteExisting,
                      onChanged: app.setOverwrite,
                    ),
                    showDivider: _isDesktop,
                  ),
                  if (_isDesktop)
                    SettingRow(
                      icon: SolarIcons.folder,
                      iconColor: AppColors.teal,
                      title: '收完自动打开文件夹',
                      trailing: Switch(
                        value: s.autoOpenOnDone,
                        onChanged: app.setAutoOpen,
                      ),
                      showDivider: false,
                    ),
                ],
              ),
            ),

            // ------------------------------------------------------ 外观
            const _Label('外观'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SettingRow(
                    icon: SolarIcons.darkMode,
                    iconColor: AppColors.indigo,
                    title: '主题',
                    showDivider: false,
                    trailing: ChevronValue(switch (s.themeMode) {
                      AppThemeMode.system => '跟随系统',
                      AppThemeMode.light => '浅色',
                      AppThemeMode.dark => '深色',
                    }),
                    onTap: () => _pickTheme(context, app),
                  ),
                ],
              ),
            ),

            // ------------------------------------------------------ 网络
            const _Label('网络'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SettingRow(
                    icon: SolarIcons.port,
                    iconColor: AppColors.primary,
                    title: '传输端口',
                    subtitle: '改动后会重启接收服务',
                    trailing: ChevronValue('${s.port}'),
                    onTap: () async {
                      final v = await showTextPrompt(
                        context,
                        title: '传输端口',
                        initial: '${s.port}',
                        hint: '1024–65535',
                      );
                      if (v == null || !context.mounted) return;
                      final p = int.tryParse(v.trim());
                      if (p == null) {
                        showToast(context, '请输入数字', error: true);
                        return;
                      }
                      final err = await app.setPort(p);
                      if (!context.mounted) return;
                      showToast(context, err ?? '端口已改为 $p', error: err != null);
                    },
                  ),
                  SettingRow(
                    icon: SolarIcons.router,
                    iconColor: AppColors.teal,
                    title: '发现方式',
                    subtitle: app.udpWorking
                        ? 'UDP 组播正常(${s.multicastGroup}:${s.discoveryPort})'
                        : '尚未收到组播回应,可在设备页用扫描兜底',
                    trailing: Icon(
                      app.udpWorking ? SolarIcons.check : SolarIcons.info,
                      size: 21,
                      color: app.udpWorking
                          ? AppColors.green
                          : AppColors.orange,
                    ),
                  ),
                  SettingRow(
                    icon: SolarIcons.sync,
                    iconColor: AppColors.green,
                    title: '重启网络服务',
                    subtitle: '换 Wi-Fi 或搜不到设备时试试',
                    showDivider: false,
                    trailing: const Icon(SolarIcons.chevronRight,
                        size: 20, color: AppColors.subtextLight),
                    onTap: () async {
                      await app.restartNetworking();
                      if (context.mounted) showToast(context, '网络服务已重启');
                    },
                  ),
                ],
              ),
            ),

            // ------------------------------------------------------ 关于
            const _Label('关于'),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  SettingRow(
                    icon: SolarIcons.info,
                    iconColor: AppColors.subtextLight,
                    title: '知行快传',
                    subtitle: '局域网点对点传输,文件不经过任何服务器',
                    showDivider: false,
                    trailing: const Text('1.0.0',
                        style: TextStyle(
                            fontSize: 14, color: AppColors.subtextLight)),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(28, 14, 28, 0),
              child: Text(
                '传输在局域网内直连完成,内容不上传云端。'
                '注意:同一局域网内的设备都能向你发起传输请求,'
                '在公共 Wi-Fi 下建议把「接收方式」设为每次询问。',
                style: TextStyle(
                    fontSize: 11.5, height: 1.6, color: AppColors.subtextLight),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickReceiveMode(BuildContext context, AppState app) async {
    await showAppSheet<void>(
      context,
      child: _OptionSheet<ReceiveMode>(
        title: '接收方式',
        current: app.settings.receiveMode,
        options: {
          ReceiveMode.ask: ('每次询问', '最安全,每批文件都要你点确认'),
          ReceiveMode.favoritesOnly: ('仅收藏设备自动', '自己的设备免确认,陌生设备仍询问'),
          ReceiveMode.auto: ('全部自动接收', '方便但风险高,公共网络别开'),
        },
        onPick: app.setReceiveMode,
      ),
    );
  }

  Future<void> _pickTheme(BuildContext context, AppState app) async {
    await showAppSheet<void>(
      context,
      child: _OptionSheet<AppThemeMode>(
        title: '主题',
        current: app.settings.themeMode,
        options: const {
          AppThemeMode.system: ('跟随系统', null),
          AppThemeMode.light: ('浅色', null),
          AppThemeMode.dark: ('深色', null),
        },
        onPick: app.setThemeMode,
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 14, 20, 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.subtextLight)),
      );
}

class _CopyValue extends StatelessWidget {
  const _CopyValue({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          showToast(context, '已复制 $value');
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(value,
                  style: const TextStyle(
                      fontSize: 13.5, color: AppColors.subtextLight)),
              const SizedBox(width: 5),
              const Icon(SolarIcons.copy,
                  size: 16, color: AppColors.subtextLight),
            ],
          ),
        ),
      );
}

/// 通用单选弹窗
class _OptionSheet<T> extends StatelessWidget {
  const _OptionSheet({
    required this.title,
    required this.current,
    required this.options,
    required this.onPick,
  });

  final String title;
  final T current;

  /// value -> (标题, 说明)
  final Map<T, (String, String?)> options;
  final void Function(T) onPick;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            for (final e in options.entries)
              SettingRow(
                title: e.value.$1,
                subtitle: e.value.$2,
                showDivider: e.key != options.keys.last,
                trailing: Icon(
                  e.key == current ? SolarIcons.check : null,
                  size: 23,
                  color: AppColors.primary,
                ),
                onTap: () {
                  onPick(e.key);
                  Navigator.of(context).maybePop();
                },
              ),
          ],
        ),
      ),
    );
  }
}
