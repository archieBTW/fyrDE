import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';
import 'state/sheets_controller.dart';
import 'widgets/bottom_sheet_bar.dart';
import 'widgets/charts_inspector_panel.dart';
import 'widgets/formula_ribbon.dart';
import 'widgets/resizable_window.dart';
import 'widgets/spreadsheet_grid.dart';
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
    title: 'fyrSheets',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final controller = SheetsController();
  if (args.isNotEmpty && File(args.first).existsSync()) {
    await controller.openWorkbookFromFile(args.first);
  }

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const FyrSheetsApp(),
    ),
  );
}

class FyrSheetsApp extends StatelessWidget {
  const FyrSheetsApp({super.key});

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
          title: 'fyrSheets',
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
          home: const SheetsShell(),
        );
      },
    );
  }
}

class SheetsShell extends StatefulWidget {
  const SheetsShell({super.key});

  @override
  State<SheetsShell> createState() => _SheetsShellState();
}

class _SheetsShellState extends State<SheetsShell> {
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

    final ctrl = context.read<SheetsController>();
    final kb = HardwareKeyboard.instance;
    final isCtrl = kb.isControlPressed || kb.isMetaPressed;
    final isShift = kb.isShiftPressed;
    final key = event.logicalKey;

    if (isCtrl) {
      if (key == LogicalKeyboardKey.keyZ) {
        isShift ? ctrl.redo() : ctrl.undo();
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
      return KeyEventResult.ignored;
    }

    if (key == LogicalKeyboardKey.arrowUp) {
      ctrl.moveSelection(-1, 0, extend: isShift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      ctrl.moveSelection(1, 0, extend: isShift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft) {
      ctrl.moveSelection(0, -1, extend: isShift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      ctrl.moveSelection(0, 1, extend: isShift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      ctrl.moveSelection(0, isShift ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      ctrl.moveSelection(isShift ? -1 : 1, 0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      ctrl.clearSelectedCells();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<SheetsController>();

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragHovering = true),
      onDragExited: (_) => setState(() => _dragHovering = false),
      onDragDone: (detail) async {
        setState(() => _dragHovering = false);
        if (detail.files.isNotEmpty) {
          await ctrl.openWorkbookFromFile(detail.files.first.path);
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
                    FormulaRibbon(),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: SpreadsheetGrid()),
                          ChartsInspectorPanel(),
                        ],
                      ),
                    ),
                    BottomSheetBar(),
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
                              horizontal: 24,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: FyrTheme.bgColor.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: FyrTheme.accentColor,
                                width: 2,
                              ),
                            ),
                            child: Text(
                              'Drop .ods, .xlsx, .csv, or .tsv Spreadsheet to Open',
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
