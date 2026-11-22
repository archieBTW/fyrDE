import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'engine/devign_export.dart';
import 'fyr_theme.dart';
import 'models/design_models.dart';
import 'state/devign_controller.dart';
import 'widgets/design_canvas.dart';
import 'widgets/resizable_window.dart';
import 'widgets/traffic_lights.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  FyrTheme.initialize();

  try {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1480, 920),
      minimumSize: Size(1024, 680),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'devign',
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  } catch (_) {
    // Allow running in headless widget test environments without window_manager.
  }

  final initialPath = args.isNotEmpty ? args.first : null;
  runApp(DevignApp(initialProjectPath: initialPath));
}

class DevignApp extends StatefulWidget {
  final String? initialProjectPath;
  const DevignApp({super.key, this.initialProjectPath});

  @override
  State<DevignApp> createState() => _DevignAppState();
}

class _DevignAppState extends State<DevignApp> {
  late final DevignController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DevignController();
    final path = widget.initialProjectPath;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      _controller.openProjectFromPath(path);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DevignController>.value(
      value: _controller,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          FyrTheme.accentColorNotifier,
          FyrTheme.themeModeNotifier,
        ]),
        builder: (context, _) {
          final isDark = FyrTheme.isDark;
          final accent = FyrTheme.accentColor;
          final baseTheme = isDark ? ThemeData.dark() : ThemeData.light();

          return MaterialApp(
            title: 'devign',
            debugShowCheckedModeBanner: false,
            themeMode: FyrTheme.themeMode,
            theme: baseTheme.copyWith(
              scaffoldBackgroundColor: FyrTheme.bgColor,
              colorScheme: baseTheme.colorScheme.copyWith(
                primary: accent,
                secondary: accent,
                surface: FyrTheme.surfaceColor,
              ),
              dividerColor: FyrTheme.dividerColor,
              sliderTheme: SliderThemeData(
                activeTrackColor: accent,
                thumbColor: accent,
                trackHeight: 3,
              ),
            ),
            home: const ResizableWindow(
              child: DevignStudioShell(),
            ),
          );
        },
      ),
    );
  }
}

class DevignStudioShell extends StatefulWidget {
  const DevignStudioShell({super.key});

  @override
  State<DevignStudioShell> createState() => _DevignStudioShellState();
}

class _DevignStudioShellState extends State<DevignStudioShell> {
  final FocusNode _shellFocus = FocusNode();

  @override
  void dispose() {
    _shellFocus.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null &&
        primaryFocus != _shellFocus &&
        primaryFocus.context?.widget is EditableText) {
      return KeyEventResult.ignored;
    }

    final ctrl = context.read<DevignController>();
    final hw = HardwareKeyboard.instance;
    final isMod = hw.isControlPressed || hw.isMetaPressed;
    final isShift = hw.isShiftPressed;
    final isAlt = hw.isAltPressed;
    final k = event.logicalKey;

    if (isMod) {
      if (k == LogicalKeyboardKey.keyZ) {
        if (isShift) {
          ctrl.redo();
        } else {
          ctrl.undo();
        }
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyY) {
        ctrl.redo();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyC) {
        ctrl.copySelected();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyV) {
        ctrl.pasteClipboard();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyD) {
        ctrl.duplicateSelected();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyG) {
        if (isShift) {
          ctrl.ungroupSelection();
        } else {
          ctrl.groupSelection();
        }
        return KeyEventResult.handled;
      }
      if (isAlt && k == LogicalKeyboardKey.keyK) {
        ctrl.createComponentFromSelection();
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.equal || k == LogicalKeyboardKey.numpadAdd) {
        ctrl.setZoom(ctrl.activePage.zoom * 1.15);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.minus ||
          k == LogicalKeyboardKey.numpadSubtract) {
        ctrl.setZoom(ctrl.activePage.zoom * 0.87);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.digit0) {
        ctrl.setZoom(1.0, pan: Offset.zero);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyS) {
        _saveProject(context, ctrl);
        return KeyEventResult.handled;
      }
      if (k == LogicalKeyboardKey.keyO) {
        _openProject(context, ctrl);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (k == LogicalKeyboardKey.delete || k == LogicalKeyboardKey.backspace) {
      ctrl.deleteSelected();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (ctrl.activeTool == DevignTool.pen) {
        ctrl.finishPenPath(closed: false);
      } else {
        ctrl.selectNode(null);
        ctrl.setTool(DevignTool.select);
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyV) {
      ctrl.setTool(DevignTool.select);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyH) {
      ctrl.setTool(DevignTool.hand);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyF) {
      ctrl.setTool(DevignTool.frame);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyR) {
      ctrl.setTool(DevignTool.rectangle);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyO) {
      ctrl.setTool(DevignTool.ellipse);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyY) {
      ctrl.setTool(DevignTool.polygon);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyS) {
      ctrl.setTool(DevignTool.star);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyL) {
      ctrl.setTool(DevignTool.line);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyA) {
      ctrl.setTool(DevignTool.arrow);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyP) {
      ctrl.setTool(DevignTool.pen);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyT) {
      ctrl.setTool(DevignTool.text);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyC) {
      ctrl.setTool(DevignTool.comment);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Future<void> _openProject(BuildContext context, DevignController ctrl) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Open .devign Project',
      type: FileType.any,
    );
    final path = result?.files.single.path;
    if (path != null) {
      await ctrl.openProjectFromPath(path);
    }
  }

  Future<void> _saveProject(BuildContext context, DevignController ctrl) async {
    String? outPath = ctrl.filePath;
    outPath ??= await FilePicker.saveFile(
      dialogTitle: 'Save .devign Project',
      fileName: '${ctrl.documentTitle.replaceAll(' ', '_').toLowerCase()}.devign',
    );
    if (outPath != null) {
      await ctrl.saveProjectToPath(outPath);
    }
  }

  Future<void> _placeImage(BuildContext context, DevignController ctrl) async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Place Image Layer',
      type: FileType.image,
    );
    final path = result?.files.single.path;
    if (path != null) {
      await ctrl.placeImageFile(path);
    }
  }

  Future<void> _showExportModal(
    BuildContext context,
    DevignController ctrl,
  ) async {
    final target = ctrl.primarySelected ??
        (ctrl.activePage.rootIds.isNotEmpty
            ? ctrl.nodes[ctrl.activePage.rootIds.first]
            : null);
    if (target == null) {
      ctrl.setStatus('Select a frame or layer to export');
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => _ExportStudioDialog(ctrl: ctrl, target: target),
    );
  }

