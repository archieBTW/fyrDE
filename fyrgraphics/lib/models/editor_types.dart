import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

enum WorkspaceMode { simple, advanced }

enum SymmetryMode {
  off('Off', Icons.block_rounded),
  vertical('Mirror V', Icons.flip_rounded),
  horizontal('Mirror H', Icons.flip_camera_android_rounded),
  quadrant('4-Way', Icons.grid_view_rounded),
  radial6('6x Radial', Icons.filter_vintage_rounded),
  radial8('8x Mandala', Icons.brightness_7_rounded);

  final String label;
  final IconData icon;
  const SymmetryMode(this.label, this.icon);
}

enum CompositionGuide {
  none('None'),
  ruleOfThirds('Rule of Thirds'),
  goldenRatio('Golden Ratio'),
  centerCrosshair('Center Crosshair');

  final String label;
  const CompositionGuide(this.label);
}

enum BrushPresetKind {
  softRound,
  hardRound,
  airbrush,
  inkPen,
  charcoal,
  watercolor,
  calligraphy,
  splatter,
}

class BrushPreset {
  final BrushPresetKind kind;
  final String name;
  final String subtitle;
  final IconData icon;
  final double size;
  final double hardness;
  final double opacity;
  final double spacing;
  final double scatter;
  final double roundness;
  final double angleDeg;

  const BrushPreset({
    required this.kind,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.size,
    required this.hardness,
    required this.opacity,
    required this.spacing,
    required this.scatter,
    required this.roundness,
    required this.angleDeg,
  });
}

const List<BrushPreset> kBrushPresets = [
  BrushPreset(
    kind: BrushPresetKind.softRound,
    name: 'Soft Round',
    subtitle: 'Smooth shading & blending',
    icon: Icons.blur_circular_rounded,
    size: 32,
    hardness: 0.25,
    opacity: 0.85,
    spacing: 0.18,
    scatter: 0.0,
    roundness: 1.0,
    angleDeg: 0,
  ),
  BrushPreset(
    kind: BrushPresetKind.hardRound,
    name: 'Hard Round',
    subtitle: 'Crisp painting & masking',
    icon: Icons.circle,
    size: 24,
    hardness: 0.92,
    opacity: 1.0,
    spacing: 0.16,
    scatter: 0.0,
    roundness: 1.0,
    angleDeg: 0,
  ),
  BrushPreset(
    kind: BrushPresetKind.airbrush,
    name: 'Airbrush',
    subtitle: 'Ultra-soft feathered buildup',
    icon: Icons.grain_rounded,
    size: 64,
    hardness: 0.05,
    opacity: 0.28,
    spacing: 0.14,
    scatter: 0.08,
    roundness: 1.0,
    angleDeg: 0,
  ),
  BrushPreset(
    kind: BrushPresetKind.inkPen,
    name: 'Studio Ink',
    subtitle: 'Clean opaque linework',
    icon: Icons.draw_rounded,
    size: 8,
    hardness: 0.98,
    opacity: 1.0,
    spacing: 0.12,
    scatter: 0.0,
    roundness: 1.0,
    angleDeg: 0,
  ),
  BrushPreset(
    kind: BrushPresetKind.charcoal,
    name: 'Charcoal',
    subtitle: 'Textured dry grain stroke',
    icon: Icons.texture_rounded,
    size: 28,
    hardness: 0.65,
    opacity: 0.55,
    spacing: 0.22,
    scatter: 0.42,
    roundness: 0.65,
    angleDeg: 35,
  ),
  BrushPreset(
    kind: BrushPresetKind.watercolor,
    name: 'Watercolor',
    subtitle: 'Translucent layered wash',
    icon: Icons.water_drop_outlined,
    size: 46,
    hardness: 0.35,
    opacity: 0.32,
    spacing: 0.20,
    scatter: 0.14,
    roundness: 0.85,
    angleDeg: 15,
  ),
  BrushPreset(
    kind: BrushPresetKind.calligraphy,
    name: 'Calligraphy',
    subtitle: 'Angled chisel nib',
    icon: Icons.create_rounded,
    size: 26,
    hardness: 0.96,
    opacity: 1.0,
    spacing: 0.10,
    scatter: 0.0,
    roundness: 0.28,
    angleDeg: -38,
  ),
  BrushPreset(
    kind: BrushPresetKind.splatter,
    name: 'Spray Splatter',
    subtitle: 'Organic speckled scatter',
    icon: Icons.scatter_plot_rounded,
    size: 16,
    hardness: 0.85,
    opacity: 0.78,
    spacing: 0.55,
    scatter: 1.35,
    roundness: 0.8,
    angleDeg: 0,
  ),
];

