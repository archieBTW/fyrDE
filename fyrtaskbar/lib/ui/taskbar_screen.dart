import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fyrtaskbar/calendar_weather.dart';
import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/phone_service.dart';
import 'package:fyrtaskbar/state/system_state.dart';
import 'package:fyrtaskbar/ui/clock_widget.dart';
import 'package:fyrtaskbar/ui/notification_popup_overlay.dart';
import 'package:fyrtaskbar/ui/phone_menu.dart';
import 'package:fyrtaskbar/ui/quick_settings.dart';
import 'package:fyrtaskbar/ui/start_menu.dart';
import 'package:fyrtaskbar/workspace_switcher.dart';
import 'package:window_manager/window_manager.dart';

class TaskbarScreen extends StatefulWidget {
  const TaskbarScreen({super.key});

  @override
  State<TaskbarScreen> createState() => _TaskbarScreenState();
}

class _TaskbarScreenState extends State<TaskbarScreen> {
  @override
  void initState() {
    super.initState();
    SystemState.activePopups.addListener(_onPopupsChanged);
  }

  @override
  void dispose() {
    SystemState.activePopups.removeListener(_onPopupsChanged);
    super.dispose();
  }

  void _onPopupsChanged() {
    if (mounted) {
      _updateWindowSize();
    }
  }

  bool _isStartMenuOpen = false;
  bool _isQuickSettingsOpen = false;
  bool _isCalendarOpen = false;
  bool _isPhoneMenuOpen = false;

  void _toggleStartMenu() async {
    setState(() {
      _isStartMenuOpen = !_isStartMenuOpen;
      if (_isStartMenuOpen) {
        _isQuickSettingsOpen = false;
        _isCalendarOpen = false;
        _isPhoneMenuOpen = false;
      }
    });
    _updateWindowSize();
  }

  void _toggleQuickSettings() async {
    setState(() {
      _isQuickSettingsOpen = !_isQuickSettingsOpen;
      if (_isQuickSettingsOpen) {
        _isStartMenuOpen = false;
        _isCalendarOpen = false;
        _isPhoneMenuOpen = false;
      }
    });
    _updateWindowSize();
  }

  void _toggleCalendar() async {
    setState(() {
      _isCalendarOpen = !_isCalendarOpen;
      if (_isCalendarOpen) {
        _isStartMenuOpen = false;
        _isQuickSettingsOpen = false;
        _isPhoneMenuOpen = false;
      }
    });
    _updateWindowSize();
  }

  void _closeMenus() {
    if (_isStartMenuOpen ||
        _isQuickSettingsOpen ||
        _isCalendarOpen ||
        _isPhoneMenuOpen) {
      setState(() {
        _isStartMenuOpen = false;
        _isQuickSettingsOpen = false;
        _isCalendarOpen = false;
        _isPhoneMenuOpen = false;
      });
      _updateWindowSize();
    }
  }

  void _togglePhoneMenu() async {
    setState(() {
      _isPhoneMenuOpen = !_isPhoneMenuOpen;
      if (_isPhoneMenuOpen) {
        _isStartMenuOpen = false;
        _isQuickSettingsOpen = false;
        _isCalendarOpen = false;
      }
    });
    _updateWindowSize();
  }

