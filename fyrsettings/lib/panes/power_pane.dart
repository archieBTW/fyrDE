import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../fyr_theme.dart';

/// Immutable representation of Power & Screen Lock settings, with pure
/// helpers for generating `swayidle` arguments and `conf.d/40-power.conf`.
class PowerLockConfig {
  final bool screenLockEnabled;
  final bool lockOnLidClose;
  final bool lockBeforeSleep;
  final bool autoLockOnIdle;
  final int lockTimeoutMinutes;
  final int dimMinutes;
  final int offMinutes;
  final int sleepMinutes;

  const PowerLockConfig({
    this.screenLockEnabled = true,
    this.lockOnLidClose = true,
    this.lockBeforeSleep = true,
    this.autoLockOnIdle = false,
    this.lockTimeoutMinutes = 5,
    this.dimMinutes = 0,
    this.offMinutes = 0,
    this.sleepMinutes = 0,
  });

  PowerLockConfig copyWith({
    bool? screenLockEnabled,
    bool? lockOnLidClose,
    bool? lockBeforeSleep,
    bool? autoLockOnIdle,
    int? lockTimeoutMinutes,
    int? dimMinutes,
    int? offMinutes,
    int? sleepMinutes,
  }) {
    return PowerLockConfig(
      screenLockEnabled: screenLockEnabled ?? this.screenLockEnabled,
      lockOnLidClose: lockOnLidClose ?? this.lockOnLidClose,
      lockBeforeSleep: lockBeforeSleep ?? this.lockBeforeSleep,
      autoLockOnIdle: autoLockOnIdle ?? this.autoLockOnIdle,
      lockTimeoutMinutes: lockTimeoutMinutes ?? this.lockTimeoutMinutes,
      dimMinutes: dimMinutes ?? this.dimMinutes,
      offMinutes: offMinutes ?? this.offMinutes,
      sleepMinutes: sleepMinutes ?? this.sleepMinutes,
    );
  }

  /// True when screen locking is restricted to manual lock (`Super+L`) and
  /// closing the laptop lid (no inactivity timeout).
  bool get isLidCloseOnlyMode =>
      screenLockEnabled && lockOnLidClose && !autoLockOnIdle;

  /// Builds the CLI arguments for `swayidle`. Returns only `['-w']` when no
  /// `swayidle` actions are active.
  List<String> buildSwayIdleArgs({required String lockCommand}) {
    final args = <String>['-w'];

    if (screenLockEnabled && autoLockOnIdle && lockTimeoutMinutes > 0) {
      args.addAll([
        'timeout',
        '${lockTimeoutMinutes * 60}',
        lockCommand,
      ]);
    }
    if (dimMinutes > 0) {
      args.addAll([
        'timeout',
        '${dimMinutes * 60}',
        'brightnessctl -s set 10%',
        'resume',
        'brightnessctl -r',
      ]);
    }
    if (offMinutes > 0) {
      args.addAll([
        'timeout',
        '${offMinutes * 60}',
        'swaymsg "output * power off"',
        'resume',
        'swaymsg "output * power on"',
      ]);
    }
    if (sleepMinutes > 0) {
      args.addAll([
        'timeout',
        '${sleepMinutes * 60}',
        'systemctl suspend',
      ]);
    }
    if (screenLockEnabled && lockBeforeSleep) {
      args.addAll(['before-sleep', lockCommand]);
    }

    return args;
  }

  /// Renders `~/.config/sway/conf.d/40-power.conf` content.
  String renderDropIn({String lockCommand = '~/.config/fyr/lock.sh'}) {
    final lines = <String>[];

    if (screenLockEnabled && lockOnLidClose) {
      lines.add('bindswitch --reload --locked lid:on exec $lockCommand');
    }

    final idleArgs = buildSwayIdleArgs(lockCommand: lockCommand);
    if (idleArgs.length > 1) {
      final formatted = idleArgs
          .map((a) => a.contains(' ') || a.contains('~') ? "'$a'" : a)
          .join(' ');
      lines.add('exec swayidle $formatted');
    }

    if (lines.isEmpty) {
      return '';
    }

    return '# POWER & SCREEN LOCK SETTINGS\n'
        '${lines.join('\n')}\n'
        '# END POWER & SCREEN LOCK SETTINGS\n';
  }
}

