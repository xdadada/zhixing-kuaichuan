import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/transfer.dart';
import '../../services/file_service.dart';
import '../../state/app_state.dart';
import '../../utils/formats.dart';
import '../file_icon.dart';
import '../solar_icons.dart';
import '../theme.dart';
import '../widgets.dart';

/// 传输详情:文件清单 + 每个文件的结果,接收的文件可定位到访达
Future<void> showTransferSheet(BuildContext context, TransferTask task) =>
    showAppSheet<void>(context, child: _TransferSheet(task: task));

class _TransferSheet extends StatelessWidget {
  const _TransferSheet({required this.task});

  final TransferTask task;

  bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sub = dark ? AppColors.subtextDark : AppColors.subtextLight;
    final sending = task.direction == TransferDirection.send;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TintedIcon(
                  sending ? SolarIcons.send : SolarIcons.receive,
                  color: sending ? AppColors.primary : AppColors.green,
                  size: 44,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${sending ? "发送给" : "接收自"} ${task.device.alias}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 17.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '${task.status.label} · ${task.files.length} 个文件 · '
                        '${formatBytes(task.totalBytes)}',
                        style: TextStyle(fontSize: 12.5, color: sub),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (task.error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(SolarIcons.warn,
                        size: 17, color: AppColors.red),
                    const SizedBox(width: 9),
                    Expanded(
                      child: SelectableText(task.error!,
                          style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.5,
                              color: AppColors.red)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text('文件清单',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600, color: sub)),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.42,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color:
                      dark ? const Color(0xFF22262D) : const Color(0xFFF4F6F9),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  itemCount: task.files.length,
                  separatorBuilder: (_, _) => const Padding(
                    padding: EdgeInsets.only(left: 56),
                    child: Divider(height: 1),
                  ),
                  itemBuilder: (_, i) => _FileRow(
                    task: task,
                    item: task.files[i],
                    canReveal: !sending && _isDesktop,
                    sub: sub,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (!sending && task.savedPaths.isNotEmpty) ...[
              _MetaRow(
                icon: SolarIcons.folder,
                label: '保存位置',
                value: _dirOf(task.savedPaths.values.first),
                sub: sub,
                onCopy: true,
              ),
              const SizedBox(height: 6),
            ],
            _MetaRow(
              icon: SolarIcons.clock,
              label: '开始时间',
              value: '${formatWhen(task.startedAt)} '
                  '${formatTime(task.startedAt)}',
              sub: sub,
            ),
            if (task.finishedAt != null) ...[
              const SizedBox(height: 6),
              _MetaRow(
                icon: SolarIcons.timer,
                label: '耗时',
                value: formatDuration(
                    task.finishedAt!.difference(task.startedAt)),
                sub: sub,
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                if (!sending &&
                    _isDesktop &&
                    task.savedPaths.isNotEmpty) ...[
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          FileService.openDir(_dirOf(task.savedPaths.values.first)),
                      child: const Text('打开文件夹'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      context.read<AppState>().removeHistory(task.id);
                      Navigator.of(context).maybePop();
                    },
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      foregroundColor: sub,
                      side: BorderSide(
                          color: dark
                              ? const Color(0xFF3A3F47)
                              : const Color(0xFFD9DEE6)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    child: const Text('删除记录',
                        style: TextStyle(
                            fontSize: 15.5, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _dirOf(String p) {
    final norm = p.replaceAll('\\', '/');
    final cut = norm.lastIndexOf('/');
    if (cut <= 0) return norm;
    final dir = norm.substring(0, cut);
    return Platform.isWindows ? dir.replaceAll('/', '\\') : dir;
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.task,
    required this.item,
    required this.canReveal,
    required this.sub,
  });

  final TransferTask task;
  final FileItem item;
  final bool canReveal;
  final Color sub;

  @override
  Widget build(BuildContext context) {
    final saved = task.savedPaths[item.id];
    final sent = task.progress[item.id] ?? 0;
    final complete = item.size > 0 ? sent >= item.size : saved != null;

    return InkWell(
      onTap: canReveal && saved != null
          ? () => FileService.revealInFolder(saved)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            FileTypeIcon(ext: item.ext, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.relativePath ?? item.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 1),
                  Text(
                    complete
                        ? formatBytes(item.size)
                        : '${formatBytes(sent)} / ${formatBytes(item.size)}',
                    style: TextStyle(fontSize: 11.5, color: sub),
                  ),
                ],
              ),
            ),
            if (complete)
              const Icon(SolarIcons.check, size: 18, color: AppColors.green)
            else if (task.status.isFinished)
              const Icon(SolarIcons.close, size: 18, color: AppColors.red),
            if (canReveal && saved != null) ...[
              const SizedBox(width: 6),
              Icon(SolarIcons.chevronRight, size: 18, color: sub),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    this.onCopy = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color sub;
  final bool onCopy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: sub),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12.5, color: sub)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w500)),
        ),
        if (onCopy)
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.only(left: 6),
            constraints: const BoxConstraints(),
            tooltip: '复制路径',
            icon: Icon(SolarIcons.copy, size: 16, color: sub),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: value));
              showToast(context, '路径已复制');
            },
          ),
      ],
    );
  }
}
