import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../engine/pixel_ops.dart';
import '../engine/pro_pixel_ops.dart';
import '../fyr_theme.dart';
import '../models/editor_types.dart';
import '../state/editor_controller.dart';
import 'dialogs.dart';
import 'pro_dialogs.dart';
import 'traffic_lights.dart';

class TopBar extends StatelessWidget {
  final VoidCallback onFitViewport;
  const TopBar({super.key, required this.onFitViewport});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<EditorController>();
    final doc = ctrl.activeDoc;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: Window title bar + Document Tabs + Quick Actions
        DragToMoveArea(
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: FyrTheme.bgColor,
              border: Border(
                bottom: BorderSide(color: FyrTheme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                const TrafficLights(),
                const SizedBox(width: 14),
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        FyrTheme.accentColor,
                        FyrTheme.accentColor.withValues(alpha: 0.55),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.layers_rounded,
                    size: 14,
                    color: FyrTheme.getContrastingColor(FyrTheme.accentColor),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'fyrGraphics',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: FyrTheme.textColor,
                  ),
                ),
                const SizedBox(width: 14),
                // Document tabs
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: ctrl.documents.length + 1,
                    separatorBuilder: (_, _) => const SizedBox(width: 4),
                    itemBuilder: (ctx, i) {
                      if (i == ctrl.documents.length) {
                        return Center(
                          child: IconButton(
                            icon: Icon(Icons.add,
                                size: 16, color: FyrTheme.textColorMuted),
                            tooltip: 'New Document (Ctrl+N)',
                            padding: const EdgeInsets.all(4),
                            constraints: const BoxConstraints(
                                minWidth: 28, minHeight: 28),
                            onPressed: () =>
                                FyrDialogs.showNewDocument(context, ctrl),
                          ),
                        );
                      }
                      final d = ctrl.documents[i];
                      final isActive = i == ctrl.activeDocIndex;
                      return Center(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(7),
                          onTap: () => ctrl.switchDocument(i),
                          child: Container(
                            height: 28,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? FyrTheme.accentColor.withValues(alpha: 0.16)
                                  : FyrTheme.cardColor,
                              borderRadius: BorderRadius.circular(7),
                              border: Border.all(
                                color: isActive
                                    ? FyrTheme.accentColor
                                        .withValues(alpha: 0.5)
                                    : FyrTheme.dividerColor,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${d.title}${d.dirty ? ' •' : ''}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: isActive
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isActive
                                        ? FyrTheme.textColor
                                        : FyrTheme.textColorMuted,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () => ctrl.closeDocument(i),
                                  child: Icon(
                                    Icons.close,
                                    size: 13,
                                    color: FyrTheme.textColorMuted,
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
                const SizedBox(width: 8),
                // Prominent Simple / Advanced Mode Toggle Pill
                _WorkspaceModeToggle(ctrl: ctrl),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.undo_rounded,
                      size: 17,
                      color: ctrl.canUndo
                          ? FyrTheme.textColor
                          : FyrTheme.textColorMuted.withValues(alpha: 0.35)),
                  tooltip: 'Undo (Ctrl+Z)',
                  onPressed: ctrl.canUndo ? ctrl.undo : null,
                ),
                IconButton(
                  icon: Icon(Icons.redo_rounded,
                      size: 17,
                      color: ctrl.canRedo
                          ? FyrTheme.textColor
                          : FyrTheme.textColorMuted.withValues(alpha: 0.35)),
                  tooltip: 'Redo (Ctrl+Y)',
                  onPressed: ctrl.canRedo ? ctrl.redo : null,
                ),
                const SizedBox(width: 4),
                if (doc != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: onFitViewport,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: FyrTheme.cardColor,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: FyrTheme.dividerColor),
                      ),
                      child: Text(
                        '${(doc.zoom * 100).round()}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: FyrTheme.textColor,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                IconButton(
                  icon: Icon(
                    ctrl.showRightDock
                        ? Icons.view_sidebar_rounded
                        : Icons.view_sidebar_outlined,
                    size: 17,
                    color: FyrTheme.textColorMuted,
                  ),
                  tooltip: 'Toggle Inspector Dock',
                  onPressed: () {
                    ctrl.showRightDock = !ctrl.showRightDock;
                    ctrl.refresh();
                  },
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: FyrTheme.accentColor,
                    foregroundColor:
                        FyrTheme.getContrastingColor(FyrTheme.accentColor),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 0),
                    minimumSize: const Size(0, 28),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                  onPressed: doc == null
                      ? null
                      : () => FyrDialogs.showExportDialog(context, ctrl),
                  icon: const Icon(Icons.upload_rounded, size: 14),
                  label: const Text('Export',
                      style:
                          TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
        // Row 2: Simple Quick Action Bar OR Advanced Pro Menu Bar
        if (!ctrl.isAdvancedMode)
          _buildSimpleQuickBar(context, ctrl, doc)
        else
          Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: FyrTheme.contentColor,
            border: Border(
              bottom: BorderSide(color: FyrTheme.dividerColor),
            ),
          ),
          child: Row(
            children: [
              _MenuButton(
                label: 'File',
                items: [
                  _menuItem('New...', 'Ctrl+N',
                      () => FyrDialogs.showNewDocument(context, ctrl)),
                  _menuItem('Open Image / Project...', 'Ctrl+O', () async {
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
                    }
                  }),
                  const PopupMenuDivider(),
                  _menuItem('Save Project (.fyrg)...', 'Ctrl+S', () async {
                    if (doc == null) return;
                    if (doc.filePath != null &&
                        doc.filePath!.toLowerCase().endsWith('.fyrg')) {
                      await ctrl.saveProjectToPath(doc.filePath!);
                    } else {
                      final savePath = await FilePicker.saveFile(
                        dialogTitle: 'Save fyrGraphics Project',
                        fileName:
                            '${doc.title.replaceAll(RegExp(r'\.[^.]+$'), '')}.fyrg',
                        type: FileType.custom,
                        allowedExtensions: ['fyrg'],
                      );
                      if (savePath != null) {
                        await ctrl.saveProjectToPath(savePath);
                      }
                    }
                  }),
                  _menuItem('Export As (PNG/JPG/BMP)...', 'Ctrl+E',
                      () => FyrDialogs.showExportDialog(context, ctrl)),
                ],
              ),
              _MenuButton(
                label: 'Edit',
                items: [
                  _menuItem('Undo', 'Ctrl+Z', ctrl.canUndo ? ctrl.undo : null),
                  _menuItem('Redo', 'Ctrl+Y', ctrl.canRedo ? ctrl.redo : null),
                  const PopupMenuDivider(),
                  _menuItem('Cut', 'Ctrl+X', ctrl.cutSelection),
                  _menuItem('Copy', 'Ctrl+C', ctrl.copySelection),
                  _menuItem('Paste as New Layer', 'Ctrl+V', ctrl.pasteClipboard),
                  const PopupMenuDivider(),
                  _menuItem('Fill with Foreground', '',
                      () => ctrl.fillSelectedPixels(ctrl.foregroundColor)),
                  _menuItem('Fill with Background', '',
                      () => ctrl.fillSelectedPixels(ctrl.backgroundColor)),
                  _menuItem('Clear / Delete', 'Del', ctrl.clearSelectedPixels),
                ],
              ),
              _MenuButton(
                label: 'Image',
                items: [
                  _menuItem(
                    'Image Size...',
                    '',
                    () => FyrDialogs.showImageSizeDialog(context, ctrl,
                        canvasOnly: false),
                  ),
                  _menuItem(
                    'Canvas Size...',
                    '',
                    () => FyrDialogs.showImageSizeDialog(context, ctrl,
                        canvasOnly: true),
                  ),
                  const PopupMenuDivider(),
                  _menuItem('Rotate 90° CW', '', () => ctrl.rotateCanvas(90)),
                  _menuItem('Rotate 90° CCW', '', () => ctrl.rotateCanvas(-90)),
                  _menuItem('Rotate 180°', '', () => ctrl.rotateCanvas(180)),
                  const PopupMenuDivider(),
                  _menuItem('Flip Canvas Horizontal', '',
                      () => ctrl.flipCanvas(horizontal: true)),
                  _menuItem('Flip Canvas Vertical', '',
                      () => ctrl.flipCanvas(horizontal: false)),
                  const PopupMenuDivider(),
                  _menuItem(
                    'Develop & Tone (Exposure / Temp / Vibrance)...',
                    '',
                    () => ProDialogs.showDevelopAdjust(context, ctrl),
                  ),
                  _menuItem(
                    'Tone Curves (RGB / R / G / B)...',
                    '',
                    () => ProDialogs.showToneCurves(context, ctrl),
                  ),
                  _menuItem(
                    'Photo Looks & Color Grades...',
                    '',
                    () => ProDialogs.showPhotoLooks(context, ctrl),
                  ),
                  const PopupMenuDivider(),
                  _menuItem(
                    'Auto Levels',
                    '',
                    () => ctrl.runImmediateFilter(
                      'Auto Levels',
                      (s, w, h, m) => ProPixelOps.autoLevels(s, selectionMask: m),
                    ),
                  ),
                  _menuItem(
                    'Auto White Balance',
                    '',
                    () => ctrl.runImmediateFilter(
                      'Auto White Balance',
                      (s, w, h, m) =>
                          ProPixelOps.autoWhiteBalance(s, selectionMask: m),
                    ),
                  ),
                  const PopupMenuDivider(),
                  _menuItem(
                    'Brightness / Contrast...',
                    '',
                    () => FyrDialogs.showBrightnessContrast(context, ctrl),
                  ),
                  _menuItem(
                    'Hue / Saturation...',
                    '',
                    () => FyrDialogs.showHueSaturation(context, ctrl),
                  ),
                  _menuItem(
                    'Levels...',
                    '',
                    () => FyrDialogs.showLevels(context, ctrl),
                  ),
                  _menuItem(
                    'Color Balance...',
                    '',
                    () => FyrDialogs.showColorBalance(context, ctrl),
                  ),
                  _menuItem(
                    'Invert Colors',
                    'Ctrl+I',
                    () => ctrl.runImmediateFilter(
                      'Invert Colors',
                      (s, w, h, m) =>
                          PixelOps.invertColors(s, selectionMask: m),
                    ),
                  ),
                  _menuItem(
                    'Desaturate (Grayscale)',
                    '',
                    () => ctrl.runImmediateFilter(
                      'Desaturate',
                      (s, w, h, m) => PixelOps.desaturate(s, selectionMask: m),
                    ),
                  ),
                  _menuItem(
                    'Posterize (6 levels)',
                    '',
                    () => ctrl.runImmediateFilter(
                      'Posterize',
                      (s, w, h, m) =>
                          PixelOps.posterize(s, 6, selectionMask: m),
                    ),
                  ),
                  _menuItem(
                    'Threshold',
                    '',
                    () => ctrl.runImmediateFilter(
                      'Threshold',
                      (s, w, h, m) =>
                          PixelOps.threshold(s, 128, selectionMask: m),
                    ),
                  ),
                ],
              ),
              _MenuButton(
                label: 'Layer',
                items: [
                  _menuItem('New Layer', 'Ctrl+Shift+N', () => ctrl.addNewLayer()),
                  _menuItem(
                      'Duplicate Layer', 'Ctrl+J', ctrl.duplicateActiveLayer),
                  _menuItem('Delete Layer', '', ctrl.deleteActiveLayer),
                  const PopupMenuDivider(),
                  _menuItem('New Text Layer...', 'T',
                      () => FyrDialogs.showTextLayerDialog(context, ctrl)),
                  if (doc?.activeLayer?.isTextLayer == true)
                    _menuItem('Rasterize Text Layer', '',
                        ctrl.rasterizeActiveTextLayer),
                  const PopupMenuDivider(),
                  _menuItem('Flip Layer Horizontal', '',
                      () => ctrl.flipActiveLayer(horizontal: true)),
                  _menuItem('Flip Layer Vertical', '',
                      () => ctrl.flipActiveLayer(horizontal: false)),
                  const PopupMenuDivider(),
                  _menuItem(
                    doc?.activeLayer?.alphaLock == true
                        ? 'Disable Alpha Lock'
                        : 'Enable Alpha Lock',
                    '',
                    doc == null
                        ? null
                        : () => ctrl.toggleLayerAlphaLock(doc.activeLayerIndex),
                  ),
                  _menuItem(
                    doc?.activeLayer?.clippingMask == true
                        ? 'Release Clipping Mask'
                        : 'Create Clipping Mask',
                    '',
                    doc == null
                        ? null
                        : () =>
                            ctrl.toggleLayerClippingMask(doc.activeLayerIndex),
                  ),
                  _menuItem(
                    'Select Layer Pixels',
                    '',
                    doc == null
                        ? null
                        : () => ctrl.selectLayerPixels(doc.activeLayerIndex),
                  ),
                  const PopupMenuDivider(),
                  _menuItem('Stamp Visible to New Layer', '',
                      ctrl.stampVisibleLayer),
                  _menuItem('Merge Down', 'Ctrl+E', ctrl.mergeDown),
                  _menuItem('Flatten Image', '', ctrl.flattenImage),
                ],
              ),
              _MenuButton(
                label: 'Select',
                items: [
                  _menuItem('Select All', 'Ctrl+A', ctrl.selectAll),
                  _menuItem('Deselect', 'Ctrl+D', ctrl.deselect),
                  _menuItem(
                      'Invert Selection', 'Ctrl+Shift+I', ctrl.invertSelection),
                  const PopupMenuDivider(),
                  _menuItem(
                    'Feather Selection...',
                    '',
                    () => ProDialogs.showFeatherSelection(context, ctrl),
                  ),
                  _menuItem(
                    'Expand / Contract...',
                    '',
                    () => ProDialogs.showModifySelection(context, ctrl),
                  ),
                  _menuItem(
                    'Stroke Selection...',
                    '',
                    () => ProDialogs.showStrokeSelection(context, ctrl),
                  ),
                ],
              ),
              _MenuButton(
                label: 'Filter',
                items: [
                  _menuItem('Gaussian Blur...', '',
                      () => FyrDialogs.showGaussianBlur(context, ctrl)),
                  _menuItem('Motion Blur...', '',
                      () => ProDialogs.showMotionBlur(context, ctrl)),
                  _menuItem('Radial Zoom Blur...', '',
                      () => ProDialogs.showRadialBlur(context, ctrl)),
                  const PopupMenuDivider(),
                  _menuItem('Unsharp Mask...', '',
                      () => ProDialogs.showUnsharpMask(context, ctrl)),
                  _menuItem('Sharpen...', '',
                      () => FyrDialogs.showSharpen(context, ctrl)),
                  const PopupMenuDivider(),
                  _menuItem('Chromatic Aberration...', '',
                      () => ProDialogs.showChromaticAberration(context, ctrl)),
                  _menuItem('Halftone Dot Screen...', '',
                      () => ProDialogs.showHalftone(context, ctrl)),
                  _menuItem('Pixelate / Mosaic...', '',
                      () => FyrDialogs.showPixelate(context, ctrl)),
                  _menuItem('Add Noise...', '',
                      () => FyrDialogs.showAddNoise(context, ctrl)),
                  _menuItem('Vignette...', '',
                      () => FyrDialogs.showVignette(context, ctrl)),
                  _menuItem('Drop Shadow...', '',
                      () => FyrDialogs.showDropShadow(context, ctrl)),
                  const PopupMenuDivider(),
                  _menuItem(
                    'Edge Detect (Sobel)',
                    '',
                    () => ctrl.runImmediateFilter(
                      'Sobel Edge Detect',
                      (s, w, h, m) => PixelOps.sobelEdgeDetect(s, w, h),
                    ),
                  ),
                  _menuItem(
                    'Emboss',
                    '',
                    () => ctrl.runImmediateFilter(
                      'Emboss',
                      (s, w, h, m) => PixelOps.emboss(s, w, h),
                    ),
                  ),
                ],
              ),
              _MenuButton(
                label: 'View',
                items: [
                  _menuItem('Zoom In', 'Ctrl++', () => ctrl.zoomBy(1.25)),
                  _menuItem('Zoom Out', 'Ctrl+-', () => ctrl.zoomBy(0.8)),
                  _menuItem('Fit on Screen', 'Ctrl+0', onFitViewport),
                  _menuItem('Actual Pixels (100%)', 'Ctrl+1', ctrl.resetZoom100),
                  const PopupMenuDivider(),
                  _menuItem(
                    doc?.showGrid == true ? 'Hide Pixel Grid' : 'Show Pixel Grid',
                    "Ctrl+'",
                    ctrl.toggleGrid,
                  ),
                  _menuItem(
                    doc?.showRulers == true ? 'Hide Rulers' : 'Show Rulers',
                    'Ctrl+R',
                    ctrl.toggleRulers,
                  ),
                  const PopupMenuDivider(),
                  _menuItem('Guide: None', '',
                      () => ctrl.setCompositionGuide(CompositionGuide.none)),
                  _menuItem(
                      'Guide: Rule of Thirds',
                      '',
                      () => ctrl.setCompositionGuide(
                          CompositionGuide.ruleOfThirds)),
                  _menuItem(
                      'Guide: Golden Ratio',
                      '',
                      () => ctrl
                          .setCompositionGuide(CompositionGuide.goldenRatio)),
                  _menuItem(
                      'Guide: Center Crosshair',
                      '',
                      () => ctrl.setCompositionGuide(
                          CompositionGuide.centerCrosshair)),
                  _menuItem(
                    'Add Center H/V Guides',
                    '',
                    doc == null
                        ? null
                        : () {
                            ctrl.addGuide(
                                horizontal: true, pos: doc.height / 2.0);
                            ctrl.addGuide(
                                horizontal: false, pos: doc.width / 2.0);
                          },
                  ),
                  _menuItem('Clear Guides', '', ctrl.clearGuides),
                ],
              ),
              _MenuButton(
                label: 'Help',
                items: [
                  _menuItem('Keyboard Shortcuts...', '?',
                      () => FyrDialogs.showShortcutsHelp(context)),
                ],
              ),
              const Spacer(),
              if (ctrl.statusMessage != null)
                Text(
                  ctrl.statusMessage!,
                  style: TextStyle(
                    fontSize: 11,
                    color: FyrTheme.accentColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSimpleQuickBar(
    BuildContext context,
    EditorController ctrl,
    GraphicsDocument? doc,
  ) {
    Widget divider() => Container(
          width: 1,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          color: FyrTheme.dividerColor,
        );

    final hasDoc = doc != null;

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: FyrTheme.contentColor,
        border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Row(
        children: [
          _SimpleQuickButton(
            icon: Icons.folder_open_rounded,
            label: 'Open',
            onTap: () async {
              final res = await FilePicker.pickFiles(
                type: FileType.custom,
                allowedExtensions: [
                  'png',
                  'jpg',
                  'jpeg',
                  'webp',
                  'bmp',
                  'gif',
                  'fyrg',
                ],
              );
              if (res != null && res.files.single.path != null) {
                await ctrl.openFileFromPath(res.files.single.path!);
              }
            },
          ),
          divider(),
          _SimpleQuickButton(
            icon: Icons.auto_fix_high_rounded,
            label: 'Auto Enhance',
            accent: true,
            onTap: hasDoc
                ? () {
                    ctrl.runImmediateFilter(
                      'Auto Enhance',
                      (s, w, h, m) => ProPixelOps.autoLevels(
                        ProPixelOps.autoWhiteBalance(s, selectionMask: m),
                        selectionMask: m,
                      ),
                    );
                  }
                : null,
          ),
          _SimpleQuickButton(
            icon: Icons.tune_rounded,
            label: 'Adjust',
            onTap: hasDoc
                ? () => ProDialogs.showDevelopAdjust(context, ctrl,
                    simpleMode: true)
                : null,
          ),
          _SimpleQuickButton(
            icon: Icons.palette_outlined,
            label: 'Photo Looks',
            onTap: hasDoc ? () => ProDialogs.showPhotoLooks(context, ctrl) : null,
          ),
          _SimpleQuickButton(
            icon: Icons.blur_on_rounded,
            label: 'Blur',
            onTap:
                hasDoc ? () => FyrDialogs.showGaussianBlur(context, ctrl) : null,
          ),
          divider(),
          _SimpleQuickButton(
            icon: Icons.rotate_right_rounded,
            label: 'Rotate',
            onTap: hasDoc ? () => ctrl.rotateCanvas(90) : null,
          ),
          _SimpleQuickButton(
            icon: Icons.flip_rounded,
            label: 'Flip',
            onTap: hasDoc ? () => ctrl.flipCanvas(horizontal: true) : null,
          ),
          const SizedBox(width: 8),
          if (ctrl.statusMessage != null)
            Expanded(
              child: Text(
                ctrl.statusMessage!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: FyrTheme.accentColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 6),
          _SimpleQuickButton(
            icon: Icons.auto_awesome,
            label: 'Pro Studio',
            trailingIcon: Icons.chevron_right_rounded,
            onTap: () => ctrl.setWorkspaceMode(WorkspaceMode.advanced),
          ),
        ],
      ),
    );
  }

  static PopupMenuItem<VoidCallback> _menuItem(
    String title,
    String shortcut,
    VoidCallback? action,
  ) {
    return PopupMenuItem<VoidCallback>(
      value: action,
      enabled: action != null,
      height: 32,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontSize: 12)),
          if (shortcut.isNotEmpty) ...[
            const SizedBox(width: 24),
            Text(
              shortcut,
              style: TextStyle(
                fontSize: 10.5,
                color: FyrTheme.textColorMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkspaceModeToggle extends StatelessWidget {
  final EditorController ctrl;
  const _WorkspaceModeToggle({required this.ctrl});

  @override
  Widget build(BuildContext context) {
    final isAdv = ctrl.isAdvancedMode;
    return Tooltip(
      message: 'Switch between Simple and Advanced Pro Studio (Ctrl+Shift+A)',
      child: Container(
        height: 28,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pill(
              label: 'Simple',
              icon: Icons.bolt_rounded,
              selected: !isAdv,
              onTap: () => ctrl.setWorkspaceMode(WorkspaceMode.simple),
            ),
            _pill(
              label: 'Advanced',
              icon: Icons.auto_awesome,
              selected: isAdv,
              onTap: () => ctrl.setWorkspaceMode(WorkspaceMode.advanced),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: selected ? FyrTheme.accentColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: selected
                  ? FyrTheme.getContrastingColor(FyrTheme.accentColor)
                  : FyrTheme.textColorMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected
                    ? FyrTheme.getContrastingColor(FyrTheme.accentColor)
                    : FyrTheme.textColorMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  final String label;
  final List<PopupMenuEntry<VoidCallback>> items;
  const _MenuButton({required this.label, required this.items});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<VoidCallback>(
      tooltip: '',
      offset: const Offset(0, 28),
      color: FyrTheme.isDark ? const Color(0xFF161619) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      itemBuilder: (_) => items,
      onSelected: (cb) => cb(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: FyrTheme.textColorMuted,
          ),
        ),
      ),
    );
  }
}

class _SimpleQuickButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final IconData? trailingIcon;
  final bool accent;
  final VoidCallback? onTap;

  const _SimpleQuickButton({
    required this.icon,
    required this.label,
    this.trailingIcon,
    this.accent = false,
    required this.onTap,
  });

  @override
  State<_SimpleQuickButton> createState() => _SimpleQuickButtonState();
}

class _SimpleQuickButtonState extends State<_SimpleQuickButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final activeHover = enabled && _hovered;

    final Color bgColor;
    final Color borderColor;
    if (activeHover) {
      bgColor = widget.accent
          ? FyrTheme.accentColor.withValues(alpha: 0.14)
          : FyrTheme.cardColor;
      borderColor = widget.accent
          ? FyrTheme.accentColor.withValues(alpha: 0.35)
          : FyrTheme.dividerColor;
    } else {
      bgColor = Colors.transparent;
      borderColor = Colors.transparent;
    }

    final Color iconColor;
    final Color textColor;
    if (!enabled) {
      iconColor = FyrTheme.textColorMuted.withValues(alpha: 0.38);
      textColor = FyrTheme.textColorMuted.withValues(alpha: 0.38);
    } else if (widget.accent) {
      iconColor = FyrTheme.accentColor;
      textColor = activeHover ? FyrTheme.textColor : FyrTheme.textColorMuted;
    } else {
      iconColor = activeHover ? FyrTheme.textColor : FyrTheme.textColorMuted;
      textColor = activeHover ? FyrTheme.textColor : FyrTheme.textColorMuted;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 13.5, color: iconColor),
                const SizedBox(width: 5),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
                if (widget.trailingIcon != null) ...[
                  const SizedBox(width: 2),
                  Icon(widget.trailingIcon, size: 13, color: iconColor),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
