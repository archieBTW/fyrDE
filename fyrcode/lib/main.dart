import 'package:flutter/material.dart';
import 'package:fyrcode/editor_screen.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'fyr_theme.dart';

void main(List<String> args) async {
  FyrTheme.initialize();
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  String initialDir = Directory.current.path;
  if (args.isNotEmpty) {
    if (Directory(args.first).existsSync()) {
      initialDir = Directory(args.first).absolute.path;
    } else if (File(args.first).existsSync()) {
      initialDir = File(args.first).parent.absolute.path;
    }
  }
  WindowOptions windowOptions = WindowOptions(
    size: const Size(1200, 800),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'FyrCode',
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(FyrCodeApp(initialDirectory: initialDir));
}

class FyrCodeApp extends StatelessWidget {
  final String initialDirectory;
  const FyrCodeApp({super.key, required this.initialDirectory});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([FyrTheme.accentColorNotifier, FyrTheme.themeModeNotifier]),
      builder: (context, child) => MaterialApp(
      title: 'FyrCode Editor',
      debugShowCheckedModeBanner: false,
      themeMode: FyrTheme.themeMode,
      theme: ThemeData.light().copyWith(
        useMaterial3: true,
        scaffoldBackgroundColor: FyrTheme.bgColor,
        colorScheme: ColorScheme.light(
          primary: FyrTheme.accentColor,
          surface: FyrTheme.surfaceColor,
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        useMaterial3: true,
        scaffoldBackgroundColor: FyrTheme.bgColor,
        colorScheme: ColorScheme.dark(
          primary: FyrTheme.accentColor,
          surface: FyrTheme.surfaceColor,
        ),
      ),
      home: EditorScreen(initialDirectory: initialDirectory),
    ));
  }
}
