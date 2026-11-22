import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/editor_types.dart';
import '../state/editor_controller.dart';

class ToolOptionsBar extends StatelessWidget {
  const ToolOptionsBar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<EditorController>();
    final tool = ctrl.activeTool;

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor,
        border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: FyrTheme.accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Text(
              _toolLabel(tool),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: FyrTheme.accentColor,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _buildOptions(ctrl, tool),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _toolLabel(ToolType t) {
    switch (t) {
      case ToolType.move:
        return 'Move';
      case ToolType.rectSelect:
        return 'Rect Marquee';
      case ToolType.ellipseSelect:
        return 'Ellipse Marquee';
      case ToolType.lassoSelect:
        return 'Lasso';
      case ToolType.magicWand:
        return 'Magic Wand';
      case ToolType.crop:
        return 'Crop';
      case ToolType.eyedropper:
        return 'Eyedropper';
      case ToolType.brush:
        return 'Brush';
      case ToolType.pencil:
        return 'Pencil';
      case ToolType.eraser:
        return 'Eraser';
      case ToolType.dodge:
        return 'Dodge';
      case ToolType.burn:
        return 'Burn';
      case ToolType.sponge:
        return 'Sponge';
      case ToolType.healingBrush:
        return 'Spot Heal';
      case ToolType.cloneStamp:
        return 'Clone Stamp';
      case ToolType.smudge:
        return 'Smudge';
      case ToolType.blurBrush:
        return 'Blur Brush';
      case ToolType.sharpenBrush:
        return 'Sharpen';
      case ToolType.bucket:
        return 'Paint Bucket';
      case ToolType.gradient:
        return 'Gradient';
      case ToolType.shape:
        return 'Shape';
      case ToolType.text:
        return 'Text';
      case ToolType.pan:
        return 'Hand';
      case ToolType.zoom:
        return 'Zoom';
    }
  }

  List<Widget> _buildOptions(EditorController ctrl, ToolType tool) {
    switch (tool) {
      case ToolType.brush:
      case ToolType.cloneStamp:
      case ToolType.smudge:
      case ToolType.blurBrush:
        return [
          if (tool == ToolType.brush && ctrl.isAdvancedMode) ...[
            Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: FyrTheme.cardColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<BrushPresetKind>(
                  value: ctrl.activeBrushPreset,
                  isDense: true,
                  dropdownColor: FyrTheme.surfaceColor,
                  style: TextStyle(fontSize: 11, color: FyrTheme.textColor),
                  items: kBrushPresets
                      .map((p) => DropdownMenuItem(
                            value: p.kind,
                            child: Text(p.name),
                          ))
                      .toList(),
                  onChanged: (k) {
                    if (k == null) return;
                    final preset =
                        kBrushPresets.firstWhere((p) => p.kind == k);
                    ctrl.applyBrushPreset(preset);
                  },
                ),
              ),
            ),
          ],
          _sliderChip(
            label: 'Size',
            valueText: '${ctrl.brushSize.round()}px',
            value: ctrl.brushSize,
            min: 1,
            max: 250,
            onChanged: (v) {
              ctrl.brushSize = v;
              ctrl.refresh();
            },
          ),
          if ((tool == ToolType.brush || tool == ToolType.cloneStamp) &&
              ctrl.isAdvancedMode)
            _sliderChip(
              label: 'Hardness',
              valueText: '${(ctrl.brushHardness * 100).round()}%',
              value: ctrl.brushHardness,
              min: 0.0,
              max: 1.0,
              onChanged: (v) {
                ctrl.brushHardness = v;
                ctrl.refresh();
              },
            ),
          _sliderChip(
            label: 'Opacity',
            valueText: '${(ctrl.brushOpacity * 100).round()}%',
            value: ctrl.brushOpacity,
            min: 0.05,
            max: 1.0,
            onChanged: (v) {
              ctrl.brushOpacity = v;
              ctrl.refresh();
            },
          ),
          if (tool == ToolType.brush && ctrl.isAdvancedMode) ...[
            _sliderChip(
              label: 'Scatter',
              valueText: '${(ctrl.brushScatter * 100).round()}%',
              value: ctrl.brushScatter,
              min: 0.0,
              max: 1.5,
              onChanged: (v) {
                ctrl.brushScatter = v;
                ctrl.refresh();
              },
            ),
            const SizedBox(width: 6),
            _symmetrySelector(ctrl),
          ],
          if (tool == ToolType.cloneStamp)
            Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                ctrl.cloneSourceAnchor == null
                    ? 'Alt + Click canvas to set clone source'
                    : 'Source: (${ctrl.cloneSourceAnchor!.dx.round()}, ${ctrl.cloneSourceAnchor!.dy.round()})',
                style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
              ),
            ),
        ];

      case ToolType.dodge:
      case ToolType.burn:
      case ToolType.sponge:
      case ToolType.sharpenBrush:
      case ToolType.healingBrush:
        return [
          _sliderChip(
            label: 'Size',
            valueText: '${ctrl.brushSize.round()}px',
            value: ctrl.brushSize,
            min: 4,
            max: 200,
            onChanged: (v) {
              ctrl.brushSize = v;
              ctrl.refresh();
            },
          ),
          if (tool != ToolType.healingBrush)
            _sliderChip(
              label: 'Strength',
              valueText: '${(ctrl.toneStrength * 100).round()}%',
              value: ctrl.toneStrength,
              min: 0.1,
              max: 1.0,
              onChanged: (v) {
                ctrl.toneStrength = v;
                ctrl.refresh();
              },
            ),
          if (tool == ToolType.sponge) ...[
            ChoiceChip(
              label: const Text('Saturate', style: TextStyle(fontSize: 10.5)),
              selected: !ctrl.spongeDesaturate,
              visualDensity: VisualDensity.compact,
              selectedColor: FyrTheme.accentColor.withValues(alpha: 0.25),
              onSelected: (_) {
                ctrl.spongeDesaturate = false;
                ctrl.refresh();
              },
            ),
            const SizedBox(width: 4),
            ChoiceChip(
              label: const Text('Desaturate', style: TextStyle(fontSize: 10.5)),
              selected: ctrl.spongeDesaturate,
              visualDensity: VisualDensity.compact,
              selectedColor: FyrTheme.accentColor.withValues(alpha: 0.25),
              onSelected: (_) {
                ctrl.spongeDesaturate = true;
                ctrl.refresh();
              },
            ),
          ],
          if (tool == ToolType.healingBrush)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'Click or dab blemishes to blend seamlessly with surrounding texture',
                style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
              ),
            ),
          if (ctrl.isAdvancedMode && tool != ToolType.healingBrush) ...[
            const SizedBox(width: 8),
            _symmetrySelector(ctrl),
          ],
        ];

      case ToolType.pencil:
        return [
          _sliderChip(
            label: 'Size',
            valueText: '${ctrl.brushSize.round()}px',
            value: ctrl.brushSize,
            min: 1,
            max: 100,
            onChanged: (v) {
              ctrl.brushSize = v;
              ctrl.refresh();
            },
          ),
        ];

      case ToolType.eraser:
        return [
          _sliderChip(
            label: 'Size',
            valueText: '${ctrl.eraserSize.round()}px',
            value: ctrl.eraserSize,
            min: 1,
            max: 250,
            onChanged: (v) {
              ctrl.eraserSize = v;
              ctrl.refresh();
            },
          ),
          _sliderChip(
            label: 'Hardness',
            valueText: '${(ctrl.eraserHardness * 100).round()}%',
            value: ctrl.eraserHardness,
            min: 0.0,
            max: 1.0,
            onChanged: (v) {
              ctrl.eraserHardness = v;
              ctrl.refresh();
            },
          ),
          _sliderChip(
            label: 'Opacity',
            valueText: '${(ctrl.eraserOpacity * 100).round()}%',
            value: ctrl.eraserOpacity,
            min: 0.05,
            max: 1.0,
            onChanged: (v) {
              ctrl.eraserOpacity = v;
              ctrl.refresh();
            },
          ),
        ];

      case ToolType.rectSelect:
      case ToolType.ellipseSelect:
      case ToolType.lassoSelect:
      case ToolType.magicWand:
        return [
          Text('Mode:',
              style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted)),
          const SizedBox(width: 6),
          ...SelectionMode.values.map((m) {
            final active = ctrl.selectionMode == m;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text(m.name[0].toUpperCase() + m.name.substring(1),
                    style: const TextStyle(fontSize: 10.5)),
                selected: active,
                visualDensity: VisualDensity.compact,
                selectedColor: FyrTheme.accentColor.withValues(alpha: 0.25),
                onSelected: (_) {
                  ctrl.selectionMode = m;
                  ctrl.refresh();
                },
              ),
            );
          }),
          if (tool == ToolType.magicWand) ...[
            const SizedBox(width: 10),
            _sliderChip(
              label: 'Tolerance',
              valueText: '${ctrl.wandTolerance}',
              value: ctrl.wandTolerance.toDouble(),
              min: 0,
              max: 200,
              onChanged: (v) {
                ctrl.wandTolerance = v.round();
                ctrl.refresh();
              },
            ),
            Row(
              children: [
                Checkbox(
                  value: ctrl.wandContiguous,
                  visualDensity: VisualDensity.compact,
                  activeColor: FyrTheme.accentColor,
                  onChanged: (v) {
                    ctrl.wandContiguous = v ?? true;
                    ctrl.refresh();
                  },
                ),
                const Text('Contiguous', style: TextStyle(fontSize: 11)),
              ],
            ),
          ],
          const SizedBox(width: 8),
          TextButton(
            onPressed: ctrl.deselect,
            child: const Text('Deselect', style: TextStyle(fontSize: 11)),
          ),
        ];

      case ToolType.bucket:
        return [
          _sliderChip(
            label: 'Tolerance',
            valueText: '${ctrl.bucketTolerance}',
            value: ctrl.bucketTolerance.toDouble(),
            min: 0,
            max: 200,
            onChanged: (v) {
              ctrl.bucketTolerance = v.round();
              ctrl.refresh();
            },
          ),
          _sliderChip(
            label: 'Opacity',
            valueText: '${(ctrl.brushOpacity * 100).round()}%',
            value: ctrl.brushOpacity,
            min: 0.05,
            max: 1.0,
            onChanged: (v) {
              ctrl.brushOpacity = v;
              ctrl.refresh();
            },
          ),
        ];

      case ToolType.gradient:
        return [
          Text('Type:',
              style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted)),
          const SizedBox(width: 6),
          ...GradientKind.values.map((k) {
            final label = switch (k) {
              GradientKind.linear => 'Linear',
              GradientKind.radial => 'Radial',
              GradientKind.fgToTransparent => 'FG → Clear',
            };
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(label, style: const TextStyle(fontSize: 11)),
                selected: ctrl.gradientKind == k,
                visualDensity: VisualDensity.compact,
                selectedColor: FyrTheme.accentColor.withValues(alpha: 0.25),
                onSelected: (_) {
                  ctrl.gradientKind = k;
                  ctrl.refresh();
                },
              ),
            );
          }),
          _sliderChip(
            label: 'Opacity',
            valueText: '${(ctrl.brushOpacity * 100).round()}%',
            value: ctrl.brushOpacity,
            min: 0.05,
            max: 1.0,
            onChanged: (v) {
              ctrl.brushOpacity = v;
              ctrl.refresh();
            },
          ),
        ];

      case ToolType.shape:
        return [
          ...ShapeKind.values.map((k) {
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                label: Text(
                  k.name[0].toUpperCase() + k.name.substring(1),
                  style: const TextStyle(fontSize: 10.5),
                ),
                selected: ctrl.shapeKind == k,
                visualDensity: VisualDensity.compact,
                selectedColor: FyrTheme.accentColor.withValues(alpha: 0.25),
                onSelected: (_) {
                  ctrl.shapeKind = k;
                  ctrl.refresh();
                },
              ),
            );
          }),
          const SizedBox(width: 8),
          FilterChip(
            label: const Text('Fill', style: TextStyle(fontSize: 10.5)),
            selected: ctrl.shapeFill,
            visualDensity: VisualDensity.compact,
            selectedColor: FyrTheme.accentColor.withValues(alpha: 0.25),
            onSelected: (v) {
              ctrl.shapeFill = v;
              ctrl.refresh();
            },
          ),
          const SizedBox(width: 4),
          FilterChip(
            label: const Text('Stroke', style: TextStyle(fontSize: 10.5)),
            selected: ctrl.shapeStroke,
            visualDensity: VisualDensity.compact,
            selectedColor: FyrTheme.accentColor.withValues(alpha: 0.25),
            onSelected: (v) {
              ctrl.shapeStroke = v;
              ctrl.refresh();
            },
          ),
          const SizedBox(width: 8),
          _sliderChip(
            label: 'Stroke',
            valueText: '${ctrl.shapeStrokeWidth.round()}px',
            value: ctrl.shapeStrokeWidth,
            min: 1,
            max: 40,
            onChanged: (v) {
              ctrl.shapeStrokeWidth = v;
              ctrl.refresh();
            },
          ),
        ];

      case ToolType.crop:
        final r = ctrl.activeCropRect;
        return [
          if (r != null)
            Text(
              'Crop: ${r.width.round()} × ${r.height.round()} px',
              style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
            ),
          const SizedBox(width: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: FyrTheme.accentColor,
              foregroundColor:
                  FyrTheme.getContrastingColor(FyrTheme.accentColor),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 26),
            ),
            onPressed: ctrl.applyCrop,
            child: const Text('Apply Crop', style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              minimumSize: const Size(0, 26),
            ),
            onPressed: () => ctrl.setTool(ToolType.move),
            child: const Text('Cancel', style: TextStyle(fontSize: 11)),
          ),
        ];

      case ToolType.text:
        return [
          Text(
            'Click anywhere on the canvas to place a Text Layer',
            style: TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
          ),
        ];

      case ToolType.move:
        return [
          Text(
            'Drag to move active layer • Arrow keys nudge 1px (Shift 10px)',
            style: TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
          ),
        ];

      case ToolType.eyedropper:
        return [
          Text(
            'Click on canvas to sample Foreground Color',
            style: TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
          ),
        ];

      case ToolType.pan:
        return [
          Text(
            'Drag to pan viewport • Hold Space in any tool to pan',
            style: TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
          ),
        ];

      case ToolType.zoom:
        return [
          Text(
            'Click to Zoom In • Alt+Click to Zoom Out • Scroll wheel zooms',
            style: TextStyle(fontSize: 11.5, color: FyrTheme.textColorMuted),
          ),
        ];
    }
  }

  Widget _symmetrySelector(EditorController ctrl) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: ctrl.symmetryMode == SymmetryMode.off
            ? FyrTheme.cardColor
            : FyrTheme.accentColor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: ctrl.symmetryMode == SymmetryMode.off
              ? FyrTheme.dividerColor
              : FyrTheme.accentColor.withValues(alpha: 0.6),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SymmetryMode>(
          value: ctrl.symmetryMode,
          isDense: true,
          dropdownColor: FyrTheme.surfaceColor,
          style: TextStyle(fontSize: 11, color: FyrTheme.textColor),
          items: SymmetryMode.values
              .map((m) => DropdownMenuItem(
                    value: m,
                    child: Text('Symmetry: ${m.label}'),
                  ))
              .toList(),
          onChanged: (m) {
            if (m != null) ctrl.setSymmetryMode(m);
          },
        ),
      ),
    );
  }

  Widget _sliderChip({
    required String label,
    required String valueText,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ',
            style: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted)),
        Text(valueText,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColor)),
        SizedBox(
          width: 96,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 2.5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              activeTrackColor: FyrTheme.accentColor,
              thumbColor: FyrTheme.accentColor,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
