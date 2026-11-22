import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/editor_types.dart';
import '../state/editor_controller.dart';

class _ToolMeta {
  final ToolType tool;
  final IconData icon;
  final String label;
  final String shortcut;
  final bool dividerAfter;

  const _ToolMeta(
    this.tool,
    this.icon,
    this.label,
    this.shortcut, {
    this.dividerAfter = false,
  });
}

const List<_ToolMeta> _allTools = [
  _ToolMeta(ToolType.move, Icons.open_with_rounded, 'Move', 'V'),
  _ToolMeta(ToolType.rectSelect, Icons.crop_free_rounded, 'Rect Marquee', 'M'),
  _ToolMeta(
      ToolType.ellipseSelect, Icons.circle_outlined, 'Ellipse Marquee', 'Shift+M'),
  _ToolMeta(ToolType.lassoSelect, Icons.gesture_rounded, 'Lasso Select', 'L'),
  _ToolMeta(ToolType.magicWand, Icons.auto_fix_high_rounded, 'Magic Wand', 'W'),
  _ToolMeta(ToolType.crop, Icons.crop_rounded, 'Crop', 'C', dividerAfter: true),
  _ToolMeta(ToolType.brush, Icons.brush_rounded, 'Brush', 'B'),
  _ToolMeta(ToolType.pencil, Icons.edit_rounded, 'Pencil', 'N'),
  _ToolMeta(ToolType.eraser, Icons.cleaning_services_rounded, 'Eraser', 'E'),
  _ToolMeta(ToolType.dodge, Icons.wb_sunny_outlined, 'Dodge (Lighten)', 'O'),
  _ToolMeta(
      ToolType.burn, Icons.brightness_3_outlined, 'Burn (Darken)', 'Shift+O'),
  _ToolMeta(ToolType.sponge, Icons.water_drop_outlined, 'Sponge (Saturation)', 'K'),
  _ToolMeta(
      ToolType.healingBrush, Icons.healing_rounded, 'Spot Healing Brush', 'J'),
  _ToolMeta(ToolType.cloneStamp, Icons.control_point_duplicate_rounded,
      'Clone Stamp', 'S'),
  _ToolMeta(ToolType.smudge, Icons.fingerprint_rounded, 'Smudge', ''),
  _ToolMeta(ToolType.blurBrush, Icons.blur_on_rounded, 'Blur Brush', ''),
  _ToolMeta(ToolType.sharpenBrush, Icons.details_rounded, 'Sharpen Brush', '',
      dividerAfter: true),
  _ToolMeta(
      ToolType.bucket, Icons.format_color_fill_rounded, 'Paint Bucket', 'G'),
  _ToolMeta(ToolType.gradient, Icons.gradient_rounded, 'Gradient', 'Shift+G'),
  _ToolMeta(ToolType.shape, Icons.category_rounded, 'Shapes', 'U'),
  _ToolMeta(ToolType.text, Icons.title_rounded, 'Text', 'T',
      dividerAfter: true),
  _ToolMeta(ToolType.eyedropper, Icons.colorize_rounded, 'Eyedropper', 'I'),
  _ToolMeta(ToolType.pan, Icons.pan_tool_alt_rounded, 'Hand / Pan', 'H'),
  _ToolMeta(ToolType.zoom, Icons.zoom_in_rounded, 'Zoom', 'Z'),
];

class ToolsDock extends StatelessWidget {
  const ToolsDock({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<EditorController>();
    final visibleTools = ctrl.isAdvancedMode
        ? _allTools
        : _allTools.where((m) => kSimpleModeTools.contains(m.tool)).toList();

    return Container(
      width: ctrl.isAdvancedMode ? 50 : 56,
      decoration: BoxDecoration(
        color: FyrTheme.sidebarColor,
        border: Border(right: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 6),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: visibleTools.map((meta) {
                  final active = ctrl.activeTool == meta.tool;
                  final tip = meta.shortcut.isEmpty
                      ? meta.label
                      : '${meta.label} (${meta.shortcut})';
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: ctrl.isAdvancedMode ? 2 : 3,
                        ),
                        child: Tooltip(
                          message: tip,
                          waitDuration: const Duration(milliseconds: 300),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => ctrl.setTool(meta.tool),
                            child: Container(
                              width: ctrl.isAdvancedMode ? 36 : 40,
                              height: ctrl.isAdvancedMode ? 31 : 38,
                              decoration: BoxDecoration(
                                color: active
                                    ? FyrTheme.accentColor
                                        .withValues(alpha: 0.22)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                                border: active
                                    ? Border.all(
                                        color: FyrTheme.accentColor
                                            .withValues(alpha: 0.7))
                                    : null,
                              ),
                              child: Icon(
                                meta.icon,
                                size: ctrl.isAdvancedMode ? 17 : 19,
                                color: active
                                    ? FyrTheme.accentColor
                                    : FyrTheme.textColorMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (ctrl.isAdvancedMode && meta.dividerAfter)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          child: Divider(
                              height: 1, color: FyrTheme.dividerColor),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          Divider(height: 1, color: FyrTheme.dividerColor),
          // FG / BG Color Swatches + Swap/Reset
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                SizedBox(
                  width: 36,
                  height: 36,
                  child: Stack(
                    children: [
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Tooltip(
                          message: 'Background Color',
                          child: GestureDetector(
                            onTap: () {
                              ctrl.showRightDock = true;
                              ctrl.topDockTab = 0;
                              ctrl.refresh();
                            },
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: ctrl.backgroundColor,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: FyrTheme.textColorMuted,
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        child: Tooltip(
                          message: 'Foreground Color',
                          child: GestureDetector(
                            onTap: () {
                              ctrl.showRightDock = true;
                              ctrl.topDockTab = 0;
                              ctrl.refresh();
                            },
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: ctrl.foregroundColor,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 1.4,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black38,
                                    blurRadius: 3,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Tooltip(
                      message: 'Swap Colors (X)',
                      child: InkWell(
                        onTap: ctrl.swapColors,
                        child: Icon(Icons.swap_horiz_rounded,
                            size: 14, color: FyrTheme.textColorMuted),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: 'Reset B/W (D)',
                      child: InkWell(
                        onTap: ctrl.resetColors,
                        child: Icon(Icons.contrast_rounded,
                            size: 13, color: FyrTheme.textColorMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
