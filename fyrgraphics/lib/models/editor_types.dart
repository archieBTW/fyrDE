import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

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
  cloneStamp,
  smudge,
  blurBrush,
  bucket,
  gradient,
  shape,
  text,
  pan,
  zoom,
}

enum SelectionMode { replace, add, subtract, intersect }

enum ShapeKind { rectangle, roundedRect, ellipse, line, arrow, polygon }

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
  })  : selection = selection ?? SelectionState(),
        history = history ?? [];

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
  CanvasPreset('Icon / Sprite', 512, 512, '1:1 Asset'),
  CanvasPreset('A4 (150 DPI)', 1240, 1754, 'Print Portrait'),
];
