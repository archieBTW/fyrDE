import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fyrtaskbar/calendar_weather.dart';
import 'package:fyrtaskbar/fyr_theme.dart';
import 'package:fyrtaskbar/phone_service.dart';
import 'package:fyrtaskbar/services/app_service.dart';
import 'package:fyrtaskbar/services/tray_service.dart';
import 'package:fyrtaskbar/state/system_state.dart';
import 'package:fyrtaskbar/ui/clock_widget.dart';
import 'package:fyrtaskbar/ui/media_controls.dart';
import 'package:fyrtaskbar/ui/notification_popup_overlay.dart';
import 'package:fyrtaskbar/ui/phone_menu.dart';
import 'package:fyrtaskbar/ui/quick_settings.dart';
import 'package:fyrtaskbar/ui/screenshot_toast.dart';
import 'package:fyrtaskbar/ui/start_menu.dart';
import 'package:fyrtaskbar/ui/tray_menu_popup.dart';
import 'package:fyrtaskbar/workspace_switcher.dart';
import 'package:wayland_layer_shell/types.dart';
import 'package:wayland_layer_shell/wayland_layer_shell.dart';
import 'package:window_manager/window_manager.dart';

class TaskbarScreen extends StatefulWidget {
  const TaskbarScreen({super.key});

  @override
  State<TaskbarScreen> createState() => _TaskbarScreenState();
}

