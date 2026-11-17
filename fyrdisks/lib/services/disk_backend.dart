import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import '../models/disk_models.dart';
import 'sudo_auth.dart';

class DiskBackend {
  static const Set<String> _criticalMounts = {
    '/',
    '/boot',
    '/boot/efi',
    '/efi',
    '/home',
    '/var',
    '/usr',
    '/etc',
    '[SWAP]',
  };

  static bool isSystemMount(String mount) {
    if (_criticalMounts.contains(mount)) return true;
    if (mount.startsWith('/var/') || mount.startsWith('/usr/')) return true;
    return false;
  }

  static List<String> _extractMounts(Map<String, dynamic> node) {
    final result = <String>[];
    final mps = node['mountpoints'];
    if (mps is List) {
      for (final m in mps) {
        if (m is String && m.trim().isNotEmpty) result.add(m.trim());
      }
    }
    final mp = node['mountpoint'];
    if (mp is String && mp.trim().isNotEmpty && !result.contains(mp.trim())) {
      result.add(mp.trim());
    }
    return result;
  }

  static int _parseInt(dynamic val) {
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val.trim()) ?? 0;
    return 0;
  }

  static int? _parseNullableInt(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val.trim());
    return null;
  }

  static bool _parseBool(dynamic val) {
    if (val is bool) return val;
    if (val is num) return val != 0;
    if (val is String) {
      final v = val.trim().toLowerCase();
      return v == '1' || v == 'true' || v == 'yes';
    }
    return false;
  }

  static int? _inferPartNumber(String devPath, dynamic partnCol) {
    final fromCol = _parseNullableInt(partnCol);
    if (fromCol != null) return fromCol;
    final match = RegExp(r'(\d+)$').firstMatch(devPath);
    return match != null ? int.tryParse(match.group(1)!) : null;
  }

  /// Parses `lsblk -J -b -p` JSON output into structured [BlockDisk] models.
  static List<BlockDisk> parseLsblkDisks(String jsonText) {
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map<String, dynamic>) return const [];
    final blockDevices = decoded['blockdevices'];
    if (blockDevices is! List) return const [];

    final disks = <BlockDisk>[];

    for (final rawDisk in blockDevices) {
      if (rawDisk is! Map<String, dynamic>) continue;
      final type = (rawDisk['type'] as String? ?? '').toLowerCase();
      if (type != 'disk') continue;

      final diskPath = (rawDisk['path'] as String? ?? rawDisk['name'] as String? ?? '').trim();
      final kname = (rawDisk['kname'] as String? ?? diskPath.split('/').last).split('/').last;
      if (diskPath.isEmpty || kname.startsWith('zram') || kname.startsWith('ram') || kname.startsWith('loop')) {
        continue;
      }

      final diskMounts = _extractMounts(rawDisk);
      bool diskIsSystem = diskMounts.any(isSystemMount);

      final rawChildren = (rawDisk['children'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
      final partitions = <BlockPartition>[];

      for (final child in rawChildren) {
        final cType = (child['type'] as String? ?? '').toLowerCase();
        if (cType == 'crypt') continue;
        final partPath = (child['path'] as String? ?? child['name'] as String? ?? '').trim();
        if (partPath.isEmpty) continue;

        final cMounts = _extractMounts(child);
        final fs = (child['fstype'] as String?)?.trim();
        final isEncrypted = fs == 'crypto_LUKS';

        Map<String, dynamic>? cryptChild;
        final nested = (child['children'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
        for (final nc in nested) {
          if ((nc['type'] as String? ?? '').toLowerCase() == 'crypt') {
            cryptChild = nc;
            break;
          }
        }

        final unlockedMounts = cryptChild != null ? _extractMounts(cryptChild) : const <String>[];
        final effectiveMounts = isEncrypted ? unlockedMounts : cMounts;
        final isCritical = effectiveMounts.any(isSystemMount) || cMounts.any(isSystemMount);
        if (isCritical) diskIsSystem = true;

        partitions.add(
          BlockPartition(
            devicePath: partPath,
            kname: (child['kname'] as String? ?? partPath.split('/').last).split('/').last,
            parentDiskPath: diskPath,
            partitionNumber: _inferPartNumber(partPath, child['partn']),
            sizeBytes: _parseInt(child['size']),
            fsType: fs,
            label: (child['label'] as String?)?.trim(),
            partLabel: (child['partlabel'] as String?)?.trim(),
            uuid: (child['uuid'] as String?)?.trim(),
            mountPoints: effectiveMounts,
            isReadOnly: _parseBool(child['ro']),
            isEncrypted: isEncrypted,
            isUnlocked: cryptChild != null,
            mapperPath: cryptChild != null
                ? (cryptChild['path'] as String? ?? cryptChild['name'] as String?)?.trim()
                : null,
            unlockedFsType: cryptChild != null ? (cryptChild['fstype'] as String?)?.trim() : null,
            unlockedLabel: cryptChild != null ? (cryptChild['label'] as String?)?.trim() : null,
            unlockedSizeBytes: cryptChild != null ? _parseNullableInt(cryptChild['size']) : null,
            isSystemCritical: isCritical,
          ),
        );
      }

      disks.add(
        BlockDisk(
          devicePath: diskPath,
          kname: kname,
          sizeBytes: _parseInt(rawDisk['size']),
          model: (rawDisk['model'] as String?)?.trim(),
          vendor: (rawDisk['vendor'] as String?)?.trim(),
          serial: (rawDisk['serial'] as String?)?.trim(),
          transport: (rawDisk['tran'] as String?)?.trim().toLowerCase(),
          fsType: (rawDisk['fstype'] as String?)?.trim(),
          label: (rawDisk['label'] as String?)?.trim(),
          partitionTable: (rawDisk['pttype'] as String?)?.trim().toLowerCase(),
          mountPoints: diskMounts,
          isRemovable: _parseBool(rawDisk['rm']),
          isHotplug: _parseBool(rawDisk['hotplug']),
          isReadOnly: _parseBool(rawDisk['ro']),
          isSystemDisk: diskIsSystem,
          partitions: partitions,
        ),
      );
    }

    // Sort external drives first, then internal disks.
    disks.sort((a, b) {
      if (a.isExternal != b.isExternal) return a.isExternal ? -1 : 1;
      return a.devicePath.compareTo(b.devicePath);
    });
    return disks;
  }

  /// Parses `parted -m <disk> unit B print free` machine-readable output.
  static List<FreeDiskRegion> parsePartedFreeRegions(String machineOutput) {
    final regions = <FreeDiskRegion>[];
    for (final rawLine in machineOutput.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || !line.contains(':free;')) continue;
      final fields = line.split(':');
      if (fields.length < 4) continue;
      final start = int.tryParse(fields[1].replaceAll('B', '').trim());
      final end = int.tryParse(fields[2].replaceAll('B', '').trim());
      final size = int.tryParse(fields[3].replaceAll('B', '').trim());
      if (start != null && end != null && size != null && size >= 4 * 1024 * 1024) {
        regions.add(FreeDiskRegion(startBytes: start, endBytes: end, sizeBytes: size));
      }
    }
    return regions;
  }

  /// Parses GNU coreutils `dd status=progress` line into bytes written and speed.
  static FlashProgressUpdate? parseDdProgressLine(String line, int totalBytes) {
    final match = RegExp(r'^(\d+)\s+bytes\b.*?,\s*([\d.]+)\s*([kKMGT]?i?B)/s').firstMatch(line.trim());
    if (match == null) {
      final simple = RegExp(r'^(\d+)\s+bytes\b').firstMatch(line.trim());
      if (simple == null) return null;
      final written = int.tryParse(simple.group(1)!);
      if (written == null) return null;
      return FlashProgressUpdate(bytesWritten: written, totalBytes: totalBytes, rawLine: line.trim());
    }

    final written = int.tryParse(match.group(1)!);
    final rateNum = double.tryParse(match.group(2)!);
    final rateUnit = match.group(3)!;
    if (written == null) return null;

    double? speedBps;
    if (rateNum != null) {
      final mult = switch (rateUnit) {
        'kB' => 1000.0,
        'KB' => 1000.0,
        'kiB' || 'KiB' => 1024.0,
        'MB' => 1000.0 * 1000.0,
        'MiB' => 1024.0 * 1024.0,
        'GB' => 1000.0 * 1000.0 * 1000.0,
        'GiB' => 1024.0 * 1024.0 * 1024.0,
        _ => 1.0,
      };
      speedBps = rateNum * mult;
    }

    return FlashProgressUpdate(
      bytesWritten: written,
      totalBytes: totalBytes,
      speedBytesPerSec: speedBps,
      rawLine: line.trim(),
    );
  }

  static Future<bool> _hasBinary(String name) async {
    try {
      final res = await Process.run('which', [name]);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<List<FilesystemOption>> detectFilesystemOptions() async {
    final checks = await Future.wait([
      _hasBinary('mkfs.ext4'),
      _hasBinary('mkfs.btrfs'),
      _hasBinary('mkfs.fat'),
      _hasBinary('mkfs.exfat'),
      _hasBinary('mkfs.ntfs'),
      _hasBinary('mkswap'),
      _hasBinary('cryptsetup'),
    ]);
    final hasExt4 = checks[0];
    final hasBtrfs = checks[1];
    final hasFat = checks[2];
    final hasExfat = checks[3];
    final hasNtfs = checks[4];
    final hasSwap = checks[5];
    final hasCryptsetup = checks[6];

    return [
      FilesystemOption(
        id: 'ext4',
        displayName: 'Linux ext4',
        toolBinary: 'mkfs.ext4',
        available: hasExt4,
      ),
      FilesystemOption(
        id: 'luks_ext4',
        displayName: 'Encrypted LUKS2 + ext4',
        toolBinary: 'cryptsetup',
        available: hasCryptsetup && hasExt4,
        supportsEncryption: true,
      ),
      FilesystemOption(
        id: 'btrfs',
        displayName: 'Btrfs',
        toolBinary: 'mkfs.btrfs',
        available: hasBtrfs,
      ),
      FilesystemOption(
        id: 'vfat',
        displayName: 'FAT32 (Universal USB)',
        toolBinary: 'mkfs.fat',
        available: hasFat,
      ),
      FilesystemOption(
        id: 'exfat',
        displayName: 'exFAT (Large USB Files)',
        toolBinary: 'mkfs.exfat',
        available: hasExfat,
      ),
      FilesystemOption(
        id: 'ntfs',
        displayName: 'NTFS (Windows Compatible)',
        toolBinary: 'mkfs.ntfs',
        available: hasNtfs,
      ),
      FilesystemOption(
        id: 'swap',
        displayName: 'Linux Swap',
        toolBinary: 'mkswap',
        available: hasSwap,
      ),
    ];
  }

  static Future<List<BlockDisk>> loadDisks({bool includeFreeRegions = false}) async {
    final res = await Process.run('lsblk', [
      '-J',
      '-b',
      '-p',
      '-o',
      'NAME,KNAME,PKNAME,PATH,TYPE,SIZE,FSTYPE,PTTYPE,PARTN,LABEL,PARTLABEL,UUID,MOUNTPOINT,MOUNTPOINTS,RM,HOTPLUG,RO,MODEL,VENDOR,SERIAL,TRAN',
    ]);
    if (res.exitCode != 0) {
      throw Exception(res.stderr.toString().trim());
    }
    final disks = parseLsblkDisks(res.stdout.toString());
    if (!includeFreeRegions) return disks;

    final enriched = <BlockDisk>[];
    for (final d in disks) {
      List<FreeDiskRegion> regions = const [];
      try {
        // Unprivileged if user is in disk group or already cached; ignore errors quietly.
        final pRes = await Process.run('parted', ['-m', d.devicePath, 'unit', 'B', 'print', 'free']);
        if (pRes.exitCode == 0) {
          regions = parsePartedFreeRegions(pRes.stdout.toString());
        }
      } catch (_) {}
      enriched.add(BlockDisk(
        devicePath: d.devicePath,
        kname: d.kname,
        sizeBytes: d.sizeBytes,
        model: d.model,
        vendor: d.vendor,
        serial: d.serial,
        transport: d.transport,
        fsType: d.fsType,
        label: d.label,
        partitionTable: d.partitionTable,
        mountPoints: d.mountPoints,
        isRemovable: d.isRemovable,
        isHotplug: d.isHotplug,
        isReadOnly: d.isReadOnly,
        isSystemDisk: d.isSystemDisk,
        partitions: d.partitions,
        freeRegions: regions,
      ));
    }
    return enriched;
  }

  static Future<DiskOpResult> mountPartition(BlockPartition part) async {
    if (part.isLocked) {
      return const DiskOpResult(ok: false, message: 'Unlock LUKS partition before mounting.');
    }
    var res = await Process.run('udisksctl', ['mount', '--no-user-interaction', '-b', part.mountTargetDevice]);
    if (res.exitCode != 0) {
      res = await Process.run('udisksctl', ['mount', '-b', part.mountTargetDevice]);
    }
    if (res.exitCode != 0) {
      final err = res.stderr.toString().trim();
      return DiskOpResult(ok: false, message: err.isNotEmpty ? err : 'Mount failed.');
    }
    return DiskOpResult(ok: true, message: res.stdout.toString().trim());
  }

  static Future<DiskOpResult> unmountPartition(BlockPartition part) async {
    if (!part.isMounted) return const DiskOpResult(ok: true, message: 'Already unmounted.');
    var res = await Process.run('udisksctl', ['unmount', '--no-user-interaction', '-b', part.mountTargetDevice]);
    if (res.exitCode != 0) {
      res = await Process.run('udisksctl', ['unmount', '-b', part.mountTargetDevice]);
    }
    if (res.exitCode != 0) {
      final err = res.stderr.toString().trim();
      return DiskOpResult(ok: false, message: err.isNotEmpty ? err : 'Unmount failed.');
    }
    return DiskOpResult(ok: true, message: 'Unmounted ${part.mountTargetDevice}.');
  }

  static Future<DiskOpResult> unlockPartition(BlockPartition part, String passphrase) async {
    Directory? tmpDir;
    try {
      tmpDir = await Directory.systemTemp.createTemp('fyr_disks_luks_');
      await Process.run('chmod', ['700', tmpDir.path]);
      final keyFile = File('${tmpDir.path}/key');
      await keyFile.writeAsString(passphrase, flush: true);
      await Process.run('chmod', ['600', keyFile.path]);

      final res = await Process.run('udisksctl', ['unlock', '-b', part.devicePath, '--key-file', keyFile.path]);
      if (res.exitCode != 0) {
        final err = res.stderr.toString().trim();
        return DiskOpResult(ok: false, message: err.isNotEmpty ? err : 'Unlock failed.');
      }
      return DiskOpResult(ok: true, message: res.stdout.toString().trim());
    } finally {
      try {
        if (tmpDir != null && tmpDir.existsSync()) await tmpDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<DiskOpResult> lockPartition(BlockPartition part) async {
    if (part.isMounted) {
      final um = await unmountPartition(part);
      if (!um.ok) return um;
    }
    var res = await Process.run('udisksctl', ['lock', '-b', part.devicePath]);
    if (res.exitCode != 0 && part.mapperPath != null) {
      res = await Process.run('udisksctl', ['lock', '-b', part.mapperPath!]);
    }
    if (res.exitCode != 0) {
      final err = res.stderr.toString().trim();
      return DiskOpResult(ok: false, message: err.isNotEmpty ? err : 'Failed to lock LUKS container.');
    }
    return DiskOpResult(ok: true, message: 'Locked ${part.devicePath}.');
  }

  static Future<DiskOpResult> powerOffDisk(BlockDisk disk) async {
    for (final p in disk.partitions) {
      if (p.isMounted) {
        final um = await unmountPartition(p);
        if (!um.ok) return um;
      }
      if (p.isEncrypted && p.isUnlocked) {
        final lk = await lockPartition(p);
        if (!lk.ok) return lk;
      }
    }
    final res = await Process.run('udisksctl', ['power-off', '-b', disk.devicePath]);
    if (res.exitCode != 0) {
      final err = res.stderr.toString().trim();
      return DiskOpResult(ok: false, message: err.isNotEmpty ? err : 'Power-off failed.');
    }
    return DiskOpResult(ok: true, message: 'Powered off ${disk.displayTitle}. Safe to remove.');
  }

  static Future<DiskOpResult> _unmountAndCloseDiskPartitions(
    BlockDisk disk,
    File? askpassFile,
  ) async {
    for (final part in disk.partitions) {
      if (part.isMounted) {
        final um = await unmountPartition(part);
        if (!um.ok) {
          final sudoUm = await SudoAuth.run(
            command: ['umount', part.mountTargetDevice],
            askpassFile: askpassFile,
          );
          if (!sudoUm.ok) {
            return DiskOpResult(
              ok: false,
              message: 'Failed to unmount ${part.mountTargetDevice}',
              details: sudoUm.stderr,
            );
          }
        }
      }
      if (part.isEncrypted && part.isUnlocked) {
        final lk = await lockPartition(part);
        if (!lk.ok && part.mapperPath != null) {
          final mapperName = part.mapperPath!.split('/').last;
          await SudoAuth.run(
            command: ['cryptsetup', 'close', mapperName],
            askpassFile: askpassFile,
          );
        }
      }
    }
    return const DiskOpResult(ok: true, message: 'Prepared disk');
  }

  static Future<DiskOpResult> createPartitionTable({
    required BlockDisk disk,
    required String tableType, // 'gpt' or 'msdos'
    File? askpassFile,
  }) async {
    if (disk.isSystemDisk) {
      return const DiskOpResult(
        ok: false,
        message: 'Refusing to re-partition the active OS system disk.',
      );
    }
    final prep = await _unmountAndCloseDiskPartitions(disk, askpassFile);
    if (!prep.ok) return prep;

    await SudoAuth.run(command: ['wipefs', '-a', disk.devicePath], askpassFile: askpassFile);
    final res = await SudoAuth.run(
      command: ['parted', '-s', disk.devicePath, 'mklabel', tableType],
      askpassFile: askpassFile,
    );
    await SudoAuth.run(command: ['partprobe', disk.devicePath], askpassFile: askpassFile);
    if (!res.ok) {
      return DiskOpResult(ok: false, message: 'Failed to create $tableType table', details: res.stderr);
    }
    return DiskOpResult(ok: true, message: 'Created ${tableType.toUpperCase()} partition table on ${disk.devicePath}.');
  }

  static Future<DiskOpResult> formatBlockDevice({
    required String targetDevice,
    required String fsId,
    required String label,
    String? luksPassphrase,
    File? askpassFile,
  }) async {
    await SudoAuth.run(command: ['wipefs', '-a', targetDevice], askpassFile: askpassFile);

    if (fsId == 'luks_ext4') {
      if (luksPassphrase == null || luksPassphrase.isEmpty) {
        return const DiskOpResult(ok: false, message: 'LUKS passphrase is required.');
      }
      Directory? tmpDir;
      final mapperName = 'fyrformat_${DateTime.now().millisecondsSinceEpoch}';
      try {
        tmpDir = await Directory.systemTemp.createTemp('fyr_luks_fmt_');
        await Process.run('chmod', ['700', tmpDir.path]);
        final keyFile = File('${tmpDir.path}/key');
        await keyFile.writeAsString(luksPassphrase, flush: true);
        await Process.run('chmod', ['600', keyFile.path]);

        final fmtRes = await SudoAuth.run(
          command: [
            'cryptsetup',
            'luksFormat',
            '--type',
            'luks2',
            '--batch-mode',
            '--key-file',
            keyFile.path,
            targetDevice,
          ],
          askpassFile: askpassFile,
        );
        if (!fmtRes.ok) {
          return DiskOpResult(ok: false, message: 'LUKS2 format failed.', details: fmtRes.stderr);
        }

        final openRes = await SudoAuth.run(
          command: ['cryptsetup', 'open', '--key-file', keyFile.path, targetDevice, mapperName],
          askpassFile: askpassFile,
        );
        if (!openRes.ok) {
          return DiskOpResult(ok: false, message: 'Failed to open new LUKS container.', details: openRes.stderr);
        }

        final extArgs = <String>[
          'mkfs.ext4',
          '-F',
          if (label.trim().isNotEmpty) ...['-L', label.trim()],
          '/dev/mapper/$mapperName',
        ];
        final mkRes = await SudoAuth.run(command: extArgs, askpassFile: askpassFile);
        await SudoAuth.run(command: ['cryptsetup', 'close', mapperName], askpassFile: askpassFile);
        if (!mkRes.ok) {
          return DiskOpResult(ok: false, message: 'Inner ext4 format failed.', details: mkRes.stderr);
        }
        return DiskOpResult(ok: true, message: 'Formatted $targetDevice as Encrypted LUKS2 + ext4.');
      } finally {
        try {
          if (tmpDir != null && tmpDir.existsSync()) await tmpDir.delete(recursive: true);
        } catch (_) {}
      }
    }

    final cleanLabel = label.trim();
    late List<String> cmd;
    switch (fsId) {
      case 'ext4':
        cmd = ['mkfs.ext4', '-F', if (cleanLabel.isNotEmpty) ...['-L', cleanLabel], targetDevice];
        break;
      case 'btrfs':
        cmd = ['mkfs.btrfs', '-f', if (cleanLabel.isNotEmpty) ...['-L', cleanLabel], targetDevice];
        break;
      case 'vfat':
        cmd = [
          'mkfs.fat',
          '-F',
          '32',
          if (cleanLabel.isNotEmpty) ...['-n', cleanLabel.substring(0, cleanLabel.length > 11 ? 11 : cleanLabel.length)],
          targetDevice,
        ];
        break;
      case 'exfat':
        cmd = ['mkfs.exfat', if (cleanLabel.isNotEmpty) ...['-L', cleanLabel], targetDevice];
        break;
      case 'ntfs':
        cmd = ['mkfs.ntfs', '-f', if (cleanLabel.isNotEmpty) ...['-L', cleanLabel], targetDevice];
        break;
      case 'swap':
        cmd = ['mkswap', if (cleanLabel.isNotEmpty) ...['-L', cleanLabel], targetDevice];
        break;
      default:
        return DiskOpResult(ok: false, message: 'Unsupported filesystem: $fsId');
    }

    final res = await SudoAuth.run(command: cmd, askpassFile: askpassFile);
    if (!res.ok) {
      return DiskOpResult(ok: false, message: 'Format ($fsId) failed.', details: res.stderr);
    }
    return DiskOpResult(ok: true, message: 'Formatted $targetDevice as $fsId.');
  }

  static Future<DiskOpResult> createPartitionAndFormat({
    required BlockDisk disk,
    required int startBytes,
    required int endBytes,
    required String fsId,
    required String label,
    String? luksPassphrase,
    File? askpassFile,
  }) async {
    if (disk.isSystemDisk && disk.mountPoints.contains('/')) {
      return const DiskOpResult(ok: false, message: 'Cannot modify partitions on root OS device directly.');
    }

    final beforeNames = disk.partitions.map((p) => p.devicePath).toSet();
    final partedFs = (fsId == 'vfat' || fsId == 'exfat' || fsId == 'ntfs') ? 'fat32' : (fsId == 'swap' ? 'linux-swap' : 'ext4');

    final res = await SudoAuth.run(
      command: [
        'parted',
        '-s',
        '-a',
        'optimal',
        disk.devicePath,
        'mkpart',
        disk.partitionTable == 'dos' ? 'primary' : (label.trim().isNotEmpty ? label.trim() : 'fyrpart'),
        partedFs,
        '${startBytes}B',
        '${endBytes}B',
      ],
      askpassFile: askpassFile,
    );
    if (!res.ok) {
      return DiskOpResult(ok: false, message: 'Failed to create partition.', details: res.stderr);
    }

    await SudoAuth.run(command: ['partprobe', disk.devicePath], askpassFile: askpassFile);
    await SudoAuth.run(command: ['udevadm', 'settle'], askpassFile: askpassFile);

    final refreshed = await loadDisks();
    final updatedDisk = refreshed.firstWhere(
      (d) => d.devicePath == disk.devicePath,
      orElse: () => disk,
    );
    final newParts = updatedDisk.partitions.where((p) => !beforeNames.contains(p.devicePath)).toList();
    if (newParts.isEmpty) {
      return const DiskOpResult(ok: true, message: 'Partition created.');
    }
    final newDev = newParts.last.devicePath;
    if (fsId == 'unformatted') {
      return DiskOpResult(ok: true, message: 'Created partition $newDev.');
    }
    return formatBlockDevice(
      targetDevice: newDev,
      fsId: fsId,
      label: label,
      luksPassphrase: luksPassphrase,
      askpassFile: askpassFile,
    );
  }

  static Future<DiskOpResult> formatPartition({
    required BlockPartition part,
    required String fsId,
    required String label,
    String? luksPassphrase,
    File? askpassFile,
  }) async {
    if (part.isSystemCritical) {
      return const DiskOpResult(ok: false, message: 'Refusing to format an active system partition.');
    }
    if (part.isMounted) {
      final um = await unmountPartition(part);
      if (!um.ok) return um;
    }
    if (part.isEncrypted && part.isUnlocked) {
      final lk = await lockPartition(part);
      if (!lk.ok) return lk;
    }
    return formatBlockDevice(
      targetDevice: part.devicePath,
      fsId: fsId,
      label: label,
      luksPassphrase: luksPassphrase,
      askpassFile: askpassFile,
    );
  }

  static Future<DiskOpResult> deletePartition({
    required BlockDisk disk,
    required BlockPartition part,
    File? askpassFile,
  }) async {
    if (part.isSystemCritical) {
      return const DiskOpResult(ok: false, message: 'Refusing to delete an active system partition.');
    }
    final num = part.partitionNumber;
    if (num == null) {
      return const DiskOpResult(ok: false, message: 'Could not determine partition number.');
    }
    if (part.isMounted) {
      final um = await unmountPartition(part);
      if (!um.ok) return um;
    }
    if (part.isEncrypted && part.isUnlocked) {
      final lk = await lockPartition(part);
      if (!lk.ok) return lk;
    }

    final res = await SudoAuth.run(
      command: ['parted', '-s', disk.devicePath, 'rm', '$num'],
      askpassFile: askpassFile,
    );
    await SudoAuth.run(command: ['partprobe', disk.devicePath], askpassFile: askpassFile);
    if (!res.ok) {
      return DiskOpResult(ok: false, message: 'Failed to delete partition.', details: res.stderr);
    }
    return DiskOpResult(ok: true, message: 'Deleted partition ${part.devicePath}.');
  }

  static Future<DiskOpResult> renamePartitionLabel({
    required BlockPartition part,
    required String newLabel,
    File? askpassFile,
  }) async {
    final target = part.mountTargetDevice;
    final fs = part.effectiveFsType.toLowerCase();
    late List<String> cmd;
    if (fs == 'ext4' || fs == 'ext3' || fs == 'ext2') {
      cmd = ['e2label', target, newLabel];
    } else if (fs == 'btrfs') {
      cmd = ['btrfs', 'filesystem', 'label', part.isMounted ? part.mountPoints.first : target, newLabel];
    } else if (fs == 'vfat' || fs == 'fat32') {
      cmd = ['fatlabel', target, newLabel];
    } else if (fs == 'exfat') {
      cmd = ['exfatlabel', target, newLabel];
    } else if (fs == 'ntfs') {
      cmd = ['ntfslabel', target, newLabel];
    } else {
      return DiskOpResult(ok: false, message: 'Label editing not supported for $fs.');
    }

    final res = await SudoAuth.run(command: cmd, askpassFile: askpassFile);
    if (!res.ok) {
      return DiskOpResult(ok: false, message: 'Failed to update label.', details: res.stderr);
    }
    return DiskOpResult(ok: true, message: 'Updated filesystem label to "$newLabel".');
  }

  static Future<String> computeSha256(String filePath) async {
    final file = File(filePath);
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  static Future<DiskOpResult> flashImageToDisk({
    required String imagePath,
    required BlockDisk targetDisk,
    File? askpassFile,
    required void Function(FlashProgressUpdate update) onProgress,
  }) async {
    if (targetDisk.isSystemDisk) {
      return const DiskOpResult(
        ok: false,
        message: 'Refusing to flash onto the active OS disk.',
      );
    }
    final imgFile = File(imagePath);
    if (!imgFile.existsSync()) {
      return const DiskOpResult(ok: false, message: 'Selected image file does not exist.');
    }
    final imgSize = imgFile.lengthSync();
    if (imgSize <= 0) {
      return const DiskOpResult(ok: false, message: 'Selected image file is empty.');
    }
    if (targetDisk.sizeBytes > 0 && imgSize > targetDisk.sizeBytes) {
      return DiskOpResult(
        ok: false,
        message: 'Image (${BlockDisk.formatBytes(imgSize)}) is larger than ${targetDisk.devicePath} (${BlockDisk.formatBytes(targetDisk.sizeBytes)}).',
      );
    }

    final prep = await _unmountAndCloseDiskPartitions(targetDisk, askpassFile);
    if (!prep.ok) return prep;

    final env = askpassFile != null
        ? <String, String>{...Platform.environment, 'SUDO_ASKPASS': askpassFile.path}
        : null;
    final ddArgs = <String>[
      askpassFile != null ? '-A' : '-n',
      'dd',
      'if=$imagePath',
      'of=${targetDisk.devicePath}',
      'bs=4M',
      'conv=fsync',
      'status=progress',
    ];

    final proc = await Process.start('sudo', ddArgs, environment: env);
    final stderrBuf = StringBuffer();
    String partial = '';

    await proc.stderr.transform(utf8.decoder).forEach((chunk) {
      stderrBuf.write(chunk);
      partial += chunk;
      final lines = partial.split(RegExp(r'[\r\n]'));
      partial = lines.removeLast();
      for (final line in lines) {
        final parsed = parseDdProgressLine(line, imgSize);
        if (parsed != null) onProgress(parsed);
      }
    });
    if (partial.isNotEmpty) {
      final parsed = parseDdProgressLine(partial, imgSize);
      if (parsed != null) onProgress(parsed);
    }

    final code = await proc.exitCode;
    if (code != 0) {
      return DiskOpResult(
        ok: false,
        message: 'Flashing failed with exit code $code.',
        details: stderrBuf.toString(),
      );
    }

    await SudoAuth.run(command: ['sync'], askpassFile: askpassFile);
    await SudoAuth.run(command: ['partprobe', targetDisk.devicePath], askpassFile: askpassFile);

    onProgress(FlashProgressUpdate(bytesWritten: imgSize, totalBytes: imgSize, rawLine: 'Complete'));
    return DiskOpResult(
      ok: true,
      message: 'Flashed ${imgFile.path.split('/').last} (${BlockDisk.formatBytes(imgSize)}) onto ${targetDisk.devicePath}.',
      details: stderrBuf.toString(),
    );
  }
}
