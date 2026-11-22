import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/design_models.dart';
import '../state/devign_controller.dart';

class DesignCanvas extends StatefulWidget {
  const DesignCanvas({super.key});

  @override
  State<DesignCanvas> createState() => DesignCanvasState();
}

class DesignCanvasState extends State<DesignCanvas> {
  Size _viewportSize = const Size(900, 650);
  bool _spacePressed = false;
  bool _isPanning = false;
  Offset? _lastPanScreen;

  // Drag states
  String? _dragMode; // 'move', 'create', 'marquee', 'handle_0..7', 'rotate', 'pen_drag'
  Offset? _dragStartCanvas;
  Offset? _dragLastCanvas;
  Rect? _creationRect;
  Rect? _marqueeRect;
  double? _initialRotation;
  Offset? _rotationCenter;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent e) {
    if (e.logicalKey == LogicalKeyboardKey.space) {
      final down = e is KeyDownEvent || e is KeyRepeatEvent;
      if (_spacePressed != down && mounted) {
        setState(() => _spacePressed = down);
      }
    }
    return false;
  }

  void zoomToFit() {
    context.read<DevignController>().zoomToFit(_viewportSize);
  }

  Offset _screenToCanvas(Offset screen, DevignController ctrl) {
    final center = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    return (screen - center - ctrl.activePage.pan) / ctrl.activePage.zoom;
  }

  int? _hitTestHandle(Rect bounds, Offset canvasPos, double zoom) {
    final tol = 9.0 / zoom;
    final pts = _handleOffsets(bounds);
    for (int i = 0; i < pts.length; i++) {
      if ((pts[i] - canvasPos).distance <= tol) return i;
    }
    // Rotation knob above top center
    final rotPt = Offset(bounds.center.dx, bounds.top - 22.0 / zoom);
    if ((rotPt - canvasPos).distance <= tol) return 8;
    return null;
  }

  static List<Offset> _handleOffsets(Rect r) => [
        r.topLeft,
        r.topCenter,
        r.topRight,
        r.centerRight,
        r.bottomRight,
        r.bottomCenter,
        r.bottomLeft,
        r.centerLeft,
      ];

  void _onPointerDown(PointerDownEvent e, DevignController ctrl) {
    if ((e.buttons & kMiddleMouseButton) != 0 ||
        _spacePressed ||
        ctrl.activeTool == DevignTool.hand) {
      _isPanning = true;
      _lastPanScreen = e.localPosition;
      return;
    }

    final pos = _screenToCanvas(e.localPosition, ctrl);
    _dragStartCanvas = pos;
    _dragLastCanvas = pos;

    if (ctrl.activeTool == DevignTool.pen) {
      ctrl.addPenPoint(pos);
      _dragMode = 'pen_drag';
      return;
    }

    if (ctrl.activeTool == DevignTool.comment) {
      _promptComment(ctrl, pos);
      return;
    }

    if (ctrl.activeTool == DevignTool.text) {
      final node = ctrl.createNode(
        type: NodeType.text,
        canvasRect: Rect.fromLTWH(pos.dx, pos.dy, 220, 40),
        text: 'New Text',
      );
      ctrl.setTool(DevignTool.select);
      _promptEditText(ctrl, node);
      return;
    }

    if (ctrl.activeTool != DevignTool.select) {
      _dragMode = 'create';
      _creationRect = Rect.fromPoints(pos, pos);
      setState(() {});
      return;
    }

    // Check resize / rotate handles first when a single node is selected
    if (ctrl.selectedIds.length == 1) {
      final selBounds = ctrl.getSelectionBounds();
      if (selBounds != null) {
        final h = _hitTestHandle(selBounds, pos, ctrl.activePage.zoom);
        if (h != null) {
          if (h == 8) {
            _dragMode = 'rotate';
            _rotationCenter = selBounds.center;
            _initialRotation = ctrl.primarySelected?.rotationDeg ?? 0;
          } else {
            _dragMode = 'handle_$h';
          }
          return;
        }
      }
    }

    // Check frame header title click
    for (final fid in ctrl.activePage.rootIds.reversed) {
      final fn = ctrl.nodes[fid];
      if (fn == null || (fn.type != NodeType.frame && fn.type != NodeType.component)) {
        continue;
      }
      final labelRect = Rect.fromLTWH(
        fn.x,
        fn.y - 24 / ctrl.activePage.zoom,
        min(fn.width, 220 / ctrl.activePage.zoom),
        22 / ctrl.activePage.zoom,
      );
      if (labelRect.contains(pos)) {
        ctrl.selectNode(fid, additive: HardwareKeyboard.instance.isShiftPressed);
        _dragMode = 'move';
        return;
      }
    }

    final hitId = ctrl.hitTest(pos);
    if (hitId != null) {
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      if (!ctrl.selectedIds.contains(hitId) || isShift) {
        ctrl.selectNode(hitId, additive: isShift);
      }
      _dragMode = 'move';
    } else {
      ctrl.selectNode(null);
      _dragMode = 'marquee';
      _marqueeRect = Rect.fromPoints(pos, pos);
      setState(() {});
    }
  }

  void _onPointerMove(PointerMoveEvent e, DevignController ctrl) {
    final pos = _screenToCanvas(e.localPosition, ctrl);

    if (_isPanning && _lastPanScreen != null) {
      ctrl.panBy(e.localPosition - _lastPanScreen!);
      _lastPanScreen = e.localPosition;
      return;
    }

    if (_dragMode == null || _dragStartCanvas == null) return;
    final prev = _dragLastCanvas ?? pos;
    _dragLastCanvas = pos;

    if (_dragMode == 'pen_drag') {
      ctrl.updateLastPenHandle(pos - _dragStartCanvas!);
      return;
    }

    if (_dragMode == 'move') {
      ctrl.moveSelectedBy(pos - prev);
      return;
    }

    if (_dragMode == 'create') {
      var r = Rect.fromPoints(_dragStartCanvas!, pos);
      if (HardwareKeyboard.instance.isShiftPressed) {
        final s = max(r.width, r.height);
        r = Rect.fromLTWH(
          pos.dx >= _dragStartCanvas!.dx ? _dragStartCanvas!.dx : _dragStartCanvas!.dx - s,
          pos.dy >= _dragStartCanvas!.dy ? _dragStartCanvas!.dy : _dragStartCanvas!.dy - s,
          s,
          s,
        );
      }
      setState(() => _creationRect = r);
      return;
    }

    if (_dragMode == 'marquee') {
      setState(() => _marqueeRect = Rect.fromPoints(_dragStartCanvas!, pos));
      return;
    }

    if (_dragMode == 'rotate' && _rotationCenter != null) {
      final startA = atan2(
        _dragStartCanvas!.dy - _rotationCenter!.dy,
        _dragStartCanvas!.dx - _rotationCenter!.dx,
      );
      final curA = atan2(
        pos.dy - _rotationCenter!.dy,
        pos.dx - _rotationCenter!.dx,
      );
      var deg = (_initialRotation ?? 0) + (curA - startA) * 180 / pi;
      if (HardwareKeyboard.instance.isShiftPressed) {
        deg = (deg / 15).round() * 15.0;
      }
      ctrl.mutateSelected((n) => n.rotationDeg = deg);
      return;
    }

    if (_dragMode!.startsWith('handle_')) {
      final handleIdx = int.tryParse(_dragMode!.substring(7)) ?? 4;
      final n = ctrl.primarySelected;
      if (n == null || n.locked) return;
      final dx = pos.dx - prev.dx;
      final dy = pos.dy - prev.dy;
      ctrl.mutateSelected((node) {
        switch (handleIdx) {
          case 0: // TL
            final nw = max(8.0, node.width - dx);
            final nh = max(8.0, node.height - dy);
            node.x += (node.width - nw);
            node.y += (node.height - nh);
            node.width = nw;
            node.height = nh;
            break;
          case 1: // TC
            final nh = max(8.0, node.height - dy);
            node.y += (node.height - nh);
            node.height = nh;
            break;
          case 2: // TR
            final nh = max(8.0, node.height - dy);
            node.y += (node.height - nh);
            node.width = max(8.0, node.width + dx);
            node.height = nh;
            break;
          case 3: // MR
            node.width = max(8.0, node.width + dx);
            break;
          case 4: // BR
            node.width = max(8.0, node.width + dx);
            node.height = max(8.0, node.height + dy);
            break;
          case 5: // BC
            node.height = max(8.0, node.height + dy);
            break;
          case 6: // BL
            final nw = max(8.0, node.width - dx);
            node.x += (node.width - nw);
            node.width = nw;
            node.height = max(8.0, node.height + dy);
            break;
          case 7: // ML
            final nw = max(8.0, node.width - dx);
            node.x += (node.width - nw);
            node.width = nw;
            break;
        }
      });
    }
  }

  void _onPointerUp(PointerUpEvent e, DevignController ctrl) {
    if (_isPanning) {
      _isPanning = false;
      _lastPanScreen = null;
      return;
    }

    final mode = _dragMode;
    _dragMode = null;
    _dragStartCanvas = null;
    _dragLastCanvas = null;

    if (mode == 'move' || mode == 'rotate' || (mode?.startsWith('handle_') ?? false)) {
      ctrl.commitTransform();
    } else if (mode == 'marquee' && _marqueeRect != null) {
      ctrl.selectInMarquee(_marqueeRect!);
      setState(() => _marqueeRect = null);
    } else if (mode == 'create' && _creationRect != null) {
      final r = _creationRect!;
      setState(() => _creationRect = null);
      final finalRect = r.width < 6 && r.height < 6
          ? Rect.fromLTWH(r.left, r.top, 140, 100)
          : r;
      final nodeType = switch (ctrl.activeTool) {
        DevignTool.frame => NodeType.frame,
        DevignTool.rectangle => NodeType.rectangle,
        DevignTool.ellipse => NodeType.ellipse,
        DevignTool.polygon => NodeType.polygon,
        DevignTool.star => NodeType.star,
        DevignTool.line => NodeType.line,
        DevignTool.arrow => NodeType.arrow,
        _ => NodeType.rectangle,
      };
      ctrl.createNode(type: nodeType, canvasRect: finalRect);
      ctrl.setTool(DevignTool.select);
    }
  }

  Future<void> _promptEditText(DevignController ctrl, DesignNode node) async {
    final tc = TextEditingController(text: node.text);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: const Text('Edit Text Layer', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: tc,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, tc.text),
              child: const Text('Apply')),
        ],
      ),
    );
    if (res != null) {
      ctrl.mutateSelected((n) => n.text = res, commit: true);
    }
  }

  Future<void> _promptComment(DevignController ctrl, Offset canvasPos) async {
    final tc = TextEditingController();
    final msg = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: const Text('Add Design Comment', style: TextStyle(fontSize: 15)),
        content: TextField(
          controller: tc,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Leave feedback for teammates...',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, tc.text),
              child: const Text('Post')),
        ],
      ),
    );
    if (msg != null && msg.trim().isNotEmpty) {
      ctrl.addComment(canvasPos, msg);
      ctrl.setTool(DevignTool.select);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DevignController>();
    final page = ctrl.activePage;

    return Expanded(
      child: LayoutBuilder(
        builder: (context, constraints) {
          _viewportSize = constraints.biggest;

          return MouseRegion(
            cursor: _spacePressed || ctrl.activeTool == DevignTool.hand
                ? SystemMouseCursors.grab
                : (ctrl.activeTool == DevignTool.select
                    ? SystemMouseCursors.basic
                    : SystemMouseCursors.precise),
            onHover: (e) {
              final p = _screenToCanvas(e.localPosition, ctrl);
              if (ctrl.activeTool == DevignTool.pen) {
                ctrl.penCursorCanvas = p;
                ctrl.refresh();
              } else {
                final h = ctrl.hitTest(p);
                if (h != ctrl.hoveredId) {
                  ctrl.hoveredId = h;
                  ctrl.refresh();
                }
              }
            },
            child: GestureDetector(
              onDoubleTapDown: (d) {
                final pos = _screenToCanvas(d.localPosition, ctrl);
                final hit = ctrl.hitTest(pos);
                if (hit != null && ctrl.nodes[hit]?.type == NodeType.text) {
                  ctrl.selectNode(hit);
                  _promptEditText(ctrl, ctrl.nodes[hit]!);
                }
              },
              child: Listener(
                onPointerSignal: (sig) {
                  if (sig is PointerScrollEvent) {
                    if (HardwareKeyboard.instance.isControlPressed ||
                        HardwareKeyboard.instance.isMetaPressed) {
                      final factor = sig.scrollDelta.dy < 0 ? 1.12 : 0.89;
                      final before = _screenToCanvas(sig.localPosition, ctrl);
                      final nz = (page.zoom * factor).clamp(0.1, 16.0);
                      final center = Offset(
                          _viewportSize.width / 2, _viewportSize.height / 2);
                      final newPan = sig.localPosition - center - before * nz;
                      ctrl.setZoom(nz, pan: newPan);
                    } else {
                      ctrl.panBy(-sig.scrollDelta);
                    }
                  }
                },
                onPointerDown: (e) => _onPointerDown(e, ctrl),
                onPointerMove: (e) => _onPointerMove(e, ctrl),
                onPointerUp: (e) => _onPointerUp(e, ctrl),
                child: ClipRect(
                  child: Stack(
                    children: [
                      ColoredBox(
                        color: FyrTheme.isDark
                            ? const Color(0xFF0A0A0D)
                            : const Color(0xFFE7E7EC),
                        child: CustomPaint(
                          size: _viewportSize,
                          painter: DevignCanvasPainter(
                            ctrl: ctrl,
                            creationRect: _creationRect,
                            marqueeRect: _marqueeRect,
                            showPrototypeLinks: ctrl.rightPanelTab == 1,
                          ),
                        ),
                      ),
                      // Comment pins overlay
                      if (ctrl.showComments)
                        ...page.comments.where((c) => !c.resolved).map((c) {
                          final screen = Offset(
                                _viewportSize.width / 2,
                                _viewportSize.height / 2,
                              ) +
                              page.pan +
                              c.position * page.zoom;
                          return Positioned(
                            left: screen.dx - 12,
                            top: screen.dy - 24,
                            child: Tooltip(
                              message: '${c.author}: ${c.message}\n(Click to resolve)',
                              child: GestureDetector(
                                onTap: () => ctrl.toggleCommentResolved(c.id),
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: FyrTheme.accentColor,
                                    borderRadius: const BorderRadius.only(
                                      topLeft: Radius.circular(12),
                                      topRight: Radius.circular(12),
                                      bottomRight: Radius.circular(12),
                                      bottomLeft: Radius.circular(3),
                                    ),
                                    border: Border.all(
                                        color: Colors.white, width: 1.5),
                                    boxShadow: const [
                                      BoxShadow(
                                          color: Colors.black45, blurRadius: 6),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.chat_bubble_rounded,
                                    size: 11,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                      // Pen tool floating hint pill
                      if (ctrl.activeTool == DevignTool.pen)
                        Positioned(
                          bottom: 18,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 7),
                              decoration: BoxDecoration(
                                color: FyrTheme.surfaceColor.withValues(alpha: 0.94),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: FyrTheme.accentColor),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Pen Tool: Click to place point • Drag for curves • Click first point to close',
                                    style: TextStyle(fontSize: 11.5),
                                  ),
                                  const SizedBox(width: 10),
                                  FilledButton(
                                    style: FilledButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 0),
                                      minimumSize: const Size(0, 24),
                                    ),
                                    onPressed: () =>
                                        ctrl.finishPenPath(closed: false),
                                    child: const Text('Done',
                                        style: TextStyle(fontSize: 11)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class DevignCanvasPainter extends CustomPainter {
  final DevignController ctrl;
  final Rect? creationRect;
  final Rect? marqueeRect;
  final bool showPrototypeLinks;

  DevignCanvasPainter({
    required this.ctrl,
    this.creationRect,
    this.marqueeRect,
    this.showPrototypeLinks = false,
  });

  static void paintNodeSubtree(
    Canvas canvas,
    DesignNode node,
    Map<String, DesignNode> nodes,
    Map<String, ui.Image> imageCache, {
    bool drawFrameLabel = true,
    double zoom = 1.0,
    bool isFlowStart = false,
  }) {
    if (!node.visible || node.opacity <= 0) return;

    canvas.save();
    canvas.translate(node.x, node.y);
    if (node.rotationDeg.abs() > 0.01) {
      canvas.translate(node.width / 2, node.height / 2);
      canvas.rotate(node.rotationDeg * pi / 180.0);
      canvas.translate(-node.width / 2, -node.height / 2);
    }

    final rect = Rect.fromLTWH(0, 0, node.width, node.height);
    final rrect = node.toRRect(rect);

    // Frame / Component header title
    if (drawFrameLabel &&
        node.parentId == null &&
        (node.type == NodeType.frame || node.type == NodeType.component)) {
      final isComp = node.type == NodeType.component;
      final labelColor = isComp ? const Color(0xFFBB86FC) : Colors.grey.shade400;
      final tp = TextPainter(
        text: TextSpan(
          text: isFlowStart ? '▶ ${node.name}' : node.name,
          style: TextStyle(
            fontSize: (12.0 / zoom).clamp(8.0, 28.0),
            fontWeight: FontWeight.w600,
            color: isFlowStart ? const Color(0xFF40C4FF) : labelColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, -tp.height - 6.0 / zoom));
    }

    if (node.opacity < 0.999 || node.blendMode != ui.BlendMode.srcOver) {
      canvas.saveLayer(
        rect.inflate(80),
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, node.opacity)
          ..blendMode = node.blendMode,
      );
    }

    // Drop Shadows
    for (final eff in node.effects) {
      if (!eff.visible || eff.kind != EffectKind.dropShadow) continue;
      final shadowPaint = Paint()
        ..color = eff.color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, max(0.5, eff.blurRadius / 2));
      final sRect = rect.shift(Offset(eff.offsetX, eff.offsetY)).inflate(eff.spread);
      if (node.type == NodeType.ellipse) {
        canvas.drawOval(sRect, shadowPaint);
      } else {
        canvas.drawRRect(node.toRRect(sRect), shadowPaint);
      }
    }

    // Layer blur wrapper
    final layerBlur = node.effects
        .where((e) => e.visible && e.kind == EffectKind.layerBlur)
        .fold<double>(0.0, (a, e) => max(a, e.blurRadius));
    if (layerBlur > 0.1) {
      canvas.saveLayer(
        rect.inflate(layerBlur * 2),
        Paint()
          ..imageFilter =
              ui.ImageFilter.blur(sigmaX: layerBlur / 2, sigmaY: layerBlur / 2),
      );
    }

    // Paint Shape Geometry
    _paintNodeGeometry(canvas, node, rect, rrect, imageCache);

    // Children
    if (node.children.isNotEmpty) {
      if (node.clipContent) {
        canvas.save();
        canvas.clipRRect(rrect);
      }
      for (final cid in node.children) {
        final child = nodes[cid];
        if (child != null) {
          paintNodeSubtree(
            canvas,
            child,
            nodes,
            imageCache,
            drawFrameLabel: false,
            zoom: zoom,
          );
        }
      }
      if (node.clipContent) {
        canvas.restore();
      }
    }

    if (layerBlur > 0.1) canvas.restore();
    if (node.opacity < 0.999 || node.blendMode != ui.BlendMode.srcOver) {
      canvas.restore();
    }
    canvas.restore();
  }

  static void _paintNodeGeometry(
    Canvas canvas,
    DesignNode node,
    Rect rect,
    RRect rrect,
    Map<String, ui.Image> imageCache,
  ) {
    if (node.type == NodeType.text) {
      final fillColor = node.fills.where((f) => f.visible).isNotEmpty
          ? node.fills
              .where((f) => f.visible)
              .last
              .color
              .withValues(alpha: node.fills.where((f) => f.visible).last.opacity)
          : Colors.white;
      final tp = TextPainter(
        text: TextSpan(
          text: node.text,
          style: TextStyle(
            fontFamily: node.fontFamily,
            fontSize: node.fontSize,
            fontWeight: node.fontWeight,
            fontStyle: node.italic ? FontStyle.italic : FontStyle.normal,
            letterSpacing: node.letterSpacing,
            height: node.lineHeight,
            color: fillColor,
          ),
        ),
        textAlign: node.textAlign,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: rect.width, maxWidth: max(1, rect.width));
      tp.paint(canvas, Offset.zero);
      return;
    }

    if (node.type == NodeType.image && node.imagePath != null) {
      final img = imageCache[node.imagePath!];
      canvas.save();
      canvas.clipRRect(rrect);
      if (img != null) {
        paintImage(
          canvas: canvas,
          rect: rect,
          image: img,
          fit: BoxFit.cover,
        );
      } else {
        canvas.drawRect(rect, Paint()..color = const Color(0xFF24242E));
      }
      canvas.restore();
    }

    final shapePath = _buildPathForNode(node, rect, rrect);

    // Fills
    for (final f in node.fills) {
      if (!f.visible || f.opacity <= 0) continue;
      final p = Paint()..style = PaintingStyle.fill;
      if (f.kind == FillKind.solid) {
        p.color = f.color.withValues(alpha: (f.color.a * f.opacity).clamp(0, 1));
      } else if (f.kind == FillKind.linearGradient) {
        final rad = f.gradientAngleDeg * pi / 180.0;
        final dx = cos(rad);
        final dy = sin(rad);
        p.shader = ui.Gradient.linear(
          rect.center - Offset(dx * rect.width / 2, dy * rect.height / 2),
          rect.center + Offset(dx * rect.width / 2, dy * rect.height / 2),
          [
            f.color.withValues(alpha: f.opacity),
            f.secondaryColor.withValues(alpha: f.opacity),
          ],
        );
      } else {
        p.shader = ui.Gradient.radial(
          rect.center,
          max(rect.width, rect.height) * 0.6,
          [
            f.color.withValues(alpha: f.opacity),
            f.secondaryColor.withValues(alpha: f.opacity),
          ],
        );
      }
      if (node.type == NodeType.path && !node.pathClosed) continue;
      if (node.type != NodeType.line && node.type != NodeType.arrow) {
        canvas.drawPath(shapePath, p);
      }
    }

    // Strokes
    for (final s in node.strokes) {
      if (!s.visible || s.width <= 0) continue;
      final sp = Paint()
        ..color = s.color.withValues(alpha: (s.color.a * s.opacity).clamp(0, 1))
        ..style = PaintingStyle.stroke
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final drawPath = s.dashed
          ? _dashPath(shapePath, s.dashLength, s.dashLength)
          : shapePath;
      canvas.drawPath(drawPath, sp);

      if (node.type == NodeType.arrow) {
        final end = Offset(rect.width, rect.height);
        final ang = atan2(rect.height, rect.width);
        final len = max(10.0, s.width * 4);
        final head = Path()
          ..moveTo(end.dx - len * cos(ang - 0.5), end.dy - len * sin(ang - 0.5))
          ..lineTo(end.dx, end.dy)
          ..lineTo(end.dx - len * cos(ang + 0.5), end.dy - len * sin(ang + 0.5));
        canvas.drawPath(head, sp);
      }
    }
  }

  static Path _buildPathForNode(DesignNode n, Rect rect, RRect rrect) {
    switch (n.type) {
      case NodeType.ellipse:
        return Path()..addOval(rect);
      case NodeType.line:
      case NodeType.arrow:
        return Path()
          ..moveTo(0, 0)
          ..lineTo(rect.width, rect.height);
      case NodeType.polygon:
        final sides = n.polygonSides.clamp(3, 16);
        final p = Path();
        for (int i = 0; i < sides; i++) {
          final a = -pi / 2 + (2 * pi * i) / sides;
          final pt = Offset(rect.center.dx + rect.width / 2 * cos(a),
              rect.center.dy + rect.height / 2 * sin(a));
          i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
        }
        return p..close();
      case NodeType.star:
        final spikes = n.polygonSides.clamp(3, 16);
        final p = Path();
        for (int i = 0; i < spikes * 2; i++) {
          final a = -pi / 2 + (pi * i) / spikes;
          final f = i.isEven ? 1.0 : n.starInnerRatio;
          final pt = Offset(rect.center.dx + rect.width / 2 * f * cos(a),
              rect.center.dy + rect.height / 2 * f * sin(a));
          i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
        }
        return p..close();
      case NodeType.path:
        final p = Path();
        if (n.pathPoints.isNotEmpty) {
          p.moveTo(n.pathPoints.first.anchor.dx, n.pathPoints.first.anchor.dy);
          for (int i = 1; i < n.pathPoints.length; i++) {
            final prev = n.pathPoints[i - 1];
            final cur = n.pathPoints[i];
            if (prev.handleOut != null || cur.handleIn != null) {
              final c1 = prev.anchor + (prev.handleOut ?? Offset.zero);
              final c2 = cur.anchor + (cur.handleIn ?? Offset.zero);
              p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, cur.anchor.dx, cur.anchor.dy);
            } else {
              p.lineTo(cur.anchor.dx, cur.anchor.dy);
            }
          }
          if (n.pathClosed) p.close();
        }
        return p;
      default:
        return Path()..addRRect(rrect);
    }
  }

  static Path _dashPath(Path src, double dash, double gap) {
    final out = Path();
    for (final m in src.computeMetrics()) {
      double d = 0;
      while (d < m.length) {
        out.addPath(m.extractPath(d, min(m.length, d + dash)), Offset.zero);
        d += dash + gap;
      }
    }
    return out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final page = ctrl.activePage;
    final z = page.zoom;
    final center = Offset(size.width / 2, size.height / 2);

    canvas.save();
    canvas.translate(center.dx + page.pan.dx, center.dy + page.pan.dy);
    canvas.scale(z);

    // Subtle infinite dot grid
    if (ctrl.showGrid && z >= 0.35) {
      final step = z >= 1.5 ? 20.0 : 40.0;
      final tl = (-center - page.pan) / z;
      final br = (Offset(size.width, size.height) - center - page.pan) / z;
      final startX = (tl.dx / step).floor() * step;
      final startY = (tl.dy / step).floor() * step;
      final dotPaint = Paint()
        ..color = (FyrTheme.isDark ? Colors.white : Colors.black)
            .withValues(alpha: 0.08)
        ..strokeWidth = 1.5 / z
        ..strokeCap = StrokeCap.round;
      final pts = <Offset>[];
      for (double y = startY; y <= br.dy; y += step) {
        for (double x = startX; x <= br.dx; x += step) {
          pts.add(Offset(x, y));
        }
      }
      canvas.drawPoints(ui.PointMode.points, pts, dotPaint);
    }

    // Render all root subtrees
    for (final rid in page.rootIds) {
      final node = ctrl.nodes[rid];
      if (node != null) {
        paintNodeSubtree(
          canvas,
          node,
          ctrl.nodes,
          ctrl.imageCache,
          zoom: z,
          isFlowStart: page.flowStartFrameId == rid,
        );
      }
    }

    // Prototype connection noodles (when Prototype tab is active)
    if (showPrototypeLinks) {
      _paintPrototypeNoodles(canvas, z);
    }

    // Hover outline
    if (ctrl.hoveredId != null && !ctrl.selectedIds.contains(ctrl.hoveredId)) {
      final hr = ctrl.getAbsoluteBounds(ctrl.hoveredId!);
      canvas.drawRect(
        hr,
        Paint()
          ..color = const Color(0xFF40C4FF).withValues(alpha: 0.7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 / z,
      );
    }

    // Selection bounding box & 8 handles + rotation knob
    final selBounds = ctrl.getSelectionBounds();
    if (selBounds != null) {
      final isComp = ctrl.primarySelected?.type == NodeType.component ||
          ctrl.primarySelected?.type == NodeType.instance;
      final selColor = isComp ? const Color(0xFFBB86FC) : const Color(0xFF40C4FF);

      for (final id in ctrl.selectedIds) {
        final b = ctrl.getAbsoluteBounds(id);
        canvas.drawRect(
          b,
          Paint()
            ..color = selColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / z,
        );
      }

      if (ctrl.selectedIds.length == 1) {
        // Dimension badge below selection
        final dimTp = TextPainter(
          text: TextSpan(
            text: '${selBounds.width.round()} × ${selBounds.height.round()}',
            style: TextStyle(
              fontSize: 10.5 / z,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final pillRect = RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(selBounds.center.dx, selBounds.bottom + 14 / z),
            width: dimTp.width + 12 / z,
            height: dimTp.height + 4 / z,
          ),
          Radius.circular(4 / z),
        );
        canvas.drawRRect(pillRect, Paint()..color = selColor);
        dimTp.paint(
          canvas,
          Offset(
            selBounds.center.dx - dimTp.width / 2,
            selBounds.bottom + 14 / z - dimTp.height / 2,
          ),
        );

        // Rotation knob
        final rotPt = Offset(selBounds.center.dx, selBounds.top - 22 / z);
        canvas.drawLine(
          selBounds.topCenter,
          rotPt,
          Paint()
            ..color = selColor
            ..strokeWidth = 1.2 / z,
        );
        canvas.drawCircle(rotPt, 4.5 / z, Paint()..color = Colors.white);
        canvas.drawCircle(
          rotPt,
          4.5 / z,
          Paint()
            ..color = selColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / z,
        );

        // 8 resize handles
        final hs = 7.0 / z;
        for (final pt in DesignCanvasState._handleOffsets(selBounds)) {
          final hr = Rect.fromCenter(center: pt, width: hs, height: hs);
          canvas.drawRect(hr, Paint()..color = Colors.white);
          canvas.drawRect(
            hr,
            Paint()
              ..color = selColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4 / z,
          );
        }
      }
    }

    // Smart Snap Guides
    for (final g in ctrl.activeSnapGuides) {
      final p = Paint()
        ..color = const Color(0xFFFF4081)
        ..strokeWidth = 1.2 / z;
      if (g.vertical) {
        canvas.drawLine(Offset(g.position, g.start), Offset(g.position, g.end), p);
      } else {
        canvas.drawLine(Offset(g.start, g.position), Offset(g.end, g.position), p);
      }
    }

    // Active Pen Path Preview
    if (ctrl.activePenPoints.isNotEmpty) {
      final pp = Path()
        ..moveTo(ctrl.activePenPoints.first.anchor.dx,
            ctrl.activePenPoints.first.anchor.dy);
      for (int i = 1; i < ctrl.activePenPoints.length; i++) {
        final prev = ctrl.activePenPoints[i - 1];
        final cur = ctrl.activePenPoints[i];
        if (prev.handleOut != null || cur.handleIn != null) {
          final c1 = prev.anchor + (prev.handleOut ?? Offset.zero);
          final c2 = cur.anchor + (cur.handleIn ?? Offset.zero);
          pp.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, cur.anchor.dx, cur.anchor.dy);
        } else {
          pp.lineTo(cur.anchor.dx, cur.anchor.dy);
        }
      }
      if (ctrl.penCursorCanvas != null) {
        pp.lineTo(ctrl.penCursorCanvas!.dx, ctrl.penCursorCanvas!.dy);
      }
      canvas.drawPath(
        pp,
        Paint()
          ..color = const Color(0xFFE040FB)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 / z,
      );
      for (final pt in ctrl.activePenPoints) {
        canvas.drawCircle(pt.anchor, 4.5 / z, Paint()..color = Colors.white);
        canvas.drawCircle(
          pt.anchor,
          4.5 / z,
          Paint()
            ..color = const Color(0xFFE040FB)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / z,
        );
      }
    }

    // Creation Preview Rect
    if (creationRect != null) {
      canvas.drawRect(
        creationRect!,
        Paint()..color = FyrTheme.accentColor.withValues(alpha: 0.16),
      );
      canvas.drawRect(
        creationRect!,
        Paint()
          ..color = FyrTheme.accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / z,
      );
    }

    // Marquee Selection Rect
    if (marqueeRect != null) {
      canvas.drawRect(
        marqueeRect!,
        Paint()..color = const Color(0xFF40C4FF).withValues(alpha: 0.12),
      );
      canvas.drawRect(
        marqueeRect!,
        Paint()
          ..color = const Color(0xFF40C4FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2 / z,
      );
    }

    canvas.restore();
  }

  void _paintPrototypeNoodles(Canvas canvas, double z) {
    final noodlePaint = Paint()
      ..color = const Color(0xFF40C4FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 / z;

    for (final n in ctrl.nodes.values) {
      final link = n.prototypeLink;
      if (link == null || link.targetFrameId == null) continue;
      if (!ctrl.nodes.containsKey(link.targetFrameId)) continue;
      final src = ctrl.getAbsoluteBounds(n.id);
      final dst = ctrl.getAbsoluteBounds(link.targetFrameId!);
      final p0 = Offset(src.right, src.center.dy);
      final p3 = Offset(dst.left, dst.center.dy);
      final ctrlOffset = max(60.0, (p3.dx - p0.dx).abs() * 0.45);
      final path = Path()
        ..moveTo(p0.dx, p0.dy)
        ..cubicTo(
          p0.dx + ctrlOffset,
          p0.dy,
          p3.dx - ctrlOffset,
          p3.dy,
          p3.dx,
          p3.dy,
        );
      canvas.drawPath(path, noodlePaint);
      canvas.drawCircle(p0, 5 / z, Paint()..color = const Color(0xFF40C4FF));
      canvas.drawCircle(p3, 5 / z, Paint()..color = const Color(0xFF40C4FF));
    }
  }

  @override
  bool shouldRepaint(covariant DevignCanvasPainter old) => true;
}
