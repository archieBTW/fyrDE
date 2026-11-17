class BlockPartition {
  final String devicePath;
  final String kname;
  final String parentDiskPath;
  final int? partitionNumber;
  final int sizeBytes;
  final String? fsType;
  final String? label;
  final String? partLabel;
  final String? uuid;
  final List<String> mountPoints;
  final bool isReadOnly;
  final bool isEncrypted;
  final bool isUnlocked;
  final String? mapperPath;
  final String? unlockedFsType;
  final String? unlockedLabel;
  final int? unlockedSizeBytes;
  final bool isSystemCritical;

  const BlockPartition({
    required this.devicePath,
    required this.kname,
    required this.parentDiskPath,
    this.partitionNumber,
    required this.sizeBytes,
    this.fsType,
    this.label,
    this.partLabel,
    this.uuid,
    this.mountPoints = const [],
    this.isReadOnly = false,
    this.isEncrypted = false,
    this.isUnlocked = false,
    this.mapperPath,
    this.unlockedFsType,
    this.unlockedLabel,
    this.unlockedSizeBytes,
    this.isSystemCritical = false,
  });

  bool get isMounted => mountPoints.isNotEmpty;

  bool get isLocked => isEncrypted && !isUnlocked;

  String get effectiveFsType => unlockedFsType ?? fsType ?? 'unformatted';

  String get displayLabel {
    final l = unlockedLabel ?? label ?? partLabel;
    if (l != null && l.trim().isNotEmpty) return l.trim();
    return devicePath.split('/').last;
  }

  String get mountTargetDevice =>
      (isEncrypted && mapperPath != null && mapperPath!.isNotEmpty)
          ? mapperPath!
          : devicePath;
}

class FreeDiskRegion {
  final int startBytes;
  final int endBytes;
  final int sizeBytes;

  const FreeDiskRegion({
    required this.startBytes,
    required this.endBytes,
    required this.sizeBytes,
  });
}

class BlockDisk {
  final String devicePath;
  final String kname;
  final int sizeBytes;
  final String? model;
  final String? vendor;
  final String? serial;
  final String? transport;
  final String? fsType;
  final String? label;
  final String? partitionTable; // 'gpt', 'dos', 'loop', or null
  final List<String> mountPoints;
  final bool isRemovable;
  final bool isHotplug;
  final bool isReadOnly;
  final bool isSystemDisk;
  final List<BlockPartition> partitions;
  final List<FreeDiskRegion> freeRegions;

  const BlockDisk({
    required this.devicePath,
    required this.kname,
    required this.sizeBytes,
    this.model,
    this.vendor,
    this.serial,
    this.transport,
    this.fsType,
    this.label,
    this.partitionTable,
    this.mountPoints = const [],
    this.isRemovable = false,
    this.isHotplug = false,
    this.isReadOnly = false,
    this.isSystemDisk = false,
    this.partitions = const [],
    this.freeRegions = const [],
  });

  bool get isExternal =>
      isRemovable || isHotplug || transport == 'usb' || transport == 'mmc';

  bool get hasAnyEncryptedPartition => partitions.any((p) => p.isEncrypted);

  String get displayTitle {
    final m = model?.trim();
    final v = vendor?.trim();
    if (m != null && m.isNotEmpty) {
      if (v != null && v.isNotEmpty && !m.toLowerCase().contains(v.toLowerCase())) {
        return '$v $m';
      }
      return m;
    }
    return devicePath;
  }

  int get allocatedPartitionBytes =>
      partitions.fold<int>(0, (sum, p) => sum + p.sizeBytes);

  int get unallocatedBytes {
    if (freeRegions.isNotEmpty) {
      return freeRegions.fold<int>(0, (sum, r) => sum + r.sizeBytes);
    }
    final rem = sizeBytes - allocatedPartitionBytes;
    return rem > 0 ? rem : 0;
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    double value = bytes.toDouble();
    int idx = 0;
    while (value >= 1000 && idx < units.length - 1) {
      value /= 1000;
      idx++;
    }
    return '${value >= 10 || idx == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)} ${units[idx]}';
  }
}

class FilesystemOption {
  final String id;
  final String displayName;
  final String toolBinary;
  final bool available;
  final bool supportsLabel;
  final bool supportsEncryption;

  const FilesystemOption({
    required this.id,
    required this.displayName,
    required this.toolBinary,
    required this.available,
    this.supportsLabel = true,
    this.supportsEncryption = false,
  });
}

class FlashProgressUpdate {
  final int bytesWritten;
  final int totalBytes;
  final double? speedBytesPerSec;
  final String rawLine;

  const FlashProgressUpdate({
    required this.bytesWritten,
    required this.totalBytes,
    this.speedBytesPerSec,
    this.rawLine = '',
  });

  double get fraction =>
      totalBytes > 0 ? (bytesWritten / totalBytes).clamp(0.0, 1.0) : 0.0;
}

class DiskOpResult {
  final bool ok;
  final bool cancelled;
  final String message;
  final String details;

  const DiskOpResult({
    required this.ok,
    this.cancelled = false,
    required this.message,
    this.details = '',
  });
}
