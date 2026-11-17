import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../engine/pixel_ops.dart';
import '../engine/project_io.dart';
import '../models/editor_types.dart';

class EditorController extends ChangeNotifier {
  static const int maxHistoryEntries = 35;

  final List<GraphicsDocument> documents = [];
  int activeDocIndex = 0;

  // Active Tool & Parameters
  ToolType activeTool = ToolType.brush;
  SelectionMode selectionMode = SelectionMode.replace;

  double brushSize = 24.0;
  double brushHardness = 0.75; // 0.0 (soft) .. 1.0 (hard)
  double brushOpacity = 1.0;

  double eraserSize = 32.0;
  double eraserHardness = 0.8;
  double eraserOpacity = 1.0;

  int wandTolerance = 32;
  bool wandContiguous = true;
  int bucketTolerance = 32;

  ShapeKind shapeKind = ShapeKind.rectangle;
  double shapeStrokeWidth = 4.0;
  bool shapeFill = true;
  bool shapeStroke = true;
  double shapeCornerRadius = 12.0;
  int shapePolygonSides = 5;

  GradientKind gradientKind = GradientKind.linear;

  String textFontFamily = 'Inter';
  double textFontSize = 54.0;
  bool textBold = false;
  bool textItalic = false;
  TextAlign textAlign = TextAlign.left;

  // Colors
  Color foregroundColor = const Color(0xFFE040FB);
  Color backgroundColor = const Color(0xFF000000);
  final List<Color> recentColors = [
    const Color(0xFFE040FB),
    const Color(0xFFFFFFFF),
    const Color(0xFF000000),
    const Color(0xFFFF5252),
    const Color(0xFF40C4FF),
    const Color(0xFF69F0AE),
    const Color(0xFFFFD740),
    const Color(0xFFFF6E40),
  ];

  // Interactive Tool Overlays (transient, not persisted)
  Offset? hoverCanvasPos;
  Color? hoverSampledColor;
  Offset? dragStartCanvas;
  Offset? dragCurrentCanvas;
  List<Offset> lassoPoints = [];
  Rect? activeCropRect;
  Offset? cloneSourceAnchor;
  Offset? _cloneStrokeStartDst;

  // Clipboard (straight RGBA pixels)
  Uint8List? _clipboardPixels;
  int _clipboardW = 0;
  int _clipboardH = 0;

  // Non-destructive filter/adjustment preview backup
  Uint8List? _previewOriginalPixels;
  int? _previewLayerIndex;

  // Async layer image upload throttling
  final Set<String> _uploadingLayerIds = {};
  final Set<String> _dirtyUploadLayerIds = {};

  // Right dock panel visibility
  bool showRightDock = true;
  int topDockTab = 0; // 0=Color, 1=Navigator
  int bottomDockTab = 0; // 0=Layers, 1=History

  // Status feedback
  String? statusMessage;
  Timer? _statusTimer;

  GraphicsDocument? get activeDoc {
    if (documents.isEmpty) return null;
    return documents[activeDocIndex.clamp(0, documents.length - 1)];
  }

  Future<void> initialize({String? initialFile}) async {
    if (initialFile != null && initialFile.isNotEmpty) {
      try {
        await openFileFromPath(initialFile);
        return;
      } catch (e) {
        setStatus('Failed to open $initialFile: $e');
      }
    }
    await createNewDocument(
      title: 'Untitled-1',
      width: 1280,
      height: 720,
      backgroundColor: Colors.transparent,
    );
  }

