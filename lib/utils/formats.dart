/// 字节数 -> 人类可读("1.2 MB")。用 1024 进制。
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes < 0) return '0 B';
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB', 'PB'];
  var value = bytes / 1024;
  var i = 0;
  while (value >= 1024 && i < units.length - 1) {
    value /= 1024;
    i++;
  }
  // 大于 100 时小数点没意义,省掉更整齐
  final d = value >= 100 ? 0 : decimals;
  return '${value.toStringAsFixed(d)} ${units[i]}';
}

/// 速度 -> "3.4 MB/s"
String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0) return '0 B/s';
  return '${formatBytes(bytesPerSecond.round())}/s';
}

/// 秒数 -> "1:05" / "12:03:45"
String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  final mm = m.toString().padLeft(2, '0');
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$m:$ss';
}

/// 剩余时间 -> "约 12 秒" / "约 3 分钟"
String formatEta(int? seconds) {
  if (seconds == null) return '计算中';
  if (seconds <= 0) return '即将完成';
  if (seconds < 60) return '约 $seconds 秒';
  if (seconds < 3600) return '约 ${(seconds / 60).ceil()} 分钟';
  return '约 ${(seconds / 3600).toStringAsFixed(1)} 小时';
}

/// 时间戳 -> "14:05"
String formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// 历史列表用的相对时间:今天显示时刻,昨天/更早显示日期
String formatWhen(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(t.year, t.month, t.day);
  final diff = today.difference(that).inDays;
  if (diff == 0) return '今天 ${formatTime(t)}';
  if (diff == 1) return '昨天 ${formatTime(t)}';
  if (diff < 7) return '$diff 天前';
  final m = t.month.toString().padLeft(2, '0');
  final d = t.day.toString().padLeft(2, '0');
  return t.year == now.year ? '$m-$d' : '${t.year}-$m-$d';
}