enum ToolType {
  move,
  rectSelect,
  ellipseSelect,
  lassoSelect,
  magicWand,
  crop,
  eyedropper,
  brush,
  pencil,
  eraser,
  dodge,
  burn,
  sponge,
  healingBrush,
  cloneStamp,
  smudge,
  blurBrush,
  sharpenBrush,
  bucket,
  gradient,
  shape,
  text,
  pan,
  zoom,
}

const Set<ToolType> kSimpleModeTools = {
  ToolType.move,
  ToolType.crop,
  ToolType.brush,
  ToolType.eraser,
  ToolType.bucket,
  ToolType.shape,
  ToolType.text,
  ToolType.eyedropper,
  ToolType.zoom,
};

enum SelectionMode { replace, add, subtract, intersect }

enum ShapeKind { rectangle, roundedRect, ellipse, line, arrow, polygon, star }

enum GradientKind { linear, radial, fgToTransparent }

enum LayerBlendMode {
  normal('Normal', ui.BlendMode.srcOver),
  multiply('Multiply', ui.BlendMode.multiply),
  screen('Screen', ui.BlendMode.screen),
  overlay('Overlay', ui.BlendMode.overlay),
  darken('Darken', ui.BlendMode.darken),
  lighten('Lighten', ui.BlendMode.lighten),
  colorDodge('Color Dodge', ui.BlendMode.colorDodge),
  colorBurn('Color Burn', ui.BlendMode.colorBurn),
  hardLight('Hard Light', ui.BlendMode.hardLight),
  softLight('Soft Light', ui.BlendMode.softLight),
  difference('Difference', ui.BlendMode.difference),
  exclusion('Exclusion', ui.BlendMode.exclusion),
  hue('Hue', ui.BlendMode.hue),
  saturation('Saturation', ui.BlendMode.saturation),
  color('Color', ui.BlendMode.color),
  luminosity('Luminosity', ui.BlendMode.luminosity);

  final String label;
  final ui.BlendMode uiBlendMode;
  const LayerBlendMode(this.label, this.uiBlendMode);
}

class TextLayerData {
  String text;
  String fontFamily;
  double fontSize;
  bool bold;
  bool italic;
  Color color;
  TextAlign align;

  TextLayerData({
    required this.text,
    this.fontFamily = 'Inter',
    this.fontSize = 48.0,
    this.bold = false,
    this.italic = false,
    this.color = Colors.white,
    this.align = TextAlign.left,
  });

  TextLayerData clone() => TextLayerData(
        text: text,
        fontFamily: fontFamily,
        fontSize: fontSize,
        bold: bold,
        italic: italic,
        color: color,
        align: align,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'bold': bold,
        'italic': italic,
        'color': color.toARGB32(),
        'align': align.index,
      };

  factory TextLayerData.fromJson(Map<String, dynamic> json) => TextLayerData(
        text: json['text'] as String? ?? 'Text',
        fontFamily: json['fontFamily'] as String? ?? 'Inter',
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 48.0,
        bold: json['bold'] as bool? ?? false,
        italic: json['italic'] as bool? ?? false,
        color: Color(json['color'] as int? ?? 0xFFFFFFFF),
        align: TextAlign.values[(json['align'] as int? ?? 0)
            .clamp(0, TextAlign.values.length - 1)],
      );
}

class RasterLayer {
  final String id;
  String name;
  bool visible;
  bool locked;
  bool alphaLock;
  bool clippingMask;
  double opacity;
  LayerBlendMode blendMode;
  double offsetX;
  double offsetY;
  int width;
  int height;
  Uint8List pixels;
  ui.Image? cachedImage;
  TextLayerData? textData;

