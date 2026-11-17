import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sway_conf_d.dart';

/// Supported system package/update backends.
enum UpdateSource {
  pacman('Pacman'),
  aur('AUR (yay)'),
  flatpak('Flatpak'),
  snap('Snap');

  final String label;
  const UpdateSource(this.label);
}

/// Represents a single pending package or application update.
class PendingUpdate {
  final String name;
  final String currentVersion;
  final String newVersion;
  final UpdateSource source;
  final String? details;

  const PendingUpdate({
    required this.name,
    required this.currentVersion,
    required this.newVersion,
    required this.source,
    this.details,
  });

  bool get requiresRoot =>
      source == UpdateSource.pacman ||
      source == UpdateSource.aur ||
      source == UpdateSource.snap;

  String get uniqueKey => '${source.name}:$name:$newVersion';
}

/// Persisted user preferences and schedule metadata for system updates.
class UpdatesConfig {
  final bool notificationsEnabled;
  final bool autoUpdateEnabled;
  final int checkIntervalHours;
  final bool includePacmanAur;
  final bool includeFlatpak;
  final bool includeSnap;
  final DateTime? lastCheckedAt;
  final DateTime? lastUpdatedAt;
  final String? lastError;

  const UpdatesConfig({
    this.notificationsEnabled = true,
    this.autoUpdateEnabled = false,
    this.checkIntervalHours = 6,
    this.includePacmanAur = true,
    this.includeFlatpak = true,
    this.includeSnap = true,
    this.lastCheckedAt,
    this.lastUpdatedAt,
    this.lastError,
  });

  UpdatesConfig copyWith({
    bool? notificationsEnabled,
    bool? autoUpdateEnabled,
    int? checkIntervalHours,
    bool? includePacmanAur,
    bool? includeFlatpak,
    bool? includeSnap,
    DateTime? lastCheckedAt,
    DateTime? lastUpdatedAt,
    String? lastError,
    bool clearLastError = false,
  }) {
    return UpdatesConfig(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      autoUpdateEnabled: autoUpdateEnabled ?? this.autoUpdateEnabled,
      checkIntervalHours: checkIntervalHours ?? this.checkIntervalHours,
      includePacmanAur: includePacmanAur ?? this.includePacmanAur,
      includeFlatpak: includeFlatpak ?? this.includeFlatpak,
      includeSnap: includeSnap ?? this.includeSnap,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'notificationsEnabled': notificationsEnabled,
        'autoUpdateEnabled': autoUpdateEnabled,
        'checkIntervalHours': checkIntervalHours,
        'includePacmanAur': includePacmanAur,
        'includeFlatpak': includeFlatpak,
        'includeSnap': includeSnap,
        if (lastCheckedAt != null)
          'lastCheckedAt': lastCheckedAt!.toIso8601String(),
        if (lastUpdatedAt != null)
          'lastUpdatedAt': lastUpdatedAt!.toIso8601String(),
        if (lastError != null && lastError!.isNotEmpty) 'lastError': lastError,
      };

  factory UpdatesConfig.fromJson(Map<String, dynamic> json) {
    final interval = (json['checkIntervalHours'] as num?)?.toInt() ?? 6;
    return UpdatesConfig(
      notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
      autoUpdateEnabled: json['autoUpdateEnabled'] as bool? ?? false,
      checkIntervalHours: interval.clamp(1, 168),
      includePacmanAur: json['includePacmanAur'] as bool? ?? true,
      includeFlatpak: json['includeFlatpak'] as bool? ?? true,
      includeSnap: json['includeSnap'] as bool? ?? true,
      lastCheckedAt: json['lastCheckedAt'] is String
          ? DateTime.tryParse(json['lastCheckedAt'] as String)
          : null,
      lastUpdatedAt: json['lastUpdatedAt'] is String
          ? DateTime.tryParse(json['lastUpdatedAt'] as String)
          : null,
      lastError: json['lastError'] as String?,
    );
  }
}

/// Availability of package manager executables on the current host.
class BackendAvailability {
  final bool hasPacman;
  final bool hasYay;
  final bool hasFlatpak;
  final bool hasSnap;
  final bool hasCheckupdates;
  final bool hasFakeroot;

