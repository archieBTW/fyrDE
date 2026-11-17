import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'engine/pixel_ops.dart';
import 'fyr_theme.dart';
import 'models/editor_types.dart';
import 'state/editor_controller.dart';
import 'widgets/canvas_viewport.dart';
import 'widgets/dialogs.dart';
import 'widgets/resizable_window.dart';
import 'widgets/right_dock.dart';
import 'widgets/tool_options_bar.dart';
import 'widgets/tools_dock.dart';
import 'widgets/top_bar.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(1420, 880),
    minimumSize: Size(960, 620),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    title: 'fyrGraphics',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final initialFile =
      args.isNotEmpty && File(args.first).existsSync() ? args.first : null;

  final controller = EditorController();
  await controller.initialize(initialFile: initialFile);

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const FyrGraphicsApp(),
    ),
  );
}

class FyrGraphicsApp extends StatelessWidget {
  const FyrGraphicsApp({super.key});

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
          title: 'fyrGraphics',
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
          home: const EditorShell(),
        );
      },
    );
  }
}

class EditorShell extends StatefulWidget {
  const EditorShell({super.key});

  @override
  State<EditorShell> createState() => _EditorShellState();
}

class _EditorShellState extends State<EditorShell> {
  final GlobalKey<CanvasViewportState> _viewportKey =
      GlobalKey<CanvasViewportState>();
  final FocusNode _rootFocus = FocusNode();
  bool _dragHovering = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportKey.currentState?.fitCurrentDocument();
      _rootFocus.requestFocus();
    });
  }

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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_isTypingInTextField()) return KeyEventResult.ignored;

    final ctrl = context.read<EditorController>();
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
      if (key == LogicalKeyboardKey.keyA) {
        ctrl.selectAll();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyD) {
        ctrl.deselect();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC) {
        ctrl.copySelection();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyX) {
        ctrl.cutSelection();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        ctrl.pasteClipboard();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyJ) {
        ctrl.duplicateActiveLayer();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyR) {
        ctrl.toggleRulers();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyN) {
        if (isShift) {
          ctrl.addNewLayer();
        } else {
          FyrDialogs.showNewDocument(context, ctrl);
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyO) {
        _openFileDialog(ctrl);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyS) {
        _saveOrExport(ctrl);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyE) {
        FyrDialogs.showExportDialog(context, ctrl);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyI) {
        if (isShift) {
          ctrl.invertSelection();
        } else {
          ctrl.runImmediateFilter(
            'Invert Colors',
            (s, w, h, m) => PixelOps.invertColors(s, selectionMask: m),
          );
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.equal ||
          key == LogicalKeyboardKey.numpadAdd) {
        ctrl.zoomBy(1.25);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.numpadSubtract) {
        ctrl.zoomBy(0.8);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit0 ||
          key == LogicalKeyboardKey.numpad0) {
        _viewportKey.currentState?.fitCurrentDocument();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.digit1 ||
          key == LogicalKeyboardKey.numpad1) {
        ctrl.resetZoom100();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    // Non-modifier shortcuts
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      ctrl.clearSelectedPixels();
      return KeyEventResult.handled;
    }

    final step = isShift ? 10.0 : 1.0;
    if (key == LogicalKeyboardKey.arrowLeft) {
      ctrl.moveActiveLayerBy(Offset(-step, 0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      ctrl.moveActiveLayerBy(Offset(step, 0));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      ctrl.moveActiveLayerBy(Offset(0, -step));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      ctrl.moveActiveLayerBy(Offset(0, step));
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.bracketLeft) {
      if (ctrl.activeTool == ToolType.eraser) {
        ctrl.eraserSize = (ctrl.eraserSize - 4).clamp(1, 250);
      } else {
        ctrl.brushSize = (ctrl.brushSize - 4).clamp(1, 250);
      }
      ctrl.refresh();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.bracketRight) {
      if (ctrl.activeTool == ToolType.eraser) {
        ctrl.eraserSize = (ctrl.eraserSize + 4).clamp(1, 250);
      } else {
        ctrl.brushSize = (ctrl.brushSize + 4).clamp(1, 250);
      }
      ctrl.refresh();
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.keyV) {
      ctrl.setTool(ToolType.move);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyM) {
      ctrl.setTool(isShift ? ToolType.ellipseSelect : ToolType.rectSelect);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyL) {
      ctrl.setTool(ToolType.lassoSelect);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyW) {
      ctrl.setTool(ToolType.magicWand);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyC) {
      ctrl.setTool(ToolType.crop);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyI) {
      ctrl.setTool(ToolType.eyedropper);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyB) {
      ctrl.setTool(ToolType.brush);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyN) {
      ctrl.setTool(ToolType.pencil);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyE) {
      ctrl.setTool(ToolType.eraser);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyS) {
      ctrl.setTool(ToolType.cloneStamp);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyG) {
      ctrl.setTool(isShift ? ToolType.gradient : ToolType.bucket);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyU) {
      ctrl.setTool(ToolType.shape);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyT) {
      ctrl.setTool(ToolType.text);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyH) {
      ctrl.setTool(ToolType.pan);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyZ) {
      ctrl.setTool(ToolType.zoom);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyX) {
      ctrl.swapColors();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.keyD) {
      ctrl.resetColors();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter && ctrl.activeTool == ToolType.crop) {
      ctrl.applyCrop();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _openFileDialog(EditorController ctrl) async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: [
        'png',
        'jpg',
        'jpeg',
        'webp',
        'bmp',
        'gif',
        'tga',
        'tiff',
        'fyrg',
      ],
    );
    if (res != null && res.files.single.path != null) {
      await ctrl.openFileFromPath(res.files.single.path!);
      _viewportKey.currentState?.fitCurrentDocument();
    }
  }

  Future<void> _saveOrExport(EditorController ctrl) async {
    final doc = ctrl.activeDoc;
    if (doc == null) return;
    if (doc.filePath != null && doc.filePath!.toLowerCase().endsWith('.fyrg')) {
      await ctrl.saveProjectToPath(doc.filePath!);
      return;
    }
    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Save fyrGraphics Project',
      fileName: '${doc.title.replaceAll(RegExp(r'\.[^.]+$'), '')}.fyrg',
      type: FileType.custom,
      allowedExtensions: ['fyrg'],
    );
    if (savePath != null) {
      await ctrl.saveProjectToPath(savePath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.read<EditorController>();

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragHovering = true),
      onDragExited: (_) => setState(() => _dragHovering = false),
      onDragDone: (detail) async {
        setState(() => _dragHovering = false);
        for (final file in detail.files) {
          try {
            await ctrl.openFileFromPath(file.path);
          } catch (e) {
            ctrl.setStatus('Could not open ${file.name}: $e');
          }
        }
        _viewportKey.currentState?.fitCurrentDocument();
      },
      child: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
        child: ResizableWindow(
          child: Scaffold(
            backgroundColor: FyrTheme.bgColor,
            body: Stack(
              children: [
                Column(
                  children: [
                    TopBar(
                      onFitViewport: () =>
                          _viewportKey.currentState?.fitCurrentDocument(),
                    ),
                    const ToolOptionsBar(),
                    Expanded(
                      child: Row(
                        children: [
                          const ToolsDock(),
                          CanvasViewport(key: _viewportKey),
                          RightDock(
                            onFitViewport: () =>
                                _viewportKey.currentState?.fitCurrentDocument(),
                          ),
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
                              'Drop Image or .fyrg Project to Open',
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
