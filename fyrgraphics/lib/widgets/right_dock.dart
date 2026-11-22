import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../engine/pro_pixel_ops.dart';
import '../fyr_theme.dart';
import '../models/editor_types.dart';
import '../state/editor_controller.dart';
import 'dialogs.dart';

class RightDock extends StatefulWidget {
  final VoidCallback onFitViewport;
  const RightDock({super.key, required this.onFitViewport});

  @override
  State<RightDock> createState() => _RightDockState();
}

class _RightDockState extends State<RightDock> {
  bool _editingFg = true;

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<EditorController>();
    if (!ctrl.showRightDock) return const SizedBox.shrink();

    final isAdv = ctrl.isAdvancedMode;
    final topTabs = isAdv
        ? const ['Color', 'Harmonies', 'Histogram', 'Navigator']
        : const ['Color'];
    final bottomTabs = isAdv
        ? const ['Layers', 'Brushes', 'History']
        : const ['Layers'];

    final safeTopTab = ctrl.topDockTab.clamp(0, topTabs.length - 1);
    final safeBottomTab = ctrl.bottomDockTab.clamp(0, bottomTabs.length - 1);

    Widget topContent() {
      if (!isAdv) return _buildColorPanel(ctrl);
      switch (safeTopTab) {
        case 1:
          return _buildHarmoniesPanel(ctrl);
        case 2:
          return _buildHistogramPanel(ctrl);
        case 3:
          return _buildNavigatorPanel(ctrl);
        default:
          return _buildColorPanel(ctrl);
      }
    }

    Widget bottomContent() {
      if (!isAdv) return _buildLayersPanel(context, ctrl);
      switch (safeBottomTab) {
        case 1:
          return _buildBrushesPanel(ctrl);
        case 2:
          return _buildHistoryPanel(ctrl);
        default:
          return _buildLayersPanel(context, ctrl);
      }
    }

