import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../engine/pixel_ops.dart';
import '../fyr_theme.dart';
import '../state/editor_controller.dart';
import 'dialogs.dart';
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
                  icon: const Icon(Icons.ios_share_rounded, size: 14),
                  label: const Text('Export',
                      style:
                          TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
        // Row 2: Photoshop/Photopea style Menu Bar
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
                ],
              ),
              _MenuButton(
                label: 'Filter',
                items: [
                  _menuItem('Gaussian Blur...', '',
                      () => FyrDialogs.showGaussianBlur(context, ctrl)),
                  _menuItem('Sharpen...', '',
                      () => FyrDialogs.showSharpen(context, ctrl)),
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