  Future<void> _showPrototypeModal(
    BuildContext context,
    DevignController ctrl,
  ) async {
    final frames = ctrl.getTopLevelFrames();
    if (frames.isEmpty) {
      ctrl.setStatus('Add at least one Frame to present a prototype');
      return;
    }
    final initialId = ctrl.activePage.flowStartFrameId ?? frames.first.id;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _PrototypePlayerDialog(
        ctrl: ctrl,
        initialFrameId: initialId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DevignController>();

    return Focus(
      focusNode: _shellFocus,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: FyrTheme.bgColor,
        body: Column(
          children: [
            _DevignTopBar(
              onOpen: () => _openProject(context, ctrl),
              onSave: () => _saveProject(context, ctrl),
              onPlaceImage: () => _placeImage(context, ctrl),
              onExport: () => _showExportModal(context, ctrl),
              onPresent: () => _showPrototypeModal(context, ctrl),
            ),
            Expanded(
              child: Row(
                children: [
                  if (ctrl.showLeftPanel) const _DevignLeftSidebar(),
                  const DesignCanvas(),
                  if (ctrl.showRightPanel)
                    _DevignRightInspector(
                      onPresent: () => _showPrototypeModal(context, ctrl),
                      onExport: () => _showExportModal(context, ctrl),
                    ),
                ],
              ),
            ),
            const _DevignStatusBar(),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// TOP STUDIO BAR
// =============================================================================

class _DevignTopBar extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback onPlaceImage;
  final VoidCallback onExport;
  final VoidCallback onPresent;

  const _DevignTopBar({
    required this.onOpen,
    required this.onSave,
    required this.onPlaceImage,
    required this.onExport,
    required this.onPresent,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DevignController>();
    final accent = FyrTheme.accentColor;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor,
        border: Border(
          bottom: BorderSide(color: FyrTheme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          const TrafficLights(),
          const SizedBox(width: 12),
          // Brand pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent, const Color(0xFF7C4DFF)],
              ),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_mosaic_rounded,
                    size: 13, color: Colors.white),
                SizedBox(width: 5),
                Text(
                  'devign',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Panel & view toggles
          _TopIconBtn(
            icon: Icons.view_sidebar_outlined,
            tooltip: 'Toggle Left Sidebar',
            active: ctrl.showLeftPanel,
            onTap: () {
              ctrl.showLeftPanel = !ctrl.showLeftPanel;
              ctrl.refresh();
            },
          ),
          const SizedBox(width: 4),
          // Editable document title
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () => _promptRenameDocument(context, ctrl),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${ctrl.documentTitle}${ctrl.dirty ? " •" : ""}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.textColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.edit_outlined,
                      size: 12, color: FyrTheme.textColorMuted),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Center tool palette
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ToolButton(
                    tool: DevignTool.select,
                    icon: Icons.near_me_rounded,
                    label: 'Move (V)',
                  ),
                  _ToolButton(
                    tool: DevignTool.hand,
                    icon: Icons.pan_tool_alt_outlined,
                    label: 'Hand (H)',
                  ),
                  _vDivider(),
                  _ToolButton(
                    tool: DevignTool.frame,
                    icon: Icons.grid_3x3_rounded,
                    label: 'Frame (F)',
                  ),
                  _ToolButton(
                    tool: DevignTool.rectangle,
                    icon: Icons.crop_square_rounded,
                    label: 'Rectangle (R)',
                  ),
                  _ToolButton(
                    tool: DevignTool.ellipse,
                    icon: Icons.circle_outlined,
                    label: 'Ellipse (O)',
                  ),
                  _ToolButton(
                    tool: DevignTool.polygon,
                    icon: Icons.hexagon_outlined,
                    label: 'Polygon (Y)',
                  ),
                  _ToolButton(
                    tool: DevignTool.star,
                    icon: Icons.star_border_rounded,
                    label: 'Star (S)',
                  ),
                  _ToolButton(
                    tool: DevignTool.line,
                    icon: Icons.horizontal_rule_rounded,
                    label: 'Line (L)',
                  ),
                  _ToolButton(
                    tool: DevignTool.arrow,
                    icon: Icons.north_east_rounded,
                    label: 'Arrow (A)',
                  ),
                  _ToolButton(
                    tool: DevignTool.pen,
                    icon: Icons.edit_road_rounded,
                    label: 'Bezier Pen (P)',
                  ),
                  _ToolButton(
                    tool: DevignTool.text,
                    icon: Icons.title_rounded,
                    label: 'Text (T)',
                  ),
                  _TopIconBtn(
                    icon: Icons.image_outlined,
                    tooltip: 'Place Image',
                    onTap: onPlaceImage,
                  ),
                  _ToolButton(
                    tool: DevignTool.comment,
                    icon: Icons.mode_comment_outlined,
                    label: 'Comment (C)',
                  ),
                  _vDivider(),
                  _TopIconBtn(
                    icon: Icons.undo_rounded,
                    tooltip: 'Undo (Ctrl+Z)',
                    enabled: ctrl.canUndo,
                    onTap: ctrl.undo,
                  ),
                  _TopIconBtn(
                    icon: Icons.redo_rounded,
                    tooltip: 'Redo (Ctrl+Shift+Z)',
                    enabled: ctrl.canRedo,
                    onTap: ctrl.redo,
                  ),
                  _vDivider(),
                  _TopIconBtn(
                    icon: Icons.workspaces_outlined,
                    tooltip: 'Create Master Component (Ctrl+Alt+K)',
                    enabled: ctrl.primarySelected != null,
                    onTap: ctrl.createComponentFromSelection,
                  ),
                  _TopIconBtn(
                    icon: Icons.folder_copy_outlined,
                    tooltip: 'Group Selection (Ctrl+G)',
                    enabled: ctrl.selectedIds.length >= 2,
                    onTap: ctrl.groupSelection,
                  ),
                  _TopIconBtn(
                    icon: Icons.grid_on_rounded,
                    tooltip: 'Toggle Dot Grid',
                    active: ctrl.showGrid,
                    onTap: () {
                      ctrl.showGrid = !ctrl.showGrid;
                      ctrl.refresh();
                    },
                  ),
                  _TopIconBtn(
                    icon: Icons.straighten_rounded,
                    tooltip: 'Smart Snap Guides',
                    active: ctrl.snapToGuides,
                    onTap: () {
                      ctrl.snapToGuides = !ctrl.snapToGuides;
                      ctrl.refresh();
                    },
                  ),
                ],
              ),
            ),
          ),
          // Zoom pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: FyrTheme.cardColor,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: FyrTheme.dividerColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => ctrl.setZoom(ctrl.activePage.zoom * 0.85),
                  child: const Icon(Icons.remove, size: 13),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => ctrl.setZoom(1.0, pan: Offset.zero),
                  child: Text(
                    '${(ctrl.activePage.zoom * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  onTap: () => ctrl.setZoom(ctrl.activePage.zoom * 1.15),
                  child: const Icon(Icons.add, size: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TopIconBtn(
            icon: Icons.folder_open_rounded,
            tooltip: 'Open Project (Ctrl+O)',
            onTap: onOpen,
          ),
          _TopIconBtn(
            icon: Icons.save_outlined,
            tooltip: 'Save Project (Ctrl+S)',
            onTap: onSave,
          ),
          const SizedBox(width: 6),
          // Present Prototype button
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              minimumSize: const Size(0, 30),
              backgroundColor: const Color(0xFF40C4FF).withValues(alpha: 0.16),
              foregroundColor: const Color(0xFF40C4FF),
            ),
            onPressed: onPresent,
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text(
              'Present',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 6),
          // Export button
          FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
              minimumSize: const Size(0, 30),
              backgroundColor: accent,
              foregroundColor: Colors.white,
            ),
            onPressed: onExport,
            icon: const Icon(Icons.download_rounded, size: 14),
            label: const Text(
              'Export',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 6),
          _TopIconBtn(
            icon: Icons.vertical_split_outlined,
            tooltip: 'Toggle Right Inspector',
            active: ctrl.showRightPanel,
            onTap: () {
              ctrl.showRightPanel = !ctrl.showRightPanel;
              ctrl.refresh();
            },
          ),
        ],
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        color: FyrTheme.dividerColor,
      );

  Future<void> _promptRenameDocument(
    BuildContext context,
    DevignController ctrl,
  ) async {
    final tc = TextEditingController(text: ctrl.documentTitle);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: const Text('Rename Document', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: tc,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, tc.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (res != null && res.isNotEmpty) {
      ctrl.documentTitle = res;
      ctrl.dirty = true;
      ctrl.refresh();
    }
  }
}

class _ToolButton extends StatelessWidget {
  final DevignTool tool;
  final IconData icon;
  final String label;

  const _ToolButton({
    required this.tool,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DevignController>();
    final active = ctrl.activeTool == tool;
    return _TopIconBtn(
      icon: icon,
      tooltip: label,
      active: active,
      onTap: () => ctrl.setTool(tool),
    );
  }
}

class _TopIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;

  const _TopIconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final accent = FyrTheme.accentColor;
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: enabled ? onTap : null,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: active
                  ? accent.withValues(alpha: 0.22)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
              border: active
                  ? Border.all(color: accent.withValues(alpha: 0.6))
                  : null,
            ),
            child: Icon(
              icon,
              size: 16,
              color: !enabled
                  ? FyrTheme.textColorMuted.withValues(alpha: 0.35)
                  : (active ? accent : FyrTheme.textColor),
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// LEFT SIDEBAR (Layers & Pages / Assets & UI Kit / Tokens & Comments)
// =============================================================================

class _DevignLeftSidebar extends StatelessWidget {
  const _DevignLeftSidebar();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DevignController>();

    return Container(
      width: 268,
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor,
        border: Border(right: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        children: [
          // 3-tab selector
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              children: [
                _SidebarTabPill(
                  label: 'Layers',
                  icon: Icons.layers_outlined,
                  selected: ctrl.leftPanelTab == 0,
                  onTap: () {
                    ctrl.leftPanelTab = 0;
                    ctrl.refresh();
                  },
                ),
                const SizedBox(width: 4),
                _SidebarTabPill(
                  label: 'Assets',
                  icon: Icons.widgets_outlined,
                  selected: ctrl.leftPanelTab == 1,
                  onTap: () {
                    ctrl.leftPanelTab = 1;
                    ctrl.refresh();
                  },
                ),
                const SizedBox(width: 4),
                _SidebarTabPill(
                  label: 'Tokens',
                  icon: Icons.palette_outlined,
                  selected: ctrl.leftPanelTab == 2,
                  onTap: () {
                    ctrl.leftPanelTab = 2;
                    ctrl.refresh();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (ctrl.leftPanelTab) {
              0 => const _LeftLayersAndPagesTab(),
              1 => const _LeftAssetsAndComponentsTab(),
              _ => const _LeftTokensAndCommentsTab(),
            },
          ),
        ],
      ),
    );
  }
}

class _SidebarTabPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarTabPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = FyrTheme.accentColor;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: selected
                ? Border.all(color: accent.withValues(alpha: 0.45))
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: selected ? accent : FyrTheme.textColorMuted,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? FyrTheme.textColor : FyrTheme.textColorMuted,
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

class _LeftLayersAndPagesTab extends StatelessWidget {
  const _LeftLayersAndPagesTab();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DevignController>();
    final query = ctrl.layerSearchQuery.trim().toLowerCase();

    final flatEntries = <(DesignNode, int)>[];
    void walk(List<String> ids, int depth) {
      for (int i = ids.length - 1; i >= 0; i--) {
        final n = ctrl.nodes[ids[i]];
        if (n == null) continue;
        if (query.isEmpty || n.name.toLowerCase().contains(query)) {
          flatEntries.add((n, depth));
        }
        if (n.children.isNotEmpty) {
          walk(n.children, depth + 1);
        }
      }
    }

    walk(ctrl.activePage.rootIds, 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Pages section header
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 4),
          child: Row(
            children: [
              Text(
                'PAGES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: FyrTheme.textColorMuted,
                ),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(4),
                onTap: () => ctrl.addPage(),
                child: const Padding(
                  padding: EdgeInsets.all(3),
                  child: Icon(Icons.add, size: 14),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: min(105, ctrl.pages.length * 28.0 + 6),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            itemCount: ctrl.pages.length,
            itemBuilder: (ctx, idx) {
              final pg = ctrl.pages[idx];
              final isCur = idx == ctrl.activePageIndex;
              return InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => ctrl.switchPage(idx),
                child: Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: isCur
                        ? FyrTheme.accentColor.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isCur
                            ? Icons.insert_drive_file_rounded
                            : Icons.insert_drive_file_outlined,
                        size: 13,
                        color: isCur
                            ? FyrTheme.accentColor
                            : FyrTheme.textColorMuted,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          pg.name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight:
                                isCur ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      Text(
                        '${pg.rootIds.length}',
                        style: TextStyle(
                          fontSize: 10,
                          color: FyrTheme.textColorMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Divider(height: 8, color: FyrTheme.dividerColor),
        // Layer filter box
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SizedBox(
            height: 28,
            child: TextField(
              style: const TextStyle(fontSize: 11.5),
              onChanged: (v) {
                ctrl.layerSearchQuery = v;
                ctrl.refresh();
              },
              decoration: InputDecoration(
                hintText: 'Filter layers...',
                hintStyle:
                    TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
                prefixIcon: const Icon(Icons.search, size: 14),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                filled: true,
                fillColor: FyrTheme.cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        // Layer tree
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            itemCount: flatEntries.length,
            itemBuilder: (ctx, i) {
              final (node, depth) = flatEntries[i];
              final selected = ctrl.selectedIds.contains(node.id);
              final isComp = node.type == NodeType.component ||
                  node.type == NodeType.instance;

              return GestureDetector(
                onDoubleTap: () => _renameLayer(context, ctrl, node),
                child: InkWell(
                  borderRadius: BorderRadius.circular(5),
                  onTap: () => ctrl.selectNode(
                    node.id,
                    additive: HardwareKeyboard.instance.isShiftPressed,
                  ),
                  child: Container(
                    height: 27,
                    padding:
                        EdgeInsets.only(left: 6.0 + depth * 14.0, right: 4),
                    decoration: BoxDecoration(
                      color: selected
                          ? (isComp
                              ? const Color(0xFFBB86FC).withValues(alpha: 0.22)
                              : FyrTheme.accentColor.withValues(alpha: 0.2))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _iconForNodeType(node.type),
                          size: 13,
                          color: isComp
                              ? const Color(0xFFBB86FC)
                              : (selected
                                  ? FyrTheme.accentColor
                                  : FyrTheme.textColorMuted),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            node.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                              color: !node.visible
                                  ? FyrTheme.textColorMuted
                                      .withValues(alpha: 0.45)
                                  : (isComp
                                      ? const Color(0xFFBB86FC)
                                      : FyrTheme.textColor),
                            ),
                          ),
                        ),
                        if (node.autoLayout.enabled)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              node.autoLayout.direction ==
                                      AutoLayoutDirection.horizontal
                                  ? Icons.view_column_outlined
                                  : Icons.view_stream_outlined,
                              size: 11,
                              color: const Color(0xFF40C4FF),
                            ),
                          ),
                        InkWell(
                          onTap: () => ctrl.reorderNode(node.id, 1),
                          child: Icon(Icons.keyboard_arrow_up,
                              size: 13, color: FyrTheme.textColorMuted),
                        ),
                        InkWell(
                          onTap: () => ctrl.reorderNode(node.id, -1),
                          child: Icon(Icons.keyboard_arrow_down,
                              size: 13, color: FyrTheme.textColorMuted),
                        ),
                        const SizedBox(width: 2),
                        InkWell(
                          onTap: () {
                            node.locked = !node.locked;
                            ctrl.refresh();
                          },
                          child: Icon(
                            node.locked
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            size: 12,
                            color: node.locked
                                ? Colors.amber
                                : FyrTheme.textColorMuted.withValues(alpha: 0.4),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () {
                            node.visible = !node.visible;
                            ctrl.refresh();
                          },
                          child: Icon(
                            node.visible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 12,
                            color: node.visible
                                ? FyrTheme.textColorMuted
                                : FyrTheme.textColorMuted.withValues(alpha: 0.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  IconData _iconForNodeType(NodeType t) => switch (t) {
        NodeType.frame => Icons.grid_3x3_rounded,
        NodeType.group => Icons.folder_outlined,
        NodeType.component => Icons.diamond_rounded,
        NodeType.instance => Icons.diamond_outlined,
        NodeType.rectangle => Icons.crop_square_rounded,
        NodeType.ellipse => Icons.circle_outlined,
        NodeType.polygon => Icons.hexagon_outlined,
        NodeType.star => Icons.star_border_rounded,
        NodeType.line => Icons.horizontal_rule_rounded,
        NodeType.arrow => Icons.north_east_rounded,
        NodeType.path => Icons.timeline_rounded,
        NodeType.text => Icons.title_rounded,
        NodeType.image => Icons.image_outlined,
      };

  Future<void> _renameLayer(
    BuildContext context,
    DevignController ctrl,
    DesignNode node,
  ) async {
    final tc = TextEditingController(text: node.name);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: const Text('Rename Layer', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: tc,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, tc.text.trim()),
              child: const Text('Rename')),
        ],
      ),
    );
    if (res != null && res.isNotEmpty) {
      node.name = res;
      ctrl.commitHistory();
    }
  }
}

class _LeftAssetsAndComponentsTab extends StatelessWidget {
  const _LeftAssetsAndComponentsTab();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DevignController>();
    final components = ctrl.getMasterComponents();

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        _sectionHeader('FRAME PRESETS'),
        const SizedBox(height: 6),
        ...kFramePresets.map(
          (preset) => Card(
            margin: const EdgeInsets.only(bottom: 5),
            color: FyrTheme.cardColor,
            elevation: 0,
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: const Icon(Icons.devices_rounded, size: 15),
              title: Text(preset.name, style: const TextStyle(fontSize: 12)),
              subtitle: Text(
                '${preset.category} • ${preset.width.round()}×${preset.height.round()}',
                style:
                    TextStyle(fontSize: 10.5, color: FyrTheme.textColorMuted),
              ),
              trailing: const Icon(Icons.add_circle_outline, size: 15),
              onTap: () => ctrl.addPresetFrame(preset),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _sectionHeader('FYR UI KIT SNIPPETS'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final item in [
              ('Primary Button', Icons.smart_button_rounded),
              ('Glass Card', Icons.blur_on_rounded),
              ('Text Input', Icons.input_rounded),
              ('Status Pill', Icons.verified_outlined),
              ('Avatar', Icons.account_circle_outlined),
            ])
              ActionChip(
                avatar: Icon(item.$2, size: 14),
                label: Text(item.$1, style: const TextStyle(fontSize: 11)),
                onPressed: () => ctrl.insertUiKitSnippet(item.$1),
              ),
          ],
        ),
        const SizedBox(height: 14),
        _sectionHeader('MASTER COMPONENTS (${components.length})'),
        const SizedBox(height: 6),
        if (components.isEmpty)
          Text(
            'Select any layer and click ❖ to create a reusable Master Component.',
            style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
          )
        else
          ...components.map(
            (comp) => Card(
              margin: const EdgeInsets.only(bottom: 5),
              color: const Color(0xFFBB86FC).withValues(alpha: 0.1),
              elevation: 0,
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                leading: const Icon(Icons.diamond_rounded,
                    size: 14, color: Color(0xFFBB86FC)),
                title: Text(comp.name, style: const TextStyle(fontSize: 12)),
                subtitle: const Text(
                  'Tap to insert linked instance',
                  style: TextStyle(fontSize: 10),
                ),
                trailing: const Icon(Icons.add, size: 15),
                onTap: () => ctrl.instantiateComponent(comp.id),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionHeader(String title) => Text(
        title,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: FyrTheme.textColorMuted,
        ),
      );
}

class _LeftTokensAndCommentsTab extends StatelessWidget {
  const _LeftTokensAndCommentsTab();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DevignController>();

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Row(
          children: [
            Text(
              'COLOR TOKENS',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: FyrTheme.textColorMuted,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                minimumSize: const Size(0, 24),
              ),
              onPressed: () => _addTokenDialog(context, ctrl),
              icon: const Icon(Icons.add, size: 13),
              label: const Text('Add', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...ctrl.colorTokens.map(
          (tok) => InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              if (ctrl.selectedNodes.isNotEmpty) {
                ctrl.mutateSelected((n) {
                  if (n.fills.isEmpty) {
                    n.fills.add(FillPaint(color: tok.color));
                  } else {
                    n.fills.last.color = tok.color;
                  }
                }, commit: true);
                ctrl.setStatus('Applied token "${tok.name}"');
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: tok.color,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(tok.name, style: const TextStyle(fontSize: 12)),
                  ),
                  Text(
                    DevignExport.colorToHex(tok.color),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: FyrTheme.textColorMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Divider(height: 22),
        Text(
          'REVIEW COMMENTS (${ctrl.activePage.comments.length})',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: FyrTheme.textColorMuted,
          ),
        ),
        const SizedBox(height: 6),
        if (ctrl.activePage.comments.isEmpty)
          Text(
            'Use the Comment tool (C) and click on the canvas to pin feedback.',
            style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
          )
        else
          ...ctrl.activePage.comments.map(
            (c) => Card(
              margin: const EdgeInsets.only(bottom: 6),
              color: FyrTheme.cardColor,
              elevation: 0,
              child: ListTile(
                dense: true,
                title: Text(
                  c.message,
                  style: TextStyle(
                    fontSize: 11.5,
                    decoration:
                        c.resolved ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text(
                  '${c.author} • (${c.position.dx.round()}, ${c.position.dy.round()})',
                  style: const TextStyle(fontSize: 10),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        c.resolved
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                        size: 15,
                        color: c.resolved ? Colors.greenAccent : null,
                      ),
                      onPressed: () => ctrl.toggleCommentResolved(c.id),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 15),
                      onPressed: () => ctrl.deleteComment(c.id),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _addTokenDialog(
    BuildContext context,
    DevignController ctrl,
  ) async {
    final nameCtrl = TextEditingController(text: 'Brand Accent');
    final hexCtrl = TextEditingController(text: '#00E5FF');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: const Text('New Color Token', style: TextStyle(fontSize: 15)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Token Name', isDense: true),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: hexCtrl,
              decoration:
                  const InputDecoration(labelText: 'Hex (#RRGGBB)', isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Add')),
        ],
      ),
    );
    if (ok == true) {
      final col = _parseHexColor(hexCtrl.text) ?? FyrTheme.accentColor;
      ctrl.addColorToken(nameCtrl.text.trim(), col);
    }
  }
}

// =============================================================================
// RIGHT INSPECTOR SIDEBAR (Design / Prototype / Code)
// =============================================================================

class _DevignRightInspector extends StatelessWidget {
  final VoidCallback onPresent;
  final VoidCallback onExport;

  const _DevignRightInspector({
    required this.onPresent,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DevignController>();

    return Container(
      width: 312,
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor,
        border: Border(left: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              children: [
                _SidebarTabPill(
                  label: 'Design',
                  icon: Icons.tune_rounded,
                  selected: ctrl.rightPanelTab == 0,
                  onTap: () {
                    ctrl.rightPanelTab = 0;
                    ctrl.refresh();
                  },
                ),
                const SizedBox(width: 4),
                _SidebarTabPill(
                  label: 'Prototype',
                  icon: Icons.bolt_rounded,
                  selected: ctrl.rightPanelTab == 1,
                  onTap: () {
                    ctrl.rightPanelTab = 1;
                    ctrl.refresh();
                  },
                ),
                const SizedBox(width: 4),
                _SidebarTabPill(
                  label: 'Code',
                  icon: Icons.code_rounded,
                  selected: ctrl.rightPanelTab == 2,
                  onTap: () {
                    ctrl.rightPanelTab = 2;
                    ctrl.refresh();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (ctrl.rightPanelTab) {
              0 => _DesignInspectorTab(onExport: onExport),
              1 => _PrototypeInspectorTab(onPresent: onPresent),
              _ => const _CodeInspectorTab(),
            },
          ),
        ],
      ),
    );
  }
}

class _DesignInspectorTab extends StatelessWidget {
  final VoidCallback onExport;
  const _DesignInspectorTab({required this.onExport});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DevignController>();
    final node = ctrl.primarySelected;

    if (node == null) {
      return ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(
            'CANVAS PROPERTIES',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: FyrTheme.textColorMuted,
            ),
          ),
          const SizedBox(height: 10),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Show Infinite Grid',
                style: TextStyle(fontSize: 12)),
            value: ctrl.showGrid,
            onChanged: (v) {
              ctrl.showGrid = v;
              ctrl.refresh();
            },
          ),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Smart Snap Alignment',
                style: TextStyle(fontSize: 12)),
            value: ctrl.snapToGuides,
            onChanged: (v) {
              ctrl.snapToGuides = v;
              ctrl.refresh();
            },
          ),
          SwitchListTile.adaptive(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Show Comment Pins',
                style: TextStyle(fontSize: 12)),
            value: ctrl.showComments,
            onChanged: (v) {
              ctrl.showComments = v;
              ctrl.refresh();
            },
          ),
          const Divider(height: 24),
          Text(
            'QUICK ADD FRAME',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: FyrTheme.textColorMuted,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in kFramePresets.take(4))
                OutlinedButton(
                  onPressed: () => ctrl.addPresetFrame(preset),
                  child: Text(preset.name, style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Alignment bar
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final (align, icon, tip) in [
              ('left', Icons.align_horizontal_left, 'Align Left'),
              ('centerH', Icons.align_horizontal_center, 'Align Center H'),
              ('right', Icons.align_horizontal_right, 'Align Right'),
              ('top', Icons.align_vertical_top, 'Align Top'),
              ('centerV', Icons.align_vertical_center, 'Align Center V'),
              ('bottom', Icons.align_vertical_bottom, 'Align Bottom'),
            ])
              _TopIconBtn(
                icon: icon,
                tooltip: tip,
                onTap: () => ctrl.alignSelected(align),
              ),
            _TopIconBtn(
              icon: Icons.horizontal_distribute,
              tooltip: 'Distribute Horizontally',
              enabled: ctrl.selectedIds.length >= 3,
              onTap: () => ctrl.distributeSelected(horizontal: true),
            ),
            _TopIconBtn(
              icon: Icons.vertical_distribute,
              tooltip: 'Distribute Vertically',
              enabled: ctrl.selectedIds.length >= 3,
              onTap: () => ctrl.distributeSelected(horizontal: false),
            ),
          ],
        ),
        const Divider(height: 18),
        // Transform geometry grid
        _InspectorHeader(
          title: '${node.type.name.toUpperCase()} • ${node.name}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 14),
                tooltip: 'Duplicate (Ctrl+D)',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
                onPressed: ctrl.duplicateSelected,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 15),
                tooltip: 'Delete',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(4),
                onPressed: ctrl.deleteSelected,
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _NumSpinField(
                label: 'X',
                value: node.x,
                onChanged: (v) =>
                    ctrl.mutateSelected((n) => n.x = v, commit: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumSpinField(
                label: 'Y',
                value: node.y,
                onChanged: (v) =>
                    ctrl.mutateSelected((n) => n.y = v, commit: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _NumSpinField(
                label: 'W',
                value: node.width,
                minVal: 2,
                onChanged: (v) =>
                    ctrl.mutateSelected((n) => n.width = v, commit: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumSpinField(
                label: 'H',
                value: node.height,
                minVal: 2,
                onChanged: (v) =>
                    ctrl.mutateSelected((n) => n.height = v, commit: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _NumSpinField(
                label: '∠',
                value: node.rotationDeg,
                onChanged: (v) =>
                    ctrl.mutateSelected((n) => n.rotationDeg = v, commit: true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumSpinField(
                label: 'R',
                value: node.radiusTL,
                minVal: 0,
                onChanged: (v) => ctrl.mutateSelected(
                  (n) => n.setUniformRadius(v),
                  commit: true,
                ),
              ),
            ),
          ],
        ),
        if (node.isContainer)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Clip Content', style: TextStyle(fontSize: 11.5)),
            value: node.clipContent,
            onChanged: (v) => ctrl.mutateSelected(
              (n) => n.clipContent = v ?? false,
              commit: true,
            ),
          ),

        // Polygon / Star specific controls
        if (node.type == NodeType.polygon || node.type == NodeType.star) ...[
          const Divider(height: 18),
          const _InspectorHeader(title: 'SHAPE GEOMETRY'),
          Row(
            children: [
              const Text('Points / Sides', style: TextStyle(fontSize: 11.5)),
              Expanded(
                child: Slider(
                  min: 3,
                  max: 12,
                  divisions: 9,
                  value: node.polygonSides.clamp(3, 12).toDouble(),
                  onChanged: (v) => ctrl.mutateSelected(
                    (n) => n.polygonSides = v.round(),
                    commit: true,
                  ),
                ),
              ),
              Text('${node.polygonSides}',
                  style: const TextStyle(fontSize: 11)),
            ],
          ),
          if (node.type == NodeType.star)
            Row(
              children: [
                const Text('Inner Ratio', style: TextStyle(fontSize: 11.5)),
                Expanded(
                  child: Slider(
                    min: 0.15,
                    max: 0.85,
                    value: node.starInnerRatio.clamp(0.15, 0.85),
                    onChanged: (v) => ctrl.mutateSelected(
                      (n) => n.starInnerRatio = v,
                      commit: true,
                    ),
                  ),
                ),
              ],
            ),
        ],

        // Auto Layout section for frames & components
        if (node.isContainer) ...[
          const Divider(height: 18),
          _InspectorHeader(
            title: 'AUTO LAYOUT (FLEX)',
            trailing: Switch.adaptive(
              value: node.autoLayout.enabled,
              onChanged: (on) {
                ctrl.mutateSelected((n) {
                  n.autoLayout.direction = on
                      ? AutoLayoutDirection.vertical
                      : AutoLayoutDirection.none;
                }, commit: true);
              },
            ),
          ),
          if (node.autoLayout.enabled) ...[
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Vertical ↓',
                      style: TextStyle(fontSize: 11)),
                  selected: node.autoLayout.direction ==
                      AutoLayoutDirection.vertical,
                  onSelected: (_) => ctrl.mutateSelected(
                    (n) =>
                        n.autoLayout.direction = AutoLayoutDirection.vertical,
                    commit: true,
                  ),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  label: const Text('Horizontal →',
                      style: TextStyle(fontSize: 11)),
                  selected: node.autoLayout.direction ==
                      AutoLayoutDirection.horizontal,
                  onSelected: (_) => ctrl.mutateSelected(
                    (n) =>
                        n.autoLayout.direction = AutoLayoutDirection.horizontal,
                    commit: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _NumSpinField(
                    label: 'Gap',
                    value: node.autoLayout.gap,
                    minVal: 0,
                    onChanged: (v) => ctrl.mutateSelected(
                      (n) => n.autoLayout.gap = v,
                      commit: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _NumSpinField(
                    label: 'PadH',
                    value: node.autoLayout.paddingH,
                    minVal: 0,
                    onChanged: (v) => ctrl.mutateSelected(
                      (n) => n.autoLayout.paddingH = v,
                      commit: true,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _NumSpinField(
                    label: 'PadV',
                    value: node.autoLayout.paddingV,
                    minVal: 0,
                    onChanged: (v) => ctrl.mutateSelected(
                      (n) => n.autoLayout.paddingV = v,
                      commit: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],

        // Typography Inspector
        if (node.type == NodeType.text) ...[
          const Divider(height: 18),
          const _InspectorHeader(title: 'TYPOGRAPHY'),
          const SizedBox(height: 6),
          TextFormField(
            key: ValueKey('txt_${node.id}'),
            initialValue: node.text,
            maxLines: 2,
            style: const TextStyle(fontSize: 12),
            decoration: const InputDecoration(
              labelText: 'Content',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => ctrl.mutateSelected((n) => n.text = v),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  initialValue: [
                    'Inter',
                    'Roboto',
                    'JetBrains Mono',
                    'Space Grotesk',
                    'Playfair Display',
                  ].contains(node.fontFamily)
                      ? node.fontFamily
                      : 'Inter',
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Font',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'Inter',
                        child: Text('Inter', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(
                        value: 'Roboto',
                        child: Text('Roboto', style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(
                        value: 'JetBrains Mono',
                        child: Text('JetBrains Mono',
                            style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(
                        value: 'Space Grotesk',
                        child: Text('Space Grotesk',
                            style: TextStyle(fontSize: 12))),
                    DropdownMenuItem(
                        value: 'Playfair Display',
                        child: Text('Playfair Display',
                            style: TextStyle(fontSize: 12))),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      ctrl.mutateSelected((n) => n.fontFamily = v,
                          commit: true);
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: _NumSpinField(
                  label: 'Sz',
                  value: node.fontSize,
                  minVal: 6,
                  onChanged: (v) => ctrl.mutateSelected(
                    (n) => n.fontSize = v,
                    commit: true,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final (align, icon) in [
                (TextAlign.left, Icons.format_align_left),
                (TextAlign.center, Icons.format_align_center),
                (TextAlign.right, Icons.format_align_right),
              ])
                _TopIconBtn(
                  icon: icon,
                  tooltip: align.name,
                  active: node.textAlign == align,
                  onTap: () => ctrl.mutateSelected(
                    (n) => n.textAlign = align,
                    commit: true,
                  ),
                ),
              _TopIconBtn(
                icon: Icons.format_italic,
                tooltip: 'Italic',
                active: node.italic,
                onTap: () => ctrl.mutateSelected(
                  (n) => n.italic = !n.italic,
                  commit: true,
                ),
              ),
              const Spacer(),
              DropdownButton<int>(
                value: node.fontWeightIndex.clamp(0, 8),
                isDense: true,
                items: [
                  for (int i = 0; i <= 8; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text('W${(i + 1) * 100}',
                          style: const TextStyle(fontSize: 11.5)),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) {
                    ctrl.mutateSelected((n) => n.fontWeightIndex = v,
                        commit: true);
                  }
                },
              ),
            ],
          ),
        ],

        const Divider(height: 18),
        // Layer Opacity
        Row(
          children: [
            const Text('Opacity', style: TextStyle(fontSize: 11.5)),
            Expanded(
              child: Slider(
                min: 0.0,
                max: 1.0,
                value: node.opacity.clamp(0.0, 1.0),
                onChanged: (v) => ctrl.mutateSelected((n) => n.opacity = v),
                onChangeEnd: (_) => ctrl.commitHistory(),
              ),
            ),
            Text('${(node.opacity * 100).round()}%',
                style: const TextStyle(fontSize: 11)),
          ],
        ),

        const Divider(height: 18),
        // Fills section
        _InspectorHeader(
          title: 'FILLS',
          trailing: IconButton(
            icon: const Icon(Icons.add, size: 15),
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(2),
            onPressed: () => ctrl.mutateSelected(
              (n) => n.fills.add(FillPaint(color: FyrTheme.accentColor)),
              commit: true,
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < node.fills.length; i++)
          _FillCard(
            fill: node.fills[i],
            onChanged: () => ctrl.mutateSelected((_) {}, commit: true),
            onRemove: () => ctrl.mutateSelected(
              (n) => n.fills.removeAt(i),
              commit: true,
            ),
          ),

        const Divider(height: 18),
        // Strokes section
        _InspectorHeader(
          title: 'STROKES',
          trailing: IconButton(
            icon: const Icon(Icons.add, size: 15),
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(2),
            onPressed: () => ctrl.mutateSelected(
              (n) => n.strokes.add(StrokePaint(
                color: const Color(0xFFE040FB),
                width: 2.0,
              )),
              commit: true,
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < node.strokes.length; i++)
          _StrokeCard(
            stroke: node.strokes[i],
            onChanged: () => ctrl.mutateSelected((_) {}, commit: true),
            onRemove: () => ctrl.mutateSelected(
              (n) => n.strokes.removeAt(i),
              commit: true,
            ),
          ),

        const Divider(height: 18),
        // Effects section
        _InspectorHeader(
          title: 'EFFECTS',
          trailing: IconButton(
            icon: const Icon(Icons.add, size: 15),
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(2),
            onPressed: () => ctrl.mutateSelected(
              (n) => n.effects.add(NodeEffect()),
              commit: true,
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (int i = 0; i < node.effects.length; i++)
          _EffectCard(
            effect: node.effects[i],
            onChanged: () => ctrl.mutateSelected((_) {}, commit: true),
            onRemove: () => ctrl.mutateSelected(
              (n) => n.effects.removeAt(i),
              commit: true,
            ),
          ),

        const Divider(height: 22),
        FilledButton.tonalIcon(
          onPressed: onExport,
          icon: const Icon(Icons.download_rounded, size: 15),
          label: Text('Export "${node.name}"',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

class _FillCard extends StatelessWidget {
  final FillPaint fill;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _FillCard({
    required this.fill,
    required this.onChanged,
    required this.onRemove,
  });

  static const _quickPalette = [
    Color(0xFFE040FB),
    Color(0xFF7C4DFF),
    Color(0xFF40C4FF),
    Color(0xFF00E676),
    Color(0xFFFFD740),
    Color(0xFFFF5252),
    Color(0xFFF5F5FA),
    Color(0xFF1A1A24),
    Color(0xFF0D0D12),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<FillKind>(
                  value: fill.kind,
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                        value: FillKind.solid,
                        child: Text('Solid', style: TextStyle(fontSize: 11.5))),
                    DropdownMenuItem(
                        value: FillKind.linearGradient,
                        child: Text('Linear Gradient',
                            style: TextStyle(fontSize: 11.5))),
                    DropdownMenuItem(
                        value: FillKind.radialGradient,
                        child: Text('Radial Gradient',
                            style: TextStyle(fontSize: 11.5))),
                  ],
                  onChanged: (k) {
                    if (k != null) {
                      fill.kind = k;
                      onChanged();
                    }
                  },
                ),
              ),
              IconButton(
                icon: Icon(
                  fill.visible ? Icons.visibility : Icons.visibility_off,
                  size: 14,
                ),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(3),
                onPressed: () {
                  fill.visible = !fill.visible;
                  onChanged();
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 14),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(3),
                onPressed: onRemove,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final c in _quickPalette)
                GestureDetector(
                  onTap: () {
                    fill.color = c;
                    onChanged();
                  },
                  onSecondaryTap: () {
                    fill.secondaryColor = c;
                    onChanged();
                  },
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: fill.color.toARGB32() == c.toARGB32()
                            ? Colors.white
                            : Colors.white24,
                        width: fill.color.toARGB32() == c.toARGB32() ? 2 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (fill.kind != FillKind.solid) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Text('Angle', style: TextStyle(fontSize: 10.5)),
                Expanded(
                  child: Slider(
                    min: 0,
                    max: 360,
                    value: fill.gradientAngleDeg.clamp(0, 360),
                    onChanged: (v) {
                      fill.gradientAngleDeg = v;
                      onChanged();
                    },
                  ),
                ),
                Text('${fill.gradientAngleDeg.round()}°',
                    style: const TextStyle(fontSize: 10.5)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StrokeCard extends StatelessWidget {
  final StrokePaint stroke;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _StrokeCard({
    required this.stroke,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              const cols = [
                Color(0xFFE040FB),
                Color(0xFF40C4FF),
                Color(0xFFFFFFFF),
                Color(0xFF69F0AE),
                Color(0xFF333344),
              ];
              final curIdx = cols
                  .indexWhere((c) => c.toARGB32() == stroke.color.toARGB32());
              stroke.color = cols[(curIdx + 1) % cols.length];
              onChanged();
            },
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: stroke.color,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: Colors.white38),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _NumSpinField(
              label: 'Px',
              value: stroke.width,
              minVal: 0.5,
              onChanged: (v) {
                stroke.width = v;
                onChanged();
              },
            ),
          ),
          const SizedBox(width: 6),
          FilterChip(
            label: const Text('Dash', style: TextStyle(fontSize: 10.5)),
            selected: stroke.dashed,
            visualDensity: VisualDensity.compact,
            onSelected: (v) {
              stroke.dashed = v;
              onChanged();
            },
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(3),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}

class _EffectCard extends StatelessWidget {
  final NodeEffect effect;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  const _EffectCard({
    required this.effect,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButton<EffectKind>(
                  value: effect.kind,
                  isDense: true,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(
                        value: EffectKind.dropShadow,
                        child: Text('Drop Shadow',
                            style: TextStyle(fontSize: 11.5))),
                    DropdownMenuItem(
                        value: EffectKind.innerShadow,
                        child: Text('Inner Shadow',
                            style: TextStyle(fontSize: 11.5))),
                    DropdownMenuItem(
                        value: EffectKind.layerBlur,
                        child: Text('Layer Blur',
                            style: TextStyle(fontSize: 11.5))),
                    DropdownMenuItem(
                        value: EffectKind.backgroundBlur,
                        child: Text('Background Blur',
                            style: TextStyle(fontSize: 11.5))),
                  ],
                  onChanged: (k) {
                    if (k != null) {
                      effect.kind = k;
                      onChanged();
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 14),
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(3),
                onPressed: onRemove,
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _NumSpinField(
                  label: 'Blur',
                  value: effect.blurRadius,
                  minVal: 0,
                  onChanged: (v) {
                    effect.blurRadius = v;
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _NumSpinField(
                  label: 'DY',
                  value: effect.offsetY,
                  onChanged: (v) {
                    effect.offsetY = v;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrototypeInspectorTab extends StatelessWidget {
  final VoidCallback onPresent;
  const _PrototypeInspectorTab({required this.onPresent});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DevignController>();
    final frames = ctrl.getTopLevelFrames();
    final node = ctrl.primarySelected;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const _InspectorHeader(title: 'FLOW STARTING FRAME'),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: frames.any((f) => f.id == ctrl.activePage.flowStartFrameId)
              ? ctrl.activePage.flowStartFrameId
              : (frames.isNotEmpty ? frames.first.id : null),
          isDense: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: [
            for (final f in frames)
              DropdownMenuItem(
                value: f.id,
                child: Text(f.name, style: const TextStyle(fontSize: 12)),
              ),
          ],
          onChanged: (id) {
            ctrl.activePage.flowStartFrameId = id;
            ctrl.commitHistory();
          },
        ),
        const Divider(height: 22),
        if (node == null)
          Text(
            'Select any button, card, or layer to wire an interactive On-Tap prototype transition.',
            style: TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
          )
        else ...[
          _InspectorHeader(
            title: 'INTERACTION • ${node.name}',
            trailing: IconButton(
              icon: Icon(
                node.prototypeLink == null ? Icons.add : Icons.delete_outline,
                size: 16,
              ),
              onPressed: () {
                ctrl.mutateSelected((n) {
                  if (n.prototypeLink == null) {
                    final dest = frames
                        .where((f) => f.id != n.id && f.id != n.parentId)
                        .firstOrNull;
                    n.prototypeLink = PrototypeLink(
                      action: PrototypeAction.navigate,
                      targetFrameId: dest?.id,
                    );
                  } else {
                    n.prototypeLink = null;
                  }
                }, commit: true);
              },
            ),
          ),
          const SizedBox(height: 8),
          if (node.prototypeLink == null)
            OutlinedButton.icon(
              onPressed: () {
                final dest = frames
                    .where((f) => f.id != node.id && f.id != node.parentId)
                    .firstOrNull;
                ctrl.mutateSelected((n) {
                  n.prototypeLink = PrototypeLink(
                    action: PrototypeAction.navigate,
                    targetFrameId: dest?.id,
                  );
                }, commit: true);
              },
              icon: const Icon(Icons.add_link_rounded, size: 15),
              label: const Text('Add On-Tap Interaction',
                  style: TextStyle(fontSize: 12)),
            )
          else ...[
            DropdownButtonFormField<PrototypeAction>(
              initialValue: node.prototypeLink!.action,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'On Tap Action',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: PrototypeAction.navigate,
                  child: Text('Navigate to Frame',
                      style: TextStyle(fontSize: 12)),
                ),
                DropdownMenuItem(
                  value: PrototypeAction.back,
                  child: Text('Navigate Back', style: TextStyle(fontSize: 12)),
                ),
              ],
              onChanged: (a) {
                if (a != null) {
                  ctrl.mutateSelected((n) => n.prototypeLink?.action = a,
                      commit: true);
                }
              },
            ),
            const SizedBox(height: 10),
            if (node.prototypeLink!.action == PrototypeAction.navigate)
              DropdownButtonFormField<String>(
                initialValue: frames.any(
                        (f) => f.id == node.prototypeLink!.targetFrameId)
                    ? node.prototypeLink!.targetFrameId
                    : null,
                isDense: true,
                decoration: const InputDecoration(
                  labelText: 'Destination Frame',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final f in frames)
                    DropdownMenuItem(
                      value: f.id,
                      child:
                          Text(f.name, style: const TextStyle(fontSize: 12)),
                    ),
                ],
                onChanged: (id) {
                  ctrl.mutateSelected(
                      (n) => n.prototypeLink?.targetFrameId = id,
                      commit: true);
                },
              ),
            const SizedBox(height: 10),
            DropdownButtonFormField<PrototypeTransition>(
              initialValue: node.prototypeLink!.transition,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Transition Animation',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final t in PrototypeTransition.values)
                  DropdownMenuItem(
                    value: t,
                    child: Text(t.name, style: const TextStyle(fontSize: 12)),
                  ),
              ],
              onChanged: (t) {
                if (t != null) {
                  ctrl.mutateSelected((n) => n.prototypeLink?.transition = t,
                      commit: true);
                }
              },
            ),
          ],
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onPresent,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('Launch Interactive Flow'),
        ),
      ],
    );
  }
}

class _CodeInspectorTab extends StatelessWidget {
  const _CodeInspectorTab();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DevignController>();
    final node = ctrl.primarySelected ??
        (ctrl.activePage.rootIds.isNotEmpty
            ? ctrl.nodes[ctrl.activePage.rootIds.first]
            : null);

    if (node == null) {
      return Center(
        child: Text(
          'Select a layer to inspect Flutter, CSS & SVG code',
          style: TextStyle(fontSize: 12, color: FyrTheme.textColorMuted),
        ),
      );
    }

    final flutterCode = DevignExport.generateFlutterCode(node);
    final cssCode = DevignExport.generateCss(node);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _CodeBlockCard(
          title: 'FLUTTER WIDGET',
          code: flutterCode,
          onCopy: () {
            Clipboard.setData(ClipboardData(text: flutterCode));
            ctrl.setStatus('Copied Flutter widget snippet to clipboard');
          },
        ),
        const SizedBox(height: 12),
        _CodeBlockCard(
          title: 'CSS STYLES',
          code: cssCode,
          onCopy: () {
            Clipboard.setData(ClipboardData(text: cssCode));
            ctrl.setStatus('Copied CSS styles to clipboard');
          },
        ),
      ],
    );
  }
}

class _CodeBlockCard extends StatelessWidget {
  final String title;
  final String code;
  final VoidCallback onCopy;

  const _CodeBlockCard({
    required this.title,
    required this.code,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: FyrTheme.textColorMuted,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 24),
                ),
                onPressed: onCopy,
                icon: const Icon(Icons.copy_rounded, size: 12),
                label: const Text('Copy', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SelectableText(
            code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.38,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// INTERACTIVE PROTOTYPE PRESENTATION PLAYER
// =============================================================================

class _PrototypePlayerDialog extends StatefulWidget {
  final DevignController ctrl;
  final String initialFrameId;

  const _PrototypePlayerDialog({
    required this.ctrl,
    required this.initialFrameId,
  });

  @override
  State<_PrototypePlayerDialog> createState() => _PrototypePlayerDialogState();
}

class _PrototypePlayerDialogState extends State<_PrototypePlayerDialog> {
  late String _currentFrameId;
  final List<String> _history = [];

  @override
  void initState() {
    super.initState();
    _currentFrameId = widget.initialFrameId;
  }

  void _handleFrameTap(Offset localInFrame, DesignNode frame) {
    final frameAbs = widget.ctrl.getAbsolutePosition(frame.id);
    final canvasPos = frameAbs + localInFrame;

    // Walk deepest hit child inside current frame and bubble up looking for prototypeLink
    String? hit = widget.ctrl.hitTest(canvasPos, preferDeepest: true);
    while (hit != null) {
      final n = widget.ctrl.nodes[hit];
      if (n == null) break;
      final link = n.prototypeLink;
      if (link != null) {
        if (link.action == PrototypeAction.back && _history.isNotEmpty) {
          setState(() => _currentFrameId = _history.removeLast());
          return;
        } else if (link.action == PrototypeAction.navigate &&
            link.targetFrameId != null &&
            widget.ctrl.nodes.containsKey(link.targetFrameId)) {
          setState(() {
            _history.add(_currentFrameId);
            _currentFrameId = link.targetFrameId!;
          });
          return;
        }
      }
      if (hit == frame.id) break;
      hit = n.parentId;
    }
  }

  @override
  Widget build(BuildContext context) {
    final frame = widget.ctrl.nodes[_currentFrameId];
    if (frame == null) {
      return const SizedBox.shrink();
    }

    return Dialog(
      backgroundColor: const Color(0xFF0B0B0F),
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Column(
        children: [
          Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: FyrTheme.surfaceColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                const Icon(Icons.play_circle_fill_rounded,
                    color: Color(0xFF40C4FF), size: 18),
                const SizedBox(width: 8),
                Text(
                  'Prototype Preview — ${frame.name}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 12),
                if (_history.isNotEmpty)
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _currentFrameId = _history.removeLast()),
                    icon: const Icon(Icons.arrow_back, size: 14),
                    label: const Text('Back', style: TextStyle(fontSize: 12)),
                  ),
                const Spacer(),
                const Text(
                  'Click interactive components to navigate screens',
                  style: TextStyle(fontSize: 11, color: Colors.white54),
                ),
                const SizedBox(width: 12),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    child: GestureDetector(
                      key: ValueKey(_currentFrameId),
                      onTapDown: (d) =>
                          _handleFrameTap(d.localPosition, frame),
                      child: SizedBox(
                        width: frame.width,
                        height: frame.height,
                        child: CustomPaint(
                          painter: _SingleNodePainter(
                            root: frame,
                            nodes: widget.ctrl.nodes,
                            imageCache: widget.ctrl.imageCache,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SingleNodePainter extends CustomPainter {
  final DesignNode root;
  final Map<String, DesignNode> nodes;
  final Map<String, ui.Image> imageCache;

  _SingleNodePainter({
    required this.root,
    required this.nodes,
    required this.imageCache,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(-root.x, -root.y);
    DevignCanvasPainter.paintNodeSubtree(
      canvas,
      root,
      nodes,
      imageCache,
      drawFrameLabel: false,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SingleNodePainter oldDelegate) => true;
}

// =============================================================================
// EXPORT STUDIO DIALOG (PNG @1x/2x/3x, SVG, .devign JSON)
// =============================================================================

class _ExportStudioDialog extends StatefulWidget {
  final DevignController ctrl;
  final DesignNode target;

  const _ExportStudioDialog({required this.ctrl, required this.target});

  @override
  State<_ExportStudioDialog> createState() => _ExportStudioDialogState();
}

class _ExportStudioDialogState extends State<_ExportStudioDialog> {
  String _format = 'PNG';
  double _scale = 2.0;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: FyrTheme.surfaceColor,
      title: Text(
        'Export "${widget.target.name}"',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _format,
              decoration: const InputDecoration(
                labelText: 'Export Format',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(value: 'PNG', child: Text('PNG Image')),
                DropdownMenuItem(value: 'SVG', child: Text('SVG Vector')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _format = v);
              },
            ),
            if (_format == 'PNG') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<double>(
                initialValue: _scale,
                decoration: const InputDecoration(
                  labelText: 'Resolution Scale',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 1.0, child: Text('1x (Standard)')),
                  DropdownMenuItem(value: 2.0, child: Text('2x (Retina / HiDPI)')),
                  DropdownMenuItem(value: 3.0, child: Text('3x (Ultra HD)')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _scale = v);
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () async {
            final ext = _format.toLowerCase();
            final slug = widget.target.name
                .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
                .toLowerCase();
            final outPath = await FilePicker.saveFile(
              dialogTitle: 'Export $_format',
              fileName: '$slug.$ext',
            );
            if (outPath == null) return;
            if (_format == 'SVG') {
              await widget.ctrl.exportSelectedSvg(outPath);
            } else {
              await DevignExport.exportNodeToPng(
                root: widget.target,
                nodes: widget.ctrl.nodes,
                outputPath: outPath,
                scale: _scale,
                paintCallback: (canvas, root) {
                  DevignCanvasPainter.paintNodeSubtree(
                    canvas,
                    root,
                    widget.ctrl.nodes,
                    widget.ctrl.imageCache,
                    drawFrameLabel: false,
                  );
                },
              );
              widget.ctrl.setStatus('Exported PNG: ${p.basename(outPath)}');
            }
            if (context.mounted) Navigator.pop(context);
          },
          icon: const Icon(Icons.download_rounded, size: 15),
          label: Text('Export $_format'),
        ),
      ],
    );
  }
}

// =============================================================================
// STATUS BAR & SHARED SMALL WIDGETS
// =============================================================================

class _DevignStatusBar extends StatelessWidget {
  const _DevignStatusBar();

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DevignController>();
    final selCount = ctrl.selectedIds.length;
    final primary = ctrl.primarySelected;

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor,
        border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Row(
        children: [
          Text(
            'Tool: ${ctrl.activeTool.name.toUpperCase()}',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: FyrTheme.accentColor,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            selCount == 0
                ? 'No selection'
                : (selCount == 1 && primary != null
                    ? 'Selected: ${primary.name} (${primary.width.round()}×${primary.height.round()})'
                    : '$selCount layers selected'),
            style: TextStyle(fontSize: 10.5, color: FyrTheme.textColorMuted),
          ),
          const Spacer(),
          Text(
            ctrl.statusMessage ?? 'Ready',
            style: TextStyle(fontSize: 10.5, color: FyrTheme.textColorMuted),
          ),
        ],
      ),
    );
  }
}

class _InspectorHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;

  const _InspectorHeader({required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: FyrTheme.textColorMuted,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _NumSpinField extends StatefulWidget {
  final String label;
  final double value;
  final double? minVal;
  final ValueChanged<double> onChanged;

  const _NumSpinField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.minVal,
  });

  @override
  State<_NumSpinField> createState() => _NumSpinFieldState();
}

class _NumSpinFieldState extends State<_NumSpinField> {
  late final TextEditingController _tc;

  @override
  void initState() {
    super.initState();
    _tc = TextEditingController(text: _fmt(widget.value));
  }

  @override
  void didUpdateWidget(covariant _NumSpinField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.value - widget.value).abs() > 0.05) {
      _tc.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  String _fmt(double v) =>
      (v - v.roundToDouble()).abs() < 0.05 ? '${v.round()}' : v.toStringAsFixed(1);

  void _submit(String raw) {
    final parsed = double.tryParse(raw.trim());
    if (parsed != null) {
      final clamped =
          widget.minVal != null ? max(widget.minVal!, parsed) : parsed;
      widget.onChanged(clamped);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: TextField(
        controller: _tc,
        style: const TextStyle(fontSize: 11.5),
        onSubmitted: _submit,
        decoration: InputDecoration(
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 7, right: 4, top: 6),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColorMuted,
              ),
            ),
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
          filled: true,
          fillColor: FyrTheme.cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: FyrTheme.dividerColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: FyrTheme.dividerColor),
          ),
        ),
      ),
    );
  }
}

Color? _parseHexColor(String raw) {
  var h = raw.trim().replaceAll('#', '');
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v != null ? Color(v) : null;
}