    return Container(
      width: isAdv ? 296 : 264,
      decoration: BoxDecoration(
        color: FyrTheme.sidebarColor,
        border: Border(left: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        children: [
          _DockTabBar(
            tabs: topTabs,
            activeIndex: safeTopTab,
            onSelect: (i) {
              ctrl.topDockTab = i;
              ctrl.refresh();
            },
          ),
          SizedBox(
            height: 256,
            child: topContent(),
          ),
          Divider(height: 1, color: FyrTheme.dividerColor),
          _DockTabBar(
            tabs: bottomTabs,
            activeIndex: safeBottomTab,
            onSelect: (i) {
              ctrl.bottomDockTab = i;
              ctrl.refresh();
            },
          ),
          Expanded(
            child: bottomContent(),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Color Picker Panel
  // ---------------------------------------------------------------------------

  Widget _buildColorPanel(EditorController ctrl) {
    final activeColor =
        _editingFg ? ctrl.foregroundColor : ctrl.backgroundColor;
    final hsv = HSVColor.fromColor(activeColor);
    final hex =
        '#${activeColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

    void updateColor(Color c) {
      if (_editingFg) {
        ctrl.setForegroundColor(c);
      } else {
        ctrl.setBackgroundColor(c);
      }
    }

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          // FG / BG selector + Hex readout
          Row(
            children: [
              _colorChipButton(
                label: 'FG',
                color: ctrl.foregroundColor,
                selected: _editingFg,
                onTap: () => setState(() => _editingFg = true),
              ),
              const SizedBox(width: 6),
              _colorChipButton(
                label: 'BG',
                color: ctrl.backgroundColor,
                selected: !_editingFg,
                onTap: () => setState(() => _editingFg = false),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(5),
                onTap: () => _showHexEditDialog(context, hex, updateColor),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: FyrTheme.cardColor,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: FyrTheme.dividerColor),
                  ),
                  child: Text(
                    hex,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: FyrTheme.textColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // HSV Saturation/Value Square + Hue Bar
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      void pickSv(Offset local) {
                        final s = (local.dx / box.maxWidth).clamp(0.0, 1.0);
                        final v =
                            (1.0 - local.dy / box.maxHeight).clamp(0.0, 1.0);
                        updateColor(
                          HSVColor.fromAHSV(1.0, hsv.hue, s, v).toColor(),
                        );
                      }

                      return GestureDetector(
                        onPanDown: (d) => pickSv(d.localPosition),
                        onPanUpdate: (d) => pickSv(d.localPosition),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: CustomPaint(
                            size: Size(box.maxWidth, box.maxHeight),
                            painter: _SvSquarePainter(hsv: hsv),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 18,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      void pickHue(Offset local) {
                        final h =
                            ((local.dy / box.maxHeight) * 360.0).clamp(0.0, 359.9);
                        updateColor(
                          HSVColor.fromAHSV(1.0, h, hsv.saturation, hsv.value)
                              .toColor(),
                        );
                      }

                      return GestureDetector(
                        onPanDown: (d) => pickHue(d.localPosition),
                        onPanUpdate: (d) => pickHue(d.localPosition),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: CustomPaint(
                            size: Size(18, box.maxHeight),
                            painter: _HueBarPainter(hue: hsv.hue),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Recent Swatches
          SizedBox(
            height: 22,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: ctrl.recentColors.length,
              separatorBuilder: (_, _) => const SizedBox(width: 4),
              itemBuilder: (_, i) {
                final c = ctrl.recentColors[i];
                return GestureDetector(
                  onTap: () => updateColor(c),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: c,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: FyrTheme.dividerColor),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _colorChipButton({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? FyrTheme.accentColor.withValues(alpha: 0.16)
              : FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? FyrTheme.accentColor : FyrTheme.dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
                border: Border.all(color: Colors.white30),
              ),
            ),
            const SizedBox(width: 5),
            Text(label,
                style:
                    const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Future<void> _showHexEditDialog(
    BuildContext context,
    String currentHex,
    ValueChanged<Color> onPick,
  ) async {
    final tc = TextEditingController(text: currentHex);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter Hex Color', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: tc,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '#E040FB',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final cleaned = tc.text.trim().replaceAll('#', '');
              if (cleaned.length == 6) {
                final val = int.tryParse('FF$cleaned', radix: 16);
                if (val != null) onPick(Color(val));
              }
              Navigator.pop(ctx);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Color Harmonies & Curated Designer Palettes (Advanced)
  // ---------------------------------------------------------------------------

  Widget _buildHarmoniesPanel(EditorController ctrl) {
    final harmonies = ProPixelOps.generateColorHarmonies(ctrl.foregroundColor);
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        ...harmonies.entries.map((entry) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: entry.value.map((c) {
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => ctrl.setForegroundColor(c, recordRecent: true),
                        child: Container(
                          height: 22,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.16),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Live RGB + Luminance Histogram (Advanced)
  // ---------------------------------------------------------------------------

  Widget _buildHistogramPanel(EditorController ctrl) {
    final layer = ctrl.activeDoc?.activeLayer;
    if (layer == null) return const SizedBox.shrink();
    final hist = ProPixelOps.computeHistogram(layer.pixels);

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'RGB & Luminance',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: FyrTheme.textColor,
                ),
              ),
              Text(
                '${layer.width}×${layer.height}',
                style: TextStyle(fontSize: 10, color: FyrTheme.textColorMuted),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CustomPaint(
                size: Size.infinite,
                painter: _HistogramPainter(hist: hist),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Shadows',
                  style: TextStyle(fontSize: 10, color: FyrTheme.textColorMuted)),
              Text('Midtones',
                  style: TextStyle(fontSize: 10, color: FyrTheme.textColorMuted)),
              Text('Highlights',
                  style: TextStyle(fontSize: 10, color: FyrTheme.textColorMuted)),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Brush Studio Presets & Dynamics (Advanced)
  // ---------------------------------------------------------------------------

  Widget _buildBrushesPanel(EditorController ctrl) {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Text(
          'PRESETS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: FyrTheme.textColorMuted,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        ...kBrushPresets.map((preset) {
          final active = ctrl.activeBrushPreset == preset.kind;
          return Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => ctrl.applyBrushPreset(preset),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: active
                      ? FyrTheme.accentColor.withValues(alpha: 0.16)
                      : FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: active
                        ? FyrTheme.accentColor
                        : FyrTheme.dividerColor,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      preset.icon,
                      size: 18,
                      color: active
                          ? FyrTheme.accentColor
                          : FyrTheme.textColorMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            preset.name,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: FyrTheme.textColor,
                            ),
                          ),
                          Text(
                            preset.subtitle,
                            style: TextStyle(
                              fontSize: 10,
                              color: FyrTheme.textColorMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${preset.size.round()}px',
                      style: TextStyle(
                          fontSize: 10, color: FyrTheme.textColorMuted),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Divider(height: 1, color: FyrTheme.dividerColor),
        const SizedBox(height: 8),
        Text(
          'NIB & DYNAMICS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: FyrTheme.textColorMuted,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 6),
        _miniSlider(
          'Spacing',
          '${(ctrl.brushSpacing * 100).round()}%',
          ctrl.brushSpacing,
          0.08,
          1.0,
          (v) {
            ctrl.brushSpacing = v;
            ctrl.refresh();
          },
        ),
        _miniSlider(
          'Scatter',
          '${(ctrl.brushScatter * 100).round()}%',
          ctrl.brushScatter,
          0.0,
          1.5,
          (v) {
            ctrl.brushScatter = v;
            ctrl.refresh();
          },
        ),
        _miniSlider(
          'Roundness',
          '${(ctrl.brushRoundness * 100).round()}%',
          ctrl.brushRoundness,
          0.15,
          1.0,
          (v) {
            ctrl.brushRoundness = v;
            ctrl.refresh();
          },
        ),
        _miniSlider(
          'Angle',
          '${ctrl.brushAngleDeg.round()}°',
          ctrl.brushAngleDeg,
          -90,
          90,
          (v) {
            ctrl.brushAngleDeg = v;
            ctrl.refresh();
          },
        ),
      ],
    );
  }

  Widget _miniSlider(
    String label,
    String valText,
    double val,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(fontSize: 11, color: FyrTheme.textColor)),
            Text(valText,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: FyrTheme.accentColor)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 9),
            activeTrackColor: FyrTheme.accentColor,
            thumbColor: FyrTheme.accentColor,
          ),
          child: Slider(
            value: val.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Navigator Panel
  // ---------------------------------------------------------------------------

  Widget _buildNavigatorPanel(EditorController ctrl) {
    final doc = ctrl.activeDoc;
    if (doc == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF141417),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: CustomPaint(
                painter: _NavigatorMinimapPainter(doc: doc),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${(doc.zoom * 100).round()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: FyrTheme.textColor,
                ),
              ),
              Expanded(
                child: Slider(
                  value: doc.zoom.clamp(0.1, 8.0),
                  min: 0.1,
                  max: 8.0,
                  activeColor: FyrTheme.accentColor,
                  onChanged: (v) => ctrl.setZoom(v),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 26)),
                onPressed: widget.onFitViewport,
                child: const Text('Fit', style: TextStyle(fontSize: 11)),
              ),
              TextButton(
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: const Size(0, 26)),
                onPressed: ctrl.resetZoom100,
                child: const Text('100%', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Layers Panel
  // ---------------------------------------------------------------------------

  Widget _buildLayersPanel(BuildContext context, EditorController ctrl) {
    final doc = ctrl.activeDoc;
    if (doc == null) return const SizedBox.shrink();
    final active = doc.activeLayer;

    return Column(
      children: [
        // Blend Mode & Opacity Row
        if (active != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
            child: Column(
              children: [
                Row(
                  children: [
                    if (ctrl.isAdvancedMode)
                      Expanded(
                        flex: 5,
                        child: Container(
                          height: 28,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: FyrTheme.cardColor,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: FyrTheme.dividerColor),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<LayerBlendMode>(
                              value: active.blendMode,
                              isExpanded: true,
                              isDense: true,
                              style: TextStyle(
                                  fontSize: 11.5, color: FyrTheme.textColor),
                              dropdownColor: FyrTheme.isDark
                                  ? const Color(0xFF1A1A1E)
                                  : Colors.white,
                              items: LayerBlendMode.values
                                  .map((m) => DropdownMenuItem(
                                        value: m,
                                        child: Text(m.label,
                                            overflow: TextOverflow.ellipsis),
                                      ))
                                  .toList(),
                              onChanged: (m) {
                                if (m != null) {
                                  ctrl.setLayerBlendMode(
                                      doc.activeLayerIndex, m);
                                }
                              },
                            ),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: Text(
                          'Layer Opacity',
                          style: TextStyle(
                              fontSize: 11, color: FyrTheme.textColorMuted),
                        ),
                      ),
                    const SizedBox(width: 8),
                    Text(
                      '${(active.opacity * 100).round()}%',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: FyrTheme.textColor),
                    ),
                  ],
                ),
                if (ctrl.isAdvancedMode) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _layerToggleChip(
                        icon: Icons.grid_4x4_rounded,
                        label: 'Alpha Lock',
                        active: active.alphaLock,
                        onTap: () =>
                            ctrl.toggleLayerAlphaLock(doc.activeLayerIndex),
                      ),
                      const SizedBox(width: 6),
                      _layerToggleChip(
                        icon: Icons.subdirectory_arrow_right_rounded,
                        label: 'Clip Mask',
                        active: active.clippingMask,
                        onTap: () =>
                            ctrl.toggleLayerClippingMask(doc.activeLayerIndex),
                      ),
                    ],
                  ),
                ],
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 2.5,
                    thumbShape:
                        const RoundSliderThumbShape(enabledThumbRadius: 5.5),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 10),
                    activeTrackColor: FyrTheme.accentColor,
                    thumbColor: FyrTheme.accentColor,
                  ),
                  child: Slider(
                    value: active.opacity,
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) =>
                        ctrl.setLayerOpacity(doc.activeLayerIndex, v),
                    onChangeEnd: (v) => ctrl.setLayerOpacity(
                      doc.activeLayerIndex,
                      v,
                      commitHistory: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Divider(height: 1, color: FyrTheme.dividerColor),
        // Layers List (top-most layer rendered at top)
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            itemCount: doc.layers.length,
            itemBuilder: (ctx, visIdx) {
              final layerIdx = doc.layers.length - 1 - visIdx;
              final layer = doc.layers[layerIdx];
              final isSelected = layerIdx == doc.activeLayerIndex;

              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => ctrl.selectLayer(layerIdx),
                  onDoubleTap: () {
                    if (layer.isTextLayer) {
                      FyrDialogs.showTextLayerDialog(
                        context,
                        ctrl,
                        existing: layer.textData,
                        replaceIndex: layerIdx,
                      );
                    } else {
                      _showRenameDialog(context, ctrl, layerIdx, layer.name);
                    }
                  },
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? FyrTheme.accentColor.withValues(alpha: 0.16)
                          : FyrTheme.cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? FyrTheme.accentColor.withValues(alpha: 0.7)
                            : FyrTheme.dividerColor,
                      ),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            layer.visible
                                ? Icons.visibility_rounded
                                : Icons.visibility_off_rounded,
                            size: 15,
                            color: layer.visible
                                ? FyrTheme.textColor
                                : FyrTheme.textColorMuted.withValues(alpha: 0.4),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 26, minHeight: 26),
                          onPressed: () => ctrl.toggleLayerVisibility(layerIdx),
                        ),
                        // Layer Thumbnail
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFF232328),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: FyrTheme.dividerColor),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: layer.cachedImage != null
                              ? RawImage(
                                  image: layer.cachedImage,
                                  fit: BoxFit.contain,
                                )
                              : const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (layer.clippingMask)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 3),
                                      child: Icon(
                                          Icons.subdirectory_arrow_right_rounded,
                                          size: 12,
                                          color: FyrTheme.accentColor),
                                    ),
                                  if (layer.isTextLayer)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Icon(Icons.title_rounded,
                                          size: 12,
                                          color: FyrTheme.accentColor),
                                    ),
                                  if (layer.alphaLock)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4),
                                      child: Icon(Icons.grid_4x4_rounded,
                                          size: 11,
                                          color: Colors.amberAccent),
                                    ),
                                  Expanded(
                                    child: Text(
                                      layer.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.normal,
                                        color: FyrTheme.textColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '${layer.blendMode.label} • ${(layer.opacity * 100).round()}%',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  color: FyrTheme.textColorMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            layer.locked
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            size: 13,
                            color: layer.locked
                                ? FyrTheme.accentColor
                                : FyrTheme.textColorMuted.withValues(alpha: 0.45),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 24, minHeight: 24),
                          onPressed: () => ctrl.toggleLayerLock(layerIdx),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        // Layer Actions Footer
        Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _layerIconBtn(Icons.add_rounded, 'New Layer',
                  () => ctrl.addNewLayer()),
              _layerIconBtn(Icons.title_rounded, 'New Text Layer',
                  () => FyrDialogs.showTextLayerDialog(context, ctrl)),
              _layerIconBtn(Icons.copy_rounded, 'Duplicate Layer',
                  ctrl.duplicateActiveLayer),
              _layerIconBtn(
                  Icons.arrow_upward_rounded, 'Move Up', ctrl.moveLayerUp),
              _layerIconBtn(
                  Icons.arrow_downward_rounded, 'Move Down', ctrl.moveLayerDown),
              _layerIconBtn(
                  Icons.merge_type_rounded, 'Merge Down', ctrl.mergeDown),
              _layerIconBtn(Icons.delete_outline_rounded, 'Delete Layer',
                  ctrl.deleteActiveLayer),
            ],
          ),
        ),
      ],
    );
  }

  Widget _layerToggleChip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: active
                ? FyrTheme.accentColor.withValues(alpha: 0.2)
                : FyrTheme.cardColor,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? FyrTheme.accentColor : FyrTheme.dividerColor,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 12,
                  color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _layerIconBtn(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 16, color: FyrTheme.textColorMuted),
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    EditorController ctrl,
    int layerIdx,
    String currentName,
  ) async {
    final tc = TextEditingController(text: currentName);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Layer', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: tc,
          autofocus: true,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              ctrl.renameLayer(layerIdx, tc.text);
              Navigator.pop(ctx);
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // History Panel
  // ---------------------------------------------------------------------------

  Widget _buildHistoryPanel(EditorController ctrl) {
    final doc = ctrl.activeDoc;
    if (doc == null) return const SizedBox.shrink();

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: doc.history.length,
      itemBuilder: (_, i) {
        final entry = doc.history[i];
        final isCurrent = i == doc.historyIndex;
        final isFuture = i > doc.historyIndex;
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => ctrl.jumpToHistory(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            margin: const EdgeInsets.only(bottom: 3),
            decoration: BoxDecoration(
              color: isCurrent
                  ? FyrTheme.accentColor.withValues(alpha: 0.18)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: isCurrent
                  ? Border.all(
                      color: FyrTheme.accentColor.withValues(alpha: 0.6))
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  isCurrent
                      ? Icons.radio_button_checked_rounded
                      : Icons.history_rounded,
                  size: 13,
                  color: isCurrent
                      ? FyrTheme.accentColor
                      : FyrTheme.textColorMuted
                          .withValues(alpha: isFuture ? 0.35 : 0.8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.label,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight:
                          isCurrent ? FontWeight.w600 : FontWeight.normal,
                      color: isFuture
                          ? FyrTheme.textColorMuted.withValues(alpha: 0.45)
                          : FyrTheme.textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HistogramPainter extends CustomPainter {
  final HistogramData hist;
  _HistogramPainter({required this.hist});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF141418),
    );

    void drawChannel(List<int> bins, Color color) {
      final path = Path()..moveTo(0, size.height);
      final denom = max(1, hist.maxCount).toDouble();
      for (int i = 0; i < 256; i++) {
        final x = (i / 255.0) * size.width;
        final h = (bins[i] / denom).clamp(0.0, 1.0) * (size.height - 6);
        path.lineTo(x, size.height - h);
      }
      path.lineTo(size.width, size.height);
      path.close();
      canvas.drawPath(path, Paint()..color = color);
    }

    drawChannel(hist.luma, Colors.white.withValues(alpha: 0.2));
    drawChannel(hist.r, Colors.redAccent.withValues(alpha: 0.35));
    drawChannel(hist.g, Colors.greenAccent.withValues(alpha: 0.32));
    drawChannel(hist.b, Colors.lightBlueAccent.withValues(alpha: 0.35));
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter old) => true;
}

class _DockTabBar extends StatelessWidget {
  final List<String> tabs;
  final int activeIndex;
  final ValueChanged<int> onSelect;

  const _DockTabBar({
    required this.tabs,
    required this.activeIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: FyrTheme.contentColor,
        border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final active = i == activeIndex;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: active ? FyrTheme.accentColor : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
              child: Text(
                tabs[i],
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                  color: active ? FyrTheme.textColor : FyrTheme.textColorMuted,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _SvSquarePainter extends CustomPainter {
  final HSVColor hsv;
  _SvSquarePainter({required this.hsv});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final pureHue = HSVColor.fromAHSV(1.0, hsv.hue, 1.0, 1.0).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, pureHue],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );

    final cx = hsv.saturation * size.width;
    final cy = (1.0 - hsv.value) * size.height;
    canvas.drawCircle(
      Offset(cx, cy),
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      Offset(cx, cy),
      7,
      Paint()
        ..color = Colors.black45
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _SvSquarePainter old) => old.hsv != hsv;
}

class _HueBarPainter extends CustomPainter {
  final double hue;
  _HueBarPainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(rect),
    );
    final y = (hue / 360.0) * size.height;
    canvas.drawRect(
      Rect.fromLTWH(0, y - 2, size.width, 4),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _HueBarPainter old) => old.hue != hue;
}

class _NavigatorMinimapPainter extends CustomPainter {
  final GraphicsDocument doc;
  _NavigatorMinimapPainter({required this.doc});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = min(size.width / doc.width, size.height / doc.height) * 0.9;
    final dw = doc.width * scale;
    final dh = doc.height * scale;
    final ox = (size.width - dw) / 2;
    final oy = (size.height - dh) / 2;

    canvas.save();
    canvas.translate(ox, oy);
    canvas.scale(scale);
    final rect = Rect.fromLTWH(0, 0, doc.width.toDouble(), doc.height.toDouble());
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = const Color(0xFF24242A));

    for (final l in doc.layers) {
      if (!l.visible || l.cachedImage == null) continue;
      canvas.drawImage(
        l.cachedImage!,
        Offset(l.offsetX, l.offsetY),
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, l.opacity)
          ..blendMode = l.blendMode.uiBlendMode,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NavigatorMinimapPainter old) => true;
}
