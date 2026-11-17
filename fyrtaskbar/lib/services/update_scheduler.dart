import 'dart:async';
import 'dart:io';

import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/state/system_state.dart';

/// Periodically checks for pacman/yay, Flatpak, and Snap updates in the
/// background, fires desktop notifications, and runs unattended auto-updates
/// when enabled in `~/.config/fyr/updates_config.json`.
class UpdateScheduler {
  static Timer? _initialTimer;
  static Timer? _periodicTimer;
  static StreamSubscription<FileSystemEvent>? _configSub;
  static bool _running = false;
  static String _lastNotifiedSignature = '';

  static void init() {
    dispose();
    _watchConfig();

    _initialTimer = Timer(const Duration(seconds: 20), () => _checkIfDue());
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _checkIfDue(),
    );
  }

  static void dispose() {
    _initialTimer?.cancel();
    _initialTimer = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _configSub?.cancel();
    _configSub = null;
  }

  static void _watchConfig() {
    try {
      final home = Platform.environment['HOME'] ?? '';
      if (home.isEmpty) return;
      final dir = Directory('$home/.config/fyr');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      _configSub = dir.watch().listen((event) {
        if (event.path.endsWith('updates_config.json')) {
          _checkIfDue();
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  static Future<void> _checkIfDue() async {
    if (_running) return;
    _running = true;
    try {
      final cfg = await UpdateService.loadConfig();
      if (!cfg.notificationsEnabled && !cfg.autoUpdateEnabled) return;

      final now = DateTime.now();
      if (cfg.lastCheckedAt != null &&
          now.difference(cfg.lastCheckedAt!).inHours < cfg.checkIntervalHours) {
        return;
      }

      await runCycle(cfg);
    } finally {
      _running = false;
    }
  }

  static Future<void> runCycle(UpdatesConfig cfg) async {
    final res = await UpdateService.checkAllUpdates(cfg);
    var nextCfg = cfg.copyWith(
      lastCheckedAt: res.checkedAt,
      clearLastError: res.errors.isEmpty,
      lastError: res.errors.isNotEmpty ? res.errors.join('; ') : null,
    );

    if (res.updates.isEmpty) {
      _lastNotifiedSignature = '';
      await UpdateService.saveConfig(nextCfg);
      return;
    }

    if (cfg.autoUpdateEnabled) {
      final installRes = await UpdateService.installUpdates(
        config: cfg,
        backends: res.backends,
        allowFlatpakOnlyIfUnauthenticated: true,
      );
      if (installRes.success) {
        nextCfg = nextCfg.copyWith(
          lastUpdatedAt: DateTime.now(),
          clearLastError: true,
        );
        await UpdateService.saveConfig(nextCfg);
        _lastNotifiedSignature = '';
        if (cfg.notificationsEnabled) {
          SystemState.addNotification(
            appName: 'System Updates',
            title: 'System Updated',
            body:
                'Installed ${res.updates.length} update${res.updates.length == 1 ? '' : 's'} automatically.',
            icon: 'system-software-update',
          );
        }
        return;
      }

      if (installRes.needsAuthentication) {
        await UpdateService.saveConfig(nextCfg);
        final sig = res.updates.map((u) => u.uniqueKey).join('|');
        if (cfg.notificationsEnabled && sig != _lastNotifiedSignature) {
          _lastNotifiedSignature = sig;
          SystemState.addNotification(
            appName: 'System Updates',
            title: 'Updates Ready (Authentication Needed)',
            body: UpdateService.formatNotificationBody(res.updates),
            icon: 'system-software-update',
            actions: const ['open_updates', 'Open Updates'],
          );
        }
        return;
      }

      if (installRes.errors.isNotEmpty) {
        nextCfg = nextCfg.copyWith(lastError: installRes.errors.join('; '));
        await UpdateService.saveConfig(nextCfg);
        if (cfg.notificationsEnabled) {
          SystemState.addNotification(
            appName: 'System Updates',
            title: 'Auto-Update Issue',
            body: installRes.errors.first,
            icon: 'dialog-warning',
            actions: const ['open_updates', 'Open Updates'],
          );
        }
        return;
      }
    }

    await UpdateService.saveConfig(nextCfg);
    if (cfg.notificationsEnabled) {
      final sig = res.updates.map((u) => u.uniqueKey).join('|');
      if (sig != _lastNotifiedSignature) {
        _lastNotifiedSignature = sig;
        SystemState.addNotification(
          appName: 'System Updates',
          title:
              '${res.updates.length} Update${res.updates.length == 1 ? '' : 's'} Available',
          body: UpdateService.formatNotificationBody(res.updates),
          icon: 'system-software-update',
          actions: const ['open_updates', 'Open Updates'],
        );
      }
    }
  }
}