class PowerPane extends StatefulWidget {
  const PowerPane({super.key});

  @override
  State<PowerPane> createState() => _PowerPaneState();
}

class _PowerPaneState extends State<PowerPane> {
  Map<String, String> _powerInfo = {};
  bool _loading = true;
  PowerLockConfig _config = const PowerLockConfig();

  static const _lockTimeoutOptions = [1, 2, 5, 10, 15, 30, 60];
  static const _dimOptions = [0, 1, 2, 5, 10, 15, 30];
  static const _offOptions = [0, 2, 5, 10, 15, 30, 60];
  static const _sleepOptions = [0, 5, 10, 15, 30, 60, 120];

  String get _resolvedLockScript {
    final home = Platform.environment['HOME'] ?? '';
    return home.isNotEmpty ? '$home/.config/fyr/lock.sh' : '~/.config/fyr/lock.sh';
  }

  @override
  void initState() {
    super.initState();
    _loadPower();
    _loadSettings();
  }

  Future<void> _loadPower() async {
    setState(() => _loading = true);
    try {
      final enumResult = await Process.run('upower', ['-e']);
      final paths = (enumResult.stdout as String)
          .split('\n')
          .where((l) => l.contains('BAT') || l.contains('DisplayDevice'));

      if (paths.isNotEmpty) {
        final infoResult = await Process.run('upower', ['-i', paths.first]);
        final lines = (infoResult.stdout as String).split('\n');

        final info = <String, String>{};
        for (var line in lines) {
          final parts = line.split(':');
          if (parts.length >= 2) {
            final key = parts[0].trim();
            final value = parts.sublist(1).join(':').trim();
            if (key.isNotEmpty && value.isNotEmpty) {
              info[key] = value;
            }
          }
        }
        if (mounted) {
          setState(() {
            _powerInfo = info;
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLockTimeout = prefs.getInt('power_lock_timeout_min') ?? 5;
    if (!mounted) return;
    setState(() {
      _config = PowerLockConfig(
        screenLockEnabled: prefs.getBool('power_screen_lock_enabled') ?? true,
        lockOnLidClose: prefs.getBool('power_lock_on_lid_close') ?? true,
        lockBeforeSleep: prefs.getBool('power_lock_before_sleep') ?? true,
        autoLockOnIdle: prefs.getBool('power_auto_lock_on_idle') ?? false,
        lockTimeoutMinutes: _lockTimeoutOptions.contains(savedLockTimeout)
            ? savedLockTimeout
            : 5,
        dimMinutes: prefs.getInt('power_dim_min') ?? 0,
        offMinutes: prefs.getInt('power_off_min') ?? 0,
        sleepMinutes: prefs.getInt('power_sleep_min') ?? 0,
      );
    });
  }

  Future<void> _updateConfig(PowerLockConfig next) async {
    setState(() => _config = next);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('power_screen_lock_enabled', next.screenLockEnabled);
    await prefs.setBool('power_lock_on_lid_close', next.lockOnLidClose);
    await prefs.setBool('power_lock_before_sleep', next.lockBeforeSleep);
    await prefs.setBool('power_auto_lock_on_idle', next.autoLockOnIdle);
    await prefs.setInt('power_lock_timeout_min', next.lockTimeoutMinutes);
    await prefs.setInt('power_dim_min', next.dimMinutes);
    await prefs.setInt('power_off_min', next.offMinutes);
    await prefs.setInt('power_sleep_min', next.sleepMinutes);

    await _applyPowerAndLock(next);
  }

  Future<void> _applyPowerAndLock(PowerLockConfig cfg) async {
    // Restart swayidle cleanly with updated rules
    try {
      await Process.run('pkill', ['-x', 'swayidle']);
    } catch (_) {}

    final liveArgs = cfg.buildSwayIdleArgs(lockCommand: _resolvedLockScript);
    if (liveArgs.length > 1) {
      try {
        await Process.start(
          'swayidle',
          liveArgs,
          mode: ProcessStartMode.detached,
        );
      } catch (_) {}
    }

    // Apply lid-close binding live in the running Sway session
    try {
      if (cfg.screenLockEnabled && cfg.lockOnLidClose) {
        await Process.run('swaymsg', [
          'bindswitch --reload --locked lid:on exec $_resolvedLockScript',
        ]);
      } else {
        await Process.run('swaymsg', ['unbindswitch --locked lid:on']);
        await Process.run('swaymsg', ['unbindswitch lid:on']);
      }
    } catch (_) {}

    await SwayConfD.removeLegacyMarkerBlock(
      '# POWER SETTINGS',
      '# END POWER SETTINGS',
    );
    await SwayConfD.removeLegacyMarkerBlock(
      '# POWER & SCREEN LOCK SETTINGS',
      '# END POWER & SCREEN LOCK SETTINGS',
    );

    final powerContent = cfg.renderDropIn();
    await SwayConfD.writeDropIn('40-power.conf', powerContent, reload: false);
  }

  Future<void> _lockNow() async {
    try {
      await Process.start(
        _resolvedLockScript,
        const [],
        mode: ProcessStartMode.detached,
      );
    } catch (_) {}
  }

  String _lockStatusSummary() {
    if (!_config.screenLockEnabled) {
      return 'Automatic screen lock is disabled (Super + L still locks manually).';
    }
    final triggers = <String>[];
    if (_config.autoLockOnIdle) {
      triggers.add('after ${_config.lockTimeoutMinutes} min idle');
    }
    if (_config.lockOnLidClose) {
      triggers.add('when laptop lid closes');
    }
    if (_config.lockBeforeSleep) {
      triggers.add('before sleep');
    }
    if (triggers.isEmpty) {
      return 'Manual lock only (Super + L).';
    }
    return 'Locks automatically ${triggers.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final percentage = _powerInfo['percentage'] ?? 'Unknown';
    final state = _powerInfo['state'] ?? 'Unknown';
    final timeToEmpty = _powerInfo['time to empty'];
    final timeToFull = _powerInfo['time to full'];

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Power & Screen Lock',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: FyrTheme.textColor,
            ),
          ),
          const SizedBox(height: 24),

          // Screen Lock Settings
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Screen Lock',
                style: TextStyle(
                  color: FyrTheme.textColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton.icon(
                onPressed: _lockNow,
                icon: Icon(Icons.lock_outline, size: 18, color: FyrTheme.accentColor),
                label: Text(
                  'Lock Now',
                  style: TextStyle(color: FyrTheme.accentColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            color: FyrTheme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: FyrTheme.isDark
                  ? BorderSide.none
                  : BorderSide(color: FyrTheme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSwitchRow(
                    title: 'Enable automatic screen lock',
                    subtitle: _lockStatusSummary(),
                    value: _config.screenLockEnabled,
                    onChanged: (val) => _updateConfig(
                      _config.copyWith(screenLockEnabled: val),
                    ),
                  ),
                  Divider(color: FyrTheme.dividerColor, height: 24),
                  Opacity(
                    opacity: _config.screenLockEnabled ? 1.0 : 0.45,
                    child: Column(
                      children: [
                        _buildSwitchRow(
                          title: 'Lock when laptop lid closes',
                          subtitle:
                              'Locks immediately whenever you close the lid',
                          value: _config.lockOnLidClose,
                          onChanged: _config.screenLockEnabled
                              ? (val) => _updateConfig(
                                    _config.copyWith(lockOnLidClose: val),
                                  )
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _buildSwitchRow(
                          title: 'Lock before system sleep',
                          subtitle:
                              'Ensures the screen is locked when waking from suspend',
                          value: _config.lockBeforeSleep,
                          onChanged: _config.screenLockEnabled
                              ? (val) => _updateConfig(
                                    _config.copyWith(lockBeforeSleep: val),
                                  )
                              : null,
                        ),
                        const SizedBox(height: 12),
                        _buildSwitchRow(
                          title: 'Auto-lock on inactivity',
                          subtitle:
                              'Turn off to only lock manually (Super + L) or on lid close',
                          value: _config.autoLockOnIdle,
                          onChanged: _config.screenLockEnabled
                              ? (val) => _updateConfig(
                                    _config.copyWith(autoLockOnIdle: val),
                                  )
                              : null,
                        ),
                        if (_config.autoLockOnIdle) ...[
                          const SizedBox(height: 12),
                          _buildDropdown(
                            'Lock screen after',
                            _config.lockTimeoutMinutes,
                            _lockTimeoutOptions,
                            _config.screenLockEnabled
                                ? (val) {
                                    if (val != null) {
                                      _updateConfig(
                                        _config.copyWith(
                                          lockTimeoutMinutes: val,
                                        ),
                                      );
                                    }
                                  }
                                : null,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Auto-Sleep & Display Settings
          Text(
            'Auto-Sleep & Display',
            style: TextStyle(
              color: FyrTheme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: FyrTheme.cardColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: FyrTheme.isDark
                  ? BorderSide.none
                  : BorderSide(color: FyrTheme.dividerColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  _buildDropdown(
                    'Dim display after',
                    _config.dimMinutes,
                    _dimOptions,
                    (val) {
                      if (val != null) {
                        _updateConfig(_config.copyWith(dimMinutes: val));
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildDropdown(
                    'Turn off display after',
                    _config.offMinutes,
                    _offOptions,
                    (val) {
                      if (val != null) {
                        _updateConfig(_config.copyWith(offMinutes: val));
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildDropdown(
                    'Put system to sleep after',
                    _config.sleepMinutes,
                    _sleepOptions,
                    (val) {
                      if (val != null) {
                        _updateConfig(_config.copyWith(sleepMinutes: val));
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),
          Text(
            'Battery Status',
            style: TextStyle(
              color: FyrTheme.textColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_powerInfo.isEmpty)
            Center(
              child: Text(
                'No battery information found',
                style: TextStyle(color: FyrTheme.textColorMuted),
              ),
            )
          else
            Card(
              color: FyrTheme.cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: FyrTheme.isDark
                    ? BorderSide.none
                    : BorderSide(color: FyrTheme.dividerColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          state.toLowerCase().contains('charging')
                              ? Icons.battery_charging_full
                              : Icons.battery_full,
                          color: FyrTheme.accentColor,
                          size: 40,
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              percentage,
                              style: TextStyle(
                                color: FyrTheme.textColor,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              state,
                              style: TextStyle(
                                color: FyrTheme.textColorMuted,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    if (timeToEmpty != null)
                      _buildProp('Time to empty', timeToEmpty),
                    if (timeToEmpty != null) const SizedBox(height: 12),
                    if (timeToFull != null)
                      _buildProp('Time to full', timeToFull),
                    if (timeToFull != null) const SizedBox(height: 12),
                    _buildProp('Vendor', _powerInfo['vendor'] ?? 'Unknown'),
                    const SizedBox(height: 12),
                    _buildProp('Model', _powerInfo['model'] ?? 'Unknown'),
                    const SizedBox(height: 12),
                    _buildProp('Capacity', _powerInfo['capacity'] ?? 'Unknown'),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: FyrTheme.textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: FyrTheme.textColorMuted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Switch(
          value: value,
          activeTrackColor: FyrTheme.accentColor,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildDropdown(
    String label,
    int currentValue,
    List<int> options,
    ValueChanged<int?>? onChanged,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 16),
        ),
        DropdownButton<int>(
          value: currentValue,
          dropdownColor: FyrTheme.surfaceColor,
          style: TextStyle(color: FyrTheme.textColor, fontSize: 16),
          underline: Container(),
          icon: Icon(Icons.arrow_drop_down, color: FyrTheme.accentColor),
          items: options.map((int value) {
            final text = value == 0
                ? 'Never'
                : (value == 1 ? '1 minute' : '$value minutes');
            return DropdownMenuItem<int>(
              value: value,
              child: Text(text),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildProp(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 16),
        ),
        Text(
          value,
          style: TextStyle(
            color: FyrTheme.textColor,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
