import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/state/system_state.dart';
import 'package:fyrtaskbar/ui/quick_toggle.dart';
import 'package:fyrtaskbar/ui/screenshot_button.dart';
import 'package:fyrtaskbar/ui/slider_row.dart';
import 'package:intl/intl.dart';

enum QuickSettingsMenu { main, wifi, bluetooth, screenshot, audio }

class QuickSettingsPopup extends StatefulWidget {
  final VoidCallback onClose;
  const QuickSettingsPopup({super.key, required this.onClose});

  @override
  State<QuickSettingsPopup> createState() => _QuickSettingsPopupState();
}

class _QuickSettingsPopupState extends State<QuickSettingsPopup>
    with SingleTickerProviderStateMixin {
  QuickSettingsMenu _currentMenu = QuickSettingsMenu.main;
  double _brightness = 0.5;
  double _volume = 0.5;
  bool _wifiEnabled = true;
  bool _bluetoothEnabled = true;
  bool _nightLightEnabled = false;
  bool _airplaneModeEnabled = false;
  bool _dockAutohideEnabled = false;
  bool _isRecording = false;

  List<Map<String, String>> _wifiNetworks = [];
  List<Map<String, String>> _btDevices = [];
  bool _isScanning = false;

  List<dynamic> _sinks = [];
  List<dynamic> _sources = [];
  String _defaultSink = '';
  String _defaultSource = '';

  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0.0, -1.0), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutQuart,
          ),
        );
    _animationController.forward();

    _brightness = SystemState.brightness.value;
    _volume = SystemState.volume.value;
    _wifiEnabled = SystemState.wifiSsid.value != null;
    _bluetoothEnabled = SystemState.bluetoothEnabled.value;
    _nightLightEnabled = SystemState.nightLight.value;
    _airplaneModeEnabled = SystemState.airplaneMode.value;
    _dockAutohideEnabled = SystemState.dockAutohide.value;
    _isRecording = SystemState.isRecording.value;
    _checkRecordingStatus();

    SystemState.brightness.addListener(_onStateChange);
    SystemState.bluetoothEnabled.addListener(_onStateChange);
    SystemState.volume.addListener(_onStateChange);
    SystemState.nightLight.addListener(_onStateChange);
    SystemState.wifiSsid.addListener(_onStateChange);
    SystemState.airplaneMode.addListener(_onStateChange);
    SystemState.isRecording.addListener(_onStateChange);
    SystemState.dockAutohide.addListener(_onStateChange);
  }

  @override
  void dispose() {
    _animationController.dispose();
    SystemState.brightness.removeListener(_onStateChange);
    SystemState.bluetoothEnabled.removeListener(_onStateChange);
    SystemState.volume.removeListener(_onStateChange);
    SystemState.nightLight.removeListener(_onStateChange);
    SystemState.wifiSsid.removeListener(_onStateChange);
    SystemState.airplaneMode.removeListener(_onStateChange);
    SystemState.isRecording.removeListener(_onStateChange);
    SystemState.dockAutohide.removeListener(_onStateChange);
    super.dispose();
  }

  void _onStateChange() {
    if (mounted) {
      setState(() {
        _brightness = SystemState.brightness.value;
        _volume = SystemState.volume.value;
        _nightLightEnabled = SystemState.nightLight.value;
        _wifiEnabled = SystemState.wifiSsid.value != null;
        _bluetoothEnabled = SystemState.bluetoothEnabled.value;
        _airplaneModeEnabled = SystemState.airplaneMode.value;
        _isRecording = SystemState.isRecording.value;
        _dockAutohideEnabled = SystemState.dockAutohide.value;
      });
    }
  }

  void _runCmd(String cmd, List<String> args) {
    Process.start(cmd, args, mode: ProcessStartMode.detached);
  }

  void _toggleWifi() {
    setState(() => _wifiEnabled = !_wifiEnabled);
    _runCmd('nmcli', ['radio', 'wifi', _wifiEnabled ? 'on' : 'off']);
  }

  void _toggleBluetooth() {
    if (!_bluetoothEnabled) {
      _runCmd('rfkill', ['unblock', 'bluetooth']);
    }
    _runCmd('bluetoothctl', ['power', !_bluetoothEnabled ? 'on' : 'off']);
    setState(() => _bluetoothEnabled = !_bluetoothEnabled);
  }

  void _toggleNightLight() {
    setState(() => _nightLightEnabled = !_nightLightEnabled);
    if (_nightLightEnabled) {
      _runCmd('wlsunset', ['-T', '5000', '-t', '3000']);
    } else {
      _runCmd('killall', ['wlsunset']);
    }
  }

  void _toggleAirplaneMode() {
    setState(() => _airplaneModeEnabled = !_airplaneModeEnabled);
    if (_airplaneModeEnabled) {
      _runCmd('rfkill', ['block', 'all']);
    } else {
      _runCmd('rfkill', ['unblock', 'all']);
    }
  }

  void _checkRecordingStatus() async {
    final result = await Process.run('pgrep', ['wf-recorder']);
    if (mounted) {
      setState(() => _isRecording = result.exitCode == 0);
    }
  }

  void _takeScreenshot(bool cropped) async {
    widget.onClose();
    await Future.delayed(const Duration(milliseconds: 200));

    final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final directory = Directory(
      '${Platform.environment['HOME']}/Pictures/screenshots',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    final filePath = '${directory.path}/screenshot_$timestamp.png';

    List<String> args = [];
    if (cropped) {
      final slurpResult = await Process.run('slurp', []);
      if (slurpResult.exitCode != 0) return;
      args = ['-g', slurpResult.stdout.toString().trim(), filePath];
    } else {
      args = [filePath];
    }

    final result = await Process.run('grim', args);
    if (result.exitCode == 0) {
      Process.run('canberra-gtk-play', ['-i', 'screen-capture']);
      Process.run('sh', ['-c', 'wl-copy < "$filePath"']);
      Process.run('notify-send', [
        'Screenshot Taken',
        'Saved to Pictures/screenshots',
        '-i',
        filePath,
      ]);
    }
  }

  void _toggleRecording() async {
    if (_isRecording) {
      await Process.run('killall', ['-s', 'SIGINT', 'wf-recorder']);
      if (mounted) setState(() => _isRecording = false);
      SystemState.isRecording.value = false;
      Process.run('notify-send', [
        'Recording Stopped',
        'Video saved to Videos/recordings',
      ]);
    } else {
      widget.onClose();
      await Future.delayed(const Duration(milliseconds: 200));

      final timestamp = DateFormat(
        'yyyy-MM-dd_HH-mm-ss',
      ).format(DateTime.now());
      final directory = Directory(
        '${Platform.environment['HOME']}/Videos/recordings',
      );
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      final filePath = '${directory.path}/recording_$timestamp.mp4';

      Process.start('wf-recorder', ['-f', filePath]).then((p) {
        p.stdout.listen((_) {});
        p.stderr.listen((_) {});
      });
      if (mounted) setState(() => _isRecording = true);
      SystemState.isRecording.value = true;
      Process.run('notify-send', ['Recording Started', 'Capturing screen...']);
    }
  }

  void _toggleDockAutohide() async {
    final file = File(
      '${Platform.environment['HOME']}/.config/fyrdock/config.json',
    );
    bool newVal = !SystemState.dockAutohide.value;
    SystemState.dockAutohide.value = newVal;
    Map<String, dynamic> data = {};
    if (await file.exists()) {
      try {
        data = jsonDecode(await file.readAsString());
      } catch (_) {}
    } else {
      await file.create(recursive: true);
    }
    data['autohide'] = newVal;
    await file.writeAsString(jsonEncode(data));
  }

  void _setBrightness(double value) {
    setState(() => _brightness = value);
    final percent = (value * 100).toInt();
    _runCmd('brightnessctl', ['set', '$percent%']);
  }

  void _setVolume(double value) {
    setState(() => _volume = value);
    final percent = (value * 100).toInt();
    _runCmd('wpctl', ['set-volume', '@DEFAULT_AUDIO_SINK@', '$percent%']);
  }

  void _playVolumeSound() {
    _runCmd('canberra-gtk-play', ['-i', 'audio-volume-change']);
  }

  Future<void> _scanWifi() async {
    setState(() {
      _isScanning = true;
      _currentMenu = QuickSettingsMenu.wifi;
    });
    try {
      final result = await Process.run('nmcli', [
        '-t',
        '-f',
        'ssid,signal,security',
        'dev',
        'wifi',
      ]);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().split('\n');
        final networks = <Map<String, String>>[];
        final seenSsids = <String>{};
        for (var line in lines) {
          final parts = line.split(':');
          if (parts.length >= 2 && parts[0].isNotEmpty) {
            if (seenSsids.contains(parts[0])) continue;
            seenSsids.add(parts[0]);
            networks.add({
              'ssid': parts[0],
              'signal': parts[1],
              'security': parts.length > 2 ? parts[2] : '',
            });
          }
        }
        setState(() => _wifiNetworks = networks);
      }
    } finally {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _scanBluetooth() async {
    setState(() {
      _isScanning = true;
      _currentMenu = QuickSettingsMenu.bluetooth;
    });
    try {
      await Process.run('bluetoothctl', ['--timeout', '5', 'scan', 'on']);
      final result = await Process.run('bluetoothctl', ['devices']);
      if (result.exitCode == 0) {
        final lines = result.stdout.toString().trim().split('\n');
        final devices = <Map<String, String>>[];
        for (var line in lines) {
          final parts = line.split(' ');
          if (parts.length >= 3) {
            devices.add({
              'address': parts[1],
              'name': parts.sublist(2).join(' '),
            });
          }
        }
        setState(() => _btDevices = devices);
      }
    } finally {
      setState(() => _isScanning = false);
    }
  }

  void _connectWifi(String ssid, [String? password]) {
    if (password != null && password.isNotEmpty) {
      _runCmd('nmcli', ['dev', 'wifi', 'connect', ssid, 'password', password]);
    } else {
      _runCmd('nmcli', ['dev', 'wifi', 'connect', ssid]);
    }
    setState(() => _currentMenu = QuickSettingsMenu.main);
  }

  Future<void> _loadAudioDevices() async {
    setState(() => _isScanning = true);
    try {
      final sinksRes = await Process.run('pactl', [
        '-f',
        'json',
        'list',
        'sinks',
      ]);
      final sourcesRes = await Process.run('pactl', [
        '-f',
        'json',
        'list',
        'sources',
      ]);

      final defaultSinkRes = await Process.run('pactl', ['get-default-sink']);
      final defaultSourceRes = await Process.run('pactl', [
        'get-default-source',
      ]);

      if (mounted) {
        setState(() {
          _sinks = jsonDecode(sinksRes.stdout);
          _sources = (jsonDecode(sourcesRes.stdout) as List)
              .where((s) => !s['name'].toString().contains('.monitor'))
              .toList();
          _defaultSink = defaultSinkRes.stdout.toString().trim();
          _defaultSource = defaultSourceRes.stdout.toString().trim();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  void _setDefaultSink(String name) {
    Process.run('pactl', ['set-default-sink', name]);
    setState(() => _defaultSink = name);
  }

  void _setDefaultSource(String name) {
    Process.run('pactl', ['set-default-source', name]);
    setState(() => _defaultSource = name);
  }

  void _showWifiPasswordDialog(String ssid) {
    final TextEditingController _passwordController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: FyrTheme.bgColor,
          title: Text(
            'Connect to $ssid',
            style: TextStyle(color: FyrTheme.textColor),
          ),
          content: TextField(
            controller: _passwordController,
            obscureText: true,
            style: TextStyle(color: FyrTheme.textColor),
            decoration: InputDecoration(
              hintText: 'Password',
              hintStyle: TextStyle(color: FyrTheme.textColorMuted),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: FyrTheme.cardColor),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: FyrTheme.accentColor),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancel',
                style: TextStyle(color: FyrTheme.textColorMuted),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _connectWifi(ssid, _passwordController.text);
              },
              child: Text(
                'Connect',
                style: TextStyle(color: FyrTheme.accentColor),
              ),
            ),
          ],
        );
      },
    );
  }

  void _connectBluetooth(String address) {
    _runCmd('bluetoothctl', ['connect', address]);
    setState(() => _currentMenu = QuickSettingsMenu.main);
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        width: 472,
        decoration: BoxDecoration(
          color: FyrTheme.bgColor,
          borderRadius: BorderRadius.only(bottomLeft: Radius.circular(16)),
          border: Border.all(color: FyrTheme.cardColor),
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: Padding(
            padding: EdgeInsets.all(32.0),
            child: _buildCurrentMenu(),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentMenu() {
    switch (_currentMenu) {
      case QuickSettingsMenu.wifi:
        return _buildWifiMenu();
      case QuickSettingsMenu.bluetooth:
        return _buildBluetoothMenu();
      case QuickSettingsMenu.screenshot:
        return _buildScreenshotMenu();
      case QuickSettingsMenu.audio:
        return _buildAudioMenu();
      case QuickSettingsMenu.main:
      default:
        return _buildMainMenu();
    }
  }

  Widget _buildMainMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ValueListenableBuilder<String?>(
                  valueListenable: SystemState.wifiSsid,
                  builder: (context, ssid, _) {
                    return QuickToggle(
                      icon: ssid != null ? Icons.wifi : Icons.wifi_off,
                      label: ssid ?? "Wi-Fi",
                      isActive: _wifiEnabled,
                      onTap: _toggleWifi,
                      onLongPress: _scanWifi,
                    );
                  },
                ),
                ValueListenableBuilder<List<String>>(
                  valueListenable: SystemState.bluetoothDevices,
                  builder: (context, devices, _) {
                    final hasDevices = devices.isNotEmpty;
                    return QuickToggle(
                      icon: hasDevices
                          ? Icons.bluetooth_connected
                          : Icons.bluetooth,
                      label: hasDevices ? devices.first : "Bluetooth",
                      isActive: _bluetoothEnabled,
                      onTap: _toggleBluetooth,
                      onLongPress: _scanBluetooth,
                    );
                  },
                ),
                QuickToggle(
                  icon: Icons.airplanemode_active,
                  label: "Airplane",
                  isActive: _airplaneModeEnabled,
                  onTap: _toggleAirplaneMode,
                ),
                QuickToggle(
                  icon: Icons.nightlight_round,
                  label: "Night Light",
                  isActive: _nightLightEnabled,
                  onTap: _toggleNightLight,
                ),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                QuickToggle(
                  icon: Icons.screenshot_monitor,
                  label: "Screenshot",
                  isActive: false,
                  onTap: () {
                    setState(() => _currentMenu = QuickSettingsMenu.screenshot);
                  },
                ),
                QuickToggle(
                  icon: Icons.visibility_off,
                  label: "Dock Autohide",
                  isActive: _dockAutohideEnabled,
                  onTap: _toggleDockAutohide,
                ),
                ValueListenableBuilder<ThemeMode>(
                  valueListenable: FyrTheme.themeModeNotifier,
                  builder: (context, themeMode, _) {
                    final isDark = themeMode == ThemeMode.dark;
                    return QuickToggle(
                      icon: isDark ? Icons.dark_mode : Icons.light_mode,
                      label: isDark ? "Dark Mode" : "Light Mode",
                      isActive: isDark,
                      onTap: () {
                        FyrTheme.setThemeMode(
                          isDark ? ThemeMode.light : ThemeMode.dark,
                        );
                      },
                    );
                  },
                ),
                QuickToggle(
                  icon: Icons.settings,
                  label: "Settings",
                  isActive: false,
                  onTap: () {
                    _runCmd('/opt/fyrsettings/fyrsettings', []);
                    widget.onClose();
                  },
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: 24),
        SliderRow(
          icon: Icons.light_mode,
          value: _brightness,
          onChanged: _setBrightness,
        ),
        SizedBox(height: 16),
        SliderRow(
          icon: Icons.volume_up,
          value: _volume,
          onChanged: _setVolume,
          onChangeEnd: (_) => _playVolumeSound(),
          trailing: IconButton(
            icon: Icon(Icons.keyboard_arrow_right, color: FyrTheme.textColor),
            onPressed: () {
              _loadAudioDevices();
              setState(() => _currentMenu = QuickSettingsMenu.audio);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWifiMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: FyrTheme.textColor, size: 20),
              onPressed: () =>
                  setState(() => _currentMenu = QuickSettingsMenu.main),
            ),
            Text(
              "Wi-Fi Networks",
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (_isScanning)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FyrTheme.accentColor,
                ),
              ),
          ],
        ),
        SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _wifiNetworks.length,
            itemBuilder: (context, index) {
              final net = _wifiNetworks[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
                title: Text(
                  net['ssid']!,
                  style: TextStyle(fontSize: 13, color: FyrTheme.textColor),
                ),
                trailing: Icon(
                  Icons.network_wifi,
                  size: 16,
                  color: FyrTheme.textColor.withOpacity(0.7),
                ),
                onTap: () {
                  if (net['security'] != null &&
                      net['security'] != '' &&
                      net['security'] != '--') {
                    _showWifiPasswordDialog(net['ssid']!);
                  } else {
                    _connectWifi(net['ssid']!);
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBluetoothMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: FyrTheme.textColor, size: 20),
              onPressed: () =>
                  setState(() => _currentMenu = QuickSettingsMenu.main),
            ),
            Text(
              "Bluetooth Devices",
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (_isScanning)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FyrTheme.accentColor,
                ),
              ),
          ],
        ),
        SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _btDevices.length,
            itemBuilder: (context, index) {
              final dev = _btDevices[index];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
                leading: Icon(
                  Icons.bluetooth,
                  size: 16,
                  color: FyrTheme.textColorMuted,
                ),
                title: Text(
                  dev['name']!,
                  style: TextStyle(fontSize: 13, color: FyrTheme.textColor),
                ),
                onTap: () => _connectBluetooth(dev['address']!),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildScreenshotMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: FyrTheme.textColor, size: 20),
              onPressed: () =>
                  setState(() => _currentMenu = QuickSettingsMenu.main),
            ),
            Text(
              "Capture Screen",
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ScreenshotButton(
              icon: Icons.fullscreen,
              label: "Full Screen",
              onTap: () => _takeScreenshot(false),
            ),
            ScreenshotButton(
              icon: Icons.crop_free,
              label: "Crop Region",
              onTap: () => _takeScreenshot(true),
            ),
            ScreenshotButton(
              icon: _isRecording ? Icons.stop_circle : Icons.videocam,
              label: _isRecording ? "Stop Record" : "Screen Record",
              isActive: _isRecording,
              onTap: _toggleRecording,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAudioMenu() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: FyrTheme.textColor, size: 20),
              onPressed: () =>
                  setState(() => _currentMenu = QuickSettingsMenu.main),
            ),
            Text(
              "Audio Devices",
              style: TextStyle(
                color: FyrTheme.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const Spacer(),
            if (_isScanning)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FyrTheme.accentColor,
                ),
              ),
          ],
        ),
        SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Text(
                    "Output (Speakers)",
                    style: TextStyle(
                      color: FyrTheme.textColorMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ..._sinks.map((s) {
                  bool isDefault = s['name'] == _defaultSink;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      Icons.speaker,
                      size: 16,
                      color: isDefault
                          ? FyrTheme.accentColor
                          : FyrTheme.textColorMuted,
                    ),
                    title: Text(
                      s['description'] ?? s['name'],
                      style: TextStyle(fontSize: 13, color: FyrTheme.textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isDefault
                        ? Icon(
                            Icons.check,
                            color: FyrTheme.accentColor,
                            size: 16,
                          )
                        : null,
                    onTap: () => _setDefaultSink(s['name']),
                  );
                }).toList(),
                Divider(color: FyrTheme.textColor.withOpacity(0.1)),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  child: Text(
                    "Input (Microphone)",
                    style: TextStyle(
                      color: FyrTheme.textColorMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ..._sources.map((s) {
                  bool isDefault = s['name'] == _defaultSource;
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    leading: Icon(
                      Icons.mic,
                      size: 16,
                      color: isDefault
                          ? FyrTheme.accentColor
                          : FyrTheme.textColorMuted,
                    ),
                    title: Text(
                      s['description'] ?? s['name'],
                      style: TextStyle(fontSize: 13, color: FyrTheme.textColor),
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: isDefault
                        ? Icon(
                            Icons.check,
                            color: FyrTheme.accentColor,
                            size: 16,
                          )
                        : null,
                    onTap: () => _setDefaultSource(s['name']),
                  );
                }).toList(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
