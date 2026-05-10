import 'dart:io';
import 'package:webview_cef/webview_cef.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';
import 'browser_screen.dart';
import 'logger_service.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await LoggerService().initialize();
  logger.i('FyrBrowser starting...');
  WebviewManager.onNativeLog = (msg) => logger.d('[Native] $msg');
  await windowManager.ensureInitialized();

  String? initialUrl;
  bool isAppMode = false;

  for (var arg in args) {
    if (arg.startsWith('--app=')) {
      initialUrl = arg.substring(6);
      isAppMode = true;
      break; // Priority to app mode
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

  FlutterError.onError = (FlutterErrorDetails details) {
    logger.e('Flutter Error', details.exception, details.stack);
  };

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
