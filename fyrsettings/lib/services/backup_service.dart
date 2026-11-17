import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class BackupSelection {
  final bool includeFyrConfigs;
  final bool includeFyrData;
  final bool includeHomeFolders;
  final bool includeFullHome;

  const BackupSelection({
    this.includeFyrConfigs = true,
    this.includeFyrData = true,
    this.includeHomeFolders = true,
    this.includeFullHome = false,
  });

  bool get hasAnySelection =>
      includeFyrConfigs ||
      includeFyrData ||
      includeHomeFolders ||
      includeFullHome;

  Map<String, dynamic> toJson() => {
        'includeFyrConfigs': includeFyrConfigs,
        'includeFyrData': includeFyrData,
        'includeHomeFolders': includeHomeFolders,
        'includeFullHome': includeFullHome,
      };

  factory BackupSelection.fromJson(Map<String, dynamic> json) {
    return BackupSelection(
      includeFyrConfigs: json['includeFyrConfigs'] as bool? ?? true,
      includeFyrData: json['includeFyrData'] as bool? ?? true,
      includeHomeFolders: json['includeHomeFolders'] as bool? ?? true,
      includeFullHome: json['includeFullHome'] as bool? ?? false,
    );
  }
}

class BackupSettingsConfig {
  final String destinationDir;
  final BackupSelection selection;
  final String? lastBackupPath;
  final DateTime? lastBackupAt;

  const BackupSettingsConfig({
    required this.destinationDir,
    this.selection = const BackupSelection(),
    this.lastBackupPath,
    this.lastBackupAt,
  });

  Map<String, dynamic> toJson() => {
        'destinationDir': destinationDir,
        'selection': selection.toJson(),
        'lastBackupPath': lastBackupPath,
        'lastBackupAt': lastBackupAt?.toIso8601String(),
      };

  factory BackupSettingsConfig.fromJson(
    Map<String, dynamic> json, {
    required String defaultDestinationDir,
  }) {
    final selRaw = json['selection'];
    return BackupSettingsConfig(
      destinationDir: (json['destinationDir'] as String?)?.trim().isNotEmpty == true
          ? (json['destinationDir'] as String).trim()
          : defaultDestinationDir,
      selection: selRaw is Map<String, dynamic>
          ? BackupSelection.fromJson(selRaw)
          : const BackupSelection(),
      lastBackupPath: json['lastBackupPath'] as String?,
      lastBackupAt: json['lastBackupAt'] is String
          ? DateTime.tryParse(json['lastBackupAt'] as String)
          : null,
    );
  }
}

class BackupDiscoveredItem {
  final String relativePath;
  final String category;
  final String description;

  const BackupDiscoveredItem({
    required this.relativePath,
    required this.category,
    required this.description,
  });
}

class BackupArchiveEntry {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modifiedAt;
  final bool isEncrypted;

  const BackupArchiveEntry({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
    required this.isEncrypted,
  });
}

class BackupManifestInfo {
  final String archivePath;
  final bool isEncrypted;
  final DateTime? createdAt;
  final String? hostname;
  final String? username;
  final List<String> includedPaths;
  final int archiveSizeBytes;

  const BackupManifestInfo({
    required this.archivePath,
    required this.isEncrypted,
    this.createdAt,
    this.hostname,
    this.username,
    required this.includedPaths,
    required this.archiveSizeBytes,
  });
}

class BackupOperationResult {
  final bool ok;
  final String message;
  final String? archivePath;
  final int? bytesWritten;
  final int itemsCount;

  const BackupOperationResult({
    required this.ok,
    required this.message,
    this.archivePath,
    this.bytesWritten,
    this.itemsCount = 0,
  });
}

class BackupService {
  static String homeDir({String? homeOverride}) =>
      homeOverride ?? Platform.environment['HOME'] ?? '/home/${Platform.environment['USER'] ?? 'archer'}';

  static String configFilePath({String? homeOverride}) =>
      p.join(homeDir(homeOverride: homeOverride), '.config/fyr/backup_config.json');

  static String defaultDestinationDir({String? homeOverride}) =>
      p.join(homeDir(homeOverride: homeOverride), 'Backups');

