import 'dart:convert';
import 'dart:io';

class DriveActionResult {
  final bool ok;
  final String message;
  final String? mountPoint;
  final String? unlockedDevicePath;

  const DriveActionResult({
    required this.ok,
    required this.message,
    this.mountPoint,
    this.unlockedDevicePath,
  });
}

class ExternalDriveVolume {
  final String devicePath;
  final String parentDiskPath;
  final String? mapperPath;
  final String? label;
  final String? model;
  final String? vendor;
  final String? transport;
  final String? fsType;
  final String? unlockedFsType;
  final String? mountPoint;
  final int sizeBytes;
  final bool isRemovable;
  final bool isHotplug;
  final bool isReadOnly;
  final bool isEncrypted;
  final bool isUnlocked;
  final bool isWholeDisk;

  const ExternalDriveVolume({
    required this.devicePath,
    required this.parentDiskPath,
    this.mapperPath,
    this.label,
    this.model,
    this.vendor,
    this.transport,
    this.fsType,
    this.unlockedFsType,
    this.mountPoint,
    required this.sizeBytes,
    required this.isRemovable,
    required this.isHotplug,
    required this.isReadOnly,
    required this.isEncrypted,
    required this.isUnlocked,
    this.isWholeDisk = false,
  });

  bool get isMounted => mountPoint != null && mountPoint!.isNotEmpty;

  bool get isLocked => isEncrypted && !isUnlocked;

  String get effectiveFsType => unlockedFsType ?? fsType ?? '';

  /// Device node targeted by `udisksctl mount/unmount`.
  String get mountTargetDevice =>
      (isEncrypted && mapperPath != null && mapperPath!.isNotEmpty)
          ? mapperPath!
          : devicePath;

  String get displayName {
    final trimmedLabel = label?.trim();
    if (trimmedLabel != null && trimmedLabel.isNotEmpty) {
      return trimmedLabel;
    }
    final devName = devicePath.split('/').last;
    final trimmedModel = model?.trim();
    if (trimmedModel != null && trimmedModel.isNotEmpty) {
      return isWholeDisk ? trimmedModel : '$trimmedModel ($devName)';
    }
    if (isEncrypted) {
      return 'Encrypted ($devName)';
    }
    return devName;
  }

  String get subtitle {
    final parts = <String>[formatBytes(sizeBytes)];
    if (isEncrypted) {
      parts.add(isUnlocked
          ? (isMounted ? 'Unlocked' : 'Unlocked • Unmounted')
          : 'Locked LUKS');
    } else if (fsType == null || fsType!.isEmpty) {
      parts.add('Unformatted');
    } else if (isMounted) {
      parts.add(fsType!);
    } else {
      parts.add('${fsType!} • Unmounted');
    }
    return parts.join(' • ');
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    double val = bytes.toDouble();
    int unit = 0;
    while (val >= 1000 && unit < units.length - 1) {
      val /= 1000;
      unit++;
    }
    return '${val >= 10 || unit == 0 ? val.toStringAsFixed(0) : val.toStringAsFixed(1)} ${units[unit]}';
  }
}

class DrivesService {
  static const Set<String> _systemMountPrefixes = {
    '/',
    '/boot',
    '/boot/efi',
    '/efi',
    '/home',
    '/var',
    '/usr',
    '/etc',
    '/opt',
    '/srv',
    '/root',
    '[SWAP]',
  };

  static bool _isSystemMount(String mount) {
    if (_systemMountPrefixes.contains(mount)) return true;
    if (mount.startsWith('/var/')) return true;
    if (mount.startsWith('/usr/')) return true;
    return false;
  }

  static List<String> _extractMounts(Map<String, dynamic> node) {
    final out = <String>[];
    final mps = node['mountpoints'];
    if (mps is List) {
      for (final item in mps) {
        if (item is String && item.trim().isNotEmpty) {
          out.add(item.trim());
        }
      }
    }
    final mp = node['mountpoint'];
    if (mp is String && mp.trim().isNotEmpty && !out.contains(mp.trim())) {
      out.add(mp.trim());
    }
    return out;
  }