  const BackendAvailability({
    required this.hasPacman,
    required this.hasYay,
    required this.hasFlatpak,
    required this.hasSnap,
    required this.hasCheckupdates,
    required this.hasFakeroot,
  });
}

/// Snapshot returned after checking all enabled update backends.
class UpdateCheckResult {
  final List<PendingUpdate> updates;
  final BackendAvailability backends;
  final List<String> errors;
  final DateTime checkedAt;

  const UpdateCheckResult({
    required this.updates,
    required this.backends,
    required this.errors,
    required this.checkedAt,
  });
}

/// Outcome of executing pending system/app updates.
class UpdateInstallResult {
  final bool success;
  final bool needsAuthentication;
  final List<String> errors;

  const UpdateInstallResult({
    required this.success,
    this.needsAuthentication = false,
    this.errors = const [],
  });
}

/// Shared service for checking, notifying, scheduling, and installing updates
/// across pacman/yay, Flatpak, and Snap.
class UpdateService {
  static String configPath({String? homeOverride}) {
    final home = homeOverride ?? Platform.environment['HOME'] ?? '';
    return '$home/.config/fyr/updates_config.json';
  }

  static Future<UpdatesConfig> loadConfig({String? homeOverride}) async {
    try {
      final file = File(configPath(homeOverride: homeOverride));
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map<String, dynamic>) {
          return UpdatesConfig.fromJson(decoded);
        }
      }
    } catch (_) {}
    return const UpdatesConfig();
  }

  static Future<void> saveConfig(
    UpdatesConfig config, {
    String? homeOverride,
  }) async {
    final path = configPath(homeOverride: homeOverride);
    await File(path).parent.create(recursive: true);
    await SwayConfD.writeFileAtomic(
      path,
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
  }

  static Future<bool> _hasBinary(String name) async {
    try {
      final res = await Process.run('which', [name]);
      return res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<BackendAvailability> detectBackends() async {
    final results = await Future.wait<bool>([
      _hasBinary('pacman'),
      _hasBinary('yay'),
      _hasBinary('flatpak'),
      _hasBinary('snap'),
      _hasBinary('checkupdates'),
      _hasBinary('fakeroot'),
    ]);
    return BackendAvailability(
      hasPacman: results[0],
      hasYay: results[1],
      hasFlatpak: results[2],
      hasSnap: results[3],
      hasCheckupdates: results[4],
      hasFakeroot: results[5],
    );
  }

  /// Parses `pacman -Qu` / `checkupdates` / `yay -Qu` output lines such as:
  /// `linux 6.12.1.arch1-1 -> 6.12.2.arch1-1`
  static List<PendingUpdate> parsePacmanQuOutput(
    String stdout, {
    UpdateSource source = UpdateSource.pacman,
  }) {
    final updates = <PendingUpdate>[];
    for (final rawLine in stdout.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('::')) continue;
      if (line.contains('[ignored]')) continue;
      final match = RegExp(r'^(\S+)\s+(\S+)\s+->\s+(\S+)').firstMatch(line);
      if (match != null) {
        updates.add(
          PendingUpdate(
            name: match.group(1)!,
            currentVersion: match.group(2)!,
            newVersion: match.group(3)!,
            source: source,
          ),
        );
      }
    }
    return updates;
  }

  /// Parses `flatpak remote-ls --updates --columns=application,name,version,branch`.
  static List<PendingUpdate> parseFlatpakUpdatesOutput(String stdout) {
    final updates = <PendingUpdate>[];
    for (final rawLine in stdout.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final cols = line.split('\t').map((c) => c.trim()).toList();
      final appId = cols.isNotEmpty ? cols[0] : '';
      if (appId.isEmpty) continue;
      final name = (cols.length > 1 && cols[1].isNotEmpty) ? cols[1] : appId;
      final version =
          (cols.length > 2 && cols[2].isNotEmpty) ? cols[2] : 'latest';
      final branch = (cols.length > 3 && cols[3].isNotEmpty) ? cols[3] : null;
      updates.add(
        PendingUpdate(
          name: name,
          currentVersion: branch ?? 'installed',
          newVersion: version,
          source: UpdateSource.flatpak,
          details: appId,
        ),
      );
    }
    return updates;
  }

  /// Parses `snap refresh --list` table lines cleanly.
  static List<PendingUpdate> parseSnapRefreshListOutput(String stdout) {
    final updates = <PendingUpdate>[];
    final lines = stdout.split('\n');
    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('Name ') && line.contains('Version')) continue;
      if (line.toLowerCase().contains('all snaps up to date')) continue;
      final cols = line.split(RegExp(r'\s+'));
      if (cols.length >= 2) {
        final name = cols[0];
        final version = cols[1];
        final rev = cols.length >= 3 ? 'rev ${cols[2]}' : 'installed';
        updates.add(
          PendingUpdate(
            name: name,
            currentVersion: rev,
            newVersion: version,
            source: UpdateSource.snap,
            details: cols.length >= 4 ? cols[3] : null,
          ),
        );
      }
    }
    return updates;
  }

  /// Formats a concise multi-backend summary suitable for desktop notifications.
  static String formatNotificationBody(List<PendingUpdate> updates) {
    if (updates.isEmpty) return 'Your system is up to date.';
    final counts = <UpdateSource, int>{};
    for (final u in updates) {
      counts[u.source] = (counts[u.source] ?? 0) + 1;
    }
    final parts = <String>[];
    for (final source in UpdateSource.values) {
      final c = counts[source] ?? 0;
      if (c > 0) {
        parts.add('$c ${source.label}');
      }
    }
    final preview = updates.take(3).map((u) => u.name).join(', ');
    final suffix = updates.length > 3 ? ', …' : '';
    return '${parts.join(' • ')}\n$preview$suffix';
  }

  static Future<bool> hasPasswordlessSudo() async {
    try {
      final res = await Process.run('sudo', ['-n', 'true']);
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<List<PendingUpdate>> _checkOfficialRepoUpdates(
    BackendAvailability backends,
    List<String> errors,
  ) async {
    if (!backends.hasPacman) return const [];

    if (backends.hasCheckupdates) {
      final res = await Process.run('checkupdates', []);
      if (res.exitCode == 0) {
        return parsePacmanQuOutput(res.stdout.toString());
      } else if (res.exitCode == 2) {
        return const [];
      }
    }

    // Rootless checkupdates equivalent using fakeroot + temporary DB path so we
    // never touch /var/lib/pacman/sync during background/unprivileged checks.
    if (backends.hasFakeroot && Directory('/var/lib/pacman/local').existsSync()) {
      Directory? tmpDb;
      try {
        tmpDb = Directory.systemTemp.createTempSync('fyr_pacman_check_');
        await Link('${tmpDb.path}/local').create('/var/lib/pacman/local');
        final syncDir = Directory('${tmpDb.path}/sync');
        await syncDir.create();
        final existingSync = Directory('/var/lib/pacman/sync');
        if (existingSync.existsSync()) {
          for (final f in existingSync.listSync().whereType<File>()) {
            if (f.path.endsWith('.db')) {
              final name = f.uri.pathSegments.last;
              await f.copy('${syncDir.path}/$name');
            }
          }
        }
        final syRes = await Process.run('fakeroot', [
          'pacman',
          '-Sy',
          '--dbpath',
          tmpDb.path,
          '--logfile',
          '/dev/null',
        ]);
        if (syRes.exitCode == 0) {
          final quRes = await Process.run('pacman', [
            '-Qu',
            '--dbpath',
            tmpDb.path,
          ]);
          if (quRes.exitCode == 0) {
            return parsePacmanQuOutput(quRes.stdout.toString());
          } else if (quRes.exitCode == 1) {
            return const [];
          }
        }
      } catch (e) {
        errors.add('Pacman check failed: $e');
      } finally {
        try {
          if (tmpDb != null && tmpDb.existsSync()) {
            tmpDb.deleteSync(recursive: true);
          }
        } catch (_) {}
      }
    }

    final fallback = await Process.run('pacman', ['-Qu']);
    if (fallback.exitCode == 0) {
      return parsePacmanQuOutput(fallback.stdout.toString());
    }
    return const [];
  }

  static Future<UpdateCheckResult> checkAllUpdates(UpdatesConfig config) async {
    final backends = await detectBackends();
    final updates = <PendingUpdate>[];
    final errors = <String>[];

    if (config.includePacmanAur && (backends.hasPacman || backends.hasYay)) {
      final repoUpdates = await _checkOfficialRepoUpdates(backends, errors);
      updates.addAll(repoUpdates);
      final repoNames = repoUpdates.map((u) => u.name).toSet();

      if (backends.hasYay) {
        try {
          final aurRes = await Process.run('yay', ['-Qua']);
          if (aurRes.exitCode == 0) {
            final aurUpdates = parsePacmanQuOutput(
              aurRes.stdout.toString(),
              source: UpdateSource.aur,
            );
            for (final u in aurUpdates) {
              if (!repoNames.contains(u.name)) {
                updates.add(u);
              }
            }
          }
        } catch (e) {
          errors.add('AUR check failed: $e');
        }
      }
    }

    if (config.includeFlatpak && backends.hasFlatpak) {
      try {
        final fpRes = await Process.run('flatpak', [
          'remote-ls',
          '--updates',
          '--columns=application,name,version,branch',
        ]);
        if (fpRes.exitCode == 0) {
          updates.addAll(parseFlatpakUpdatesOutput(fpRes.stdout.toString()));
        } else {
          final err = fpRes.stderr.toString().trim();
          if (err.isNotEmpty) errors.add('Flatpak: $err');
        }
      } catch (e) {
        errors.add('Flatpak check failed: $e');
      }
    }

    if (config.includeSnap && backends.hasSnap) {
      try {
        final snapRes = await Process.run('snap', ['refresh', '--list']);
        final out = snapRes.stdout.toString();
        final err = snapRes.stderr.toString();
        if (snapRes.exitCode == 0) {
          updates.addAll(parseSnapRefreshListOutput(out));
        } else if (!err.toLowerCase().contains('all snaps up to date')) {
          if (err.trim().isNotEmpty) errors.add('Snap: ${err.trim()}');
        }
      } catch (e) {
        errors.add('Snap check failed: $e');
      }
    }

    return UpdateCheckResult(
      updates: updates,
      backends: backends,
      errors: errors,
      checkedAt: DateTime.now(),
    );
  }

  /// Validates [password] via `sudo -S -v` without placing secrets in args.
  static Future<bool> validateSudoPassword(String password) async {
    try {
      final proc = await Process.start('sudo', ['-S', '-p', '', '-v']);
      proc.stdin.writeln(password);
      await proc.stdin.flush();
      await proc.stdin.close();
      return await proc.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<int> _runStreaming(
    String executable,
    List<String> args, {
    Map<String, String>? environment,
    void Function(String line)? onLog,
  }) async {
    onLog?.call('\$ $executable ${args.join(' ')}');
    final proc = await Process.start(
      executable,
      args,
      environment: environment,
    );
    final subOut = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => onLog?.call(line));
    final subErr = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => onLog?.call(line));
    final code = await proc.exitCode;
    await subOut.cancel();
    await subErr.cancel();
    return code;
  }

  /// Installs updates for enabled backends, optionally writing an ephemeral
  /// `SUDO_ASKPASS` helper when [sudoPassword] is supplied so `yay` and `snap`
  /// succeed cleanly without a TTY.
  static Future<UpdateInstallResult> installUpdates({
    required UpdatesConfig config,
    BackendAvailability? backends,
    String? sudoPassword,
    bool allowFlatpakOnlyIfUnauthenticated = false,
    void Function(String line)? onLog,
  }) async {
    final detected = backends ?? await detectBackends();
    final errors = <String>[];

    final needsRootBackend =
        (config.includePacmanAur && (detected.hasYay || detected.hasPacman)) ||
        (config.includeSnap && detected.hasSnap);

    bool canRunRoot = !needsRootBackend || await hasPasswordlessSudo();
    File? askpassFile;
    Map<String, String>? sudoEnv;

    try {
      if (needsRootBackend && !canRunRoot && sudoPassword != null &&
          sudoPassword.isNotEmpty) {
        final valid = await validateSudoPassword(sudoPassword);
        if (!valid) {
          return const UpdateInstallResult(
            success: false,
            needsAuthentication: true,
            errors: ['Incorrect sudo password.'],
          );
        }
        canRunRoot = true;

        // Create an ephemeral askpass helper strictly for `yay` / `sudo -A`
        // in case sudo ticket expires during long AUR builds.
        final tmpDir = Directory.systemTemp.createTempSync('fyr_askpass_');
        askpassFile = File('${tmpDir.path}/askpass.sh');
        final escaped = sudoPassword.replaceAll("'", "'\\''");
        await askpassFile.writeAsString("#!/bin/sh\nprintf '%s\\n' '$escaped'\n");
        await Process.run('chmod', ['700', askpassFile.path]);
        sudoEnv = <String, String>{
          ...Platform.environment,
          'SUDO_ASKPASS': askpassFile.path,
        };
      }

      if (config.includePacmanAur && (detected.hasYay || detected.hasPacman)) {
        if (!canRunRoot) {
          if (!allowFlatpakOnlyIfUnauthenticated) {
            return const UpdateInstallResult(
              success: false,
              needsAuthentication: true,
              errors: ['Administrator authentication required for system updates.'],
            );
          }
          onLog?.call('Skipping pacman/yay auto-update (authentication required).');
        } else if (detected.hasYay) {
          final code = await _runStreaming(
            'yay',
            [
              '-Syu',
              '--noconfirm',
              '--sudoflags',
              sudoEnv != null ? '-A' : '-n',
            ],
            environment: sudoEnv,
            onLog: onLog,
          );
          if (code != 0) {
            errors.add('yay exited with status $code');
          }
        } else {
          final code = await _runStreaming(
            'sudo',
            [sudoEnv != null ? '-A' : '-n', 'pacman', '-Syu', '--noconfirm'],
            environment: sudoEnv,
            onLog: onLog,
          );
          if (code != 0) {
            errors.add('pacman exited with status $code');
          }
        }
      }

      if (config.includeFlatpak && detected.hasFlatpak) {
        final code = await _runStreaming(
          'flatpak',
          ['update', '-y', '--noninteractive'],
          onLog: onLog,
        );
        if (code != 0) {
          errors.add('flatpak exited with status $code');
        }
      }

      if (config.includeSnap && detected.hasSnap) {
        if (!canRunRoot) {
          if (!allowFlatpakOnlyIfUnauthenticated) {
            return const UpdateInstallResult(
              success: false,
              needsAuthentication: true,
              errors: ['Administrator authentication required for Snap updates.'],
            );
          }
          onLog?.call('Skipping snap refresh (authentication required).');
        } else {
          final code = await _runStreaming(
            'sudo',
            [sudoEnv != null ? '-A' : '-n', 'snap', 'refresh'],
            environment: sudoEnv,
            onLog: onLog,
          );
          if (code != 0) {
            errors.add('snap refresh exited with status $code');
          }
        }
      }

      final needsAuthNotice =
          needsRootBackend && !canRunRoot && allowFlatpakOnlyIfUnauthenticated;
      return UpdateInstallResult(
        success: errors.isEmpty && !needsAuthNotice,
        needsAuthentication: needsAuthNotice,
        errors: errors,
      );
    } finally {
      try {
        if (askpassFile != null && askpassFile.parent.existsSync()) {
          askpassFile.parent.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
  }
}
