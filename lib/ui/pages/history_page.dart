import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/transfer.dart';
import '../../state/app_state.dart';
import '../../utils/formats.dart';
import '../file_icon.dart';
import '../solar_icons.dart';
import '../theme.dart';
import '../widgets.dart';
import 'transfer_sheet.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final active = app.active;
    final history = app.history;

    return Scaffold(
      appBar: AppBar(
        title: const Text('传输记录'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              tooltip: '清空记录',
              icon: const Icon(SolarIcons.trash),
              onPressed: () => _confirmClear(context, app),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        bottom: false,
        child: (active.isEmpty && history.isEmpty)
            ? const _EmptyHistory()
            : ListView(
                padding: const EdgeInsets.only(top: 8, bottom: 24),
                children: [
                  if (active.isNotEmpty) ...[
                    const _SectionLabel('进行中'),
                    AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (var i = 0; i < active.length; i++)
                            _ActiveRow(
                              task: active[i],
                              showDivider: i != active.length - 1,
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (history.isNotEmpty) ...[
                    const _SectionLabel('已完成'),
                    AppCard(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: [
                          for (var i = 0; i < history.length; i++)
                            _HistoryRow(
                              task: history[i],
                              showDivider: i != history.length - 1,
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空传输记录?'),
        content: const Text('只删除记录列表,已经收到的文件不会被删除。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消',
                  style: TextStyle(color: AppColors.subtextLight))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空',
                style: TextStyle(
                    color: AppColors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (ok == true) app.clearHistory();
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 12, 20, 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.subtextLight)),
      );
}

// ---------------------------------------------------------------- 进行中的行

class _ActiveRow extends StatelessWidget {
  const _ActiveRow({required this.task, required this.showDivider});

  final TransferTask task;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final sending = task.direction == TransferDirection.send;
    final current = task.files
        .where((f) => f.id == task.currentFileId)
        .firstOrNull;
    final waiting = task.status == TransferStatus.waiting;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
          child: Column(
            children: [
              Row(
                children: [
                  TintedIcon(
                    sending ? SolarIcons.send : SolarIcons.receive,
                    color: sending ? AppColors.primary : AppColors.green,
                    size: 38,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${sending ? "发送给" : "接收自"} ${task.device.alias}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          waiting
                              ? '等待对方确认…'
                              : '${current?.name ?? "准备中"} · '
                                  '${task.doneCount}/${task.files.length}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12.5, color: AppColors.subtextLight),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '取消',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(SolarIcons.close,
                        size: 24, color: AppColors.subtextLight),
                    onPressed: () => app.cancelTask(task),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: waiting ? null : task.fraction,
                  minHeight: 6,
                  backgroundColor: Theme.of(context).brightness ==
                          Brightness.dark
                      ? const Color(0xFF2A2F37)
                      : const Color(0xFFE9EDF3),
                  valueColor: AlwaysStoppedAnimation(
                      sending ? AppColors.primary : AppColors.green),
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Text(
                    '${formatBytes(task.transferredBytes)} / '
                    '${formatBytes(task.totalBytes)}',
                    style: const TextStyle(
                        fontSize: 11.5, color: AppColors.subtextLight),
                  ),
                  const Spacer(),
                  if (!waiting) ...[
                    Text(formatSpeed(task.bytesPerSecond),
                        style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                    const SizedBox(width: 10),
                    Text(formatEta(task.etaSeconds),
                        style: const TextStyle(
                            fontSize: 11.5, color: AppColors.subtextLight)),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(),
      ],
    );
  }
}

// -------------------------------------------------------------- 已完成的行

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.task, required this.showDivider});

  final TransferTask task;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final sending = task.direction == TransferDirection.send;
    final (statusColor, statusIcon) = switch (task.status) {
      TransferStatus.done => (AppColors.green, SolarIcons.check),
      TransferStatus.failed => (AppColors.red, SolarIcons.warn),
      TransferStatus.rejected => (AppColors.orange, SolarIcons.block),
      TransferStatus.canceled => (AppColors.subtextLight, SolarIcons.close),
      _ => (AppColors.subtextLight, SolarIcons.clock),
    };

    final firstFile = task.files.firstOrNull;
    final title = task.files.length == 1
        ? (firstFile?.name ?? '未知文件')
        : '${task.files.length} 个文件';

    return SettingRow(
      showDivider: showDivider,
      icon: task.files.length == 1 && firstFile != null
          ? FileTypeIcon.iconFor(firstFile.ext)
          : SolarIcons.archive,
      iconColor: task.files.length == 1 && firstFile != null
          ? AppColors.forExtension(firstFile.ext)
          : (sending ? AppColors.primary : AppColors.green),
      title: title,
      subtitle: '${sending ? "发给" : "来自"} ${task.device.alias} · '
          '${formatBytes(task.totalBytes)} · '
          '${formatWhen(task.finishedAt ?? task.startedAt)}',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 18, color: statusColor),
          const SizedBox(width: 5),
          Text(task.status.label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: statusColor)),
          const SizedBox(width: 2),
          const Icon(SolarIcons.chevronRight,
              size: 19, color: AppColors.subtextLight),
        ],
      ),
      onTap: () => showTransferSheet(context, task),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TintedIcon(SolarIcons.transfer,
                  color: AppColors.subtextLight, size: 56),
              const SizedBox(height: 16),
              const Text('还没有传输记录',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              const Text('发送或接收文件后,这里会留下记录。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      height: 1.6,
                      color: AppColors.subtextLight)),
            ],
          ),
        ),
      );
}