  static int _parseSize(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw.trim()) ?? 0;
    return 0;
  }

  static bool _parseBool(dynamic raw) {
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final v = raw.trim().toLowerCase();
      return v == '1' || v == 'true' || v == 'yes';
    }
    return false;
  }

  static bool _nodeHasSystemMount(Map<String, dynamic> node) {
    for (final m in _extractMounts(node)) {
      if (_isSystemMount(m)) return true;
    }
    final children = node['children'];
    if (children is List) {
      for (final child in children) {
        if (child is Map<String, dynamic> && _nodeHasSystemMount(child)) {
          return true;
        }
      }
    }
    return false;
  }

  /// Parses `lsblk -J -b -p -o ...` JSON output and returns external,
  /// removable, user-mounted, and LUKS encrypted volumes for the sidebar.
  static List<ExternalDriveVolume> parseLsblkJson(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return const [];
    final blockDevices = decoded['blockdevices'];
    if (blockDevices is! List) return const [];

    final volumes = <ExternalDriveVolume>[];

    for (final rawDisk in blockDevices) {
      if (rawDisk is! Map<String, dynamic>) continue;
      final diskType = (rawDisk['type'] as String? ?? '').toLowerCase();
      final diskPath = (rawDisk['path'] as String? ?? rawDisk['name'] as String? ?? '').trim();
      if (diskPath.isEmpty || diskType != 'disk') continue;

      final kname = (rawDisk['kname'] as String? ?? diskPath).split('/').last;
      if (kname.startsWith('zram') || kname.startsWith('loop') || kname.startsWith('ram')) {
        continue;
      }

      final tran = (rawDisk['tran'] as String?)?.trim().toLowerCase();
      final model = (rawDisk['model'] as String?)?.trim();
      final vendor = (rawDisk['vendor'] as String?)?.trim();
      final isRemovable = _parseBool(rawDisk['rm']);
      final isHotplug = _parseBool(rawDisk['hotplug']);
      final isExternalDisk = tran == 'usb' || tran == 'mmc' || isRemovable || isHotplug;
      final children = (rawDisk['children'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];

      if (children.isEmpty) {
        final mounts = _extractMounts(rawDisk);
        final hasSystemMount = mounts.any(_isSystemMount);
        final fs = (rawDisk['fstype'] as String?)?.trim();
        final isEncrypted = fs == 'crypto_LUKS';
        if (!hasSystemMount && (isExternalDisk || isEncrypted || mounts.isNotEmpty)) {
          volumes.add(
            ExternalDriveVolume(
              devicePath: diskPath,
              parentDiskPath: diskPath,
              label: (rawDisk['label'] as String?)?.trim(),
              model: model,
              vendor: vendor,
              transport: tran,
              fsType: fs,
              mountPoint: mounts.isNotEmpty ? mounts.first : null,
              sizeBytes: _parseSize(rawDisk['size']),
              isRemovable: isRemovable,
              isHotplug: isHotplug,
              isReadOnly: _parseBool(rawDisk['ro']),
              isEncrypted: isEncrypted,
              isUnlocked: false,
              isWholeDisk: true,
            ),
          );
        }
        continue;
      }

      for (final part in children) {
        final partType = (part['type'] as String? ?? '').toLowerCase();
        if (partType == 'crypt') continue;
        final partPath = (part['path'] as String? ?? part['name'] as String? ?? '').trim();
        if (partPath.isEmpty) continue;

        final fs = (part['fstype'] as String?)?.trim();
        if (fs == 'swap') continue;

        final partMounts = _extractMounts(part);
        final partHasSystem = _nodeHasSystemMount(part);
        final isEncrypted = fs == 'crypto_LUKS';

        final partChildren = (part['children'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
        Map<String, dynamic>? cryptChild;
        for (final pc in partChildren) {
          if ((pc['type'] as String? ?? '').toLowerCase() == 'crypt') {
            cryptChild = pc;
            break;
          }
        }

        final mapperPath = cryptChild != null
            ? (cryptChild['path'] as String? ?? cryptChild['name'] as String?)?.trim()
            : null;
        final unlockedMounts = cryptChild != null ? _extractMounts(cryptChild) : const <String>[];
        final effectiveMounts = isEncrypted ? unlockedMounts : partMounts;
        final unlockedFs = cryptChild != null ? (cryptChild['fstype'] as String?)?.trim() : null;
        final label = (cryptChild?['label'] as String?)?.trim() ??
            (part['label'] as String?)?.trim() ??
            (part['partlabel'] as String?)?.trim() ??
            (rawDisk['label'] as String?)?.trim();

        final isMediaMount = effectiveMounts.any(
          (m) => m.startsWith('/run/media/') || m.startsWith('/media/') || m.startsWith('/mnt/'),
        );

        // Skip internal OS partitions, but include external drives, media mounts,
        // and non-OS LUKS encrypted partitions.
        if (partHasSystem) continue;
        if (!isExternalDisk && !isEncrypted && !isMediaMount) continue;
        if ((fs == null || fs.isEmpty) && !isEncrypted && !isMediaMount) continue;

        volumes.add(
          ExternalDriveVolume(
            devicePath: partPath,
            parentDiskPath: diskPath,
            mapperPath: mapperPath,
            label: label,
            model: model,
            vendor: vendor,
            transport: tran,
            fsType: fs,
            unlockedFsType: unlockedFs,
            mountPoint: effectiveMounts.isNotEmpty ? effectiveMounts.first : null,
            sizeBytes: _parseSize(cryptChild?['size'] ?? part['size']),
            isRemovable: isRemovable || _parseBool(part['rm']),
            isHotplug: isHotplug || _parseBool(part['hotplug']),
            isReadOnly: _parseBool(cryptChild?['ro'] ?? part['ro']),
            isEncrypted: isEncrypted,
            isUnlocked: cryptChild != null,
          ),
        );
      }
    }

    return volumes;
  }

  static Future<List<ExternalDriveVolume>> listExternalDrives() async {
    try {
      final res = await Process.run('lsblk', [
        '-J',
        '-b',
        '-p',
        '-o',
        'NAME,KNAME,PKNAME,PATH,TYPE,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT,MOUNTPOINTS,RM,HOTPLUG,RO,MODEL,VENDOR,SERIAL,TRAN,PARTLABEL',
      ]);
      if (res.exitCode != 0) return const [];
      return parseLsblkJson(res.stdout.toString());
    } catch (_) {
      return const [];
    }
  }

  static String? parseMountPointFromUdisksStdout(String stdoutText) {
    final match = RegExp(r'Mounted\s+\S+\s+at\s+(.+)\.?$').firstMatch(stdoutText.trim());
    if (match == null) return null;
    var path = match.group(1)!.trim();
    if (path.endsWith('.') && !Directory(path).existsSync()) {
      path = path.substring(0, path.length - 1);
    }
    return path;
  }

  static String? parseUnlockedDeviceFromUdisksStdout(String stdoutText) {
    final match = RegExp(r'Unlocked\s+\S+\s+as\s+([^\s.]+)\.?').firstMatch(stdoutText.trim());
    return match?.group(1)?.trim();
  }

  static Future<DriveActionResult> mountVolume(ExternalDriveVolume vol) async {
    final target = vol.mountTargetDevice;
    if (vol.isMounted) {
      return DriveActionResult(
        ok: true,
        message: 'Already mounted at ${vol.mountPoint}',
        mountPoint: vol.mountPoint,
      );
    }
    if (vol.isLocked) {
      return const DriveActionResult(
        ok: false,
        message: 'Encrypted drive must be unlocked before mounting.',
      );
    }
    if (vol.fsType == null || vol.fsType!.isEmpty) {
      return const DriveActionResult(
        ok: false,
        message: 'This drive has no formatted filesystem yet. Format it in fyrDisks first.',
      );
    }

    var res = await Process.run('udisksctl', ['mount', '--no-user-interaction', '-b', target]);
    if (res.exitCode != 0) {
      res = await Process.run('udisksctl', ['mount', '-b', target]);
    }
    if (res.exitCode != 0) {
      final err = res.stderr.toString().trim();
      return DriveActionResult(
        ok: false,
        message: err.isNotEmpty ? err : 'Failed to mount $target.',
      );
    }

    String? mountPoint = parseMountPointFromUdisksStdout(res.stdout.toString());
    if (mountPoint == null || !Directory(mountPoint).existsSync()) {
      final refreshed = await listExternalDrives();
      for (final d in refreshed) {
        if (d.devicePath == vol.devicePath || d.mountTargetDevice == target) {
          mountPoint = d.mountPoint;
          break;
        }
      }
    }
    return DriveActionResult(
      ok: true,
      message: mountPoint != null ? 'Mounted at $mountPoint' : 'Mounted $target',
      mountPoint: mountPoint,
    );
  }

  static Future<DriveActionResult> unlockVolume(
    ExternalDriveVolume vol,
    String passphrase,
  ) async {
    if (!vol.isEncrypted) {
      return const DriveActionResult(ok: false, message: 'Device is not LUKS encrypted.');
    }
    Directory? keyDir;
    try {
      keyDir = await Directory.systemTemp.createTemp('fyr_luks_key_');
      await Process.run('chmod', ['700', keyDir.path]);
      final keyFile = File('${keyDir.path}/key');
      await keyFile.writeAsString(passphrase, flush: true);
      await Process.run('chmod', ['600', keyFile.path]);

      final res = await Process.run('udisksctl', [
        'unlock',
        '-b',
        vol.devicePath,
        '--key-file',
        keyFile.path,
      ]);
      if (res.exitCode != 0) {
        final rawErr = res.stderr.toString().trim();
        final lower = rawErr.toLowerCase();
        final friendly = (lower.contains('passphrase') || lower.contains('no key available') || lower.contains('keyslot'))
            ? 'Incorrect passphrase for ${vol.displayName}.'
            : (rawErr.isNotEmpty ? rawErr : 'Failed to unlock ${vol.devicePath}.');
        return DriveActionResult(ok: false, message: friendly);
      }

      String? unlockedDev = parseUnlockedDeviceFromUdisksStdout(res.stdout.toString());
      final refreshed = await listExternalDrives();
      for (final item in refreshed) {
        if (item.devicePath == vol.devicePath) {
          unlockedDev = item.mapperPath ?? unlockedDev;
          return DriveActionResult(
            ok: true,
            message: 'Unlocked ${vol.displayName}',
            unlockedDevicePath: unlockedDev,
            mountPoint: item.mountPoint,
          );
        }
      }
      return DriveActionResult(
        ok: true,
        message: 'Unlocked ${vol.displayName}',
        unlockedDevicePath: unlockedDev,
      );
    } finally {
      try {
        if (keyDir != null && keyDir.existsSync()) {
          await keyDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  static Future<DriveActionResult> unmountVolume(ExternalDriveVolume vol) async {
    if (!vol.isMounted) {
      return const DriveActionResult(ok: true, message: 'Already unmounted.');
    }
    var res = await Process.run('udisksctl', [
      'unmount',
      '--no-user-interaction',
      '-b',
      vol.mountTargetDevice,
    ]);
    if (res.exitCode != 0) {
      res = await Process.run('udisksctl', ['unmount', '-b', vol.mountTargetDevice]);
    }
    if (res.exitCode != 0) {
      final err = res.stderr.toString().trim();
      return DriveActionResult(
        ok: false,
        message: err.isNotEmpty ? err : 'Could not unmount ${vol.displayName} (device may be busy).',
      );
    }
    return DriveActionResult(ok: true, message: 'Unmounted ${vol.displayName}.');
  }

  static Future<DriveActionResult> lockVolume(ExternalDriveVolume vol) async {
    if (!vol.isEncrypted || !vol.isUnlocked) {
      return const DriveActionResult(ok: true, message: 'Drive is already locked.');
    }
    if (vol.isMounted) {
      final umountRes = await unmountVolume(vol);
      if (!umountRes.ok) return umountRes;
    }

    var res = await Process.run('udisksctl', ['lock', '-b', vol.devicePath]);
    if (res.exitCode != 0 && vol.mapperPath != null) {
      res = await Process.run('udisksctl', ['lock', '-b', vol.mapperPath!]);
    }
    if (res.exitCode != 0) {
      final err = res.stderr.toString().trim();
      return DriveActionResult(
        ok: false,
        message: err.isNotEmpty ? err : 'Failed to lock ${vol.displayName}.',
      );
    }
    return DriveActionResult(ok: true, message: 'Locked ${vol.displayName}.');
  }

  static Future<DriveActionResult> ejectVolume(ExternalDriveVolume vol) async {
    if (vol.isMounted) {
      final umountRes = await unmountVolume(vol);
      if (!umountRes.ok) return umountRes;
    }
    if (vol.isEncrypted && vol.isUnlocked) {
      final lockRes = await lockVolume(vol);
      if (!lockRes.ok) return lockRes;
    }

    final remaining = await listExternalDrives();
    final stillActiveOnDisk = remaining.any(
      (d) => d.parentDiskPath == vol.parentDiskPath && (d.isMounted || d.isUnlocked),
    );
    if (!stillActiveOnDisk && (vol.isRemovable || vol.isHotplug || vol.transport == 'usb')) {
      final pwr = await Process.run('udisksctl', ['power-off', '-b', vol.parentDiskPath]);
      if (pwr.exitCode == 0) {
        return DriveActionResult(ok: true, message: 'Safely ejected ${vol.displayName}.');
      }
    }
    return DriveActionResult(
      ok: true,
      message: 'Unmounted ${vol.displayName}. Safe to disconnect.',
    );
  }
}
