import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'panes/wifi_pane.dart';
import 'panes/bluetooth_pane.dart';
import 'panes/display_pane.dart';
import 'panes/power_pane.dart';
import 'panes/personalization_pane.dart';
import 'panes/default_apps_pane.dart';
import 'panes/sound_pane.dart';
import 'panes/touchpad_pane.dart';
import 'fyr_theme.dart';

void main(List<String> args) async {
  FyrTheme.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  int initialIndex = 0;
  for (final rawArg in args) {
    final arg = rawArg.toLowerCase().replaceAll('--', '').trim();
    if (arg == 'personalization' ||
        arg == 'appearance' ||
        arg == 'wallpaper' ||
        arg == 'background') {
      initialIndex = 4;
    } else if (arg == 'displays' || arg == 'display') {
      initialIndex = 2;
    } else if (arg == 'sound' || arg == 'audio') {
      initialIndex = 3;
    } else if (arg == 'default-apps' || arg == 'apps') {
      initialIndex = 5;
    } else if (arg == 'power' || arg == 'battery') {
      initialIndex = 6;
    } else if (arg == 'bluetooth') {
      initialIndex = 1;
    } else if (arg == 'wifi' || arg == 'network') {
      initialIndex = 0;
    } else if (arg == 'touchpad' || arg == 'mouse' || arg == 'input') {
      initialIndex = 7;
    }
  }

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(FyrSettingsApp(initialIndex: initialIndex));
}

class FyrSettingsApp extends StatelessWidget {
  final int initialIndex;
  const FyrSettingsApp({super.key, this.initialIndex = 0});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.accentColorNotifier, FyrTheme.themeModeNotifier]),
      builder: (context, child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FyrSettings',
      themeMode: FyrTheme.themeMode,
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'San Francisco'),
        colorScheme: ColorScheme.dark(
          primary: FyrTheme.accentColor,
          secondary: FyrTheme.accentColor,
        ),
      ),
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: ThemeData.light().textTheme.apply(fontFamily: 'San Francisco'),
        colorScheme: ColorScheme.light(
          primary: FyrTheme.accentColor,
          secondary: FyrTheme.accentColor,
        ),
      ),
      home: SettingsScreen(initialIndex: initialIndex),
    ),
    );
  }
}

class SettingsCategory {
  final String name;
  final IconData icon;
  final Widget pane;

  SettingsCategory(this.name, this.icon, this.pane);
}

class SettingsScreen extends StatefulWidget {
  final int initialIndex;
  const SettingsScreen({super.key, this.initialIndex = 0});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late int _selectedIndex;
  bool _isSidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
  }

  @override
  Widget build(BuildContext context) {
    final List<SettingsCategory> _categories = [
      SettingsCategory('Wi-Fi', Icons.wifi, WiFiPane()),
      SettingsCategory('Bluetooth', Icons.bluetooth, BluetoothPane()),
      SettingsCategory('Displays', Icons.monitor, DisplayPane()),
      SettingsCategory('Sound', Icons.volume_up, SoundPane()),
      SettingsCategory('Personalization', Icons.palette, PersonalizationPane()),
      SettingsCategory('Default Apps', Icons.apps, DefaultAppsPane()),
      SettingsCategory('Power', Icons.battery_charging_full, PowerPane()),
      SettingsCategory('Mouse & Touchpad', Icons.touch_app, TouchpadPane()),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: _isSidebarCollapsed ? 72 : 260,
            color: FyrTheme.accentColor.withOpacity(0.8),
            child: Column(
              children: [
                DragToMoveArea(
                  child: Container(
                    height: 48,
                    padding: EdgeInsets.only(left: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildTrafficLight(
                          Colors.redAccent,
                          () => windowManager.close(),
                        ),
                        SizedBox(width: 8),
                        _buildTrafficLight(
                          Colors.orangeAccent,
                          () => windowManager.minimize(),
                        ),
                        SizedBox(width: 8),
                        _buildTrafficLight(Colors.greenAccent, () async {
                          if (await windowManager.isMaximized()) {
                            windowManager.unmaximize();
                          } else {
                            windowManager.maximize();
                          }
                        }),
                      ],
                    ),
                  ),
                ),
                if (!_isSidebarCollapsed)
                  Padding(
                    padding: EdgeInsets.only(left: 24.0, right: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Settings',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.menu_open,
                            color: Colors.white,
                          ),
                          onPressed: () =>
                              setState(() => _isSidebarCollapsed = true),
                        ),
                      ],
                    ),
                  ),
                if (!_isSidebarCollapsed)
                  SizedBox(height: 32)
                else
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    child: IconButton(
                      icon: Icon(Icons.menu, color: Colors.white),
                      onPressed: () =>
                          setState(() => _isSidebarCollapsed = false),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final isSelected = _selectedIndex == index;
                      return Padding(
                        padding: EdgeInsets.only(bottom: 8.0),
                        child: InkWell(
                          onTap: () => setState(() => _selectedIndex = index),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? FyrTheme.hoverColor
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  category.icon,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white70,
                                  size: 20,
                                ),
                                if (!_isSidebarCollapsed) ...[
                                  SizedBox(width: 16),
                                  Text(
                                    category.name,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.white70,
                                      fontSize: 15,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Container(
              color: FyrTheme.bgColor,
              child: Column(
                children: [
                  DragToMoveArea(
                    child: Container(height: 48, color: Colors.transparent),
                  ),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 48.0,
                        right: 48.0,
                        bottom: 48.0,
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: KeyedSubtree(
                          key: ValueKey(_selectedIndex),
                          child: _categories[_selectedIndex].pane,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrafficLight(Color color, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26, width: 0.5),
          ),
        ),
      ),
    );
  }
}
