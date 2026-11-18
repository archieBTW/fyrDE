import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';
import 'state/slides_controller.dart';
import 'widgets/element_toolbar.dart';
import 'widgets/resizable_window.dart';
import 'widgets/slide_canvas.dart';
import 'widgets/slide_filmstrip.dart';
import 'widgets/slide_inspector.dart';
import 'widgets/top_bar.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1440, 880),
    minimumSize: Size(980, 640),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'fyrSlides',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final controller = SlidesController();
  if (args.isNotEmpty && File(args.first).existsSync()) {
    await controller.openDeck(args.first);
  }

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const FyrSlidesApp(),
    ),
  );
}

class FyrSlidesApp extends StatelessWidget {
  const FyrSlidesApp({super.key});

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
          title: 'fyrSlides',
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
          home: const SlidesShell(),
        );
      },
    );
  }
}

class SlidesShell extends StatefulWidget {
  const SlidesShell({super.key});

  @override
  State<SlidesShell> createState() => _SlidesShellState();
}

class _SlidesShellState extends State<SlidesShell> {
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

    final ctrl = context.read<SlidesController>();
    final kb = HardwareKeyboard.instance;
    final isCtrl = kb.isControlPressed || kb.isMetaPressed;
    final key = event.logicalKey;

    if (ctrl.isPresenting) {
      if (key == LogicalKeyboardKey.escape) {
        ctrl.stopPresentation();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.pageDown) {
        ctrl.nextSlide();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.pageUp) {
        ctrl.prevSlide();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_isTypingInTextField()) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.f5) {
      ctrl.startPresentation(fromBeginning: kb.isShiftPressed);
      return KeyEventResult.handled;
    }

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
        ctrl.duplicateSelectedElement();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyM) {
        ctrl.addSlide();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.pageDown) {
      ctrl.nextSlide();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      ctrl.prevSlide();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      ctrl.deleteSelectedElement();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SlidesController>();

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragHovering = true),
      onDragExited: (_) => setState(() => _dragHovering = false),
      onDragDone: (detail) async {
        setState(() => _dragHovering = false);
        for (final f in detail.files) {
          final lower = f.path.toLowerCase();
          if (lower.endsWith('.odp') || lower.endsWith('.pptx')) {
            await ctrl.openDeck(f.path);
            break;
          }
        }
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
                    ElementToolbar(),
                    Expanded(
                      child: Row(
                        children: [
                          SlideFilmstrip(),
                          SlideCanvas(),
                          SlideInspector(),
                        ],
                      ),
                    ),
                  ],
                ),
                if (ctrl.isPresenting)
                  const Positioned.fill(
                    child: PresentationOverlay(),
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
                              'Drop OpenDocument (.odp) or PowerPoint (.pptx) Presentation',
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