  void setStatus(String msg) {
    statusMessage = msg;
    _statusTimer?.cancel();
    _statusTimer = Timer(const Duration(seconds: 3), () {
      statusMessage = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void setTool(ToolType tool) {
    if (activeTool == tool) return;
    if (activeTool == ToolType.crop && tool != ToolType.crop) {
      activeCropRect = null;
    }
    activeTool = tool;
    if (tool == ToolType.crop && activeDoc != null) {
      activeCropRect = Rect.fromLTWH(
        0,
        0,
        activeDoc!.width.toDouble(),
        activeDoc!.height.toDouble(),
      );
    }
    notifyListeners();
  }

  void setForegroundColor(Color c, {bool recordRecent = false}) {
    foregroundColor = c;
    if (recordRecent) {
      _pushRecentColor(c);
    }
    notifyListeners();
  }

  void setBackgroundColor(Color c) {
    backgroundColor = c;
    notifyListeners();
  }

  void swapColors() {
    final tmp = foregroundColor;
    foregroundColor = backgroundColor;
    backgroundColor = tmp;
    notifyListeners();
  }

  void resetColors() {
    foregroundColor = Colors.black;
    backgroundColor = Colors.white;
    notifyListeners();
  }

  void _pushRecentColor(Color c) {
    recentColors.removeWhere((e) => e.toARGB32() == c.toARGB32());
    recentColors.insert(0, c);
    if (recentColors.length > 16) {
      recentColors.removeLast();
    }
  }

  void setHoverPosition(Offset? canvasPos) {
    hoverCanvasPos = canvasPos;
    final doc = activeDoc;
    if (doc != null && canvasPos != null) {
      final x = canvasPos.dx.floor();
      final y = canvasPos.dy.floor();
      final layer = doc.activeLayer;
      if (layer != null) {
        final lx = (x - layer.offsetX).round();
        final ly = (y - layer.offsetY).round();
        hoverSampledColor =
            PixelOps.samplePixel(layer.pixels, layer.width, layer.height, lx, ly);
      } else {
        hoverSampledColor = null;
      }
    } else {
      hoverSampledColor = null;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Document Lifecycle
  // ---------------------------------------------------------------------------

  Future<void> createNewDocument({
    required String title,
    required int width,
    required int height,
    Color backgroundColor = Colors.transparent,
  }) async {
    final w = width.clamp(1, 8192);
    final h = height.clamp(1, 8192);
    final pixels = backgroundColor.a == 0
        ? PixelOps.createBlankRgba(w, h)
        : PixelOps.createFilledRgba(w, h, backgroundColor);
    final uiImg = await PixelOps.decodeStraightRgbaToUiImage(pixels, w, h);

    final layer = RasterLayer(
      id: _newId(),
      name: backgroundColor.a == 0 ? 'Layer 1' : 'Background',
      width: w,
      height: h,
      pixels: pixels,
      cachedImage: uiImg,
    );

    final doc = GraphicsDocument(
      id: _newId(),
      title: title,
      width: w,
      height: h,
      layers: [layer],
      activeLayerIndex: 0,
    );
    _recordHistoryEntry(doc, 'New Document');
    documents.add(doc);
    activeDocIndex = documents.length - 1;
    if (activeTool == ToolType.crop) {
      activeCropRect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    }
    notifyListeners();
  }

  Future<void> openFileFromPath(String filePath) async {
    final ext = p.extension(filePath).toLowerCase();
    GraphicsDocument doc;
    if (ext == '.fyrg') {
      doc = await ProjectIO.loadFyrgProject(filePath);
    } else {
      final decoded = await ProjectIO.loadImageFile(filePath);
      final uiImg = await PixelOps.decodeStraightRgbaToUiImage(
        decoded.rgba,
        decoded.width,
        decoded.height,
      );
      final layer = RasterLayer(
        id: _newId(),
        name: 'Background',
        width: decoded.width,
        height: decoded.height,
        pixels: decoded.rgba,
        cachedImage: uiImg,
      );
      doc = GraphicsDocument(
        id: _newId(),
        title: p.basename(filePath),
        filePath: filePath,
        width: decoded.width,
        height: decoded.height,
        layers: [layer],
        activeLayerIndex: 0,
      );
    }
    _recordHistoryEntry(doc, 'Open ${p.basename(filePath)}');
    documents.add(doc);
    activeDocIndex = documents.length - 1;
    setStatus('Opened ${p.basename(filePath)} (${doc.width}×${doc.height})');
  }

  void switchDocument(int index) {
    if (index < 0 || index >= documents.length) return;
    activeDocIndex = index;
    activeCropRect = activeTool == ToolType.crop && activeDoc != null
        ? Rect.fromLTWH(
            0, 0, activeDoc!.width.toDouble(), activeDoc!.height.toDouble())
        : null;
    notifyListeners();
  }

  void closeDocument(int index) {
    if (index < 0 || index >= documents.length) return;
    documents.removeAt(index);
    if (activeDocIndex >= documents.length) {
      activeDocIndex = max(0, documents.length - 1);
    }
    notifyListeners();
  }

  Future<void> saveProjectToPath(String path) async {
    final doc = activeDoc;
    if (doc == null) return;
    final outPath =
        path.toLowerCase().endsWith('.fyrg') ? path : '$path.fyrg';
    await ProjectIO.saveFyrgProject(doc, outPath);
    doc.filePath = outPath;
    doc.title = p.basename(outPath);
    doc.dirty = false;
    setStatus('Saved project ${doc.title}');
  }

  Future<void> exportDocumentToPath({
    required String path,
    required String format,
    int jpgQuality = 92,
    double scale = 1.0,
  }) async {
    final doc = activeDoc;
    if (doc == null) return;
    await ProjectIO.exportImageFile(
      doc: doc,
      outputPath: path,
      format: format,
      jpgQuality: jpgQuality,
      scale: scale,
    );
    doc.dirty = false;
    setStatus('Exported ${p.basename(path)}');
  }

  // ---------------------------------------------------------------------------
  // Zoom & View
  // ---------------------------------------------------------------------------

  void setZoom(double z, {Offset? focalPan}) {
    final doc = activeDoc;
    if (doc == null) return;
    doc.zoom = z.clamp(0.05, 32.0);
    if (focalPan != null) doc.panOffset = focalPan;
    notifyListeners();
  }

  void zoomBy(double factor) {
    final doc = activeDoc;
    if (doc == null) return;
    doc.zoom = (doc.zoom * factor).clamp(0.05, 32.0);
    notifyListeners();
  }

  void fitToViewport(Size viewportSize) {
    final doc = activeDoc;
    if (doc == null || viewportSize.isEmpty) return;
    final pad = 64.0;
    final availW = max(60.0, viewportSize.width - pad);
    final availH = max(60.0, viewportSize.height - pad);
    final z = min(availW / doc.width, availH / doc.height).clamp(0.05, 8.0);
    doc.zoom = z;
    doc.panOffset = Offset.zero;
    notifyListeners();
  }

  void resetZoom100() {
    final doc = activeDoc;
    if (doc == null) return;
    doc.zoom = 1.0;
    doc.panOffset = Offset.zero;
    notifyListeners();
  }

  void panBy(Offset delta) {
    final doc = activeDoc;
    if (doc == null) return;
    doc.panOffset += delta;
    notifyListeners();
  }

  void toggleGrid() {
    final doc = activeDoc;
    if (doc == null) return;
    doc.showGrid = !doc.showGrid;
    notifyListeners();
  }

  void toggleRulers() {
    final doc = activeDoc;
    if (doc == null) return;
    doc.showRulers = !doc.showRulers;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Layer Management
  // ---------------------------------------------------------------------------

  Future<void> addNewLayer({String? name, Color? fill}) async {
    final doc = activeDoc;
    if (doc == null) return;
    final pixels = fill == null || fill.a == 0
        ? PixelOps.createBlankRgba(doc.width, doc.height)
        : PixelOps.createFilledRgba(doc.width, doc.height, fill);
    final img =
        await PixelOps.decodeStraightRgbaToUiImage(pixels, doc.width, doc.height);
    final layer = RasterLayer(
      id: _newId(),
      name: name ?? 'Layer ${doc.layers.length + 1}',
      width: doc.width,
      height: doc.height,
      pixels: pixels,
      cachedImage: img,
    );
    final insertAt = (doc.activeLayerIndex + 1).clamp(0, doc.layers.length);
    doc.layers.insert(insertAt, layer);
    doc.activeLayerIndex = insertAt;
    doc.dirty = true;
    _recordHistoryEntry(doc, 'New Layer');
    notifyListeners();
  }

  Future<void> addOrUpdateTextLayer({
    required TextLayerData data,
    Offset origin = const Offset(40, 40),
    int? replaceIndex,
  }) async {
    final doc = activeDoc;
    if (doc == null) return;
    final pixels = await ProjectIO.renderTextToRgba(
      data,
      doc.width,
      doc.height,
      origin: origin,
    );
    final uiImg =
        await PixelOps.decodeStraightRgbaToUiImage(pixels, doc.width, doc.height);

    if (replaceIndex != null &&
        replaceIndex >= 0 &&
        replaceIndex < doc.layers.length) {
      final layer = doc.layers[replaceIndex];
      layer.textData = data.clone();
      layer.name = data.text.split('\n').first.trim().isEmpty
          ? 'Text'
          : data.text.split('\n').first.trim();
      layer.pixels = pixels;
      layer.cachedImage = uiImg;
      doc.dirty = true;
      _recordHistoryEntry(doc, 'Edit Text Layer');
    } else {
      final layer = RasterLayer(
        id: _newId(),
        name: data.text.split('\n').first.trim().isEmpty
            ? 'Text Layer'
            : data.text.split('\n').first.trim(),
        width: doc.width,
        height: doc.height,
        pixels: pixels,
        cachedImage: uiImg,
        textData: data.clone(),
      );
      final insertAt = (doc.activeLayerIndex + 1).clamp(0, doc.layers.length);
      doc.layers.insert(insertAt, layer);
      doc.activeLayerIndex = insertAt;
      doc.dirty = true;
      _recordHistoryEntry(doc, 'Add Text Layer');
    }
    notifyListeners();
  }

  void rasterizeActiveTextLayer() {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null || !layer.isTextLayer) return;
    layer.textData = null;
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Rasterize Text');
    notifyListeners();
  }

  void selectLayer(int index) {
    final doc = activeDoc;
    if (doc == null || index < 0 || index >= doc.layers.length) return;
    doc.activeLayerIndex = index;
    notifyListeners();
  }

  void toggleLayerVisibility(int index) {
    final doc = activeDoc;
    if (doc == null || index < 0 || index >= doc.layers.length) return;
    doc.layers[index].visible = !doc.layers[index].visible;
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Toggle Visibility');
    notifyListeners();
  }

  void toggleLayerLock(int index) {
    final doc = activeDoc;
    if (doc == null || index < 0 || index >= doc.layers.length) return;
    doc.layers[index].locked = !doc.layers[index].locked;
    notifyListeners();
  }

  void setLayerOpacity(int index, double opacity, {bool commitHistory = false}) {
    final doc = activeDoc;
    if (doc == null || index < 0 || index >= doc.layers.length) return;
    doc.layers[index].opacity = opacity.clamp(0.0, 1.0);
    doc.dirty = true;
    if (commitHistory) {
      _recordHistoryEntry(doc, 'Layer Opacity');
    }
    notifyListeners();
  }

  void setLayerBlendMode(int index, LayerBlendMode mode) {
    final doc = activeDoc;
    if (doc == null || index < 0 || index >= doc.layers.length) return;
    doc.layers[index].blendMode = mode;
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Blend Mode: ${mode.label}');
    notifyListeners();
  }

  void renameLayer(int index, String newName) {
    final doc = activeDoc;
    if (doc == null || index < 0 || index >= doc.layers.length) return;
    if (newName.trim().isEmpty) return;
    doc.layers[index].name = newName.trim();
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Rename Layer');
    notifyListeners();
  }

  Future<void> duplicateActiveLayer() async {
    final doc = activeDoc;
    final active = doc?.activeLayer;
    if (doc == null || active == null) return;
    final dupPixels = Uint8List.fromList(active.pixels);
    final img = await PixelOps.decodeStraightRgbaToUiImage(
      dupPixels,
      active.width,
      active.height,
    );
    final copy = RasterLayer(
      id: _newId(),
      name: '${active.name} Copy',
      visible: active.visible,
      locked: active.locked,
      opacity: active.opacity,
      blendMode: active.blendMode,
      offsetX: active.offsetX,
      offsetY: active.offsetY,
      width: active.width,
      height: active.height,
      pixels: dupPixels,
      cachedImage: img,
      textData: active.textData?.clone(),
    );
    final insertAt = (doc.activeLayerIndex + 1).clamp(0, doc.layers.length);
    doc.layers.insert(insertAt, copy);
    doc.activeLayerIndex = insertAt;
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Duplicate Layer');
    notifyListeners();
  }

  void deleteActiveLayer() {
    final doc = activeDoc;
    if (doc == null || doc.layers.length <= 1) {
      setStatus('Cannot delete the only remaining layer');
      return;
    }
    doc.layers.removeAt(doc.activeLayerIndex);
    doc.activeLayerIndex =
        doc.activeLayerIndex.clamp(0, doc.layers.length - 1);
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Delete Layer');
    notifyListeners();
  }

  void moveLayerUp() {
    final doc = activeDoc;
    if (doc == null || doc.activeLayerIndex >= doc.layers.length - 1) return;
    final i = doc.activeLayerIndex;
    final tmp = doc.layers[i + 1];
    doc.layers[i + 1] = doc.layers[i];
    doc.layers[i] = tmp;
    doc.activeLayerIndex = i + 1;
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Reorder Layer');
    notifyListeners();
  }

  void moveLayerDown() {
    final doc = activeDoc;
    if (doc == null || doc.activeLayerIndex <= 0) return;
    final i = doc.activeLayerIndex;
    final tmp = doc.layers[i - 1];
    doc.layers[i - 1] = doc.layers[i];
    doc.layers[i] = tmp;
    doc.activeLayerIndex = i - 1;
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Reorder Layer');
    notifyListeners();
  }

  Future<void> mergeDown() async {
    final doc = activeDoc;
    if (doc == null || doc.activeLayerIndex <= 0) return;
    final topIdx = doc.activeLayerIndex;
    final botIdx = topIdx - 1;
    final merged = await ProjectIO.flattenLayers(
      [doc.layers[botIdx], doc.layers[topIdx]],
      doc.width,
      doc.height,
    );
    final img = await PixelOps.decodeStraightRgbaToUiImage(
      merged,
      doc.width,
      doc.height,
    );
    doc.layers[botIdx] = RasterLayer(
      id: doc.layers[botIdx].id,
      name: doc.layers[botIdx].name,
      visible: true,
      locked: doc.layers[botIdx].locked,
      opacity: 1.0,
      blendMode: LayerBlendMode.normal,
      width: doc.width,
      height: doc.height,
      pixels: merged,
      cachedImage: img,
    );
    doc.layers.removeAt(topIdx);
    doc.activeLayerIndex = botIdx;
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Merge Down');
    notifyListeners();
  }

  Future<void> flattenImage() async {
    final doc = activeDoc;
    if (doc == null || doc.layers.length <= 1) return;
    final flattened =
        await ProjectIO.flattenLayers(doc.layers, doc.width, doc.height);
    final img = await PixelOps.decodeStraightRgbaToUiImage(
      flattened,
      doc.width,
      doc.height,
    );
    doc.layers = [
      RasterLayer(
        id: _newId(),
        name: 'Flattened',
        width: doc.width,
        height: doc.height,
        pixels: flattened,
        cachedImage: img,
      ),
    ];
    doc.activeLayerIndex = 0;
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Flatten Image');
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Active Painting & Tool Execution
  // ---------------------------------------------------------------------------

  void paintStrokeSegment(Offset canvasFrom, Offset canvasTo,
      {required bool isEraser, required bool isPencil}) {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null || layer.locked || !layer.visible) return;
    if (layer.isTextLayer) {
      setStatus('Rasterize text layer before painting on it');
      return;
    }

    final localFrom =
        Offset(canvasFrom.dx - layer.offsetX, canvasFrom.dy - layer.offsetY);
    final localTo =
        Offset(canvasTo.dx - layer.offsetX, canvasTo.dy - layer.offsetY);

    PixelOps.drawStrokeSegment(
      pixels: layer.pixels,
      width: layer.width,
      height: layer.height,
      from: localFrom,
      to: localTo,
      radius: (isEraser ? eraserSize : brushSize) / 2.0,
      hardness: isPencil ? 1.0 : (isEraser ? eraserHardness : brushHardness),
      opacity: isPencil ? 1.0 : (isEraser ? eraserOpacity : brushOpacity),
      color: foregroundColor,
      erase: isEraser,
      hardPixelEdge: isPencil,
      selectionMask: doc.selection.mask,
      selectionWidth: doc.width,
      selectionHeight: doc.height,
      layerOffsetX: layer.offsetX,
      layerOffsetY: layer.offsetY,
    );
    doc.dirty = true;
    _scheduleLayerImageUpload(layer);
  }

  void paintCloneSegment(Offset canvasFrom, Offset canvasTo,
      {required bool isStart}) {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null || layer.locked || !layer.visible) return;
    if (cloneSourceAnchor == null) {
      setStatus('Alt + Click on canvas to set Clone Stamp source first');
      return;
    }
    if (isStart) {
      _cloneStrokeStartDst = canvasFrom;
      _previewOriginalPixels ??= Uint8List.fromList(layer.pixels);
    }
    final anchorStart = _cloneStrokeStartDst ?? canvasFrom;
    final srcOffsetX = cloneSourceAnchor!.dx - anchorStart.dx;
    final srcOffsetY = cloneSourceAnchor!.dy - anchorStart.dy;
    final srcPixels = _previewOriginalPixels ?? layer.pixels;

    final localFrom =
        Offset(canvasFrom.dx - layer.offsetX, canvasFrom.dy - layer.offsetY);
    final localTo =
        Offset(canvasTo.dx - layer.offsetX, canvasTo.dy - layer.offsetY);
    final dist = (localTo - localFrom).distance;
    final spacing = max(1.0, (brushSize / 2.0) * 0.3);
    final steps = max(1, (dist / spacing).ceil());

    for (int i = 0; i <= steps; i++) {
      final t = steps == 0 ? 0.0 : i / steps;
      final cx = localFrom.dx + (localTo.dx - localFrom.dx) * t;
      final cy = localFrom.dy + (localTo.dy - localFrom.dy) * t;
      PixelOps.stampCloneDab(
        dstPixels: layer.pixels,
        sourcePixels: srcPixels,
        width: layer.width,
        height: layer.height,
        cx: cx,
        cy: cy,
        srcOffsetX: srcOffsetX,
        srcOffsetY: srcOffsetY,
        radius: brushSize / 2.0,
        hardness: brushHardness,
        opacity: brushOpacity,
        selectionMask: doc.selection.mask,
        selectionWidth: doc.width,
        selectionHeight: doc.height,
        layerOffsetX: layer.offsetX,
        layerOffsetY: layer.offsetY,
      );
    }
    doc.dirty = true;
    _scheduleLayerImageUpload(layer);
  }

  void paintBlurOrSmudgeSegment(Offset canvasFrom, Offset canvasTo,
      {required bool smudge}) {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null || layer.locked || !layer.visible) return;
    final localFrom =
        Offset(canvasFrom.dx - layer.offsetX, canvasFrom.dy - layer.offsetY);
    final localTo =
        Offset(canvasTo.dx - layer.offsetX, canvasTo.dy - layer.offsetY);
    PixelOps.applyLocalBlurOrSmudge(
      pixels: layer.pixels,
      width: layer.width,
      height: layer.height,
      from: localFrom,
      to: localTo,
      radius: brushSize / 2.0,
      strength: brushOpacity.clamp(0.15, 0.9),
      smudge: smudge,
      selectionMask: doc.selection.mask,
      selectionWidth: doc.width,
      selectionHeight: doc.height,
      layerOffsetX: layer.offsetX,
      layerOffsetY: layer.offsetY,
    );
    doc.dirty = true;
    _scheduleLayerImageUpload(layer);
  }

  Future<void> commitStrokeHistory(String label) async {
    _previewOriginalPixels = null;
    _cloneStrokeStartDst = null;
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null) return;
    layer.cachedImage = await PixelOps.decodeStraightRgbaToUiImage(
      layer.pixels,
      layer.width,
      layer.height,
    );
    _pushRecentColor(foregroundColor);
    _recordHistoryEntry(doc, label);
    notifyListeners();
  }

  void moveActiveLayerBy(Offset delta) {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null || layer.locked) return;
    layer.offsetX += delta.dx;
    layer.offsetY += delta.dy;
    doc.dirty = true;
    notifyListeners();
  }

  void commitMoveLayer() {
    final doc = activeDoc;
    if (doc == null) return;
    _recordHistoryEntry(doc, 'Move Layer');
    notifyListeners();
  }

  Future<void> applyBucketFill(Offset canvasPos) async {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null || layer.locked || !layer.visible) return;
    if (layer.isTextLayer) {
      setStatus('Rasterize text layer before using Paint Bucket');
      return;
    }
    final lx = (canvasPos.dx - layer.offsetX).floor();
    final ly = (canvasPos.dy - layer.offsetY).floor();
    PixelOps.floodFill(
      pixels: layer.pixels,
      width: layer.width,
      height: layer.height,
      startX: lx,
      startY: ly,
      fillColor: foregroundColor,
      tolerance: bucketTolerance,
      opacity: brushOpacity,
      selectionMask: doc.selection.mask,
      selectionWidth: doc.width,
      selectionHeight: doc.height,
      layerOffsetX: layer.offsetX,
      layerOffsetY: layer.offsetY,
    );
    layer.cachedImage = await PixelOps.decodeStraightRgbaToUiImage(
      layer.pixels,
      layer.width,
      layer.height,
    );
    doc.dirty = true;
    _pushRecentColor(foregroundColor);
    _recordHistoryEntry(doc, 'Paint Bucket');
    notifyListeners();
  }

