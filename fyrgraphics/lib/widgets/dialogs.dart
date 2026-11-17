import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../engine/pixel_ops.dart';
import '../fyr_theme.dart';
import '../models/editor_types.dart';
import '../state/editor_controller.dart';

class FyrDialogs {
  static Dialog _styledDialog({
    required BuildContext context,
    required String title,
    required Widget child,
    List<Widget>? actions,
    double width = 440,
  }) {
    final isDark = FyrTheme.isDark;
    return Dialog(
      backgroundColor: isDark ? const Color(0xFF141416) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: FyrTheme.dividerColor, width: 1),
      ),
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
              ),
              child: Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: FyrTheme.textColor,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: child,
            ),
            if (actions != null && actions.isNotEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: actions,
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Future<void> showNewDocument(
    BuildContext context,
    EditorController ctrl,
  ) async {
    final titleCtrl =
        TextEditingController(text: 'Untitled-${ctrl.documents.length + 1}');
    final widthCtrl = TextEditingController(text: '1280');
    final heightCtrl = TextEditingController(text: '720');
    String bgChoice = 'transparent';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => _styledDialog(
          context: ctx,
          title: 'New Document',
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: titleCtrl,
                decoration: const InputDecoration(
                  labelText: 'Document Name',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Presets',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: FyrTheme.textColorMuted,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kCanvasPresets.map((preset) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      widthCtrl.text = preset.width.toString();
                      heightCtrl.text = preset.height.toString();
                      setState(() {});
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: FyrTheme.cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: FyrTheme.dividerColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(preset.name,
                              style: const TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600)),
                          Text('${preset.width} × ${preset.height}',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: FyrTheme.textColorMuted)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: widthCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Width (px)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: heightCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Height (px)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: bgChoice,
                decoration: const InputDecoration(
                  labelText: 'Background Contents',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'transparent', child: Text('Transparent')),
                  DropdownMenuItem(value: 'white', child: Text('White')),
                  DropdownMenuItem(value: 'black', child: Text('Black')),
                  DropdownMenuItem(
                      value: 'fg', child: Text('Foreground Color')),
                ],
                onChanged: (v) => setState(() => bgChoice = v ?? 'transparent'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: FyrTheme.accentColor,
                foregroundColor:
                    FyrTheme.getContrastingColor(FyrTheme.accentColor),
              ),
              onPressed: () async {
                final w = int.tryParse(widthCtrl.text) ?? 1280;
                final h = int.tryParse(heightCtrl.text) ?? 720;
                Color bg = Colors.transparent;
                if (bgChoice == 'white') bg = Colors.white;
                if (bgChoice == 'black') bg = Colors.black;
                if (bgChoice == 'fg') bg = ctrl.foregroundColor;
                Navigator.pop(ctx);
                await ctrl.createNewDocument(
                  title: titleCtrl.text.trim().isEmpty
                      ? 'Untitled'
                      : titleCtrl.text.trim(),
                  width: w,
                  height: h,
                  backgroundColor: bg,
                );
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> showExportDialog(
    BuildContext context,
    EditorController ctrl,
  ) async {
    final doc = ctrl.activeDoc;
    if (doc == null) return;
    String format = 'png';
    int quality = 92;
    double scale = 1.0;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => _styledDialog(
          context: ctx,
          title: 'Export Image',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: format,
                decoration: const InputDecoration(
                  labelText: 'Format',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                      value: 'png', child: Text('PNG (Lossless + Alpha)')),
                  DropdownMenuItem(
                      value: 'jpg', child: Text('JPEG (Compressed)')),
                  DropdownMenuItem(value: 'bmp', child: Text('BMP (Bitmap)')),
                  DropdownMenuItem(value: 'tga', child: Text('TGA (Targa)')),
                  DropdownMenuItem(value: 'gif', child: Text('GIF')),
                ],
                onChanged: (v) => setState(() => format = v ?? 'png'),
              ),
              const SizedBox(height: 14),
              if (format == 'jpg') ...[
                Text('JPEG Quality: $quality%',
                    style: const TextStyle(fontSize: 12)),
                Slider(
                  value: quality.toDouble(),
                  min: 10,
                  max: 100,
                  divisions: 90,
                  activeColor: FyrTheme.accentColor,
                  onChanged: (v) => setState(() => quality = v.round()),
                ),
              ],
              Text(
                'Scale: ${(scale * 100).round()}%  (${(doc.width * scale).round()} × ${(doc.height * scale).round()} px)',
                style: const TextStyle(fontSize: 12),
              ),
              Slider(
                value: scale,
                min: 0.25,
                max: 4.0,
                divisions: 15,
                activeColor: FyrTheme.accentColor,
                onChanged: (v) => setState(() => scale = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: FyrTheme.accentColor,
                foregroundColor:
                    FyrTheme.getContrastingColor(FyrTheme.accentColor),
              ),
              onPressed: () async {
                final baseName = doc.title.replaceAll(RegExp(r'\.[^.]+$'), '');
                final savePath = await FilePicker.saveFile(
                  dialogTitle: 'Export Image',
                  fileName: '$baseName.$format',
                  type: FileType.custom,
                  allowedExtensions: [format],
                );
                if (savePath != null) {
                  final out = savePath.toLowerCase().endsWith('.$format')
                      ? savePath
                      : '$savePath.$format';
                  await ctrl.exportDocumentToPath(
                    path: out,
                    format: format,
                    jpgQuality: quality,
                    scale: scale,
                  );
                }
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Export...'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> showTextLayerDialog(
    BuildContext context,
    EditorController ctrl, {
    Offset origin = const Offset(60, 60),
    TextLayerData? existing,
    int? replaceIndex,
  }) async {
    final textCtrl =
        TextEditingController(text: existing?.text ?? 'fyrGraphics');
    double fontSize = existing?.fontSize ?? ctrl.textFontSize;
    bool bold = existing?.bold ?? ctrl.textBold;
    bool italic = existing?.italic ?? ctrl.textItalic;
    Color textColor = existing?.color ?? ctrl.foregroundColor;
    String fontFamily = existing?.fontFamily ?? ctrl.textFontFamily;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => _styledDialog(
          context: ctx,
          title: existing == null ? 'Add Text Layer' : 'Edit Text Layer',
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: textCtrl,
                maxLines: 4,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Text Content',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: fontFamily,
                      decoration: const InputDecoration(
                        labelText: 'Font',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Inter', child: Text('Inter')),
                        DropdownMenuItem(value: 'Outfit', child: Text('Outfit')),
                        DropdownMenuItem(
                            value: 'monospace', child: Text('Monospace')),
                        DropdownMenuItem(value: 'serif', child: Text('Serif')),
                      ],
                      onChanged: (v) =>
                          setState(() => fontFamily = v ?? 'Inter'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton.filledTonal(
                    isSelected: bold,
                    onPressed: () => setState(() => bold = !bold),
                    icon: const Icon(Icons.format_bold, size: 18),
                    tooltip: 'Bold',
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    isSelected: italic,
                    onPressed: () => setState(() => italic = !italic),
                    icon: const Icon(Icons.format_italic, size: 18),
                    tooltip: 'Italic',
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text('Size: ${fontSize.round()} px',
                      style: const TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: fontSize,
                      min: 10,
                      max: 240,
                      activeColor: FyrTheme.accentColor,
                      onChanged: (v) => setState(() => fontSize = v),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: FyrTheme.accentColor,
                foregroundColor:
                    FyrTheme.getContrastingColor(FyrTheme.accentColor),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                await ctrl.addOrUpdateTextLayer(
                  data: TextLayerData(
                    text: textCtrl.text,
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    bold: bold,
                    italic: italic,
                    color: textColor,
                  ),
                  origin: origin,
                  replaceIndex: replaceIndex,
                );
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  static Future<void> showImageSizeDialog(
    BuildContext context,
    EditorController ctrl, {
    required bool canvasOnly,
  }) async {
    final doc = ctrl.activeDoc;
    if (doc == null) return;
    final wCtrl = TextEditingController(text: doc.width.toString());
    final hCtrl = TextEditingController(text: doc.height.toString());
    bool lockAspect = !canvasOnly;
    final aspect = doc.width / doc.height;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => _styledDialog(
          context: ctx,
          title: canvasOnly ? 'Canvas Size' : 'Image Size (Resample)',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: wCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Width (px)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        if (lockAspect) {
                          final nw = int.tryParse(v);
                          if (nw != null && nw > 0) {
                            hCtrl.text = (nw / aspect).round().toString();
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: hCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Height (px)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        if (lockAspect) {
                          final nh = int.tryParse(v);
                          if (nh != null && nh > 0) {
                            wCtrl.text = (nh * aspect).round().toString();
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                value: lockAspect,
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Maintain Aspect Ratio',
                    style: TextStyle(fontSize: 12)),
                onChanged: (v) => setState(() => lockAspect = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: FyrTheme.accentColor,
                foregroundColor:
                    FyrTheme.getContrastingColor(FyrTheme.accentColor),
              ),
              onPressed: () async {
                final nw = int.tryParse(wCtrl.text) ?? doc.width;
                final nh = int.tryParse(hCtrl.text) ?? doc.height;
                Navigator.pop(ctx);
                if (canvasOnly) {
                  await ctrl.resizeCanvas(nw, nh);
                } else {
                  await ctrl.resizeImage(nw, nh);
                }
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
  }

  /// Live-preview adjustment/filter modal wrapper.
  static Future<void> showLivePixelFilterDialog({
    required BuildContext context,
    required EditorController ctrl,
    required String title,
    required List<FilterParam> params,
    required Function(Map<String, double> values) onBuildTransform,
  }) async {
    final doc = ctrl.activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null || layer.locked) return;

    final values = {for (final p in params) p.key: p.initial};
    ctrl.beginLayerPreview();
    await ctrl.applyPreviewTransform(onBuildTransform(values));

    if (!context.mounted) return;
    bool applied = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => _styledDialog(
          context: ctx,
          title: title,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: params.map((param) {
              final v = values[param.key]!;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(param.label, style: const TextStyle(fontSize: 12)),
                        Text(
                          param.decimals == 0
                              ? v.round().toString()
                              : v.toStringAsFixed(param.decimals),
                          style: TextStyle(
                            fontSize: 12,
                            color: FyrTheme.accentColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: v,
                      min: param.min,
                      max: param.max,
                      activeColor: FyrTheme.accentColor,
                      onChanged: (nv) {
                        setState(() => values[param.key] = nv);
                        ctrl.applyPreviewTransform(onBuildTransform(values));
                      },
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await ctrl.cancelLayerPreview();
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: FyrTheme.accentColor,
                foregroundColor:
                    FyrTheme.getContrastingColor(FyrTheme.accentColor),
              ),
              onPressed: () {
                applied = true;
                ctrl.commitLayerPreview(title);
                Navigator.pop(ctx);
              },
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
    );
    if (!applied) {
      await ctrl.cancelLayerPreview();
    }
  }

  static Future<void> showBrightnessContrast(
      BuildContext context, EditorController ctrl) {
    return showLivePixelFilterDialog(
      context: context,
      ctrl: ctrl,
      title: 'Brightness / Contrast',
      params: [
        FilterParam('brightness', 'Brightness', -100, 100, 0),
        FilterParam('contrast', 'Contrast', -100, 100, 0),
      ],
      onBuildTransform: (v) => (src, w, h, mask) =>
          PixelOps.adjustBrightnessContrast(
            src,
            w,
            h,
            brightness: v['brightness']!,
            contrast: v['contrast']!,
            selectionMask: mask,
          ),
    );
  }

  static Future<void> showHueSaturation(
      BuildContext context, EditorController ctrl) {
    return showLivePixelFilterDialog(
      context: context,
      ctrl: ctrl,
      title: 'Hue / Saturation',
      params: [
        FilterParam('hue', 'Hue Shift (°)', -180, 180, 0),
        FilterParam('sat', 'Saturation', -100, 100, 0),
        FilterParam('light', 'Lightness', -100, 100, 0),
      ],
      onBuildTransform: (v) => (src, w, h, mask) => PixelOps.adjustHsl(
            src,
            w,
            h,
            hueShift: v['hue']!,
            saturation: v['sat']!,
            lightness: v['light']!,
            selectionMask: mask,
          ),
    );
  }

  static Future<void> showLevels(BuildContext context, EditorController ctrl) {
    return showLivePixelFilterDialog(
      context: context,
      ctrl: ctrl,
      title: 'Levels',
      params: [
        FilterParam('black', 'Black Point', 0, 240, 0),
        FilterParam('gamma', 'Gamma (Midtones)', 0.2, 3.0, 1.0, decimals: 2),
        FilterParam('white', 'White Point', 15, 255, 255),
      ],
      onBuildTransform: (v) => (src, w, h, mask) => PixelOps.adjustLevels(
            src,
            blackPoint: v['black']!.round(),
            gamma: v['gamma']!,
            whitePoint: v['white']!.round(),
            selectionMask: mask,
          ),
    );
  }

  static Future<void> showColorBalance(
      BuildContext context, EditorController ctrl) {
    return showLivePixelFilterDialog(
      context: context,
      ctrl: ctrl,
      title: 'Color Balance',
      params: [
        FilterParam('cr', 'Cyan  ↔  Red', -100, 100, 0),
        FilterParam('mg', 'Magenta  ↔  Green', -100, 100, 0),
        FilterParam('yb', 'Yellow  ↔  Blue', -100, 100, 0),
      ],
      onBuildTransform: (v) => (src, w, h, mask) => PixelOps.adjustColorBalance(
            src,
            cyanRed: v['cr']!,
            magentaGreen: v['mg']!,
            yellowBlue: v['yb']!,
            selectionMask: mask,
          ),
    );
  }

  static Future<void> showGaussianBlur(
      BuildContext context, EditorController ctrl) {
    return showLivePixelFilterDialog(
      context: context,
      ctrl: ctrl,
      title: 'Gaussian Blur',
      params: [
        FilterParam('radius', 'Radius (px)', 0, 50, 6, decimals: 1),
      ],
      onBuildTransform: (v) => (src, w, h, mask) => PixelOps.gaussianBlur(
            src,
            w,
            h,
            v['radius']!,
            selectionMask: mask,
          ),
    );
  }

  static Future<void> showSharpen(
      BuildContext context, EditorController ctrl) {
    return showLivePixelFilterDialog(
      context: context,
      ctrl: ctrl,
      title: 'Sharpen',
      params: [
        FilterParam('amount', 'Amount', 0, 4.0, 1.2, decimals: 2),
      ],
      onBuildTransform: (v) => (src, w, h, mask) => PixelOps.sharpen(
            src,
            w,
            h,
            amount: v['amount']!,
            selectionMask: mask,
          ),
    );
  }

  static Future<void> showPixelate(
      BuildContext context, EditorController ctrl) {
    return showLivePixelFilterDialog(
      context: context,
      ctrl: ctrl,
      title: 'Pixelate / Mosaic',
      params: [
        FilterParam('cell', 'Cell Size (px)', 2, 64, 10),
      ],
      onBuildTransform: (v) => (src, w, h, mask) => PixelOps.pixelate(
            src,
            w,
            h,
            v['cell']!.round(),
            selectionMask: mask,
          ),
    );
  }

  static Future<void> showAddNoise(
      BuildContext context, EditorController ctrl) {
    return showLivePixelFilterDialog(
      context: context,
      ctrl: ctrl,
      title: 'Add Noise',
      params: [
        FilterParam('amount', 'Intensity', 1, 120, 28),
      ],
      onBuildTransform: (v) => (src, w, h, mask) => PixelOps.addNoise(
            src,
            w,
            h,
            amount: v['amount']!,
            selectionMask: mask,
          ),
    );
  }

  static Future<void> showVignette(
      BuildContext context, EditorController ctrl) {
    return showLivePixelFilterDialog(
      context: context,
      ctrl: ctrl,
      title: 'Vignette',
      params: [
        FilterParam('intensity', 'Intensity', 0.1, 1.0, 0.65, decimals: 2),
        FilterParam('radius', 'Inner Radius', 0.2, 0.9, 0.65, decimals: 2),
      ],
      onBuildTransform: (v) => (src, w, h, mask) => PixelOps.vignette(
            src,
            w,
            h,
            intensity: v['intensity']!,
            radius: v['radius']!,
          ),
    );
  }

  static Future<void> showDropShadow(
      BuildContext context, EditorController ctrl) {
    return showLivePixelFilterDialog(
      context: context,
      ctrl: ctrl,
      title: 'Drop Shadow',
      params: [
        FilterParam('dx', 'Offset X (px)', -60, 60, 10),
        FilterParam('dy', 'Offset Y (px)', -60, 60, 10),
        FilterParam('blur', 'Blur Radius', 0, 40, 10, decimals: 1),
      ],
      onBuildTransform: (v) => (src, w, h, mask) => PixelOps.dropShadow(
            src,
            w,
            h,
            dx: v['dx']!.round(),
            dy: v['dy']!.round(),
            blurRadius: v['blur']!,
          ),
    );
  }

  static Future<void> showShortcutsHelp(BuildContext context) async {
    const shortcuts = [
      ('V', 'Move Tool'),
      ('M', 'Rectangular Marquee'),
      ('L', 'Lasso Selection'),
      ('W', 'Magic Wand'),
      ('C', 'Crop Tool'),
      ('I', 'Eyedropper'),
      ('B', 'Brush Tool'),
      ('N', 'Pencil Tool'),
      ('E', 'Eraser Tool'),
      ('S', 'Clone Stamp (Alt+Click source)'),
      ('G', 'Paint Bucket / Gradient'),
      ('U', 'Shape Tool'),
      ('T', 'Text Tool'),
      ('H / Space', 'Hand / Pan'),
      ('Z', 'Zoom Tool'),
      ('X / D', 'Swap / Reset FG & BG Colors'),
      ('[ / ]', 'Decrease / Increase Brush Size'),
      ('Ctrl+Z / Ctrl+Y', 'Undo / Redo'),
      ('Ctrl+A / Ctrl+D', 'Select All / Deselect'),
      ('Ctrl+C / X / V', 'Copy / Cut / Paste Layer'),
      ('Ctrl+N / O / S', 'New / Open / Save Project'),
      ('Ctrl+E', 'Export Image'),
      ('Ctrl+0 / Ctrl+1', 'Fit Canvas / 100% Zoom'),
    ];
    await showDialog<void>(
      context: context,
      builder: (ctx) => _styledDialog(
        context: ctx,
        title: 'fyrGraphics Shortcuts',
        width: 480,
        child: SizedBox(
          height: 360,
          child: ListView.separated(
            itemCount: shortcuts.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: FyrTheme.dividerColor),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 130,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: FyrTheme.cardColor,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: FyrTheme.dividerColor),
                    ),
                    child: Text(
                      shortcuts[i].$1,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: FyrTheme.accentColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(shortcuts[i].$2,
                        style: const TextStyle(fontSize: 12)),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: FyrTheme.accentColor,
              foregroundColor:
                  FyrTheme.getContrastingColor(FyrTheme.accentColor),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class FilterParam {
  final String key;
  final String label;
  final double min;
  final double max;
  final double initial;
  final int decimals;

  FilterParam(
    this.key,
    this.label,
    this.min,
    this.max,
    this.initial, {
    this.decimals = 0,
  });
}