  RasterLayer({
    required this.id,
    required this.name,
    this.visible = true,
    this.locked = false,
    this.alphaLock = false,
    this.clippingMask = false,
    this.opacity = 1.0,
    this.blendMode = LayerBlendMode.normal,
    this.offsetX = 0.0,
    this.offsetY = 0.0,
    required this.width,
    required this.height,
    required this.pixels,
    this.cachedImage,
    this.textData,
  });

  bool get isTextLayer => textData != null;

  RasterLayer clone({bool copyImageRef = true}) => RasterLayer(
        id: id,
        name: name,
        visible: visible,
        locked: locked,
        alphaLock: alphaLock,
        clippingMask: clippingMask,
        opacity: opacity,
        blendMode: blendMode,
        offsetX: offsetX,
        offsetY: offsetY,
        width: width,
        height: height,
        pixels: Uint8List.fromList(pixels),
        cachedImage: copyImageRef ? cachedImage : null,
        textData: textData?.clone(),
      );
}

class SelectionState {
  Uint8List? mask;
  ui.Path? outlinePath;
  Rect? bounds;

  SelectionState({this.mask, this.outlinePath, this.bounds});

  bool get hasSelection => mask != null && bounds != null && !bounds!.isEmpty;

  void clear() {
    mask = null;
    outlinePath = null;
    bounds = null;
  }

  SelectionState clone() => SelectionState(
        mask: mask != null ? Uint8List.fromList(mask!) : null,
        outlinePath: outlinePath != null ? ui.Path.from(outlinePath!) : null,
        bounds: bounds,
      );
}

class HistoryEntry {
  final String label;
  final int width;
  final int height;
  final List<RasterLayer> layers;
  final int activeLayerIndex;
  final Uint8List? selectionMask;
  final Rect? selectionBounds;

  HistoryEntry({
    required this.label,
    required this.width,
    required this.height,
    required this.layers,
    required this.activeLayerIndex,
    this.selectionMask,
    this.selectionBounds,
  });
}

class GraphicsDocument {
  final String id;
  String title;
  String? filePath;
  int width;
  int height;
  List<RasterLayer> layers;
  int activeLayerIndex;
  SelectionState selection;
  List<HistoryEntry> history;
  int historyIndex;
  bool dirty;
  double zoom;
  Offset panOffset;
  bool showGrid;
  bool showRulers;
  CompositionGuide compositionGuide;
  List<double> hGuides;
  List<double> vGuides;

  GraphicsDocument({
    required this.id,
    required this.title,
    this.filePath,
    required this.width,
    required this.height,
    required this.layers,
    this.activeLayerIndex = 0,
    SelectionState? selection,
    List<HistoryEntry>? history,
    this.historyIndex = 0,
    this.dirty = false,
    this.zoom = 1.0,
    this.panOffset = Offset.zero,
    this.showGrid = false,
    this.showRulers = true,
    this.compositionGuide = CompositionGuide.none,
    List<double>? hGuides,
    List<double>? vGuides,
  })  : selection = selection ?? SelectionState(),
        history = history ?? [],
        hGuides = hGuides ?? [],
        vGuides = vGuides ?? [];

  RasterLayer? get activeLayer {
    if (layers.isEmpty) return null;
    final idx = activeLayerIndex.clamp(0, layers.length - 1);
    return layers[idx];
  }
}

class CanvasPreset {
  final String name;
  final int width;
  final int height;
  final String subtitle;

  const CanvasPreset(this.name, this.width, this.height, this.subtitle);
}

const List<CanvasPreset> kCanvasPresets = [
  CanvasPreset('Full HD (1080p)', 1920, 1080, '16:9 Screen'),
  CanvasPreset('HD (720p)', 1280, 720, '16:9 Compact'),
  CanvasPreset('4K UHD', 3840, 2160, '16:9 Ultra HD'),
  CanvasPreset('Square Post', 1080, 1080, '1:1 Social'),
  CanvasPreset('Portrait', 1080, 1350, '4:5 Vertical'),
  CanvasPreset('Story / Reel', 1080, 1920, '9:16 Vertical'),
  CanvasPreset('Icon / Sprite', 512, 512, '1:1 Asset'),
  CanvasPreset('A4 (150 DPI)', 1240, 1754, 'Print Portrait'),
];
