import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../fyr_theme.dart';

/// Configuration model and Sway config serializer/parser for touchpad settings.
class TouchpadSettingsConfig {
  static const String startMarker = '# TOUCHPAD SETTINGS';
  static const String endMarker = '# END TOUCHPAD SETTINGS';

  final bool tapToClick;
  final bool tapAndDrag;
  final bool naturalScroll;
  final bool disableWhileTyping;
  final double pointerSpeed;

  const TouchpadSettingsConfig({
    this.tapToClick = true,
    this.tapAndDrag = true,
    this.naturalScroll = false,
    this.disableWhileTyping = true,
    this.pointerSpeed = 0.0,
  });

  TouchpadSettingsConfig copyWith({
    bool? tapToClick,
    bool? tapAndDrag,
    bool? naturalScroll,
    bool? disableWhileTyping,
    double? pointerSpeed,
  }) {
    return TouchpadSettingsConfig(
      tapToClick: tapToClick ?? this.tapToClick,
      tapAndDrag: tapAndDrag ?? this.tapAndDrag,
      naturalScroll: naturalScroll ?? this.naturalScroll,
      disableWhileTyping: disableWhileTyping ?? this.disableWhileTyping,
      pointerSpeed: pointerSpeed ?? this.pointerSpeed,
    );
  }

  /// Renders the Sway `input "type:touchpad"` configuration block.
  List<String> toSwayConfigLines() {
    final accel = pointerSpeed.clamp(-1.0, 1.0).toStringAsFixed(2);
    return [
      startMarker,
      'input "type:touchpad" {',
      '    tap ${tapToClick ? "enabled" : "disabled"}',
      '    tap_button_map lrm',
      '    drag ${tapAndDrag ? "enabled" : "disabled"}',
      '    dwt ${disableWhileTyping ? "enabled" : "disabled"}',
      '    natural_scroll ${naturalScroll ? "enabled" : "disabled"}',
      '    pointer_accel $accel',
      '}',
      endMarker,
    ];
  }

  /// Parses `# TOUCHPAD SETTINGS` from [content], falling back to defaults.
  factory TouchpadSettingsConfig.fromSwayConfigContent(String content) {
    final lines = content.split('\n');
    bool inBlock = false;
    bool tap = true;
    bool tapDrag = true;
    bool natural = false;
    bool dwt = true;
    double accel = 0.0;

    for (final raw in lines) {
      final line = raw.trim();
      if (line == startMarker) {
        inBlock = true;
        continue;
      }
      if (line == endMarker) {
        inBlock = false;
        continue;
      }
      if (!inBlock) continue;
      if (line.startsWith('tap ')) {
        tap = line.endsWith('enabled');
      } else if (line.startsWith('drag ') || line.startsWith('tap_drag ')) {
        tapDrag = line.endsWith('enabled');
      } else if (line.startsWith('natural_scroll ')) {
        natural = line.endsWith('enabled');
      } else if (line.startsWith('dwt ')) {
        dwt = line.endsWith('enabled');
      } else if (line.startsWith('pointer_accel ')) {
        accel = double.tryParse(line.split(RegExp(r'\s+')).last) ?? 0.0;
      }
    }

    return TouchpadSettingsConfig(
      tapToClick: tap,
      tapAndDrag: tapDrag,
      naturalScroll: natural,
      disableWhileTyping: dwt,
      pointerSpeed: accel.clamp(-1.0, 1.0),
    );
  }

  /// Replaces or appends the `# TOUCHPAD SETTINGS` block inside [existingContent].
  static String upsertSwayConfigContent(
    String existingContent,
    TouchpadSettingsConfig config,
  ) {
    final lines = existingContent.split('\n');
    final filtered = <String>[];
    bool inBlock = false;

    for (final line in lines) {
      if (line.trim() == startMarker) {
        inBlock = true;
        continue;
      }
      if (line.trim() == endMarker) {
        inBlock = false;
        continue;
      }
      if (!inBlock) {
        filtered.add(line);
      }
    }

    while (filtered.isNotEmpty && filtered.last.trim().isEmpty) {
      filtered.removeLast();
    }

    filtered.addAll(config.toSwayConfigLines());
    return '${filtered.join('\n')}\n';
  }
}

class TouchpadPane extends StatefulWidget {
  final Future<({TouchpadSettingsConfig config, String? deviceName})>
      Function()? loadState;
  final Future<void> Function(TouchpadSettingsConfig config)? onApplyConfig;

  const TouchpadPane({
    super.key,
    this.loadState,
    this.onApplyConfig,
  });

  @override
  State<TouchpadPane> createState() => _TouchpadPaneState();
}

