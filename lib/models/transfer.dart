import 'device.dart';

/// 待发送 / 待接收的单个文件条目
class FileItem {
  FileItem({
    required this.id,
    required this.name,
    required this.size,
    this.path,
    this.relativePath,
  });

  /// 会话内唯一 id(发送端生成)
  final String id;
  final String name;
  final int size;

  /// 发送端本地路径;接收端为 null(尚未落盘)
  final String? path;

  /// 发送整个文件夹时的相对路径,如 "photos/2024/a.jpg"。
  /// 接收端据此重建目录结构。
  final String? relativePath;

  String get ext {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1);
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        if (relativePath != null) 'relativePath': relativePath,
      };

  static FileItem? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final name = j['name'];
    final size = j['size'];
    if (id is! String || id.isEmpty) return null;
    if (name is! String || name.isEmpty) return null;
    if (size is! int || size < 0) return null;
    return FileItem(
      id: id,
      name: name,
      size: size,
      relativePath: j['relativePath'] as String?,
    );
  }
}

enum TransferDirection { send, receive }

enum TransferStatus {
  /// 等待对方确认接收
  waiting,
  transferring,
  done,
  failed,
  /// 本端或对端主动取消
  canceled,
  /// 对方拒绝接收
  rejected;

  bool get isFinished => this != waiting && this != transferring;

  String get label => switch (this) {
        TransferStatus.waiting => '等待确认',
        TransferStatus.transferring => '传输中',
        TransferStatus.done => '已完成',
        TransferStatus.failed => '失败',
        TransferStatus.canceled => '已取消',
        TransferStatus.rejected => '被拒绝',
      };
}

/// 一次传输任务(一个会话 = 一批文件)
class TransferTask {
  TransferTask({
    required this.id,
    required this.direction,
    required this.device,
    required this.files,
    this.status = TransferStatus.waiting,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  /// 会话 id,两端一致
  final String id;
  final TransferDirection direction;
  final Device device;
  final List<FileItem> files;

  TransferStatus status = TransferStatus.waiting;
  DateTime startedAt;
  DateTime? finishedAt;

  /// 失败原因 / 取消说明
  String? error;

  /// 每个文件已传字节数,key = FileItem.id
  final Map<String, int> progress = {};

  /// 接收端:文件最终落盘路径,key = FileItem.id
  final Map<String, String> savedPaths = {};

  /// 当前正在传的文件 id
  String? currentFileId;

  /// 瞬时速度(字节/秒),由 AppState 每秒采样计算
  double bytesPerSecond = 0;

  int get totalBytes => files.fold(0, (s, f) => s + f.size);

  int get transferredBytes {
    var sum = 0;
    for (final f in files) {
      sum += (progress[f.id] ?? 0).clamp(0, f.size);
    }
    return sum;
  }

  double get fraction {
    final total = totalBytes;
    if (total == 0) return status == TransferStatus.done ? 1 : 0;
    return (transferredBytes / total).clamp(0.0, 1.0);
  }

  int get doneCount =>
      files.where((f) => (progress[f.id] ?? 0) >= f.size && f.size >= 0).length;

  /// 剩余秒数;速度为 0 时返回 null(显示 "--")
  int? get etaSeconds {
    if (bytesPerSecond <= 0) return null;
    final left = totalBytes - transferredBytes;
    if (left <= 0) return 0;
    return (left / bytesPerSecond).round();
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'direction': direction.name,
        'device': device.toJson(),
        'files': files.map((f) => f.toJson()).toList(),
        'status': status.name,
        'startedAt': startedAt.toIso8601String(),
        if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
        if (error != null) 'error': error,
        'savedPaths': savedPaths,
        // 历史记录只需知道每个文件传了多少,不必保留实时字段
        'progress': progress,
      };

  static TransferTask? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    if (id is! String) return null;
    final dev = j['device'];
    if (dev is! Map<String, dynamic>) return null;
    final device = Device.fromJson(dev);
    if (device == null) return null;
    final rawFiles = j['files'];
    if (rawFiles is! List) return null;
    final files = rawFiles
        .whereType<Map<String, dynamic>>()
        .map(FileItem.fromJson)
        .whereType<FileItem>()
        .toList();
    final task = TransferTask(
      id: id,
      direction: TransferDirection.values.firstWhere(
        (d) => d.name == j['direction'],
        orElse: () => TransferDirection.receive,
      ),
      device: device,
      files: files,
      status: TransferStatus.values.firstWhere(
        (s) => s.name == j['status'],
        orElse: () => TransferStatus.failed,
      ),
      startedAt: DateTime.tryParse('${j['startedAt']}') ?? DateTime.now(),
    );
    task.finishedAt = DateTime.tryParse('${j['finishedAt']}');
    task.error = j['error'] as String?;
    final sp = j['savedPaths'];
    if (sp is Map) {
      sp.forEach((k, v) {
        if (k is String && v is String) task.savedPaths[k] = v;
      });
    }
    final pr = j['progress'];
    if (pr is Map) {
      pr.forEach((k, v) {
        if (k is String && v is int) task.progress[k] = v;
      });
    }
    return task;
  }
}
