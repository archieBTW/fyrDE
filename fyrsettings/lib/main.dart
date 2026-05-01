import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'panes/wifi_pane.dart';
import 'panes/bluetooth_pane.dart';
import 'panes/display_pane.dart';
import 'panes/power_pane.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

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

  runApp(const FyrSettingsApp());
}

class FyrSettingsApp extends StatelessWidget {
  const FyrSettingsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FyrSettings',
      theme: ThemeData(
        fontFamily: 'San Francisco',
        scaffoldBackgroundColor: Colors.transparent,
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Colors.purple,
          secondary: Colors.purpleAccent,
        ),
      ),
      home: const SettingsScreen(),
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
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _selectedIndex = 0;
  bool _isSidebarCollapsed = false;

  final List<SettingsCategory> _categories = [
    SettingsCategory('Wi-Fi', Icons.wifi, const WiFiPane()),
    SettingsCategory('Bluetooth', Icons.bluetooth, const BluetoothPane()),
    SettingsCategory('Displays', Icons.monitor, const DisplayPane()),
    SettingsCategory('Power', Icons.battery_charging_full, const PowerPane()),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: _isSidebarCollapsed ? 72 : 260,
            color: Colors.purple.withOpacity(0.8),
            child: Column(
              children: [
                DragToMoveArea(
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.only(left: 20),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _buildTrafficLight(
                          Colors.redAccent,
                          () => windowManager.close(),
                        ),
                        const SizedBox(width: 8),
                        _buildTrafficLight(
                          Colors.orangeAccent,
                          () => windowManager.minimize(),
                        ),
                        const SizedBox(width: 8),
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
                    padding: const EdgeInsets.only(left: 24.0, right: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Settings',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
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
                  const SizedBox(height: 32)
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16.0),
                    child: IconButton(
                      icon: const Icon(Icons.menu, color: Colors.white),
                      onPressed: () =>
                          setState(() => _isSidebarCollapsed = false),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _categories.length,
                    itemBuilder: (context, index) {
                      final category = _categories[index];
                      final isSelected = _selectedIndex == index;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: InkWell(
                          onTap: () => setState(() => _selectedIndex = index),
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withOpacity(0.15)
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
                                  const SizedBox(width: 16),
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
              color: const Color(0xFF1E1E1E).withOpacity(0.6),
              child: Column(
                children: [
                  DragToMoveArea(
                    child: Container(height: 48, color: Colors.transparent),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(
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
