import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../utils/formats.dart';
import 'file_icon.dart';
import 'solar_icons.dart';
import 'theme.dart';
import 'widgets.dart';

/// 监听待确认的接收请求,弹出确认卡片。
///
/// 包在整个 App 外层,任何页面在前台都能弹出。
class ReceiveGate extends StatefulWidget {
  const ReceiveGate({super.key, required this.child});

  final Widget child;

  @override
  State<ReceiveGate> createState() => _ReceiveGateState();
}

class _ReceiveGateState extends State<ReceiveGate> {
  /// 正在展示弹窗的请求,避免同一请求反复弹
  PendingApproval? _showing;

  @override
  void initState() {
    super.initState();
    // 首帧之后再挂监听,initState 里 context 还不能用 read
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      app.addListener(_check);
      _check();
    });
  }

  @override
  void dispose() {
    // read 在 dispose 阶段仍可用于取消监听
    context.read<AppState>().removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (!mounted || _showing != null) return;
    final app = context.read<AppState>();
    final next = app.pendingApprovals.where((p) => !p.settled).firstOrNull;
    if (next == null) return;
    _showing = next;
    showAppSheet<void>(
      context,
      child: _ApprovalSheet(pending: next),
    ).whenComplete(() {
      // 用户滑掉弹窗等于拒绝
      app.resolveApproval(next, false);
      _showing = null;
      // 队列里可能还有下一个请求
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ApprovalSheet extends StatelessWidget {
  const _ApprovalSheet({required this.pending});

  final PendingApproval pending;

  @override
  Widget build(BuildContext context) {
    final task = pending.task;
    final app = context.read<AppState>();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final sub = dark ? AppColors.subtextDark : AppColors.subtextLight;
    final total = task.totalBytes;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TintedIcon(SolarIcons.receive,
                    color: AppColors.primary, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.device.alias,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('想发给你 ${task.files.length} 个文件 · ${formatBytes(total)}',
                          style: TextStyle(fontSize: 13, color: sub)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 文件清单:超过 5 个就滚动,不把弹窗顶到屏幕外
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.34,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF22262D)
                      : const Color(0xFFF4F6F9),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: task.files.length,
                  separatorBuilder: (_, _) => const Padding(
                    padding: EdgeInsets.only(left: 56),
                    child: Divider(height: 1),
                  ),
                  itemBuilder: (_, i) {
                    final f = task.files[i];
                    return Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: Row(
                        children: [
                          FileTypeIcon(ext: f.ext, size: 32),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(f.relativePath ?? f.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w500)),
                                Text(formatBytes(f.size),
                                    style:
                                        TextStyle(fontSize: 12, color: sub)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('保存到 ${app.saveDirResolved ?? "默认目录"}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: sub)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      app.resolveApproval(pending, false);
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
                    child: const Text('拒绝',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: () {
                      app.resolveApproval(pending, true);
                      Navigator.of(context).maybePop();
                    },
                    child: const Text('接收'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
