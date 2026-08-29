import 'package:flutter/material.dart';

/// Para 风格:极浅蓝灰背景、大圆角白卡、蓝色强调、彩色小图标
class AppColors {
  static const primary = Color(0xFF2F7CF6);
  static const primaryDark = Color(0xFF1B5FD9);

  // 浅色
  static const bgLight = Color(0xFFF2F5F9);
  static const cardLight = Colors.white;
  static const textLight = Color(0xFF17181C);
  static const subtextLight = Color(0xFF8A919E);
  static const dividerLight = Color(0xFFF0F2F5);

  // 深色
  static const bgDark = Color(0xFF0F1115);
  static const cardDark = Color(0xFF1A1D23);
  static const textDark = Color(0xFFF2F3F5);
  static const subtextDark = Color(0xFF8A919E);
  static const dividerDark = Color(0xFF262A31);

  static const green = Color(0xFF34C759);
  static const orange = Color(0xFFFF9F0A);
  static const red = Color(0xFFFF453A);
  static const teal = Color(0xFF32ADE6);
  static const purple = Color(0xFF5E5CE6);
  static const pink = Color(0xFFFF2D55);
  static const indigo = Color(0xFF4B4DED);

  /// 按文件扩展名给出图标底色,列表里一眼分清类型
  static Color forExtension(String ext) => switch (ext.toLowerCase()) {
        'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' || 'bmp' ||
        'tiff' || 'svg' =>
          green,
        'mp4' || 'mov' || 'mkv' || 'avi' || 'webm' || 'flv' || 'm4v' => purple,
        'mp3' || 'wav' || 'flac' || 'aac' || 'm4a' || 'ogg' => pink,
        'zip' || 'rar' || '7z' || 'tar' || 'gz' || 'bz2' || 'xz' => orange,
        'pdf' => red,
        'doc' || 'docx' || 'txt' || 'md' || 'rtf' || 'pages' => teal,
        'xls' || 'xlsx' || 'csv' || 'numbers' => green,
        'ppt' || 'pptx' || 'key' => orange,
        'dart' || 'py' || 'js' || 'ts' || 'go' || 'rs' || 'java' || 'c' ||
        'cpp' || 'h' || 'swift' || 'kt' || 'json' || 'yaml' || 'yml' ||
        'xml' || 'html' || 'css' || 'sh' =>
          indigo,
        'app' || 'dmg' || 'exe' || 'msi' || 'apk' || 'ipa' || 'deb' => primary,
        _ => subtextLight,
      };
}

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bg = dark ? AppColors.bgDark : AppColors.bgLight;
  final card = dark ? AppColors.cardDark : AppColors.cardLight;
  final text = dark ? AppColors.textDark : AppColors.textLight;

  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: brightness,
    primary: AppColors.primary,
    surface: card,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    fontFamilyFallback: const ['PingFang SC', 'Microsoft YaHei', 'Noto Sans SC'],
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: text,
        fontSize: 28,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    dividerTheme: DividerThemeData(
      color: dark ? AppColors.dividerDark : AppColors.dividerLight,
      thickness: 1,
      space: 1,
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? AppColors.primary
              : (dark ? const Color(0xFF3A3F47) : const Color(0xFFD3D8E0))),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      // 关闭态给轨道一圈描边,浅灰滑块在白卡上也能看清边界
      trackOutlineColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? Colors.transparent
              : (dark ? const Color(0xFF4A505A) : const Color(0xFFC2C8D2))),
      trackOutlineWidth: const WidgetStatePropertyAll(1),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: TextStyle(
        color: text,
        fontSize: 19,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: TextStyle(
        color: dark ? AppColors.subtextDark : const Color(0xFF4A5057),
        fontSize: 14.5,
        height: 1.55,
      ),
    ),
    // 下拉菜单(订阅操作等)与全局风格一致:大圆角、柔和阴影、无 tint
    popupMenuTheme: PopupMenuThemeData(
      color: card,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: dark ? 0.5 : 0.14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
      textStyle: TextStyle(
        color: text,
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF272B33) : const Color(0xFF23262B),
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF33373E) : const Color(0xFF23262B),
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF22262D) : const Color(0xFFF4F6F9),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      hintStyle: const TextStyle(color: AppColors.subtextLight, fontSize: 15),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      indicatorColor: Colors.transparent,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            size: 26,
            color: states.contains(WidgetState.selected)
                ? text
                : (dark ? const Color(0xFF5A6069) : const Color(0xFFB9BfC9)),
          )),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? text
                : (dark ? const Color(0xFF5A6069) : const Color(0xFFB9BFC9)),
          )),
    ),
  );
}
