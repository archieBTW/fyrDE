import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';
import 'models/director_types.dart';
import 'state/director_controller.dart';
import 'widgets/inspector_panel.dart';
import 'widgets/media_bin_panel.dart';
import 'widgets/program_monitor.dart';
import 'widgets/resizable_window.dart';
import 'widgets/timeline_panel.dart';
import 'widgets/top_bar.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1440, 880),
    minimumSize: Size(980, 640),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'fyrDirector',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final controller = DirectorController();
  if (args.isNotEmpty && File(args.first).existsSync()) {
    final arg = args.first;
    if (arg.toLowerCase().endsWith('.fyrd')) {
      await controller.openProject(arg);
    } else {
      await controller.importMediaFiles([arg]);
      if (controller.mediaBin.isNotEmpty) {
        controller.addAssetToTimeline(controller.mediaBin.first);
      }
    }
  }

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const FyrDirectorApp(),
    ),
  );
}

class FyrDirectorApp extends StatelessWidget {
  const FyrDirectorApp({super.key});

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
          title: 'fyrDirector',
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
          home: const DirectorShell(),
        );
      },
    );
  }
}

class DirectorShell extends StatefulWidget {
  const DirectorShell({super.key});

  @override
  State<DirectorShell> createState() => _DirectorShellState();
}

class _DirectorShellState extends State<DirectorShell> {
  final FocusNode _rootFocus = FocusNode();
  bool _dragHovering = false;

  @override
  void dispose() {
    _rootFocus.dispose();
    super.dispose();
  }

  bool _isTypingInTextField() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null || focus == _rootFocus) return false;
    final ctx = focus.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_isTypingInTextField()) return KeyEventResult.ignored;

    final ctrl = context.read<DirectorController>();
    final kb = HardwareKeyboard.instance;
    final isCtrl = kb.isControlPressed || kb.isMetaPressed;
    final key = event.logicalKey;

    if (isCtrl) {
      if (key == LogicalKeyboardKey.keyZ) {
        kb.isShiftPressed ? ctrl.redo() : ctrl.undo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        ctrl.redo();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyD) {
        ctrl.duplicateSelectedClip();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.space) {
      ctrl.togglePlay();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      ctrl.stepFrame(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      ctrl.stepFrame(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      ctrl.seekTo(0.0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      ctrl.seekTo(ctrl.contentEndSec);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyV) {
      ctrl.activeTool = DirectorTool.select;
      ctrl.refresh();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      ctrl.activeTool = DirectorTool.razor;
      ctrl.refresh();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      ctrl.splitAtPlayhead();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      ctrl.snapEnabled = !ctrl.snapEnabled;
      ctrl.refresh();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      ctrl.deleteSelectedClip();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<DirectorController>();

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragHovering = true),
      onDragExited: (_) => setState(() => _dragHovering = false),
      onDragDone: (detail) async {
        setState(() => _dragHovering = false);
        final paths = detail.files.map((f) => f.path).toList();
        await ctrl.importMediaFiles(paths);
      },
      child: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: ResizableWindow(
          child: Scaffold(
            backgroundColor: FyrTheme.bgColor,
            body: Stack(
              children: [
                const Column(
                  children: [
                    TopBar(),
                    Expanded(
                      child: Row(
                        children: [
                          MediaBinPanel(),
                          ProgramMonitor(),
                          InspectorPanel(),
                        ],
                      ),
                    ),
                    TimelinePanel(),
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
                              'Drop Video, Audio, or Image Files to Import',
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
      ),
    );
  }
}
