import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/editor_types.dart';
import '../state/editor_controller.dart';
import 'dialogs.dart';

class CanvasViewport extends StatefulWidget {
  const CanvasViewport({super.key});

  @override
  State<CanvasViewport> createState() => CanvasViewportState();
}

class CanvasViewportState extends State<CanvasViewport>
    with SingleTickerProviderStateMixin {
  late final AnimationController _antsController;
  Size _lastViewportSize = const Size(800, 600);
  Offset? _lastStrokeCanvas;
  Offset? _lastPanScreen;
  bool _isMiddlePanning = false;
  bool _spacePressed = false;
  bool _isDragging = false;
  int? _cropDragCorner; // null=new rect, 0=TL, 1=TR, 2=BR, 3=BL, 4=move

  @override
  void initState() {
    super.initState();
    _antsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _antsController.dispose();
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.space) {
      final down = event is KeyDownEvent || event is KeyRepeatEvent;
      if (_spacePressed != down && mounted) {
        setState(() => _spacePressed = down);
      }
    }
    return false;
  }

  void fitCurrentDocument() {
    context.read<EditorController>().fitToViewport(_lastViewportSize);
  }

  Offset _screenToCanvas(
      Offset screenPos, Size viewportSize, GraphicsDocument doc) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final rel = (screenPos - center - doc.panOffset) / doc.zoom;
    return rel + Offset(doc.width / 2, doc.height / 2);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<EditorController>();
    final doc = ctrl.activeDoc;

    if (doc == null) {
      return Expanded(
        child: Container(
          color: FyrTheme.contentColor,
          child: Center(
            child: Text(
              'No document open — File → New',
              style: TextStyle(color: FyrTheme.textColorMuted),
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final rulerSize = doc.showRulers ? 20.0 : 0.0;
                final vpSize = Size(
                  max(10.0, constraints.maxWidth - rulerSize),
                  max(10.0, constraints.maxHeight - rulerSize),
                );
                _lastViewportSize = vpSize;

                return Stack(
                  children: [
                    // Main Canvas Interaction Area
                    Positioned(
                      left: rulerSize,
                      top: rulerSize,
                      right: 0,
                      bottom: 0,
                      child: MouseRegion(
                        cursor: _cursorForTool(ctrl.activeTool),
                        onHover: (e) => ctrl.setHoverPosition(
                            _screenToCanvas(e.localPosition, vpSize, doc)),
                        onExit: (_) => ctrl.setHoverPosition(null),
                        child: Listener(
                          onPointerSignal: (signal) {
                            if (signal is PointerScrollEvent) {
                              final factor =
                                  signal.scrollDelta.dy < 0 ? 1.12 : 0.89;
                              final before = _screenToCanvas(
                                  signal.localPosition, vpSize, doc);
                              final newZoom = (doc.zoom * factor).clamp(0.05, 32.0);
                              final center =
                                  Offset(vpSize.width / 2, vpSize.height / 2);
                              final afterOffset = signal.localPosition -
                                  center -
                                  (before - Offset(doc.width / 2, doc.height / 2)) *
                                      newZoom;
                              ctrl.setZoom(newZoom, focalPan: afterOffset);
                            }
                          },
                          onPointerDown: (e) =>
                              _onPointerDown(e, ctrl, doc, vpSize),
                          onPointerMove: (e) =>
                              _onPointerMove(e, ctrl, doc, vpSize),
                          onPointerUp: (e) => _onPointerUp(e, ctrl, doc, vpSize),
                          child: ClipRect(
                            child: ColoredBox(
                              color: FyrTheme.isDark
                                  ? const Color(0xFF0E0E10)
                                  : const Color(0xFFE5E5EA),
                              child: AnimatedBuilder(
                                animation: _antsController,
                                builder: (context, _) {
                                  return CustomPaint(
                                    size: vpSize,
                                    painter: _CanvasPainter(
                                      doc: doc,
                                      ctrl: ctrl,
                                      antsPhase: _antsController.value,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Top & Left Rulers
                    if (doc.showRulers) ...[
                      Positioned(
                        left: 0,
                        top: 0,
                        width: rulerSize,
                        height: rulerSize,
                        child: Container(
                          decoration: BoxDecoration(
                            color: FyrTheme.surfaceColor,
                            border: Border(
                              right: BorderSide(color: FyrTheme.dividerColor),
                              bottom: BorderSide(color: FyrTheme.dividerColor),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: rulerSize,
                        top: 0,
                        right: 0,
                        height: rulerSize,
                        child: CustomPaint(
                          painter: _RulerPainter(
                            horizontal: true,
                            doc: doc,
                            viewportSize: vpSize,
                            textColor: FyrTheme.textColorMuted,
                            bgColor: FyrTheme.surfaceColor,
                            borderColor: FyrTheme.dividerColor,
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        top: rulerSize,
                        bottom: 0,
                        width: rulerSize,
                        child: CustomPaint(
                          painter: _RulerPainter(
                            horizontal: false,
                            doc: doc,
                            viewportSize: vpSize,
                            textColor: FyrTheme.textColorMuted,
                            bgColor: FyrTheme.surfaceColor,
                            borderColor: FyrTheme.dividerColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
          // Bottom Status Strip
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: FyrTheme.bgColor,
              border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              children: [
                Text(
                  '${doc.width} × ${doc.height} px',
                  style: TextStyle(fontSize: 10.5, color: FyrTheme.textColorMuted),
                ),
                const SizedBox(width: 14),
                Text(
                  'Zoom: ${(doc.zoom * 100).round()}%',
                  style: TextStyle(fontSize: 10.5, color: FyrTheme.textColorMuted),
                ),
                if (ctrl.hoverCanvasPos != null) ...[
                  const SizedBox(width: 14),
                  Text(
                    'X: ${ctrl.hoverCanvasPos!.dx.floor()}  Y: ${ctrl.hoverCanvasPos!.dy.floor()}',
                    style:
                        TextStyle(fontSize: 10.5, color: FyrTheme.textColorMuted),
                  ),
                ],
                if (ctrl.hoverSampledColor != null) ...[
                  const SizedBox(width: 14),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: ctrl.hoverSampledColor,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: FyrTheme.dividerColor),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'RGBA(${(ctrl.hoverSampledColor!.r * 255).round()}, ${(ctrl.hoverSampledColor!.g * 255).round()}, ${(ctrl.hoverSampledColor!.b * 255).round()}, ${(ctrl.hoverSampledColor!.a * 255).round()})',
                    style:
                        TextStyle(fontSize: 10.5, color: FyrTheme.textColorMuted),
                  ),
                ],
                const Spacer(),
                if (doc.activeLayer != null)
                  Text(
                    'Layer: ${doc.activeLayer!.name}',
                    style:
                        TextStyle(fontSize: 10.5, color: FyrTheme.textColorMuted),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  MouseCursor _cursorForTool(ToolType t) {
    if (_spacePressed || t == ToolType.pan) return SystemMouseCursors.grab;
    if (t == ToolType.move) return SystemMouseCursors.move;
    if (t == ToolType.text) return SystemMouseCursors.text;
    if (t == ToolType.zoom) return SystemMouseCursors.zoomIn;
    return SystemMouseCursors.precise;
  }

  bool get _isAltPressed => HardwareKeyboard.instance.isAltPressed;

  void _onPointerDown(
    PointerDownEvent e,
    EditorController ctrl,
    GraphicsDocument doc,
    Size vpSize,
  ) {
    if ((e.buttons & kMiddleMouseButton) != 0 ||
        _spacePressed ||
        ctrl.activeTool == ToolType.pan) {
      _isMiddlePanning = true;
      _lastPanScreen = e.localPosition;
      return;
    }

    final canvasPos = _screenToCanvas(e.localPosition, vpSize, doc);
    _isDragging = true;
    ctrl.dragStartCanvas = canvasPos;
    ctrl.dragCurrentCanvas = canvasPos;

    switch (ctrl.activeTool) {
      case ToolType.brush:
      case ToolType.pencil:
      case ToolType.eraser:
        _lastStrokeCanvas = canvasPos;
        ctrl.paintStrokeSegment(
          canvasPos,
          canvasPos,
          isEraser: ctrl.activeTool == ToolType.eraser,
          isPencil: ctrl.activeTool == ToolType.pencil,
        );
        break;
      case ToolType.cloneStamp:
        if (_isAltPressed) {
          ctrl.cloneSourceAnchor = canvasPos;
          _isDragging = false;
          ctrl.setStatus(
              'Clone source set (${canvasPos.dx.round()}, ${canvasPos.dy.round()})');
        } else {
          _lastStrokeCanvas = canvasPos;
          ctrl.paintCloneSegment(canvasPos, canvasPos, isStart: true);
        }
        break;
      case ToolType.smudge:
      case ToolType.blurBrush:
        _lastStrokeCanvas = canvasPos;
        ctrl.paintBlurOrSmudgeSegment(
          canvasPos,
          canvasPos,
          smudge: ctrl.activeTool == ToolType.smudge,
        );
        break;
      case ToolType.eyedropper:
        ctrl.sampleEyedropper(canvasPos);
        break;
      case ToolType.bucket:
        _isDragging = false;
        ctrl.applyBucketFill(canvasPos);
        break;
      case ToolType.magicWand:
        _isDragging = false;
        ctrl.applyMagicWandSelection(canvasPos);
        break;
      case ToolType.lassoSelect:
        ctrl.lassoPoints = [canvasPos];
        ctrl.refresh();
        break;
      case ToolType.text:
        _isDragging = false;
        FyrDialogs.showTextLayerDialog(context, ctrl, origin: canvasPos);
        break;
      case ToolType.zoom:
        _isDragging = false;
        ctrl.zoomBy(_isAltPressed ? 0.8 : 1.25);
        break;
      case ToolType.crop:
        _cropDragCorner = _hitTestCropHandle(ctrl.activeCropRect, canvasPos, doc.zoom);
        if (_cropDragCorner == null) {
          ctrl.activeCropRect = Rect.fromPoints(canvasPos, canvasPos);
        }
        ctrl.refresh();
        break;
      default:
        break;
    }
  }

  int? _hitTestCropHandle(Rect? rect, Offset p, double zoom) {
    if (rect == null) return null;
    final tol = 14.0 / zoom;
    final corners = [
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ];
    for (int i = 0; i < 4; i++) {
      if ((corners[i] - p).distance <= tol) return i;
    }
    if (rect.contains(p)) return 4;
    return null;
  }

  void _onPointerMove(
    PointerMoveEvent e,
    EditorController ctrl,
    GraphicsDocument doc,
    Size vpSize,
  ) {
    final canvasPos = _screenToCanvas(e.localPosition, vpSize, doc);
    ctrl.setHoverPosition(canvasPos);

    if (_isMiddlePanning && _lastPanScreen != null) {
      ctrl.panBy(e.localPosition - _lastPanScreen!);
      _lastPanScreen = e.localPosition;
      return;
    }
    if (!_isDragging) return;

    final prev = ctrl.dragCurrentCanvas ?? canvasPos;
    ctrl.dragCurrentCanvas = canvasPos;

    switch (ctrl.activeTool) {
      case ToolType.move:
        ctrl.moveActiveLayerBy(canvasPos - prev);
        break;
      case ToolType.brush:
      case ToolType.pencil:
      case ToolType.eraser:
        ctrl.paintStrokeSegment(
          _lastStrokeCanvas ?? prev,
          canvasPos,
          isEraser: ctrl.activeTool == ToolType.eraser,
          isPencil: ctrl.activeTool == ToolType.pencil,
        );
        _lastStrokeCanvas = canvasPos;
        break;
      case ToolType.cloneStamp:
        ctrl.paintCloneSegment(_lastStrokeCanvas ?? prev, canvasPos,
            isStart: false);
        _lastStrokeCanvas = canvasPos;
        break;
      case ToolType.smudge:
      case ToolType.blurBrush:
        ctrl.paintBlurOrSmudgeSegment(
          _lastStrokeCanvas ?? prev,
          canvasPos,
          smudge: ctrl.activeTool == ToolType.smudge,
        );
        _lastStrokeCanvas = canvasPos;
        break;
      case ToolType.eyedropper:
        ctrl.sampleEyedropper(canvasPos);
        break;
      case ToolType.lassoSelect:
        ctrl.lassoPoints.add(canvasPos);
        ctrl.refresh();
        break;
      case ToolType.crop:
        final r = ctrl.activeCropRect;
        if (r != null && _cropDragCorner != null) {
          final dx = canvasPos.dx - prev.dx;
          final dy = canvasPos.dy - prev.dy;
          switch (_cropDragCorner) {
            case 0:
              ctrl.activeCropRect = Rect.fromLTRB(
                min(r.right - 4, canvasPos.dx),
                min(r.bottom - 4, canvasPos.dy),
                r.right,
                r.bottom,
              );
              break;
            case 1:
              ctrl.activeCropRect = Rect.fromLTRB(
                r.left,
                min(r.bottom - 4, canvasPos.dy),
                max(r.left + 4, canvasPos.dx),
                r.bottom,
              );
              break;
            case 2:
              ctrl.activeCropRect = Rect.fromLTRB(
                r.left,
                r.top,
                max(r.left + 4, canvasPos.dx),
                max(r.top + 4, canvasPos.dy),
              );
              break;
            case 3:
              ctrl.activeCropRect = Rect.fromLTRB(
                min(r.right - 4, canvasPos.dx),
                r.top,
                r.right,
                max(r.top + 4, canvasPos.dy),
              );
              break;
            case 4:
              ctrl.activeCropRect = r.shift(Offset(dx, dy));
              break;
          }
        } else if (ctrl.dragStartCanvas != null) {
          ctrl.activeCropRect =
              Rect.fromPoints(ctrl.dragStartCanvas!, canvasPos);
        }
        ctrl.refresh();
        break;
      default:
        ctrl.refresh();
        break;
    }
  }

  Future<void> _onPointerUp(
    PointerUpEvent e,
    EditorController ctrl,
    GraphicsDocument doc,
    Size vpSize,
  ) async {
    if (_isMiddlePanning) {
      _isMiddlePanning = false;
      _lastPanScreen = null;
      return;
    }
    if (!_isDragging) return;
    _isDragging = false;

    final start = ctrl.dragStartCanvas;
    final end = ctrl.dragCurrentCanvas;
    ctrl.dragStartCanvas = null;
    ctrl.dragCurrentCanvas = null;
    _lastStrokeCanvas = null;
    _cropDragCorner = null;

    switch (ctrl.activeTool) {
      case ToolType.move:
        ctrl.commitMoveLayer();
        break;
      case ToolType.brush:
        await ctrl.commitStrokeHistory('Brush Stroke');
        break;
      case ToolType.pencil:
        await ctrl.commitStrokeHistory('Pencil Stroke');
        break;
      case ToolType.eraser:
        await ctrl.commitStrokeHistory('Eraser');
        break;
      case ToolType.cloneStamp:
        await ctrl.commitStrokeHistory('Clone Stamp');
        break;
      case ToolType.smudge:
        await ctrl.commitStrokeHistory('Smudge');
        break;
      case ToolType.blurBrush:
        await ctrl.commitStrokeHistory('Blur Brush');
        break;
      case ToolType.rectSelect:
        if (start != null && end != null) {
          ctrl.applyRectSelection(Rect.fromPoints(start, end));
        }
        break;
      case ToolType.ellipseSelect:
        if (start != null && end != null) {
          ctrl.applyEllipseSelection(Rect.fromPoints(start, end));
        }
        break;
      case ToolType.lassoSelect:
        final pts = List<Offset>.from(ctrl.lassoPoints);
        ctrl.lassoPoints.clear();
        ctrl.applyLassoSelection(pts);
        break;
      case ToolType.gradient:
        if (start != null && end != null) {
          await ctrl.applyGradientDrag(start, end);
        }
        break;
      case ToolType.shape:
        if (start != null && end != null) {
          await ctrl.applyShapeDrag(start, end);
        }
        break;
      default:
        ctrl.refresh();
        break;
    }
  }
}

class _CanvasPainter extends CustomPainter {
  final GraphicsDocument doc;
  final EditorController ctrl;
  final double antsPhase;

  _CanvasPainter({
    required this.doc,
    required this.ctrl,
    required this.antsPhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.save();
    canvas.translate(center.dx + doc.panOffset.dx, center.dy + doc.panOffset.dy);
    canvas.scale(doc.zoom);
    canvas.translate(-doc.width / 2.0, -doc.height / 2.0);

    final docRect = Rect.fromLTWH(0, 0, doc.width.toDouble(), doc.height.toDouble());

    // Drop shadow behind artboard
    canvas.drawRect(
      docRect,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 14 / doc.zoom),
    );

    // Transparency Checkerboard
    canvas.save();
    canvas.clipRect(docRect);
    _drawCheckerboard(canvas, docRect, doc.zoom);

    // Layers composited in order
    for (final layer in doc.layers) {
      if (!layer.visible || layer.opacity <= 0.0) continue;
      final img = layer.cachedImage;
      if (img == null) continue;
      final paint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, layer.opacity)
        ..blendMode = layer.blendMode.uiBlendMode
        ..filterQuality =
            doc.zoom >= 2.0 ? FilterQuality.none : FilterQuality.medium;
      canvas.drawImage(img, Offset(layer.offsetX, layer.offsetY), paint);
    }

    // Pixel Grid at high zoom
    if (doc.showGrid && doc.zoom >= 4.0) {
      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.14)
        ..strokeWidth = 1.0 / doc.zoom;
      for (int x = 1; x < doc.width; x++) {
        canvas.drawLine(
            Offset(x.toDouble(), 0), Offset(x.toDouble(), doc.height.toDouble()), gridPaint);
      }
      for (int y = 1; y < doc.height; y++) {
        canvas.drawLine(
            Offset(0, y.toDouble()), Offset(doc.width.toDouble(), y.toDouble()), gridPaint);
      }
    }

    canvas.restore();

    // Crisp artboard border
    canvas.drawRect(
      docRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 / doc.zoom,
    );

    // Marching Ants Selection
    if (doc.selection.hasSelection && doc.selection.outlinePath != null) {
      _drawMarchingAnts(canvas, doc.selection.outlinePath!, doc.zoom, antsPhase);
    }

    // Active Tool Drag Overlays
    _drawActiveOverlays(canvas);

    canvas.restore();
  }

  void _drawCheckerboard(Canvas canvas, Rect rect, double zoom) {
    final cell = max(8.0, 12.0 / min(1.0, zoom));
    canvas.drawRect(rect, Paint()..color = const Color(0xFF202024));
    final lightPaint = Paint()..color = const Color(0xFF2C2C32);
    final cols = (rect.width / cell).ceil();
    final rows = (rect.height / cell).ceil();
    final path = Path();
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        if ((r + c).isOdd) {
          path.addRect(Rect.fromLTWH(c * cell, r * cell, cell, cell));
        }
      }
    }
    canvas.drawPath(path, lightPaint);
  }

  void _drawMarchingAnts(
      Canvas canvas, ui.Path outline, double zoom, double phase) {
    final sw = 1.2 / zoom;
    canvas.drawPath(
      outline,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw,
    );
    final dashLen = 6.0 / zoom;
    final dashed = _dashPath(outline, dashLen, dashLen, phase * dashLen * 2);
    canvas.drawPath(
      dashed,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = sw,
    );
  }

  ui.Path _dashPath(ui.Path source, double dash, double gap, double offset) {
    final out = ui.Path();
    for (final metric in source.computeMetrics()) {
      double dist = -(offset % (dash + gap));
      while (dist < metric.length) {
        final s = max(0.0, dist);
        final e = min(metric.length, dist + dash);
        if (e > s) {
          out.addPath(metric.extractPath(s, e), Offset.zero);
        }
        dist += dash + gap;
      }
    }
    return out;
  }

  void _drawActiveOverlays(Canvas canvas) {
    final start = ctrl.dragStartCanvas;
    final curr = ctrl.dragCurrentCanvas;
    final sw = 1.4 / doc.zoom;

    if (start != null && curr != null) {
      if (ctrl.activeTool == ToolType.rectSelect) {
        canvas.drawRect(
          Rect.fromPoints(start, curr),
          Paint()
            ..color = FyrTheme.accentColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = sw,
        );
      } else if (ctrl.activeTool == ToolType.ellipseSelect) {
        canvas.drawOval(
          Rect.fromPoints(start, curr),
          Paint()
            ..color = FyrTheme.accentColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = sw,
        );
      } else if (ctrl.activeTool == ToolType.gradient) {
        canvas.drawLine(
          start,
          curr,
          Paint()
            ..color = Colors.white
            ..strokeWidth = sw * 1.5,
        );
        canvas.drawCircle(start, 4 / doc.zoom, Paint()..color = ctrl.foregroundColor);
        canvas.drawCircle(curr, 4 / doc.zoom, Paint()..color = ctrl.backgroundColor);
      } else if (ctrl.activeTool == ToolType.shape) {
        final previewPaint = Paint()
          ..color = FyrTheme.accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw;
        final rect = Rect.fromPoints(start, curr);
        if (ctrl.shapeKind == ShapeKind.ellipse) {
          canvas.drawOval(rect, previewPaint);
        } else if (ctrl.shapeKind == ShapeKind.line ||
            ctrl.shapeKind == ShapeKind.arrow) {
          canvas.drawLine(start, curr, previewPaint);
        } else {
          canvas.drawRect(rect, previewPaint);
        }
      }
    }

    if (ctrl.activeTool == ToolType.lassoSelect && ctrl.lassoPoints.length > 1) {
      final path = Path()
        ..moveTo(ctrl.lassoPoints.first.dx, ctrl.lassoPoints.first.dy);
      for (final p in ctrl.lassoPoints.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = FyrTheme.accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw,
      );
    }

    // Crop Overlay
    if (ctrl.activeTool == ToolType.crop && ctrl.activeCropRect != null) {
      final cr = ctrl.activeCropRect!;
      final full = Rect.fromLTWH(0, 0, doc.width.toDouble(), doc.height.toDouble());
      final dimPath = Path.combine(
        PathOperation.difference,
        Path()..addRect(full),
        Path()..addRect(cr),
      );
      canvas.drawPath(
        dimPath,
        Paint()..color = Colors.black.withValues(alpha: 0.55),
      );
      canvas.drawRect(
        cr,
        Paint()
          ..color = FyrTheme.accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 / doc.zoom,
      );
      final hs = 5.0 / doc.zoom;
      for (final c in [cr.topLeft, cr.topRight, cr.bottomRight, cr.bottomLeft]) {
        canvas.drawRect(
          Rect.fromCenter(center: c, width: hs * 2, height: hs * 2),
          Paint()..color = Colors.white,
        );
      }
    }

    // Clone source crosshair
    if (ctrl.activeTool == ToolType.cloneStamp &&
        ctrl.cloneSourceAnchor != null) {
      final p = ctrl.cloneSourceAnchor!;
      final s = 8.0 / doc.zoom;
      final cp = Paint()
        ..color = FyrTheme.accentColor
        ..strokeWidth = 1.4 / doc.zoom;
      canvas.drawLine(Offset(p.dx - s, p.dy), Offset(p.dx + s, p.dy), cp);
      canvas.drawLine(Offset(p.dx, p.dy - s), Offset(p.dx, p.dy + s), cp);
      canvas.drawCircle(p, s * 0.7, cp..style = PaintingStyle.stroke);
    }

    // Brush / Eraser cursor ring
    final hp = ctrl.hoverCanvasPos;
    if (hp != null &&
        (ctrl.activeTool == ToolType.brush ||
            ctrl.activeTool == ToolType.pencil ||
            ctrl.activeTool == ToolType.eraser ||
            ctrl.activeTool == ToolType.cloneStamp ||
            ctrl.activeTool == ToolType.smudge ||
            ctrl.activeTool == ToolType.blurBrush)) {
      final rad = (ctrl.activeTool == ToolType.eraser
              ? ctrl.eraserSize
              : ctrl.brushSize) /
          2.0;
      canvas.drawCircle(
        hp,
        rad,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1 / doc.zoom,
      );
      canvas.drawCircle(
        hp,
        rad,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.6 / doc.zoom,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}

class _RulerPainter extends CustomPainter {
  final bool horizontal;
  final GraphicsDocument doc;
  final Size viewportSize;
  final Color textColor;
  final Color bgColor;
  final Color borderColor;

  _RulerPainter({
    required this.horizontal,
    required this.doc,
    required this.viewportSize,
    required this.textColor,
    required this.bgColor,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bgColor);
    final tickPaint = Paint()
      ..color = textColor.withValues(alpha: 0.45)
      ..strokeWidth = 1;

    final step = _pickStep(doc.zoom);
    final center = horizontal ? viewportSize.width / 2 : viewportSize.height / 2;
    final pan = horizontal ? doc.panOffset.dx : doc.panOffset.dy;
    final dim = horizontal ? doc.width : doc.height;

    final startPx = ((0 - center - pan) / doc.zoom + dim / 2);
    final endPx =
        (((horizontal ? size.width : size.height) - center - pan) / doc.zoom +
            dim / 2);

    final firstTick = (startPx / step).floor() * step;
    for (double v = firstTick; v <= endPx; v += step) {
      final screen = center + pan + (v - dim / 2) * doc.zoom;
      if (horizontal) {
        canvas.drawLine(Offset(screen, size.height - 6),
            Offset(screen, size.height), tickPaint);
        final tp = TextPainter(
          text: TextSpan(
            text: v.round().toString(),
            style: TextStyle(fontSize: 8.5, color: textColor),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(screen + 2, 2));
      } else {
        canvas.drawLine(Offset(size.width - 6, screen),
            Offset(size.width, screen), tickPaint);
        final tp = TextPainter(
          text: TextSpan(
            text: v.round().toString(),
            style: TextStyle(fontSize: 8.5, color: textColor),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(2, screen + 2));
      }
    }

    canvas.drawLine(
      horizontal ? Offset(0, size.height) : Offset(size.width, 0),
      Offset(size.width, size.height),
      Paint()..color = borderColor,
    );
  }

  double _pickStep(double zoom) {
    final targetScreenPx = 70.0;
    final raw = targetScreenPx / zoom;
    for (final s in [10.0, 25.0, 50.0, 100.0, 200.0, 500.0, 1000.0]) {
      if (s >= raw) return s;
    }
    return 1000.0;
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) => true;
}