  Future<void> applyGradientDrag(Offset start, Offset end) async {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null || layer.locked || !layer.visible) return;
    if (layer.isTextLayer) {
      setStatus('Rasterize text layer before applying Gradient');
      return;
    }
    PixelOps.applyGradient(
      pixels: layer.pixels,
      width: layer.width,
      height: layer.height,
      start: Offset(start.dx - layer.offsetX, start.dy - layer.offsetY),
      end: Offset(end.dx - layer.offsetX, end.dy - layer.offsetY),
      startColor: foregroundColor,
      endColor: backgroundColor,
      kind: gradientKind,
      opacity: brushOpacity,
      selectionMask: doc.selection.mask,
      selectionWidth: doc.width,
      selectionHeight: doc.height,
      layerOffsetX: layer.offsetX,
      layerOffsetY: layer.offsetY,
    );
    layer.cachedImage = await PixelOps.decodeStraightRgbaToUiImage(
      layer.pixels,
      layer.width,
      layer.height,
    );
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Gradient Fill');
    notifyListeners();
  }

  Future<void> applyShapeDrag(Offset start, Offset end) async {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null || layer.locked || !layer.visible) return;
    if (layer.isTextLayer) {
      setStatus('Rasterize text layer or add a new layer for Shapes');
      return;
    }
    if ((end - start).distance < 2.0) return;

    final overlay = await ProjectIO.renderShapeOverlay(
      width: layer.width,
      height: layer.height,
      kind: shapeKind,
      start: Offset(start.dx - layer.offsetX, start.dy - layer.offsetY),
      end: Offset(end.dx - layer.offsetX, end.dy - layer.offsetY),
      fillColor: foregroundColor,
      strokeColor: backgroundColor,
      strokeWidth: shapeStrokeWidth,
      hasFill: shapeFill,
      hasStroke: shapeStroke,
      cornerRadius: shapeCornerRadius,
      polygonSides: shapePolygonSides,
    );
    ProjectIO.compositeOverlayOntoLayer(
      base: layer.pixels,
      overlay: overlay,
      width: layer.width,
      height: layer.height,
      selectionMask: doc.selection.mask,
      selectionWidth: doc.width,
      selectionHeight: doc.height,
      layerOffsetX: layer.offsetX,
      layerOffsetY: layer.offsetY,
    );
    layer.cachedImage = await PixelOps.decodeStraightRgbaToUiImage(
      layer.pixels,
      layer.width,
      layer.height,
    );
    doc.dirty = true;
    _pushRecentColor(foregroundColor);
    _recordHistoryEntry(doc, 'Draw ${shapeKind.name}');
    notifyListeners();
  }

  Future<void> sampleEyedropper(Offset canvasPos) async {
    final doc = activeDoc;
    if (doc == null) return;
    final x = canvasPos.dx.floor();
    final y = canvasPos.dy.floor();
    if (x < 0 || x >= doc.width || y < 0 || y >= doc.height) return;
    // Sample from top-most visible non-transparent pixel at (x, y)
    for (int i = doc.layers.length - 1; i >= 0; i--) {
      final l = doc.layers[i];
      if (!l.visible) continue;
      final lx = (x - l.offsetX).round();
      final ly = (y - l.offsetY).round();
      final c = PixelOps.samplePixel(l.pixels, l.width, l.height, lx, ly);
      if (c.a > 0.02) {
        setForegroundColor(Color.fromARGB(255, (c.r * 255).round(),
            (c.g * 255).round(), (c.b * 255).round()),
            recordRecent: true);
        return;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Selection Operations
  // ---------------------------------------------------------------------------

  void applyRectSelection(Rect rect) {
    final doc = activeDoc;
    if (doc == null) return;
    if (rect.width < 1 || rect.height < 1) {
      deselect();
      return;
    }
    final mask = PixelOps.buildRectSelectionMask(doc.width, doc.height, rect);
    _setCombinedSelection(doc, mask, 'Rectangular Selection');
  }

  void applyEllipseSelection(Rect rect) {
    final doc = activeDoc;
    if (doc == null) return;
    if (rect.width < 1 || rect.height < 1) {
      deselect();
      return;
    }
    final mask =
        PixelOps.buildEllipseSelectionMask(doc.width, doc.height, rect);
    _setCombinedSelection(doc, mask, 'Elliptical Selection');
  }

  void applyLassoSelection(List<Offset> points) {
    final doc = activeDoc;
    if (doc == null || points.length < 3) {
      deselect();
      return;
    }
    final mask =
        PixelOps.buildPolygonSelectionMask(doc.width, doc.height, points);
    _setCombinedSelection(doc, mask, 'Lasso Selection');
  }

  void applyMagicWandSelection(Offset canvasPos) {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null) return;
    final lx = (canvasPos.dx - layer.offsetX).floor();
    final ly = (canvasPos.dy - layer.offsetY).floor();
    final layerMask = PixelOps.magicWandMask(
      pixels: layer.pixels,
      width: layer.width,
      height: layer.height,
      startX: lx,
      startY: ly,
      tolerance: wandTolerance,
      contiguous: wandContiguous,
    );

    // Map layer-local mask to canvas coordinates
    final canvasMask = Uint8List(doc.width * doc.height);
    final ox = layer.offsetX.round();
    final oy = layer.offsetY.round();
    for (int y = 0; y < layer.height; y++) {
      final cy = y + oy;
      if (cy < 0 || cy >= doc.height) continue;
      for (int x = 0; x < layer.width; x++) {
        final cx = x + ox;
        if (cx < 0 || cx >= doc.width) continue;
        canvasMask[cy * doc.width + cx] = layerMask[y * layer.width + x];
      }
    }
    _setCombinedSelection(doc, canvasMask, 'Magic Wand');
  }

  void _setCombinedSelection(
      GraphicsDocument doc, Uint8List nextMask, String label) {
    final combined = PixelOps.combineSelectionMasks(
      doc.selection.mask,
      nextMask,
      selectionMode,
    );
    final bounds = PixelOps.computeMaskBounds(combined, doc.width, doc.height);
    if (bounds == null) {
      doc.selection.clear();
    } else {
      doc.selection.mask = combined;
      doc.selection.bounds = bounds;
      doc.selection.outlinePath =
          PixelOps.computeMaskOutlinePath(combined, doc.width, doc.height);
    }
    _recordHistoryEntry(doc, label);
    notifyListeners();
  }

  void selectAll() {
    final doc = activeDoc;
    if (doc == null) return;
    final mask = Uint8List(doc.width * doc.height)..fillRange(0, doc.width * doc.height, 255);
    final rect = Rect.fromLTWH(0, 0, doc.width.toDouble(), doc.height.toDouble());
    doc.selection.mask = mask;
    doc.selection.bounds = rect;
    doc.selection.outlinePath = ui.Path()..addRect(rect);
    _recordHistoryEntry(doc, 'Select All');
    notifyListeners();
  }

  void deselect() {
    final doc = activeDoc;
    if (doc == null || !doc.selection.hasSelection) return;
    doc.selection.clear();
    _recordHistoryEntry(doc, 'Deselect');
    notifyListeners();
  }

  void invertSelection() {
    final doc = activeDoc;
    if (doc == null) return;
    if (!doc.selection.hasSelection) {
      selectAll();
      return;
    }
    final inv = PixelOps.invertSelectionMask(doc.selection.mask!);
    final bounds = PixelOps.computeMaskBounds(inv, doc.width, doc.height);
    if (bounds == null) {
      doc.selection.clear();
    } else {
      doc.selection.mask = inv;
      doc.selection.bounds = bounds;
      doc.selection.outlinePath =
          PixelOps.computeMaskOutlinePath(inv, doc.width, doc.height);
    }
    _recordHistoryEntry(doc, 'Invert Selection');
    notifyListeners();
  }

  Future<void> clearSelectedPixels() async {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null || layer.locked) return;
    PixelOps.clearPixelsWithSelection(
      pixels: layer.pixels,
      width: layer.width,
      height: layer.height,
      selectionMask: doc.selection.mask,
      selectionWidth: doc.width,
      selectionHeight: doc.height,
      layerOffsetX: layer.offsetX,
      layerOffsetY: layer.offsetY,
    );
    layer.cachedImage = await PixelOps.decodeStraightRgbaToUiImage(
      layer.pixels,
      layer.width,
      layer.height,
    );
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Clear Pixels');
    notifyListeners();
  }

  Future<void> fillSelectedPixels(Color color) async {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null || layer.locked) return;
    PixelOps.fillLayerWithSelection(
      pixels: layer.pixels,
      width: layer.width,
      height: layer.height,
      color: color,
      selectionMask: doc.selection.mask,
      selectionWidth: doc.width,
      selectionHeight: doc.height,
      layerOffsetX: layer.offsetX,
      layerOffsetY: layer.offsetY,
    );
    layer.cachedImage = await PixelOps.decodeStraightRgbaToUiImage(
      layer.pixels,
      layer.width,
      layer.height,
    );
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Fill');
    notifyListeners();
  }

  void copySelection() {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null) return;
    final copy = Uint8List.fromList(layer.pixels);
    if (doc.selection.hasSelection) {
      final mask = doc.selection.mask!;
      for (int y = 0; y < layer.height; y++) {
        final sy = (y + layer.offsetY).round();
        for (int x = 0; x < layer.width; x++) {
          final sx = (x + layer.offsetX).round();
          int sel = 0;
          if (sx >= 0 && sx < doc.width && sy >= 0 && sy < doc.height) {
            sel = mask[sy * doc.width + sx];
          }
          final idx = (y * layer.width + x) * 4;
          copy[idx + 3] = ((copy[idx + 3] * sel) / 255.0).round().clamp(0, 255);
        }
      }
    }
    _clipboardPixels = copy;
    _clipboardW = layer.width;
    _clipboardH = layer.height;
    setStatus('Copied to clipboard');
  }

  Future<void> cutSelection() async {
    copySelection();
    await clearSelectedPixels();
  }

  Future<void> pasteClipboard() async {
    final doc = activeDoc;
    if (doc == null || _clipboardPixels == null) return;
    final pixels = Uint8List.fromList(_clipboardPixels!);
    final img = await PixelOps.decodeStraightRgbaToUiImage(
      pixels,
      _clipboardW,
      _clipboardH,
    );
    final pasted = RasterLayer(
      id: _newId(),
      name: 'Pasted Layer',
      width: _clipboardW,
      height: _clipboardH,
      pixels: pixels,
      cachedImage: img,
    );
    final insertAt = (doc.activeLayerIndex + 1).clamp(0, doc.layers.length);
    doc.layers.insert(insertAt, pasted);
    doc.activeLayerIndex = insertAt;
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Paste');
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Filters, Adjustments & Live Preview
  // ---------------------------------------------------------------------------

  void beginLayerPreview() {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null || layer.locked) return;
    _previewOriginalPixels = Uint8List.fromList(layer.pixels);
    _previewLayerIndex = doc.activeLayerIndex;
  }

  Future<void> applyPreviewTransform(
    Uint8List Function(Uint8List src, int w, int h, Uint8List? mask) transform,
  ) async {
    final doc = activeDoc;
    if (doc == null ||
        _previewOriginalPixels == null ||
        _previewLayerIndex == null) {
      return;
    }
    final layer = doc.layers[_previewLayerIndex!];
    final mask = _alignedLayerSelectionMask(doc, layer);
    layer.pixels = transform(_previewOriginalPixels!, layer.width, layer.height, mask);
    layer.cachedImage = await PixelOps.decodeStraightRgbaToUiImage(
      layer.pixels,
      layer.width,
      layer.height,
    );
    notifyListeners();
  }

  void commitLayerPreview(String label) {
    final doc = activeDoc;
    if (doc != null && _previewOriginalPixels != null) {
      doc.dirty = true;
      _recordHistoryEntry(doc, label);
    }
    _previewOriginalPixels = null;
    _previewLayerIndex = null;
    notifyListeners();
  }

  Future<void> cancelLayerPreview() async {
    final doc = activeDoc;
    if (doc != null &&
        _previewOriginalPixels != null &&
        _previewLayerIndex != null &&
        _previewLayerIndex! < doc.layers.length) {
      final layer = doc.layers[_previewLayerIndex!];
      layer.pixels = _previewOriginalPixels!;
      layer.cachedImage = await PixelOps.decodeStraightRgbaToUiImage(
        layer.pixels,
        layer.width,
        layer.height,
      );
    }
    _previewOriginalPixels = null;
    _previewLayerIndex = null;
    notifyListeners();
  }

  Future<void> runImmediateFilter(
    String label,
    Uint8List Function(Uint8List src, int w, int h, Uint8List? mask) transform,
  ) async {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null || layer.locked) return;
    final mask = _alignedLayerSelectionMask(doc, layer);
    layer.pixels = transform(layer.pixels, layer.width, layer.height, mask);
    layer.cachedImage = await PixelOps.decodeStraightRgbaToUiImage(
      layer.pixels,
      layer.width,
      layer.height,
    );
    doc.dirty = true;
    _recordHistoryEntry(doc, label);
    notifyListeners();
  }

  Uint8List? _alignedLayerSelectionMask(
      GraphicsDocument doc, RasterLayer layer) {
    if (!doc.selection.hasSelection) return null;
    final sel = doc.selection.mask!;
    final ox = layer.offsetX.round();
    final oy = layer.offsetY.round();
    if (ox == 0 && oy == 0 && layer.width == doc.width && layer.height == doc.height) {
      return sel;
    }
    final out = Uint8List(layer.width * layer.height);
    for (int y = 0; y < layer.height; y++) {
      final sy = y + oy;
      if (sy < 0 || sy >= doc.height) continue;
      for (int x = 0; x < layer.width; x++) {
        final sx = x + ox;
        if (sx < 0 || sx >= doc.width) continue;
        out[y * layer.width + x] = sel[sy * doc.width + sx];
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Image / Canvas Geometric Transforms
  // ---------------------------------------------------------------------------

  Future<void> resizeImage(int newW, int newH) async {
    final doc = activeDoc;
    if (doc == null) return;
    final w = newW.clamp(1, 8192);
    final h = newH.clamp(1, 8192);
    final sx = w / doc.width;
    final sy = h / doc.height;

    for (final l in doc.layers) {
      final nw = max(1, (l.width * sx).round());
      final nh = max(1, (l.height * sy).round());
      l.pixels = PixelOps.resizeBilinear(l.pixels, l.width, l.height, nw, nh);
      l.width = nw;
      l.height = nh;
      l.offsetX *= sx;
      l.offsetY *= sy;
      l.cachedImage =
          await PixelOps.decodeStraightRgbaToUiImage(l.pixels, nw, nh);
    }
    doc.width = w;
    doc.height = h;
    doc.selection.clear();
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Image Size ($w×$h)');
    notifyListeners();
  }

  Future<void> resizeCanvas(int newW, int newH,
      {Alignment anchor = Alignment.center}) async {
    final doc = activeDoc;
    if (doc == null) return;
    final w = newW.clamp(1, 8192);
    final h = newH.clamp(1, 8192);
    final dx = ((w - doc.width) * ((anchor.x + 1) / 2.0)).roundToDouble();
    final dy = ((h - doc.height) * ((anchor.y + 1) / 2.0)).roundToDouble();
    for (final l in doc.layers) {
      l.offsetX += dx;
      l.offsetY += dy;
    }
    doc.width = w;
    doc.height = h;
    doc.selection.clear();
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Canvas Size ($w×$h)');
    notifyListeners();
  }

  Future<void> applyCrop() async {
    final doc = activeDoc;
    final rect = activeCropRect;
    if (doc == null || rect == null) return;
    final clipped = rect.intersect(
      Rect.fromLTWH(0, 0, doc.width.toDouble(), doc.height.toDouble()),
    );
    if (clipped.width < 1 || clipped.height < 1) return;

    final nw = clipped.width.round();
    final nh = clipped.height.round();

    for (final l in doc.layers) {
      l.pixels = PixelOps.cropOrPadLayer(
        l.pixels,
        l.width,
        l.height,
        l.offsetX,
        l.offsetY,
        clipped,
      );
      l.width = nw;
      l.height = nh;
      l.offsetX = 0;
      l.offsetY = 0;
      l.cachedImage =
          await PixelOps.decodeStraightRgbaToUiImage(l.pixels, nw, nh);
    }
    doc.width = nw;
    doc.height = nh;
    doc.selection.clear();
    doc.dirty = true;
    activeCropRect = Rect.fromLTWH(0, 0, nw.toDouble(), nh.toDouble());
    _recordHistoryEntry(doc, 'Crop ($nw×$nh)');
    notifyListeners();
  }

  Future<void> flipActiveLayer({required bool horizontal}) async {
    final doc = activeDoc;
    final layer = doc?.activeLayer;
    if (doc == null || layer == null || layer.locked) return;
    layer.pixels = horizontal
        ? PixelOps.flipHorizontal(layer.pixels, layer.width, layer.height)
        : PixelOps.flipVertical(layer.pixels, layer.width, layer.height);
    layer.cachedImage = await PixelOps.decodeStraightRgbaToUiImage(
      layer.pixels,
      layer.width,
      layer.height,
    );
    doc.dirty = true;
    _recordHistoryEntry(
      doc,
      horizontal ? 'Flip Layer Horizontal' : 'Flip Layer Vertical',
    );
    notifyListeners();
  }

  Future<void> flipCanvas({required bool horizontal}) async {
    final doc = activeDoc;
    if (doc == null) return;
    for (final l in doc.layers) {
      l.pixels = horizontal
          ? PixelOps.flipHorizontal(l.pixels, l.width, l.height)
          : PixelOps.flipVertical(l.pixels, l.width, l.height);
      if (horizontal) {
        l.offsetX = doc.width - l.offsetX - l.width;
      } else {
        l.offsetY = doc.height - l.offsetY - l.height;
      }
      l.cachedImage = await PixelOps.decodeStraightRgbaToUiImage(
        l.pixels,
        l.width,
        l.height,
      );
    }
    doc.selection.clear();
    doc.dirty = true;
    _recordHistoryEntry(
      doc,
      horizontal ? 'Flip Canvas Horizontal' : 'Flip Canvas Vertical',
    );
    notifyListeners();
  }

  Future<void> rotateCanvas(int degreesCW) async {
    final doc = activeDoc;
    if (doc == null) return;
    final oldW = doc.width;
    final oldH = doc.height;

    if (degreesCW == 90) {
      for (final l in doc.layers) {
        final nw = l.height;
        final nh = l.width;
        l.pixels = PixelOps.rotate90CW(l.pixels, l.width, l.height);
        final nx = oldH - l.offsetY - l.height;
        final ny = l.offsetX;
        l.width = nw;
        l.height = nh;
        l.offsetX = nx;
        l.offsetY = ny;
        l.cachedImage =
            await PixelOps.decodeStraightRgbaToUiImage(l.pixels, nw, nh);
      }
      doc.width = oldH;
      doc.height = oldW;
    } else if (degreesCW == -90 || degreesCW == 270) {
      for (final l in doc.layers) {
        final nw = l.height;
        final nh = l.width;
        l.pixels = PixelOps.rotate90CCW(l.pixels, l.width, l.height);
        final nx = l.offsetY;
        final ny = oldW - l.offsetX - l.width;
        l.width = nw;
        l.height = nh;
        l.offsetX = nx;
        l.offsetY = ny;
        l.cachedImage =
            await PixelOps.decodeStraightRgbaToUiImage(l.pixels, nw, nh);
      }
      doc.width = oldH;
      doc.height = oldW;
    } else if (degreesCW == 180) {
      for (final l in doc.layers) {
        l.pixels = PixelOps.rotate180(l.pixels, l.width, l.height);
        l.offsetX = oldW - l.offsetX - l.width;
        l.offsetY = oldH - l.offsetY - l.height;
        l.cachedImage = await PixelOps.decodeStraightRgbaToUiImage(
          l.pixels,
          l.width,
          l.height,
        );
      }
    }
    doc.selection.clear();
    doc.dirty = true;
    _recordHistoryEntry(doc, 'Rotate Canvas $degreesCW°');
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // History (Undo / Redo / Jump)
  // ---------------------------------------------------------------------------

  bool get canUndo => activeDoc != null && activeDoc!.historyIndex > 0;
  bool get canRedo =>
      activeDoc != null &&
      activeDoc!.historyIndex < activeDoc!.history.length - 1;

  void _recordHistoryEntry(GraphicsDocument doc, String label) {
    if (doc.historyIndex < doc.history.length - 1) {
      doc.history.removeRange(doc.historyIndex + 1, doc.history.length);
    }
    doc.history.add(
      HistoryEntry(
        label: label,
        width: doc.width,
        height: doc.height,
        layers: doc.layers.map((l) => l.clone()).toList(),
        activeLayerIndex: doc.activeLayerIndex,
        selectionMask: doc.selection.mask != null
            ? Uint8List.fromList(doc.selection.mask!)
            : null,
        selectionBounds: doc.selection.bounds,
      ),
    );
    if (doc.history.length > maxHistoryEntries) {
      doc.history.removeAt(0);
    }
    doc.historyIndex = doc.history.length - 1;
  }

  Future<void> undo() async {
    final doc = activeDoc;
    if (doc == null || doc.historyIndex <= 0) return;
    await jumpToHistory(doc.historyIndex - 1);
  }

  Future<void> redo() async {
    final doc = activeDoc;
    if (doc == null || doc.historyIndex >= doc.history.length - 1) return;
    await jumpToHistory(doc.historyIndex + 1);
  }

  Future<void> jumpToHistory(int idx) async {
    final doc = activeDoc;
    if (doc == null || idx < 0 || idx >= doc.history.length) return;
    final entry = doc.history[idx];
    doc.width = entry.width;
    doc.height = entry.height;
    doc.layers = [];
    for (final l in entry.layers) {
      final cloned = l.clone(copyImageRef: false);
      cloned.cachedImage = await PixelOps.decodeStraightRgbaToUiImage(
        cloned.pixels,
        cloned.width,
        cloned.height,
      );
      doc.layers.add(cloned);
    }
    doc.activeLayerIndex =
        entry.activeLayerIndex.clamp(0, max(0, doc.layers.length - 1));
    if (entry.selectionMask != null && entry.selectionBounds != null) {
      final m = Uint8List.fromList(entry.selectionMask!);
      doc.selection.mask = m;
      doc.selection.bounds = entry.selectionBounds;
      doc.selection.outlinePath =
          PixelOps.computeMaskOutlinePath(m, doc.width, doc.height);
    } else {
      doc.selection.clear();
    }
    doc.historyIndex = idx;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  void _scheduleLayerImageUpload(RasterLayer layer) {
    if (_uploadingLayerIds.contains(layer.id)) {
      _dirtyUploadLayerIds.add(layer.id);
      notifyListeners();
      return;
    }
    _uploadLayerImage(layer);
  }

  Future<void> _uploadLayerImage(RasterLayer layer) async {
    _uploadingLayerIds.add(layer.id);
    try {
      final img = await PixelOps.decodeStraightRgbaToUiImage(
        layer.pixels,
        layer.width,
        layer.height,
      );
      layer.cachedImage = img;
      notifyListeners();
    } finally {
      _uploadingLayerIds.remove(layer.id);
      if (_dirtyUploadLayerIds.remove(layer.id)) {
        _uploadLayerImage(layer);
      }
    }
  }

  void refresh() => notifyListeners();

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(9999)}';
}
