import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';
import 'state/docs_controller.dart';
import 'widgets/document_canvas.dart';
import 'widgets/formatting_ribbon.dart';
import 'widgets/left_panel.dart';
import 'widgets/resizable_window.dart';
import 'widgets/right_inspector.dart';
import 'widgets/top_bar.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1440, 880),
    minimumSize: Size(960, 620),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'fyrDocs',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final controller = DocsController();
  if (args.isNotEmpty && File(args.first).existsSync()) {
    await controller.openDocumentFile(args.first);
  }

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const FyrDocsApp(),
    ),
  );
}

class FyrDocsApp extends StatelessWidget {
  const FyrDocsApp({super.key});

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
          title: 'fyrDocs',
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
          home: const DocsShell(),
        );
      },
    );
  }
}

class DocsShell extends StatefulWidget {
  const DocsShell({super.key});

  @override
  State<DocsShell> createState() => _DocsShellState();
}

class _DocsShellState extends State<DocsShell> {
  final FocusNode _rootFocus = FocusNode();
  bool _dragHovering = false;

  @override
  void dispose() {
    _rootFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final ctrl = context.read<DocsController>();
    final kb = HardwareKeyboard.instance;
    final isCtrl = kb.isControlPressed || kb.isMetaPressed;
    final key = event.logicalKey;

    if (!isCtrl) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.keyZ) {
      kb.isShiftPressed ? ctrl.redo() : ctrl.undo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyY) {
      ctrl.redo();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB) {
      ctrl.toggleBold();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyI) {
      ctrl.toggleItalic();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyU) {
      ctrl.toggleUnderline();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyF) {
      ctrl.showFindBar = !ctrl.showFindBar;
      ctrl.refresh();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      ctrl.newBlankDocument();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      final path = ctrl.document.filePath;
      if (path != null) {
        ctrl.saveDocumentFile(path);
      } else {
        FilePicker.saveFile(
          dialogTitle: 'Save OpenDocument (.odt)',
          fileName: '${ctrl.document.title}.${ctrl.document.format}',
        ).then((out) {
          if (out != null) ctrl.saveDocumentFile(out);
        });
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyO) {
      FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['odt', 'docx', 'doc', 'rtf', 'md', 'html', 'txt'],
      ).then((res) {
        if (res != null && res.files.single.path != null) {
          ctrl.openDocumentFile(res.files.single.path!);
        }
      });
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<DocsController>();

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragHovering = true),
      onDragExited: (_) => setState(() => _dragHovering = false),
      onDragDone: (detail) async {
        setState(() => _dragHovering = false);
        if (detail.files.isNotEmpty) {
          await ctrl.openDocumentFile(detail.files.first.path);
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
                    FormattingRibbon(),
                    Expanded(
                      child: Row(
                        children: [
                          LeftPanel(),
                          DocumentCanvas(),
                          RightInspector(),
                        ],
                      ),
                    ),
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
                              'Drop .ODT, .DOCX, .MD, or .TXT Document to Open',
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
