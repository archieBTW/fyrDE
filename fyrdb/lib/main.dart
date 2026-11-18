import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'fyr_theme.dart';
import 'models/db_models.dart';
import 'state/db_controller.dart';
import 'widgets/data_browser_panel.dart';
import 'widgets/db_navigator.dart';
import 'widgets/er_diagram_canvas.dart';
import 'widgets/resizable_window.dart';
import 'widgets/sql_editor_panel.dart';
import 'widgets/structure_ddl_panel.dart';
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
    title: 'fyrDB',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  final controller = DbController();
  if (args.isNotEmpty) {
    final existing = args.where((p) => File(p).existsSync()).toList();
    if (existing.isNotEmpty) {
      await controller.openFiles(existing);
    }
  }

  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const FyrDbApp(),
    ),
  );
}

class FyrDbApp extends StatelessWidget {
  final DbController? controller;
  const FyrDbApp({super.key, this.controller});

  @override
  Widget build(BuildContext context) {
    Widget app = AnimatedBuilder(
      animation: Listenable.merge([
        FyrTheme.accentColorNotifier,
        FyrTheme.themeModeNotifier,
      ]),
      builder: (context, _) {
        final accent = FyrTheme.accentColor;
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'fyrDB',
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
          home: const DbShell(),
        );
      },
    );

    if (controller != null) {
      return ChangeNotifierProvider.value(value: controller!, child: app);
    }
    // Ensure a provider exists if FyrDbApp is instantiated directly in tests
    return Builder(
      builder: (ctx) {
        try {
          ctx.read<DbController>();
          return app;
        } catch (_) {
          return ChangeNotifierProvider(
            create: (_) => DbController(),
            child: app,
          );
        }
      },
    );
  }
}

class DbShell extends StatefulWidget {
  const DbShell({super.key});

  @override
  State<DbShell> createState() => _DbShellState();
}

class _DbShellState extends State<DbShell> {
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

    final ctrl = context.read<DbController>();
    final kb = HardwareKeyboard.instance;
    final isCtrl = kb.isControlPressed || kb.isMetaPressed;
    final key = event.logicalKey;

    if (isCtrl) {
      if (key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter) {
        ctrl.runActiveQuery();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyN) {
        ctrl.newSqlTab();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyS) {
        if (ctrl.pendingEditCount > 0) {
          ctrl.commitPendingChanges();
        } else {
          ctrl.formatActiveSql();
        }
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DbController>();

    return DropTarget(
      onDragEntered: (_) => setState(() => _dragHovering = true),
      onDragExited: (_) => setState(() => _dragHovering = false),
      onDragDone: (detail) async {
        setState(() => _dragHovering = false);
        final paths = detail.files.map((f) => f.path).toList();
        await ctrl.openFiles(paths);
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
                    Expanded(
                      child: Row(
                        children: [
                          const DbNavigator(),
                          Expanded(child: _buildActiveWorkspace(ctrl)),
                        ],
                      ),
                    ),
                    _buildStatusBar(ctrl),
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
                              'Drop .sqlite, .db, or .sql Files to Mount & Execute',
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

  Widget _buildActiveWorkspace(DbController ctrl) {
    switch (ctrl.workspaceMode) {
      case DbWorkspaceMode.sqlEditor:
        return const SqlEditorPanel();
      case DbWorkspaceMode.dataGrid:
        return const DataBrowserPanel();
      case DbWorkspaceMode.structureDdl:
        return const StructureDdlPanel();
      case DbWorkspaceMode.erDiagram:
        return const ErDiagramCanvas();
    }
  }

  Widget _buildStatusBar(DbController ctrl) {
    final accent = FyrTheme.accentColor;
    final conn = ctrl.activeConnection;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFF4ADE80),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${conn.name} • ${conn.driver.label}',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: FyrTheme.textColor,
            ),
          ),
          const SizedBox(width: 14),
          if (ctrl.statusMessage != null)
            Expanded(
              child: Text(
                ctrl.statusMessage!,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10.5,
                  color: accent,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            )
          else
            const Spacer(),
          Text(
            'Selected: ${ctrl.selectedTableName}  •  Ctrl+Enter Run SQL  •  Ctrl+N New Tab',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: FyrTheme.textColorMuted,
            ),
          ),
        ],
      ),
    );
  }
}