class _TouchpadPaneState extends State<TouchpadPane> {
  TouchpadSettingsConfig _config = const TouchpadSettingsConfig();
  String? _deviceName;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTouchpadState();
  }

  String get _swayConfigPath =>
      '${Platform.environment['HOME'] ?? ''}/.config/sway/config';

  Future<void> _loadTouchpadState() async {
    if (widget.loadState != null) {
      final result = await widget.loadState!();
      if (!mounted) return;
      setState(() {
        _config = result.config;
        _deviceName = result.deviceName;
        _loading = false;
      });
      return;
    }

    TouchpadSettingsConfig loaded = const TouchpadSettingsConfig();
    String? detectedName;

    try {
      final configFile = File(_swayConfigPath);
      if (await configFile.exists()) {
        loaded = TouchpadSettingsConfig.fromSwayConfigContent(
          await configFile.readAsString(),
        );
      }
    } catch (_) {}

    try {
      final res = await Process.run('swaymsg', ['-t', 'get_inputs'])
          .timeout(const Duration(seconds: 2));
      if (res.exitCode == 0) {
        final inputs = jsonDecode(res.stdout as String);
        if (inputs is List) {
          for (final item in inputs) {
            if (item is Map && item['type'] == 'touchpad') {
              detectedName = item['name'] as String?;
              final libinput = item['libinput'];
              if (libinput is Map) {
                loaded = TouchpadSettingsConfig(
                  tapToClick: libinput['tap'] == 'enabled',
                  tapAndDrag: libinput['tap_drag'] != 'disabled',
                  naturalScroll: libinput['natural_scroll'] == 'enabled',
                  disableWhileTyping: libinput['dwt'] != 'disabled',
                  pointerSpeed:
                      (libinput['accel_speed'] as num?)?.toDouble() ??
                      loaded.pointerSpeed,
                );
              }
              break;
            }
          }
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _config = loaded;
      _deviceName = detectedName;
      _loading = false;
    });
  }

  Future<void> _updateConfig(TouchpadSettingsConfig next) async {
    setState(() => _config = next);

    if (widget.onApplyConfig != null) {
      await widget.onApplyConfig!(next);
      return;
    }

    try {
      final accel = next.pointerSpeed.clamp(-1.0, 1.0).toStringAsFixed(2);
      await Process.run('swaymsg', [
        'input',
        'type:touchpad',
        'tap',
        next.tapToClick ? 'enabled' : 'disabled',
        'tap_button_map',
        'lrm',
        'drag',
        next.tapAndDrag ? 'enabled' : 'disabled',
        'dwt',
        next.disableWhileTyping ? 'enabled' : 'disabled',
        'natural_scroll',
        next.naturalScroll ? 'enabled' : 'disabled',
        'pointer_accel',
        accel,
      ]).timeout(const Duration(seconds: 2));
    } catch (_) {}

    try {
      final configFile = File(_swayConfigPath);
      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final updated = TouchpadSettingsConfig.upsertSwayConfigContent(
          content,
          next,
        );
        await configFile.writeAsString(updated);
      }
    } catch (_) {}
  }

  Widget _buildToggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
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
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  color: FyrTheme.textColorMuted,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeThumbColor: FyrTheme.accentColor,
          onChanged: onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mouse & Touchpad',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: FyrTheme.textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _deviceName != null
                ? 'Active touchpad: $_deviceName'
                : 'Configure touchpad gestures, tap-to-click, and pointer behavior',
            style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 14),
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            Text(
              'Touchpad Behavior',
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
                    _buildToggleRow(
                      title: 'Tap to Click',
                      subtitle:
                          'Tap with one finger to left-click, two fingers to right-click, and three fingers to middle-click.',
                      value: _config.tapToClick,
                      onChanged: (val) =>
                          _updateConfig(_config.copyWith(tapToClick: val)),
                    ),
                    Divider(color: FyrTheme.dividerColor, height: 28),
                    _buildToggleRow(
                      title: 'Tap and Drag',
                      subtitle:
                          'Double-tap and hold on the touchpad to drag windows or select text.',
                      value: _config.tapAndDrag,
                      onChanged: (val) =>
                          _updateConfig(_config.copyWith(tapAndDrag: val)),
                    ),
                    Divider(color: FyrTheme.dividerColor, height: 28),
                    _buildToggleRow(
                      title: 'Natural Scrolling',
                      subtitle:
                          'Invert two-finger scroll direction to match touchscreen scrolling.',
                      value: _config.naturalScroll,
                      onChanged: (val) =>
                          _updateConfig(_config.copyWith(naturalScroll: val)),
                    ),
                    Divider(color: FyrTheme.dividerColor, height: 28),
                    _buildToggleRow(
                      title: 'Disable Touchpad While Typing',
                      subtitle:
                          'Prevent accidental palm taps and cursor jumps when typing.',
                      value: _config.disableWhileTyping,
                      onChanged: (val) => _updateConfig(
                        _config.copyWith(disableWhileTyping: val),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Pointer Speed',
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Touchpad Pointer Acceleration',
                          style: TextStyle(
                            color: FyrTheme.textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          _config.pointerSpeed.toStringAsFixed(2),
                          style: TextStyle(
                            color: FyrTheme.accentColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _config.pointerSpeed.clamp(-1.0, 1.0),
                      min: -1.0,
                      max: 1.0,
                      divisions: 20,
                      activeColor: FyrTheme.accentColor,
                      onChanged: (val) =>
                          _updateConfig(_config.copyWith(pointerSpeed: val)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

