import 'package:flutter/material.dart';

import '../models/device.dart';
import 'solar_icons.dart';
import 'theme.dart';
import 'widgets.dart';

/// 按扩展名给出图标 + 底色
class FileTypeIcon extends StatelessWidget {
  const FileTypeIcon({super.key, required this.ext, this.size = 38});

  final String ext;
  final double size;

  @override
  Widget build(BuildContext context) => TintedIcon(
        iconFor(ext),
        color: AppColors.forExtension(ext),
        size: size,
      );

  static IconData iconFor(String ext) => switch (ext.toLowerCase()) {
        'jpg' || 'jpeg' || 'png' || 'gif' || 'webp' || 'heic' || 'bmp' ||
        'tiff' || 'svg' =>
          SolarIcons.fileImage,
        'mp4' || 'mov' || 'mkv' || 'avi' || 'webm' || 'flv' || 'm4v' =>
          SolarIcons.fileVideo,
        'mp3' || 'wav' || 'flac' || 'aac' || 'm4a' || 'ogg' =>
          SolarIcons.fileAudio,
        'zip' || 'rar' || '7z' || 'tar' || 'gz' || 'bz2' || 'xz' =>
          SolarIcons.fileZip,
        'pdf' || 'doc' || 'docx' || 'txt' || 'md' || 'rtf' || 'pages' ||
        'xls' || 'xlsx' || 'csv' || 'ppt' || 'pptx' =>
          SolarIcons.fileText,
        _ => SolarIcons.file,
      };
}

/// 设备类型图标
class DeviceIcon extends StatelessWidget {
  const DeviceIcon({
    super.key,
    required this.type,
    this.size = 44,
    this.color,
  });

  final DeviceType type;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => TintedIcon(
        iconFor(type),
        color: color ?? colorFor(type),
        size: size,
      );

  static IconData iconFor(DeviceType t) => switch (t) {
        DeviceType.desktop => SolarIcons.desktop,
        DeviceType.laptop => SolarIcons.laptop,
        DeviceType.phone => SolarIcons.phone,
        DeviceType.tablet => SolarIcons.tablet,
        DeviceType.unknown => SolarIcons.unknownDevice,
      };

  static Color colorFor(DeviceType t) => switch (t) {
        DeviceType.desktop => AppColors.indigo,
        DeviceType.laptop => AppColors.primary,
        DeviceType.phone => AppColors.teal,
        DeviceType.tablet => AppColors.purple,
        DeviceType.unknown => AppColors.subtextLight,
      };
}
