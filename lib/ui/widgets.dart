import 'package:flutter/material.dart';

import 'solar_icons.dart';
import 'theme.dart';

/// Para 风格白色圆角卡片
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: padding,
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    );
  }
}

/// 彩色圆角小图标(Para 设置页样式)
class TintedIcon extends StatelessWidget {
  const TintedIcon(this.icon, {super.key, required this.color, this.size = 38});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.95), color.withValues(alpha: 0.75)],
        ),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.55),
    );
  }
}

/// 卡片内的一行设置项:图标 + 标题 + 尾部
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.icon,
    this.iconColor,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  final String title;
  final IconData? icon;
  final Color? iconColor;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          if (icon != null) ...[
            TintedIcon(icon!, color: iconColor ?? AppColors.primary, size: 34),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: theme.brightness == Brightness.dark
                              ? AppColors.subtextDark
                              : AppColors.subtextLight)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        onTap == null
            ? row
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(20),
                child: row,
              ),
        if (showDivider)
          const Padding(
            padding: EdgeInsets.only(left: 66),
            child: Divider(),
          ),
      ],
    );
  }
}

/// 尾部「值 + >」样式
class ChevronValue extends StatelessWidget {
  const ChevronValue(this.value, {super.key});

  final String value;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = dark ? AppColors.subtextDark : AppColors.subtextLight;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: TextStyle(fontSize: 14.5, color: color)),
        const SizedBox(width: 2),
        Icon(SolarIcons.chevronRight, size: 20, color: color),
      ],
    );
  }
}

/// 底部弹窗容器:顶部把手 + 内容(顶部把手 + 圆角)
Future<T?> showAppSheet<T>(BuildContext context, {required Widget child}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            decoration: BoxDecoration(
              color: Theme.of(ctx).brightness == Brightness.dark
                  ? const Color(0xFF33373E)
                  : const Color(0xFFE1E4E9),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Flexible(child: child),
        ],
      ),
    ),
  );
}

/// 通用输入对话框
Future<String?> showTextPrompt(
  BuildContext context, {
  required String title,
  String? hint,
  String? initial,
  String confirmText = '确定',
  int maxLines = 1,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: maxLines,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消',
                style: TextStyle(color: AppColors.subtextLight))),
        TextButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          child: Text(confirmText,
              style: const TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

/// 顶部轻提示(成功/失败带 Solar 图标)
void showToast(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(
      content: Row(
        children: [
          Icon(error ? SolarIcons.close : SolarIcons.check,
              size: 19, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      behavior: SnackBarBehavior.floating,
      backgroundColor: error ? AppColors.red : const Color(0xFF2B2F36),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      duration: const Duration(seconds: 2),
    ));
}