  void _updateWindowSize() async {
    const channel = MethodChannel('fyrtaskbar/resize');
    if (_isStartMenuOpen ||
        _isQuickSettingsOpen ||
        _isCalendarOpen ||
        _isPhoneMenuOpen ||
        SystemState.activePopups.value.isNotEmpty) {
      try {
        await channel.invokeMethod('setSize', {
          'width': SystemState.screenWidth,
          'height': SystemState.screenHeight,
        });
      } catch (_) {}
      await windowManager.setSize(
        Size(
          SystemState.screenWidth.toDouble(),
          SystemState.screenHeight.toDouble(),
        ),
      );
    } else {
      try {
        await channel.invokeMethod('setSize', {
          'width': SystemState.screenWidth,
          'height': 56,
        });
      } catch (_) {}
      await windowManager.setSize(Size(SystemState.screenWidth.toDouble(), 56));
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _closeMenus();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(color: FyrTheme.bgColor),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.center,
                    child: GestureDetector(
                      onTap: _toggleCalendar,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        color: Colors.transparent,
                        child: const ClockWidget(),
                      ),
                    ),
                  ),
                  const NotificationPopupOverlay(),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: _toggleStartMenu,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            alignment: Alignment.center,
                            child: Image.asset(
                              'assets/icons/fyr_icon.png',
                              width: 36,
                              height: 36,
                            ),
                          ),
                        ),
                        const WorkspaceSwitcher(),
                      ],
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () async {
                            await Process.run('swaymsg', [
                              '[app_id="fyroverview"] scratchpad show, resize set ${SystemState.screenWidth} ${SystemState.screenHeight}, border none, move absolute position 0 0',
                            ]);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.dashboard,
                              color: FyrTheme.textColor.withOpacity(0.9),
                              size: 18,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            await Process.run(
                              '${Platform.environment['HOME']}/.config/fyr/retile.py',
                              [],
                            );
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.sort,
                              color: FyrTheme.textColor.withOpacity(0.9),
                              size: 18,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            await Process.run(
                              '${Platform.environment['HOME']}/.config/fyr/toggle_floating.sh',
                              [],
                            );
                            await SystemState.update();
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            child: ValueListenableBuilder<bool>(
                              valueListenable: SystemState.floatingMode,
                              builder: (context, isFloating, _) {
                                return Icon(
                                  isFloating ? Icons.layers : Icons.grid_view,
                                  color: FyrTheme.textColor.withOpacity(0.9),
                                  size: 18,
                                );
                              },
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            await Process.run('swaymsg', [
                              'layout toggle splitv splith',
                            ]);
                            SystemState.updateSwayState();
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            child: ValueListenableBuilder<String>(
                              valueListenable: SystemState.splitLayout,
                              builder: (context, split, _) {
                                IconData icon = Icons.crop_square;
                                if (split == 'splitv') icon = Icons.splitscreen;
                                if (split == 'splith')
                                  icon = Icons.vertical_split;
                                return Icon(
                                  icon,
                                  color: FyrTheme.textColor.withOpacity(0.9),
                                  size: 18,
                                );
                              },
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: _toggleQuickSettings,
                          behavior: HitTestBehavior.opaque,
                          child: Container(
                            padding: EdgeInsets.only(left: 12, right: 20),
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ValueListenableBuilder<bool>(
                                  valueListenable: SystemState.isRecording,
                                  builder: (context, isRecording, _) {
                                    if (!isRecording)
                                      return const SizedBox.shrink();
                                    return GestureDetector(
                                      onTap: () async {
                                        await Process.run('killall', [
                                          '-s',
                                          'SIGINT',
                                          'wf-recorder',
                                        ]);
                                        Process.run('notify-send', [
                                          'Recording Stopped',
                                          'Video saved to Videos/recordings',
                                        ]);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 12,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.circle,
                                              color: Colors.redAccent,
                                              size: 10,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              "REC",
                                              style: TextStyle(
                                                color: Colors.redAccent,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                ValueListenableBuilder<PhoneInfo?>(
                                  valueListenable: SystemState.primaryPhone,
                                  builder: (context, phone, _) {
                                    return GestureDetector(
                                      onTap: () {
                                        if (phone == null || !phone.isPaired) {
                                          Process.run('fyrphone', []);
                                        } else {
                                          _togglePhoneMenu();
                                        }
                                      },
                                      behavior: HitTestBehavior.opaque,
                                      child: Row(
                                        children: [
                                          Icon(
                                            phone != null && phone.isConnected
                                                ? Icons.smartphone
                                                : Icons.phonelink_erase,
                                            color:
                                                phone != null &&
                                                    phone.isConnected
                                                ? FyrTheme.textColor
                                                      .withOpacity(0.9)
                                                : FyrTheme.textColor
                                                      .withOpacity(0.4),
                                            size: 18,
                                          ),
                                          if (phone != null &&
                                              phone.isConnected) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              "${phone.batteryLevel}%",
                                              style: TextStyle(
                                                color: FyrTheme.textColor
                                                    .withOpacity(0.7),
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(width: 12),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                                ValueListenableBuilder<String?>(
                                  valueListenable: SystemState.wifiSsid,
                                  builder: (context, ssid, _) {
                                    return Icon(
                                      ssid != null
                                          ? Icons.wifi
                                          : Icons.wifi_off,
                                      color: ssid != null
                                          ? FyrTheme.textColor.withOpacity(0.9)
                                          : FyrTheme.textColor.withOpacity(0.4),
                                      size: 18,
                                    );
                                  },
                                ),
                                SizedBox(width: 12),
                                ValueListenableBuilder<List<String>>(
                                  valueListenable: SystemState.bluetoothDevices,
                                  builder: (context, devices, _) {
                                    return Icon(
                                      devices.isNotEmpty
                                          ? Icons.bluetooth_connected
                                          : Icons.bluetooth,
                                      color: devices.isNotEmpty
                                          ? FyrTheme.textColor.withOpacity(0.9)
                                          : FyrTheme.textColor.withOpacity(0.4),
                                      size: 18,
                                    );
                                  },
                                ),
                                SizedBox(width: 12),
                                ValueListenableBuilder<bool>(
                                  valueListenable: SystemState.isCharging,
                                  builder: (context, isCharging, _) {
                                    return ValueListenableBuilder<int>(
                                      valueListenable: SystemState.batteryLevel,
                                      builder: (context, level, _) {
                                        IconData batteryIcon = isCharging
                                            ? Icons.battery_charging_full
                                            : (level > 20
                                                  ? Icons.battery_full
                                                  : Icons.battery_alert);
                                        Color batteryColor =
                                            level <= 20 && !isCharging
                                            ? Colors.redAccent
                                            : FyrTheme.textColor.withOpacity(
                                                0.9,
                                              );

                                        return Row(
                                          children: [
                                            Icon(
                                              batteryIcon,
                                              color: batteryColor,
                                              size: 18,
                                            ),
                                            SizedBox(width: 4),
                                            Text(
                                              "${level}%",
                                              style: TextStyle(
                                                color: batteryColor,
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Popups
            Expanded(
              child: GestureDetector(
                onTap: _closeMenus,
                behavior: HitTestBehavior.opaque,
                child: ClipRect(
                  child: Stack(
                    children: [
                      if (_isStartMenuOpen)
                        Positioned(
                          top: 0,
                          left: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onTap: () {},
                            child: StartMenuPopup(
                              key: ValueKey(FyrTheme.iconThemeName),
                              onClose: _toggleStartMenu,
                            ),
                          ),
                        ),
                      if (_isCalendarOpen)
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: GestureDetector(
                              onTap: () {},
                              child: CalendarMenuPopup(
                                onClose: _toggleCalendar,
                              ),
                            ),
                          ),
                        ),
                      if (_isPhoneMenuOpen)
                        Positioned(
                          top: 0,
                          right: 60,
                          child: GestureDetector(
                            onTap: () {},
                            child: PhoneMenuPopup(onClose: _togglePhoneMenu),
                          ),
                        ),
                      if (_isQuickSettingsOpen)
                        Positioned(
                          top: -1,
                          right: -1,
                          child: GestureDetector(
                            onTap: () {}, // absorb taps
                            child: QuickSettingsPopup(
                              onClose: _toggleQuickSettings,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
