import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'fyr_theme.dart';
import 'tabs/open_apps_tab.dart';
import 'tabs/performance_tab.dart';
import 'tabs/processes_tab.dart';
import 'widgets/fyr_tab_bar.dart';
import 'widgets/fyr_title_bar.dart';

/// Index of the tab requested via the `--tab=` CLI flag.
int _initialTab = 0;

Future<void> main(List<String> args) async {
  for (final raw in args) {
    final arg = raw.trim().toLowerCase();
    if (arg == '--processes' || arg == '--tab=processes') {
      _initialTab = 1;
    } else if (arg == '--performance' || arg == '--tab=performance') {
      _initialTab = 2;
    } else if (arg == '--apps' || arg == '--tab=apps') {
      _initialTab = 0;
    }
  }

  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();

  // Deliberately compact: a task manager should feel like a utility window,
  // not a full desktop app. Everything still reflows down to minimumSize.
  const windowOptions = WindowOptions(
    size: Size(880, 600),
    minimumSize: Size(640, 430),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'fyrMonitor',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const FyrMonitorApp());
}

class FyrMonitorApp extends StatelessWidget {
  const FyrMonitorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
      builder: (context, _) {
        final accent = FyrTheme.accentColor;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'fyrMonitor',
          themeMode: FyrTheme.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.light(
              primary: accent,
              secondary: accent,
              surface: FyrTheme.surfaceColor,
            ),
            scaffoldBackgroundColor: FyrTheme.bgColor,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.dark(
              primary: accent,
              secondary: accent,
              surface: FyrTheme.surfaceColor,
            ),
            scaffoldBackgroundColor: FyrTheme.bgColor,
          ),
          home: MonitorShell(initialTab: _initialTab),
        );
      },
    );
  }
}

/// Task Manager shell: custom title bar + tab strip + the three tabs.
///
/// The [IndexedStack] keeps each tab's state alive, and every tab receives an
/// `active` flag so only the visible one polls `/proc`.
class MonitorShell extends StatefulWidget {
  const MonitorShell({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<MonitorShell> createState() => _MonitorShellState();
}

class _MonitorShellState extends State<MonitorShell> {
  static const List<FyrTabItem> _tabs = [
    FyrTabItem(label: 'Open Apps', icon: Icons.grid_view_rounded),
    FyrTabItem(label: 'Processes', icon: Icons.memory_rounded),
    FyrTabItem(label: 'Performance', icon: Icons.insights_rounded),
  ];

  late int _index = widget.initialTab.clamp(0, _tabs.length - 1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FyrTheme.bgColor,
      body: Column(
        children: [
          const FyrTitleBar(
            title: 'fyrMonitor',
            subtitle: 'Task Manager',
            icon: Icons.monitor_heart_outlined,
            trailing: [
              Padding(
                padding: EdgeInsets.only(right: 6),
                child: LiveDot(),
              ),
            ],
          ),
          FyrTabBar(
            items: _tabs,
            index: _index,
            onChanged: (index) => setState(() => _index = index),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              color: FyrTheme.contentColor,
              child: IndexedStack(
                index: _index,
                children: [
                  OpenAppsTab(active: _index == 0),
                  ProcessesTab(active: _index == 1),
                  PerformanceTab(active: _index == 2),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small indicator that reassures the user polling is live.
///
/// Deliberately static: a repeating animation would keep Flutter scheduling
/// frames forever, which is exactly the idle cost this app is meant to avoid.
class LiveDot extends StatelessWidget {
  const LiveDot({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: Colors.greenAccent,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 7),
        Text(
          'live · 1.5 s',
          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 10.5),
        ),
      ],
    );
  }
}
