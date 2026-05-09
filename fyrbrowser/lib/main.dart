import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';
import 'browser_screen.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  String? initialUrl;
  bool isAppMode = false;

  for (var arg in args) {
    if (arg.startsWith('--app=')) {
      initialUrl = arg.substring(6);
      isAppMode = true;
    } else if (!arg.startsWith('-')) {
      initialUrl = arg;
    }
  }

  WindowOptions windowOptions = WindowOptions(
    size: const Size(1280, 720),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden, // Always hidden, we use custom traffic lights
    title: isAppMode ? 'FyrBrowser PWA' : 'FyrBrowser',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  FyrTheme.initialize();
  runApp(FyrBrowser(initialUrl: initialUrl, isAppMode: isAppMode));
}

class FyrBrowser extends StatelessWidget {
  final String? initialUrl;
  final bool isAppMode;

  const FyrBrowser({super.key, this.initialUrl, this.isAppMode = false});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: FyrTheme.themeModeNotifier,
      builder: (context, themeMode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'FyrBrowser',
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: FyrTheme.accentColor,
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: FyrTheme.accentColor,
            scaffoldBackgroundColor: Colors.black,
            useMaterial3: true,
          ),
          themeMode: themeMode,
          home: BrowserScreen(initialUrl: initialUrl, isAppMode: isAppMode),
        );
      },
    );
  }
}