class _TaskbarScreenState extends State<TaskbarScreen> {
  StreamSubscription<void>? _appsSub;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    AppService.getInstalledAppsSync();
    SystemState.activePopups.addListener(_onPopupsChanged);
    SystemState.activeScreenshotToast.addListener(_onPopupsChanged);
    _appsSub = AppService.onAppsChanged.listen((_) {
      if (mounted) _precacheStartMenuIcons();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _precacheStartMenuIcons();
  }

  void _precacheStartMenuIcons() {
    final apps = AppService.cachedApps ?? AppService.getInstalledAppsSync();
    for (final app in apps) {
      if (app.icon.startsWith('/') &&
          !app.icon.toLowerCase().endsWith('.svg')) {
        final file = File(app.icon);
        if (file.existsSync()) {
          precacheImage(
            ResizeImage(FileImage(file), width: 48, height: 48),
            context,
            onError: (_, __) {},
          );
        }
      }
    }
  }

  @override
  void dispose() {
    _appsSub?.cancel();
    SystemState.activePopups.removeListener(_onPopupsChanged);
    SystemState.activeScreenshotToast.removeListener(_onPopupsChanged);
    _focusNode.dispose();
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
  TrayItem? _activeTrayItem;
  List<TrayMenuEntry> _activeTrayEntries = const [];
  double _trayMenuRight = 240;

  bool get _hasOpenMenu =>
      _isStartMenuOpen ||
      _isQuickSettingsOpen ||
      _isCalendarOpen ||
      _isPhoneMenuOpen ||
      _activeTrayItem != null;

  void _toggleStartMenu() async {
    setState(() {
      _isStartMenuOpen = !_isStartMenuOpen;
      if (_isStartMenuOpen) {
        _isQuickSettingsOpen = false;
        _isCalendarOpen = false;
        _isPhoneMenuOpen = false;
        _activeTrayItem = null;
      }
    });
    if (_isStartMenuOpen) _focusNode.requestFocus();
    _updateWindowSize();
  }

  void _toggleQuickSettings() async {
    setState(() {
      _isQuickSettingsOpen = !_isQuickSettingsOpen;
      if (_isQuickSettingsOpen) {
        _isStartMenuOpen = false;
        _isCalendarOpen = false;
        _isPhoneMenuOpen = false;
        _activeTrayItem = null;
      }
    });
    if (_isQuickSettingsOpen) _focusNode.requestFocus();
    _updateWindowSize();
  }

  void _toggleCalendar() async {
    setState(() {
      _isCalendarOpen = !_isCalendarOpen;
      if (_isCalendarOpen) {
        _isStartMenuOpen = false;
        _isQuickSettingsOpen = false;
        _isPhoneMenuOpen = false;
        _activeTrayItem = null;
      }
    });
    if (_isCalendarOpen) _focusNode.requestFocus();
    _updateWindowSize();
  }

  void _closeMenus() {
    if (_hasOpenMenu) {
      setState(() {
        _isStartMenuOpen = false;
        _isQuickSettingsOpen = false;
        _isCalendarOpen = false;
        _isPhoneMenuOpen = false;
        _activeTrayItem = null;
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
        _activeTrayItem = null;
      }
    });
    if (_isPhoneMenuOpen) _focusNode.requestFocus();
    _updateWindowSize();
  }

  Future<void> _openTrayMenu(TrayItem item, Offset globalPos) async {
    if (_activeTrayItem?.serviceKey == item.serviceKey) {
      setState(() => _activeTrayItem = null);
      _updateWindowSize();
      return;
    }
    final entries = await TrayService.fetchMenu(item);
    if (!mounted) return;
    final rightOffset = (SystemState.screenWidth - globalPos.dx - 120)
        .clamp(12.0, math.max(12.0, SystemState.screenWidth - 260.0))
        .toDouble();
    setState(() {
      _isStartMenuOpen = false;
      _isQuickSettingsOpen = false;
      _isCalendarOpen = false;
      _isPhoneMenuOpen = false;
      _activeTrayItem = item;
      _activeTrayEntries = entries;
      _trayMenuRight = rightOffset;
    });
    _focusNode.requestFocus();
    _updateWindowSize();
  }

  Widget _buildTrayIcon(TrayItem item) {
    Widget iconWidget;
    if (item.resolvedIconFile != null) {
      final path = item.resolvedIconFile!;
      if (path.toLowerCase().endsWith('.svg')) {
        iconWidget = SvgPicture.file(
          File(path),
          width: 18,
          height: 18,
          fit: BoxFit.contain,
          placeholderBuilder: (_) => Icon(
            Icons.apps_rounded,
            size: 16,
            color: FyrTheme.textColor.withValues(alpha: 0.75),
          ),
        );
      } else {
        iconWidget = Image.file(
          File(path),
          width: 18,
          height: 18,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => Icon(
            Icons.apps_rounded,
            size: 16,
            color: FyrTheme.textColor.withValues(alpha: 0.85),
          ),
        );
      }
    } else if (item.pixmapImage != null) {
      iconWidget = RawImage(
        image: item.pixmapImage,
        width: 18,
        height: 18,
        fit: BoxFit.contain,
      );
    } else {
      iconWidget = Icon(
        Icons.shield_outlined,
        size: 16,
        color: FyrTheme.accentColor,
      );
    }

    if (item.status == 'NeedsAttention') {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          iconWidget,
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: FyrTheme.accentColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      );
    }
    return iconWidget;
  }

  bool _isOverlayLayer = false;
  bool _isExclusiveKeyboard = false;
  bool _updatingWindowSize = false;
  bool _pendingWindowSizeUpdate = false;
  int _lastWindowWidth = -1;
  int _lastWindowHeight = -1;
  String _lastInputRegionKey = '';

  void _updateWindowSize() {
    if (_updatingWindowSize) {
      _pendingWindowSizeUpdate = true;
      return;
    }
    _updatingWindowSize = true;
    () async {
      try {
        do {
          _pendingWindowSizeUpdate = false;
          await _applyWindowState();
        } while (_pendingWindowSizeUpdate && mounted);
      } finally {
        _updatingWindowSize = false;
      }
    }();
  }

  Future<void> _applyWindowState() async {
    const channel = MethodChannel('fyrtaskbar/resize');
    final waylandLayerShellPlugin = WaylandLayerShell();
    final hasOpenMenu = _hasOpenMenu;
    final hasScreenshot = SystemState.activeScreenshotToast.value != null;
    final popupCount = SystemState.activePopups.value.length;
    final hasToast = hasScreenshot || popupCount > 0;
    final expanded = hasOpenMenu || hasToast;

    final int screenWidth = SystemState.screenWidth;
    final int screenHeight = SystemState.screenHeight;
    final int targetHeight = expanded ? screenHeight : 56;

    if (expanded) {
      if (!_isOverlayLayer) {
        _isOverlayLayer = true;
        try {
          await waylandLayerShellPlugin.setLayer(ShellLayer.layerOverlay);
        } catch (_) {}
      }

      if (hasOpenMenu != _isExclusiveKeyboard) {
        _isExclusiveKeyboard = hasOpenMenu;
        try {
          await waylandLayerShellPlugin.setKeyboardMode(
            hasOpenMenu
                ? ShellKeyboardMode.keyboardModeExclusive
                : ShellKeyboardMode.keyboardModeOnDemand,
          );
        } catch (_) {}
      }

      if (_lastWindowWidth != screenWidth ||
          _lastWindowHeight != targetHeight) {
        _lastWindowWidth = screenWidth;
        _lastWindowHeight = targetHeight;
        try {
          await channel.invokeMethod('setSize', {
            'width': screenWidth,
            'height': targetHeight,
          });
        } catch (_) {}
        try {
          await windowManager.setSize(
            Size(screenWidth.toDouble(), targetHeight.toDouble()),
          );
        } catch (_) {}
      }

      if (hasOpenMenu) {
        if (_lastInputRegionKey != 'full') {
          _lastInputRegionKey = 'full';
          try {
            await channel.invokeMethod('setInputRegion', {'full': true});
          } catch (_) {}
        }
      } else {
        // Passive toasts/notifications only: restrict input to the top bar,
        // top-center notification popups, and top-right screenshot toast so
        // the rest of the desktop stays clickable.
        final int maxToastHeight = math.max(0, screenHeight - 56);
        final rects = <Map<String, int>>[
          {'x': 0, 'y': 0, 'width': screenWidth, 'height': 56},
        ];
        final keyParts = <String>['toast', '$screenWidth'];

        if (popupCount > 0 && maxToastHeight > 0) {
          final int popupWidth = math.min(356, screenWidth);
          final int popupX = math.max(0, (screenWidth - popupWidth) ~/ 2);
          final int popupHeight = math.min(
            maxToastHeight,
            12 + math.min(popupCount, 3) * 180 + 24,
          );
          rects.add({
            'x': popupX,
            'y': 56,
            'width': popupWidth,
            'height': popupHeight,
          });
          keyParts.add('p:$popupX:$popupWidth:$popupHeight');
        }

        if (hasScreenshot && maxToastHeight > 0) {
          final int shotWidth = math.min(356, screenWidth);
          final int shotX = math.max(0, screenWidth - shotWidth);
          final int shotHeight = math.min(maxToastHeight, 290);
          rects.add({
            'x': shotX,
            'y': 56,
            'width': shotWidth,
            'height': shotHeight,
          });
          keyParts.add('s:$shotX:$shotWidth:$shotHeight');
        }

        final regionKey = keyParts.join('|');
        if (_lastInputRegionKey != regionKey) {
          _lastInputRegionKey = regionKey;
          try {
            await channel.invokeMethod('setInputRegion', {'rects': rects});
          } catch (_) {}
        }
      }
    } else {
      if (_isExclusiveKeyboard) {
        _isExclusiveKeyboard = false;
        try {
          await waylandLayerShellPlugin.setKeyboardMode(
            ShellKeyboardMode.keyboardModeOnDemand,
          );
        } catch (_) {}
      }

      if (_lastWindowWidth != screenWidth || _lastWindowHeight != 56) {
        _lastWindowWidth = screenWidth;
        _lastWindowHeight = 56;
        try {
          await channel.invokeMethod('setSize', {
            'width': screenWidth,
            'height': 56,
          });
        } catch (_) {}
        try {
          await windowManager.setSize(Size(screenWidth.toDouble(), 56));
        } catch (_) {}
      }

      if (_lastInputRegionKey != 'full') {
        _lastInputRegionKey = 'full';
        try {
          await channel.invokeMethod('setInputRegion', {'full': true});
        } catch (_) {}
      }

      if (_isOverlayLayer) {
        _isOverlayLayer = false;
        try {
          await waylandLayerShellPlugin.setLayer(ShellLayer.layerTop);
        } catch (_) {}
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _closeMenus();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 56,
              width: double.infinity,
              decoration: BoxDecoration(color: FyrTheme.panelBgColor),
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
                        TaskbarMediaPill(onOpenDetails: _toggleQuickSettings),
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
                        ValueListenableBuilder<List<TrayItem>>(
                          valueListenable: TrayService.items,
                          builder: (context, trayItems, _) {
                            if (trayItems.isEmpty) {
                              return const SizedBox.shrink();
                            }
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ...trayItems.map((item) {
                                  final isActive =
                                      _activeTrayItem?.serviceKey ==
                                      item.serviceKey;
                                  return _TrayIconButton(
                                    item: item,
                                    isActive: isActive,
                                    icon: _buildTrayIcon(item),
                                    onPrimaryTap: (pos) async {
                                      if (item.itemIsMenu &&
                                          item.menuPath != null) {
                                        await _openTrayMenu(item, pos);
                                      } else {
                                        final ok = await TrayService.activate(
                                          item,
                                          pos.dx.round(),
                                          pos.dy.round(),
                                        );
                                        if (!ok && item.menuPath != null) {
                                          await _openTrayMenu(item, pos);
                                        }
                                      }
                                    },
                                    onSecondaryTap: (pos) async {
                                      if (item.menuPath != null) {
                                        await _openTrayMenu(item, pos);
                                      }
                                    },
                                    onMiddleTap: (pos) async {
                                      await TrayService.secondaryActivate(
                                        item,
                                        pos.dx.round(),
                                        pos.dy.round(),
                                      );
                                    },
                                    onScroll: (delta) {
                                      TrayService.scroll(item, delta);
                                    },
                                  );
                                }),
                                Container(
                                  width: 1,
                                  height: 18,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  color: FyrTheme.textColor.withValues(
                                    alpha: 0.15,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        GestureDetector(
                          onTap: () async {
                            final home = Platform.environment['HOME'] ?? '';
                            final script = '$home/.config/fyr/overview_toggle.sh';
                            if (File(script).existsSync()) {
                              await Process.run(script, ['workspace']);
                            } else {
                              await Process.start(
                                '/opt/fyroverview/fyroverview',
                                ['--show'],
                                mode: ProcessStartMode.detached,
                              );
                            }
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
                                  valueListenable: SystemState.activeVpnName,
                                  builder: (context, vpnName, _) {
                                    if (vpnName == null || vpnName.isEmpty) {
                                      return const SizedBox.shrink();
                                    }
                                    return Semantics(
                                      container: true,
                                      label: 'VPN: $vpnName',
                                      child: Padding(
                                        padding: const EdgeInsets.only(
                                          right: 12,
                                        ),
                                        child: Icon(
                                          Icons.vpn_lock_rounded,
                                          color: FyrTheme.accentColor,
                                          size: 18,
                                        ),
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
                      Positioned(
                        top: 0,
                        left: 0,
                        height: _isStartMenuOpen
                            ? null
                            : math.max(
                                400.0,
                                SystemState.screenHeight.toDouble() - 56.0,
                              ),
                        bottom: _isStartMenuOpen ? 0 : null,
                        child: Offstage(
                          offstage: !_isStartMenuOpen,
                          child: GestureDetector(
                            onTap: () {},
                            child: StartMenuPopup(
                              key: ValueKey(FyrTheme.iconThemeName),
                              isOpen: _isStartMenuOpen,
                              onClose: _toggleStartMenu,
                            ),
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
                      if (_activeTrayItem != null)
                        Positioned(
                          top: 12,
                          right: _trayMenuRight,
                          child: GestureDetector(
                            onTap: () {},
                            child: TrayMenuPopup(
                              item: _activeTrayItem!,
                              entries: _activeTrayEntries,
                              onClose: _closeMenus,
                            ),
                          ),
                        ),
                      const ScreenshotToastOverlay(),
                      const NotificationPopupOverlay(),
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

class _TrayIconButton extends StatefulWidget {
  final TrayItem item;
  final bool isActive;
  final Widget icon;
  final Future<void> Function(Offset globalPosition) onPrimaryTap;
  final Future<void> Function(Offset globalPosition) onSecondaryTap;
  final Future<void> Function(Offset globalPosition) onMiddleTap;
  final void Function(int delta) onScroll;

  const _TrayIconButton({
    required this.item,
    required this.isActive,
    required this.icon,
    required this.onPrimaryTap,
    required this.onSecondaryTap,
    required this.onMiddleTap,
    required this.onScroll,
  });

  @override
  State<_TrayIconButton> createState() => _TrayIconButtonState();
}

class _TrayIconButtonState extends State<_TrayIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isActive
        ? FyrTheme.accentColor.withValues(alpha: 0.22)
        : (_hovered
              ? FyrTheme.textColor.withValues(alpha: 0.1)
              : Colors.transparent);
    final borderColor = widget.isActive
        ? FyrTheme.accentColor.withValues(alpha: 0.5)
        : Colors.transparent;

    return Semantics(
      label: widget.item.displayLabel,
      button: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Listener(
          onPointerSignal: (event) {
            if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
              widget.onScroll(event.scrollDelta.dy > 0 ? -1 : 1);
            }
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => widget.onPrimaryTap(details.globalPosition),
              onSecondaryTapUp: (details) =>
                  widget.onSecondaryTap(details.globalPosition),
              onTertiaryTapUp: (details) =>
                  widget.onMiddleTap(details.globalPosition),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor, width: 1),
                ),
                child: widget.icon,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
