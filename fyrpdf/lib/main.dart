import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';
import 'state/pdf_app_controller.dart';
import 'widgets/pdf_canvas_view.dart';
import 'widgets/reader_toolbar.dart';
import 'widgets/resizable_window.dart';
import 'widgets/sidebar_panel.dart';
import 'widgets/top_bar.dart';
import 'widgets/welcome_view.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1280, 820),
    minimumSize: Size(840, 560),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'fyrPDF',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final controller = PdfAppController();
  await controller.initialize();

  // Open any existing .pdf file arguments passed via CLI or desktop file handler
  for (final rawArg in args) {
    final arg = rawArg.startsWith('file://')
        ? Uri.tryParse(rawArg)?.toFilePath() ?? rawArg
        : rawArg;
    if (arg.toLowerCase().endsWith('.pdf') && File(arg).existsSync()) {
      await controller.openFile(arg);
    }
  }

  runApp(FyrPdfApp(controller: controller));
}

class FyrPdfApp extends StatelessWidget {
  final PdfAppController? controller;
  const FyrPdfApp({super.key, this.controller});

  @override
  Widget build(BuildContext context) {
    final appWidget = AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
      builder: (context, _) {
        final accent = FyrTheme.accentColor;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'fyrPDF',
          themeMode: FyrTheme.themeMode,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.light(
              primary: accent,
              secondary: accent,
              surface: FyrTheme.surfaceColor,
            ),
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
            scaffoldBackgroundColor: const Color(0xFF000000),
          ),
          home: const PdfShell(),
        );
      },
    );

    if (controller != null) {
      return ChangeNotifierProvider.value(
        value: controller!,
        child: appWidget,
      );
    }

    return ChangeNotifierProvider(
      create: (_) => PdfAppController()..initialize(),
      child: appWidget,
    );
  }
}

class PdfShell extends StatefulWidget {
  const PdfShell({super.key});

  @override
  State<PdfShell> createState() => _PdfShellState();
}

class _PdfShellState extends State<PdfShell> {
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

    final ctrl = context.read<PdfAppController>();
    final kb = HardwareKeyboard.instance;
    final isCtrl = kb.isControlPressed || kb.isMetaPressed;
    final key = event.logicalKey;

    if (isCtrl) {
      if (key == LogicalKeyboardKey.keyO) {
        pickAndOpenPdfFiles(ctrl);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyW && ctrl.hasOpenDocument) {
        ctrl.closeActiveTab();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyF && ctrl.hasOpenDocument) {
        ctrl.openSearchBar();
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.equal ||
              key == LogicalKeyboardKey.add ||
              key == LogicalKeyboardKey.numpadAdd) &&
          ctrl.hasOpenDocument) {
        ctrl.zoomIn();
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.minus ||
              key == LogicalKeyboardKey.numpadSubtract) &&
          ctrl.hasOpenDocument) {
        ctrl.zoomOut();
        return KeyEventResult.handled;
      }
      if ((key == LogicalKeyboardKey.digit0 ||
              key == LogicalKeyboardKey.numpad0) &&
          ctrl.hasOpenDocument) {
        ctrl.resetZoom();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyB && ctrl.hasOpenDocument) {
        ctrl.toggleSidebar();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyD && ctrl.hasOpenDocument) {
        ctrl.toggleBookmarkForCurrentPage();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyI && ctrl.hasOpenDocument) {
        ctrl.toggleDarkReadingMode();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Do not intercept navigation keys while typing inside a TextField
    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
    if (focusedWidget is EditableText) {
      return KeyEventResult.ignored;
    }

    if (!ctrl.hasOpenDocument) return KeyEventResult.ignored;

    if (key == LogicalKeyboardKey.pageDown) {
      ctrl.nextPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      ctrl.previousPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      ctrl.firstPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      ctrl.lastPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape &&
        (ctrl.activeTab?.showSearchBar ?? false)) {
      ctrl.closeSearchBar();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<PdfAppController>();

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragHovering = true),
      onDragExited: (_) => setState(() => _dragHovering = false),
      onDragDone: (detail) async {
        setState(() => _dragHovering = false);
        int opened = 0;
        for (final file in detail.files) {
          if (file.path.toLowerCase().endsWith('.pdf')) {
            final ok = await ctrl.openFile(file.path);
            if (ok) opened++;
          }
        }
        if (opened == 0 && detail.files.isNotEmpty) {
          ctrl.setStatus('Only .pdf files can be opened in fyrPDF');
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
                Column(
                  children: [
                    const TopBar(),
                    if (ctrl.hasOpenDocument) const ReaderToolbar(),
                    Expanded(
                      child: ctrl.hasOpenDocument
                          ? const Row(
                              children: [
                                SidebarPanel(),
                                Expanded(child: PdfCanvasView()),
                              ],
                            )
                          : const WelcomeView(),
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
                                horizontal: 24, vertical: 16),
                            decoration: BoxDecoration(
                              color: FyrTheme.bgColor.withValues(alpha: 0.94),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: FyrTheme.accentColor,
                                width: 2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.picture_as_pdf_rounded,
                                  size: 22,
                                  color: FyrTheme.accentColor,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  'Drop PDF Document to Open in fyrPDF',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: FyrTheme.textColor,
                                  ),
                                ),
                              ],
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