  static Future<BackupSettingsConfig> loadConfig({String? homeOverride}) async {
    final defaultDest = defaultDestinationDir(homeOverride: homeOverride);
    final file = File(configFilePath(homeOverride: homeOverride));
    if (!file.existsSync()) {
      return BackupSettingsConfig(destinationDir: defaultDest);
    }
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return BackupSettingsConfig.fromJson(
          decoded,
          defaultDestinationDir: defaultDest,
        );
      }
    } catch (_) {}
    return BackupSettingsConfig(destinationDir: defaultDest);
  }

  static Future<void> saveConfig(
    BackupSettingsConfig config, {
    String? homeOverride,
  }) async {
    final file = File(configFilePath(homeOverride: homeOverride));
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(config.toJson()));
  }

  /// Finds mounted external media directories (e.g. `/run/media/$USER/*`).
  static List<String> listMountedExternalDestinations() {
    final user = Platform.environment['USER'] ?? '';
    final candidates = <String>[];
    for (final base in ['/run/media/$user', '/media/$user', '/media']) {
      if (base.isEmpty || base.endsWith('/')) continue;
      final dir = Directory(base);
      if (!dir.existsSync()) continue;
      try {
        for (final ent in dir.listSync()) {
          if (ent is Directory && !candidates.contains(ent.path)) {
            candidates.add(ent.path);
          }
        }
      } catch (_) {}
    }
    candidates.sort();
    return candidates;
  }

  /// Discovers all existing Fyr configuration, journal, tag, and user home
  /// paths inside [homeOverride] or `$HOME` matching [selection].
  static List<BackupDiscoveredItem> discoverPaths(
    BackupSelection selection, {
    String? homeOverride,
  }) {
    final home = homeDir(homeOverride: homeOverride);
    final items = <BackupDiscoveredItem>[];
    final seenRel = <String>{};

    void addIfExists(String relPath, String category, String description) {
      if (seenRel.contains(relPath)) return;
      final abs = p.join(home, relPath);
      if (FileSystemEntity.typeSync(abs) != FileSystemEntityType.notFound) {
        seenRel.add(relPath);
        items.add(BackupDiscoveredItem(
          relativePath: relPath,
          category: category,
          description: description,
        ));
      }
    }

    if (selection.includeFullHome) {
      items.add(const BackupDiscoveredItem(
        relativePath: '.',
        category: 'Home Folder',
        description: 'Entire home directory (excluding caches, mounts & sockets)',
      ));
      return items;
    }

    if (selection.includeFyrConfigs) {
      addIfExists('.config/fyr', 'Fyr Configs', 'Theme, primary display, updates, music, photos & emulator settings');
      addIfExists('.config/sway', 'Fyr Configs', 'SwayFX config, conf.d drop-ins & floating rules');
      addIfExists('.config/fyrdock', 'Fyr Configs', 'Dock preferences & pinned applications');
      addIfExists('.config/fyrtaskbar', 'Fyr Configs', 'Taskbar & weather settings');

      final cfgDir = Directory(p.join(home, '.config'));
      if (cfgDir.existsSync()) {
        try {
          for (final ent in cfgDir.listSync()) {
            final name = p.basename(ent.path);
            if (name.startsWith('fyr') || name.startsWith('dev.fyrde.')) {
              addIfExists(p.join('.config', name), 'Fyr Configs', '$name configuration');
            }
          }
        } catch (_) {}
      }
    }

    if (selection.includeFyrData) {
      addIfExists('.fyr', 'Fyr Data & Tags', 'fyrfiles tags, custom tag colors, sidebar pins & S3 config');
      addIfExists('Documents/fyrjournal', 'Fyr Data & Tags', 'fyrJournal entries & personal notes');

      final shareDir = Directory(p.join(home, '.local/share'));
      if (shareDir.existsSync()) {
        try {
          for (final ent in shareDir.listSync()) {
            final name = p.basename(ent.path);
            if (name.startsWith('fyr') ||
                name.startsWith('dev.fyrde.') ||
                name.startsWith('com.fyr.') ||
                name.startsWith('com.example.fyr')) {
              addIfExists(
                p.join('.local/share', name),
                'Fyr Data & Tags',
                '$name preferences & app state',
              );
            }
          }
        } catch (_) {}
      }
    }

    if (selection.includeHomeFolders) {
      for (final folder in const ['Desktop', 'Documents', 'Downloads', 'Music', 'Pictures', 'Videos']) {
        addIfExists(folder, 'Home Folders', '~/$folder user files');
      }
    }

    return items;
  }

  static List<String> buildDefaultExcludes({
    required String homePath,
    required String destinationDir,
  }) {
    final excludes = <String>[
      '.cache',
      '.local/share/Trash',
      '.fyr/mounts',
      '.pub-cache',
      '.npm/_cacache',
      '.cargo/registry',
      '*.sock',
      '*.fyrbackup.tar.gz',
      '*.fyrbackup.tar.gz.gpg',
    ];
    final normHome = p.normalize(homePath);
    final normDest = p.normalize(destinationDir);
    if (p.isWithin(normHome, normDest)) {
      excludes.add(p.relative(normDest, from: normHome));
    } else if (normDest == normHome) {
      excludes.add('fyr-backup-*.fyrbackup.*');
    }
    return excludes;
  }

  /// Estimates total bytes for the selected backup items using `du -sb`.
  static Future<int> estimateSizeBytes(
    BackupSelection selection, {
    String? homeOverride,
    String? destinationDir,
  }) async {
    final home = homeDir(homeOverride: homeOverride);
    final items = discoverPaths(selection, homeOverride: home);
    if (items.isEmpty) return 0;

    final excludes = buildDefaultExcludes(
      homePath: home,
      destinationDir: destinationDir ?? defaultDestinationDir(homeOverride: home),
    );
    final args = <String>[
      '-sb',
      ...excludes.map((e) => '--exclude=$e'),
      ...items.map((i) => i.relativePath),
    ];
    try {
      final res = await Process.run('du', args, workingDirectory: home);
      if (res.exitCode != 0 && res.stdout.toString().trim().isEmpty) return 0;
      int total = 0;
      for (final line in res.stdout.toString().split('\n')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.isNotEmpty) {
          total += int.tryParse(parts.first) ?? 0;
        }
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static Future<BackupOperationResult> createBackup({
    required BackupSelection selection,
    required String destinationDir,
    String? encryptionPassphrase,
    String? homeOverride,
  }) async {
    if (!selection.hasAnySelection) {
      return const BackupOperationResult(ok: false, message: 'Select at least one category to back up.');
    }
    final home = homeDir(homeOverride: homeOverride);
    final items = discoverPaths(selection, homeOverride: home);
    if (items.isEmpty) {
      return const BackupOperationResult(ok: false, message: 'No matching folders or files exist to back up.');
    }

    final dest = Directory(destinationDir);
    if (!dest.existsSync()) {
      await dest.create(recursive: true);
    }

    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    final encrypt = encryptionPassphrase != null && encryptionPassphrase.isNotEmpty;
    final archiveName = encrypt
        ? 'fyr-backup-$stamp.fyrbackup.tar.gz.gpg'
        : 'fyr-backup-$stamp.fyrbackup.tar.gz';
    final finalPath = p.join(dest.path, archiveName);

    Directory? stageDir;
    try {
      stageDir = await Directory.systemTemp.createTemp('fyr_backup_stage_');
      final manifestFile = File(p.join(stageDir.path, 'fyr-backup-manifest.json'));
      final manifestData = {
        'createdAt': now.toIso8601String(),
        'hostname': Platform.localHostname,
        'username': Platform.environment['USER'] ?? 'archer',
        'homeDir': home,
        'selection': selection.toJson(),
        'includedPaths': items.map((e) => e.relativePath).toList(),
      };
      await manifestFile.writeAsString(const JsonEncoder.withIndent('  ').convert(manifestData));

      final plainTarGz = encrypt ? p.join(stageDir.path, 'backup.tar.gz') : finalPath;
      final excludes = buildDefaultExcludes(homePath: home, destinationDir: dest.path);

      // Avoid duplicate entry if both includeFyrData (Documents/fyrjournal) and
      // includeHomeFolders (Documents) are selected.
      final tarRelPaths = <String>[];
      for (final item in items) {
        if (item.relativePath == 'Documents/fyrjournal' &&
            items.any((other) => other.relativePath == 'Documents' || other.relativePath == '.')) {
          continue;
        }
        tarRelPaths.add(item.relativePath);
      }

      final tarArgs = <String>[
        '--ignore-failed-read',
        '--warning=no-file-changed',
        ...excludes.map((e) => '--exclude=$e'),
        '-czf',
        plainTarGz,
        '-C',
        stageDir.path,
        'fyr-backup-manifest.json',
        '-C',
        home,
        ...tarRelPaths,
      ];

      final tarRes = await Process.run('tar', tarArgs);
      if (tarRes.exitCode != 0 && tarRes.exitCode != 1) {
        final err = tarRes.stderr.toString().trim();
        return BackupOperationResult(
          ok: false,
          message: err.isNotEmpty ? err : 'tar failed with exit code ${tarRes.exitCode}.',
        );
      }

      if (encrypt) {
        await Process.run('chmod', ['700', stageDir.path]);
        final passFile = File(p.join(stageDir.path, 'pass'));
        await passFile.writeAsString(encryptionPassphrase, flush: true);
        await Process.run('chmod', ['600', passFile.path]);

        final gpgRes = await Process.run('gpg', [
          '--batch',
          '--yes',
          '--pinentry-mode',
          'loopback',
          '--symmetric',
          '--cipher-algo',
          'AES256',
          '--passphrase-file',
          passFile.path,
          '-o',
          finalPath,
          plainTarGz,
        ]);
        if (gpgRes.exitCode != 0) {
          final err = gpgRes.stderr.toString().trim();
          return BackupOperationResult(
            ok: false,
            message: err.isNotEmpty ? 'GPG encryption failed: $err' : 'Failed to encrypt backup archive.',
          );
        }
      }

      final outFile = File(finalPath);
      final size = outFile.existsSync() ? outFile.lengthSync() : 0;

      final currentCfg = await loadConfig(homeOverride: home);
      await saveConfig(
        BackupSettingsConfig(
          destinationDir: dest.path,
          selection: selection,
          lastBackupPath: finalPath,
          lastBackupAt: now,
        ),
        homeOverride: home,
      );
      // Keep unused ref check quiet
      assert(currentCfg.destinationDir.isNotEmpty || dest.path.isNotEmpty);

      return BackupOperationResult(
        ok: true,
        message: 'Created backup archive $archiveName (${formatBytes(size)})',
        archivePath: finalPath,
        bytesWritten: size,
        itemsCount: items.length,
      );
    } catch (e) {
      return BackupOperationResult(ok: false, message: 'Backup failed: $e');
    } finally {
      try {
        if (stageDir != null && stageDir.existsSync()) {
          await stageDir.delete(recursive: true);
        }
      } catch (_) {}
    }
  }

  static List<BackupArchiveEntry> listBackupsInDirectory(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) return const [];
    final entries = <BackupArchiveEntry>[];
    try {
      for (final ent in dir.listSync()) {
        if (ent is! File) continue;
        final name = p.basename(ent.path);
        final lower = name.toLowerCase();
        if (lower.endsWith('.fyrbackup.tar.gz') || lower.endsWith('.fyrbackup.tar.gz.gpg')) {
          final stat = ent.statSync();
          entries.add(BackupArchiveEntry(
            path: ent.path,
            name: name,
            sizeBytes: stat.size,
            modifiedAt: stat.modified,
            isEncrypted: lower.endsWith('.gpg'),
          ));
        }
      }
      entries.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    } catch (_) {}
    return entries;
  }

  static Future<BackupManifestInfo?> inspectArchive(
    String archivePath, {
    String? passphrase,
  }) async {
    final f = File(archivePath);
    if (!f.existsSync()) return null;
    final size = f.lengthSync();
    final isEnc = archivePath.toLowerCase().endsWith('.gpg');

    Directory? tmpDir;
    try {
      String tarGzPath = archivePath;
      if (isEnc) {
        if (passphrase == null || passphrase.isEmpty) {
          return BackupManifestInfo(
            archivePath: archivePath,
            isEncrypted: true,
            includedPaths: const [],
            archiveSizeBytes: size,
          );
        }
        tmpDir = await Directory.systemTemp.createTemp('fyr_backup_inspect_');
        await Process.run('chmod', ['700', tmpDir.path]);
        final passFile = File(p.join(tmpDir.path, 'pass'));
        await passFile.writeAsString(passphrase, flush: true);
        await Process.run('chmod', ['600', passFile.path]);
        tarGzPath = p.join(tmpDir.path, 'decrypted.tar.gz');

        final gpgRes = await Process.run('gpg', [
          '--batch',
          '--yes',
          '--pinentry-mode',
          'loopback',
          '--passphrase-file',
          passFile.path,
          '-o',
          tarGzPath,
          '-d',
          archivePath,
        ]);
        if (gpgRes.exitCode != 0) return null;
      }

      final manifestRes = await Process.run(
        'tar',
        ['-xOzf', tarGzPath, 'fyr-backup-manifest.json'],
      );
      if (manifestRes.exitCode == 0) {
        final decoded = jsonDecode(manifestRes.stdout.toString());
        if (decoded is Map<String, dynamic>) {
          return BackupManifestInfo(
            archivePath: archivePath,
            isEncrypted: isEnc,
            createdAt: decoded['createdAt'] is String
                ? DateTime.tryParse(decoded['createdAt'] as String)
                : null,
            hostname: decoded['hostname'] as String?,
            username: decoded['username'] as String?,
            includedPaths: (decoded['includedPaths'] as List?)?.whereType<String>().toList() ?? const [],
            archiveSizeBytes: size,
          );
        }
      }

      final listRes = await Process.run('tar', ['-tzf', tarGzPath]);
      if (listRes.exitCode == 0) {
        final top = <String>{};
        for (final line in listRes.stdout.toString().split('\n')) {
          final cleaned = line.trim();
          if (cleaned.isEmpty || cleaned == 'fyr-backup-manifest.json') continue;
          top.add(cleaned.split('/').first);
        }
        return BackupManifestInfo(
          archivePath: archivePath,
          isEncrypted: isEnc,
          includedPaths: top.toList()..sort(),
          archiveSizeBytes: size,
        );
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      try {
        if (tmpDir != null && tmpDir.existsSync()) await tmpDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<BackupOperationResult> restoreArchive({
    required String archivePath,
    String? passphrase,
    String? targetHomeOverride,
  }) async {
    final targetHome = targetHomeOverride ?? homeDir();
    final targetDir = Directory(targetHome);
    if (!targetDir.existsSync()) {
      await targetDir.create(recursive: true);
    }
    final f = File(archivePath);
    if (!f.existsSync()) {
      return const BackupOperationResult(ok: false, message: 'Backup archive not found.');
    }

    final isEnc = archivePath.toLowerCase().endsWith('.gpg');
    Directory? tmpDir;
    try {
      String tarGzPath = archivePath;
      if (isEnc) {
        if (passphrase == null || passphrase.isEmpty) {
          return const BackupOperationResult(ok: false, message: 'Passphrase required for encrypted backup.');
        }
        tmpDir = await Directory.systemTemp.createTemp('fyr_backup_restore_');
        await Process.run('chmod', ['700', tmpDir.path]);
        final passFile = File(p.join(tmpDir.path, 'pass'));
        await passFile.writeAsString(passphrase, flush: true);
        await Process.run('chmod', ['600', passFile.path]);
        tarGzPath = p.join(tmpDir.path, 'restore.tar.gz');

        final gpgRes = await Process.run('gpg', [
          '--batch',
          '--yes',
          '--pinentry-mode',
          'loopback',
          '--passphrase-file',
          passFile.path,
          '-o',
          tarGzPath,
          '-d',
          archivePath,
        ]);
        if (gpgRes.exitCode != 0) {
          final rawErr = gpgRes.stderr.toString().trim();
          return BackupOperationResult(
            ok: false,
            message: rawErr.toLowerCase().contains('bad session key') ||
                    rawErr.toLowerCase().contains('decryption failed')
                ? 'Incorrect backup passphrase.'
                : (rawErr.isNotEmpty ? rawErr : 'Failed to decrypt archive.'),
          );
        }
      }

      final res = await Process.run(
        'tar',
        [
          '-xzf',
          tarGzPath,
          '-C',
          targetHome,
          '--exclude=fyr-backup-manifest.json',
        ],
      );
      if (res.exitCode != 0) {
        final err = res.stderr.toString().trim();
        return BackupOperationResult(
          ok: false,
          message: err.isNotEmpty ? err : 'Restore failed with exit code ${res.exitCode}.',
        );
      }

      return BackupOperationResult(
        ok: true,
        message: 'Restored ${p.basename(archivePath)} to $targetHome',
        archivePath: archivePath,
      );
    } catch (e) {
      return BackupOperationResult(ok: false, message: 'Restore error: $e');
    } finally {
      try {
        if (tmpDir != null && tmpDir.existsSync()) await tmpDir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    double v = bytes.toDouble();
    int idx = 0;
    while (v >= 1000 && idx < units.length - 1) {
      v /= 1000;
      idx++;
    }
    return '${v >= 10 || idx == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1)} ${units[idx]}';
  }
}
