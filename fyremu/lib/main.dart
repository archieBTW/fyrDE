import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';
import 'state/emu_controller.dart';
import 'widgets/core_manager_dialog.dart';
import 'widgets/emulator_viewport.dart';
import 'widgets/library_view.dart';
import 'widgets/resizable_window.dart';
import 'widgets/top_bar.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1280, 820),
    minimumSize: Size(860, 560),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'fyrEmu',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final initialRom =
      args.isNotEmpty && File(args.first).existsSync() ? args.first : null;

  final controller = EmuController();
  await controller.initialize(initialRomPath: initialRom);

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const FyrEmuApp(),
    ),
  );
}

class FyrEmuApp extends StatelessWidget {
  const FyrEmuApp({super.key});

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
          title: 'fyrEmu',
          themeMode: FyrTheme.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.light(
              primary: accent,
              secondary: accent,
              surface: FyrTheme.surfaceColor,
            ),
            textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
            scaffoldBackgroundColor: Colors.white,
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.dark(
              primary: accent,
              secondary: accent,
              surface: FyrTheme.surfaceColor,
            ),
            textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
            scaffoldBackgroundColor: const Color(0xFF000000),
          ),
          home: const EmuShell(),
        );
      },
    );
  }
}

class EmuShell extends StatefulWidget {
  const EmuShell({super.key});

  @override
  State<EmuShell> createState() => _EmuShellState();
}

class _EmuShellState extends State<EmuShell> {
  bool _dragHovering = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    super.dispose();
  }

  bool _isTypingInTextField() {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onGlobalKey(KeyEvent event) {
    if (!mounted) return false;
    final ctrl = context.read<EmuController>();
    if (_isTypingInTextField()) return false;

    if (event is KeyDownEvent && ctrl.capturingButton == null && ctrl.isRunning) {
      if (event.logicalKey == LogicalKeyboardKey.f5) {
        ctrl.saveQuickState();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.f8) {
        ctrl.loadQuickState();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.keyP) {
        ctrl.togglePause();
        return true;
      }
      if (event.logicalKey == LogicalKeyboardKey.tab) {
        ctrl.cycleSpeed();
        return true;
      }
    }

    ctrl.handleKeyboardEvent(event);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<EmuController>();

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragHovering = true),
      onDragExited: (_) => setState(() => _dragHovering = false),
      onDragDone: (detail) async {
        setState(() => _dragHovering = false);
        if (detail.files.isNotEmpty) {
          final ok = await ctrl.launchRomFile(detail.files.first.path);
          if (!ok && context.mounted) {
            await CoreManagerDialog.show(context);
          }
        }
      },
      child: ResizableWindow(
        child: Scaffold(
          backgroundColor: FyrTheme.bgColor,
          body: Stack(
            children: [
              Column(
                children: [
                  const TopBar(),
                  if (ctrl.isRunning)
                    const EmulatorViewport()
                  else
                    const LibraryView(),
                ],
              ),
              if (_dragHovering)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      color: FyrTheme.accentColor.withValues(alpha: 0.14),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 14),
                          decoration: BoxDecoration(
                            color: FyrTheme.bgColor.withValues(alpha: 0.92),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: FyrTheme.accentColor, width: 2),
                          ),
                          child: Text(
                            'Drop ROM (.gb, .gbc, .gba, .nes, .sfc, .zip) to Play',
                            style: GoogleFonts.outfit(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: FyrTheme.textColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
