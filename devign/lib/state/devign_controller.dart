import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../engine/devign_export.dart';
import '../models/design_models.dart';

class SnapGuide {
  final bool vertical;
  final double position; // canvas coordinate
  final double start;
  final double end;
  final String? distanceLabel;

  const SnapGuide({
    required this.vertical,
    required this.position,
    required this.start,
    required this.end,
    this.distanceLabel,
  });
}

class DevignController extends ChangeNotifier {
  static const int maxHistory = 50;

  String documentTitle = 'Untitled Design';
  String? filePath;
  bool dirty = false;

  final List<DesignPage> pages = [];
  int activePageIndex = 0;

  Map<String, DesignNode> nodes = {};
  List<ColorToken> colorTokens = [];

  DevignTool activeTool = DevignTool.select;
  int rightPanelTab = 0; // 0=Design, 1=Prototype, 2=Code
  int leftPanelTab = 0; // 0=Layers, 1=Assets, 2=Tokens
  bool showLeftPanel = true;
  bool showRightPanel = true;
  String layerSearchQuery = '';
  bool showGrid = true;
  bool showRulers = true;
  bool showComments = true;
  bool snapToGuides = true;

  Set<String> selectedIds = {};
  String? hoveredId;
  List<SnapGuide> activeSnapGuides = [];
  List<BezierPoint> activePenPoints = [];
  Offset? penCursorCanvas;

  // Clipboard & Image Cache
  List<Map<String, dynamic>> _clipboardPayloads = [];
  final Map<String, ui.Image> imageCache = {};

  // History snapshots
  final List<String> _undoStack = [];
  int _historyCursor = -1;

  // Status banner
  String? statusMessage;
  Timer? _statusTimer;
  int _idSeq = 1;

  DevignController() {
    loadStarterWorkspace();
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  DesignPage get activePage =>
      pages[activePageIndex.clamp(0, max(0, pages.length - 1))];

  DesignNode? get primarySelected =>
      selectedIds.isEmpty ? null : nodes[selectedIds.first];

  List<DesignNode> get selectedNodes =>
      selectedIds.map((id) => nodes[id]).whereType<DesignNode>().toList();

  bool get canUndo => _historyCursor > 0;
  bool get canRedo => _historyCursor < _undoStack.length - 1;

  String _nextId(String prefix) =>
      '${prefix}_${DateTime.now().microsecondsSinceEpoch}_${_idSeq++}';

  void setStatus(String msg) {
    statusMessage = msg;
    _statusTimer?.cancel();
    _statusTimer = Timer(const Duration(seconds: 3), () {
      statusMessage = null;
      notifyListeners();
    });
    notifyListeners();
  }

  Future<void> initialize({String? initialFile}) async {
    if (initialFile != null && File(initialFile).existsSync()) {
      try {
        await openProjectFromPath(initialFile);
        return;
      } catch (e) {
        setStatus('Could not open $initialFile: $e');
      }
    }
    loadStarterWorkspace();
  }

  void loadStarterWorkspace() {
    pages.clear();
    nodes.clear();
    selectedIds.clear();
    _undoStack.clear();
    _historyCursor = -1;
    documentTitle = 'Fyr Mobile App Kit';
    filePath = null;
    dirty = false;

    colorTokens = [
      ColorToken(id: 'tok_accent', name: 'Fyr Purple', color: const Color(0xFF9C27B0)),
      ColorToken(id: 'tok_magenta', name: 'Neon Pink', color: const Color(0xFFE040FB)),
      ColorToken(id: 'tok_cyan', name: 'Electric Cyan', color: const Color(0xFF40C4FF)),
      ColorToken(id: 'tok_surface', name: 'Obsidian Card', color: const Color(0xFF16161C)),
      ColorToken(id: 'tok_bg', name: 'Deep Canvas', color: const Color(0xFF0D0D12)),
      ColorToken(id: 'tok_mint', name: 'Success Mint', color: const Color(0xFF69F0AE)),
      ColorToken(id: 'tok_text', name: 'Pure Text', color: const Color(0xFFF5F5FA)),
      ColorToken(id: 'tok_muted', name: 'Muted Slate', color: const Color(0xFF9E9EB0)),
    ];

    final page = DesignPage(
      id: _nextId('page'),
      name: 'App Screens',
      zoom: 0.72,
      pan: const Offset(-260, -200),
    );
    pages.add(page);
    activePageIndex = 0;

    // Screen 1: Welcome / Login Screen (Fyr Phone)
    final loginFrameId = _nextId('frame');
    final loginFrame = DesignNode(
      id: loginFrameId,
      name: '01 / Welcome Screen',
      type: NodeType.frame,
      x: 40,
      y: 40,
      width: 393,
      height: 852,
      clipContent: true,
      radiusTL: 44,
      radiusTR: 44,
      radiusBR: 44,
      radiusBL: 44,
      fills: [
        FillPaint(
          kind: FillKind.linearGradient,
          color: const Color(0xFF13111C),
          secondaryColor: const Color(0xFF0A0A0F),
          gradientAngleDeg: 160,
        ),
      ],
      strokes: [StrokePaint(color: const Color(0xFF2B2838), width: 1.5)],
      effects: [
        NodeEffect(
          kind: EffectKind.dropShadow,
          color: const Color(0x70000000),
          offsetY: 20,
          blurRadius: 40,
        ),
      ],
    );
    nodes[loginFrameId] = loginFrame;
    page.rootIds.add(loginFrameId);
    page.flowStartFrameId = loginFrameId;

    // Screen 2: Dashboard Screen (Fyr Phone)
    final dashFrameId = _nextId('frame');
    final dashFrame = DesignNode(
      id: dashFrameId,
      name: '02 / Dashboard',
      type: NodeType.frame,
      x: 520,
      y: 40,
      width: 393,
      height: 852,
      clipContent: true,
      radiusTL: 44,
      radiusTR: 44,
      radiusBR: 44,
      radiusBL: 44,
      fills: [FillPaint(color: const Color(0xFF0F0F14))],
      strokes: [StrokePaint(color: const Color(0xFF2B2838), width: 1.5)],
      effects: [
        NodeEffect(
          kind: EffectKind.dropShadow,
          color: const Color(0x70000000),
          offsetY: 20,
          blurRadius: 40,
        ),
      ],
    );
    nodes[dashFrameId] = dashFrame;
    page.rootIds.add(dashFrameId);

    // Ambient glow orb inside Screen 1
    _addChild(
      loginFrameId,
      DesignNode(
        id: _nextId('orb'),
        name: 'Ambient Glow',
        type: NodeType.ellipse,
        x: 76,
        y: 90,
        width: 240,
        height: 240,
        fills: [
          FillPaint(
            kind: FillKind.radialGradient,
            color: const Color(0xFF9C27B0),
            secondaryColor: const Color(0x0040C4FF),
            opacity: 0.45,
          ),
        ],
        effects: [NodeEffect(kind: EffectKind.layerBlur, blurRadius: 36)],
      ),
    );

    _addChild(
      loginFrameId,
      DesignNode(
        id: _nextId('badge'),
        name: 'Logo Badge',
        type: NodeType.rectangle,
        x: 156,
        y: 165,
        width: 80,
        height: 80,
        radiusTL: 24,
        radiusTR: 24,
        radiusBR: 24,
        radiusBL: 24,
        fills: [
          FillPaint(
            kind: FillKind.linearGradient,
            color: const Color(0xFFE040FB),
            secondaryColor: const Color(0xFF7C4DFF),
          ),
        ],
        effects: [
          NodeEffect(
            kind: EffectKind.dropShadow,
            color: const Color(0x66E040FB),
            offsetY: 12,
            blurRadius: 28,
          ),
        ],
      ),
    );

    _addChild(
      loginFrameId,
      DesignNode(
        id: _nextId('title'),
        name: 'Hero Headline',
        type: NodeType.text,
        x: 36,
        y: 285,
        width: 320,
        height: 88,
        text: 'Design Without\nBoundaries.',
        fontSize: 34,
        fontWeightIndex: 7,
        textAlign: TextAlign.center,
        fills: [FillPaint(color: const Color(0xFFF5F5FA))],
      ),
    );

    _addChild(
      loginFrameId,
      DesignNode(
        id: _nextId('sub'),
        name: 'Subtitle',
        type: NodeType.text,
        x: 46,
        y: 386,
        width: 300,
        height: 48,
        text: 'Vector frames, auto layout, tokens & interactive prototypes.',
        fontSize: 14,
        fontWeightIndex: 3,
        textAlign: TextAlign.center,
        fills: [FillPaint(color: const Color(0xFF9E9EB0))],
      ),
    );

    // Master Component Button inside Screen 1 wired to Screen 2!
    final ctaId = _nextId('comp');
    _addChild(
      loginFrameId,
      DesignNode(
        id: ctaId,
        name: 'Primary CTA Button',
        type: NodeType.component,
        x: 36,
        y: 710,
        width: 321,
        height: 56,
        radiusTL: 16,
        radiusTR: 16,
        radiusBR: 16,
        radiusBL: 16,
        fills: [
          FillPaint(
            kind: FillKind.linearGradient,
            color: const Color(0xFFE040FB),
            secondaryColor: const Color(0xFF7C4DFF),
            gradientAngleDeg: 90,
          ),
        ],
        effects: [
          NodeEffect(
            kind: EffectKind.dropShadow,
            color: const Color(0x55E040FB),
            offsetY: 10,
            blurRadius: 24,
          ),
        ],
        prototypeLink: PrototypeLink(
          action: PrototypeAction.navigate,
          targetFrameId: dashFrameId,
          transition: PrototypeTransition.slideLeft,
        ),
      ),
    );
    _addChild(
      ctaId,
      DesignNode(
        id: _nextId('txt'),
        name: 'Button Label',
        type: NodeType.text,
        x: 60,
        y: 17,
        width: 200,
        height: 24,
        text: 'Get Started  →',
        fontSize: 16,
        fontWeightIndex: 6,
        textAlign: TextAlign.center,
        fills: [FillPaint(color: Colors.white)],
      ),
    );

    // Populate Screen 2 (Dashboard) with Auto-Layout Stack!
    _addChild(
      dashFrameId,
      DesignNode(
        id: _nextId('back'),
        name: 'Back Pill',
        type: NodeType.rectangle,
        x: 24,
        y: 56,
        width: 84,
        height: 34,
        radiusTL: 12,
        radiusTR: 12,
        radiusBR: 12,
        radiusBL: 12,
        fills: [FillPaint(color: const Color(0xFF1D1D26))],
        strokes: [StrokePaint(color: const Color(0xFF2E2E3A), width: 1)],
        prototypeLink: PrototypeLink(
          action: PrototypeAction.back,
          transition: PrototypeTransition.slideLeft,
        ),
      ),
    );
    _addChild(
      dashFrameId,
      DesignNode(
        id: _nextId('backtxt'),
        name: 'Back Text',
        type: NodeType.text,
        x: 38,
        y: 64,
        width: 60,
        height: 20,
        text: '← Back',
        fontSize: 13,
        fontWeightIndex: 5,
        fills: [FillPaint(color: const Color(0xFFF5F5FA))],
        prototypeLink: PrototypeLink(
          action: PrototypeAction.back,
          transition: PrototypeTransition.slideLeft,
        ),
      ),
    );

    _addChild(
      dashFrameId,
      DesignNode(
        id: _nextId('dtitle'),
        name: 'Dashboard Title',
        type: NodeType.text,
        x: 24,
        y: 112,
        width: 300,
        height: 38,
        text: 'Studio Overview',
        fontSize: 28,
        fontWeightIndex: 7,
        fills: [FillPaint(color: const Color(0xFFF5F5FA))],
      ),
    );

    final cardsStackId = _nextId('stack');
    _addChild(
      dashFrameId,
      DesignNode(
        id: cardsStackId,
        name: 'Metrics Auto-Layout',
        type: NodeType.frame,
        x: 24,
        y: 170,
        width: 345,
        height: 410,
        radiusTL: 20,
        radiusTR: 20,
        radiusBR: 20,
        radiusBL: 20,
        fills: [FillPaint(color: const Color(0xFF15151D))],
        strokes: [StrokePaint(color: const Color(0xFF272733), width: 1)],
        autoLayout: AutoLayoutConfig(
          direction: AutoLayoutDirection.vertical,
          gap: 14,
          paddingH: 16,
          paddingV: 16,
        ),
      ),
    );

    for (final cardData in [
      ('Active Prototypes', const Color(0xFF9C27B0), const Color(0xFFE040FB)),
      ('Design Tokens', const Color(0xFF2979FF), const Color(0xFF40C4FF)),
      ('Exported Assets', const Color(0xFF00C853), const Color(0xFF69F0AE)),
    ]) {
      final cardId = _nextId('card');
      _addChild(
        cardsStackId,
        DesignNode(
          id: cardId,
          name: cardData.$1,
          type: NodeType.rectangle,
          x: 0,
          y: 0,
          width: 313,
          height: 112,
          radiusTL: 16,
          radiusTR: 16,
          radiusBR: 16,
          radiusBL: 16,
          fills: [
            FillPaint(
              kind: FillKind.linearGradient,
              color: cardData.$2,
              secondaryColor: cardData.$3,
              opacity: 0.9,
            ),
          ],
        ),
      );
    }
    applyAutoLayout(cardsStackId);

    page.comments.add(
      CanvasComment(
        id: _nextId('cmt'),
        position: const Offset(432, 710),
        author: 'Design Review',
        message: 'Tap "Present ▶" in the top right to test this live flow!',
      ),
    );

    selectedIds = {loginFrameId};
    _pushHistory();
    notifyListeners();
  }

  void _addChild(String parentId, DesignNode child) {
    child.parentId = parentId;
    nodes[child.id] = child;
    nodes[parentId]?.children.add(child.id);
  }

  // ---------------------------------------------------------------------------
  // Coordinate Geometry & Tree Helpers
  // ---------------------------------------------------------------------------

  Offset getAbsolutePosition(String id) {
    final node = nodes[id];
    if (node == null) return Offset.zero;
    double ax = node.x;
    double ay = node.y;
    String? pId = node.parentId;
    while (pId != null) {
      final parent = nodes[pId];
      if (parent == null) break;
      ax += parent.x;
      ay += parent.y;
      pId = parent.parentId;
    }
    return Offset(ax, ay);
  }

  Rect getAbsoluteBounds(String id) {
    final node = nodes[id];
    if (node == null) return Rect.zero;
    final pos = getAbsolutePosition(id);
    return Rect.fromLTWH(pos.dx, pos.dy, node.width, node.height);
  }

  Rect? getSelectionBounds() {
    if (selectedIds.isEmpty) return null;
    Rect? acc;
    for (final id in selectedIds) {
      final r = getAbsoluteBounds(id);
      acc = acc == null ? r : acc.expandToInclude(r);
    }
    return acc;
  }

  List<DesignNode> getTopLevelFrames() {
    return activePage.rootIds
        .map((id) => nodes[id])
        .whereType<DesignNode>()
        .where((n) => n.type == NodeType.frame || n.type == NodeType.component)
        .toList();
  }

  List<DesignNode> getMasterComponents() {
    return nodes.values
        .where((n) => n.type == NodeType.component)
        .toList();
  }

  String? hitTest(Offset canvasPos, {bool preferDeepest = true}) {
    String? hitInList(List<String> ids) {
      for (int i = ids.length - 1; i >= 0; i--) {
        final id = ids[i];
        final n = nodes[id];
        if (n == null || !n.visible || n.locked) continue;
        final rect = getAbsoluteBounds(id);
        final inSelf = rect.inflate(n.type == NodeType.line || n.type == NodeType.arrow ? 6 : 0).contains(canvasPos);

        if (n.children.isNotEmpty && (!n.clipContent || inSelf)) {
          final deep = hitInList(n.children);
          if (deep != null && preferDeepest) return deep;
        }
        if (inSelf) return id;
      }
      return null;
    }

    return hitInList(activePage.rootIds);
  }

  String? findContainingFrame(Offset canvasPos, {String? excludeId}) {
    for (int i = activePage.rootIds.length - 1; i >= 0; i--) {
      final id = activePage.rootIds[i];
      if (id == excludeId) continue;
      final n = nodes[id];
      if (n == null || !n.visible || n.locked || !n.isContainer) continue;
      if (getAbsoluteBounds(id).contains(canvasPos)) return id;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Selection, Tools, Pages & Viewport
  // ---------------------------------------------------------------------------

  void setTool(DevignTool tool) {
    if (activeTool == tool) return;
    if (activeTool == DevignTool.pen && activePenPoints.length >= 2) {
      finishPenPath(closed: false);
    } else {
      activePenPoints.clear();
    }
    activeTool = tool;
    notifyListeners();
  }

  void selectNode(String? id, {bool additive = false}) {
    if (id == null) {
      selectedIds.clear();
    } else if (additive) {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
    } else {
      selectedIds = {id};
    }
    notifyListeners();
  }

  void selectInMarquee(Rect canvasRect) {
    final found = <String>{};
    void visit(List<String> ids) {
      for (final id in ids) {
        final n = nodes[id];
        if (n == null || !n.visible || n.locked) continue;
        if (canvasRect.overlaps(getAbsoluteBounds(id))) {
          found.add(id);
        }
        if (n.children.isNotEmpty) visit(n.children);
      }
    }

    visit(activePage.rootIds);
    selectedIds = found;
    notifyListeners();
  }

  void addPage([String? name]) {
    final pObj = DesignPage(
      id: _nextId('page'),
      name: name ?? 'Page ${pages.length + 1}',
    );
    pages.add(pObj);
    activePageIndex = pages.length - 1;
    selectedIds.clear();
    _pushHistory();
    notifyListeners();
  }

  void switchPage(int idx) {
    if (idx < 0 || idx >= pages.length) return;
    activePageIndex = idx;
    selectedIds.clear();
    notifyListeners();
  }

  void setZoom(double z, {Offset? pan}) {
    activePage.zoom = z.clamp(0.1, 16.0);
    if (pan != null) activePage.pan = pan;
    notifyListeners();
  }

  void panBy(Offset delta) {
    activePage.pan += delta;
    notifyListeners();
  }

  void zoomToFit(Size viewport) {
    if (activePage.rootIds.isEmpty || viewport.isEmpty) {
      activePage.zoom = 1.0;
      activePage.pan = Offset.zero;
      notifyListeners();
      return;
    }
    Rect? bounds;
    for (final id in activePage.rootIds) {
      final r = getAbsoluteBounds(id);
      bounds = bounds == null ? r : bounds.expandToInclude(r);
    }
    if (bounds == null || bounds.isEmpty) return;
    final scaleX = (viewport.width - 120) / max(1, bounds.width);
    final scaleY = (viewport.height - 120) / max(1, bounds.height);
    final z = min(scaleX, scaleY).clamp(0.15, 2.0);
    activePage.zoom = z;
    activePage.pan = -bounds.center * z;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Creating Nodes, Preset Frames, UI Kit Components & Bezier Pen
  // ---------------------------------------------------------------------------

  DesignNode createNode({
    required NodeType type,
    required Rect canvasRect,
    String? name,
    String? parentId,
    Color? fillColor,
    String? text,
    String? imagePath,
  }) {
    final resolvedParent = parentId ??
        (type == NodeType.frame
            ? null
            : findContainingFrame(canvasRect.center));
    final parentPos = resolvedParent != null
        ? getAbsolutePosition(resolvedParent)
        : Offset.zero;

    final id = _nextId(type.name);
    final isLine = type == NodeType.line || type == NodeType.arrow;
    final node = DesignNode(
      id: id,
      name: name ?? _defaultName(type),
      type: type,
      parentId: resolvedParent,
      x: canvasRect.left - parentPos.dx,
      y: canvasRect.top - parentPos.dy,
      width: max(isLine ? 1 : 8, canvasRect.width),
      height: max(isLine ? 1 : 8, canvasRect.height),
      clipContent: type == NodeType.frame,
      radiusTL: type == NodeType.rectangle ? 12 : 0,
      radiusTR: type == NodeType.rectangle ? 12 : 0,
      radiusBR: type == NodeType.rectangle ? 12 : 0,
      radiusBL: type == NodeType.rectangle ? 12 : 0,
      fills: isLine
          ? []
          : [
              FillPaint(
                color: fillColor ??
                    (type == NodeType.frame
                        ? const Color(0xFF16161D)
                        : (type == NodeType.text
                            ? const Color(0xFFF5F5FA)
                            : const Color(0xFF9C27B0))),
              ),
            ],
      strokes: isLine
          ? [StrokePaint(color: const Color(0xFFE040FB), width: 2.5)]
          : (type == NodeType.frame
              ? [StrokePaint(color: const Color(0xFF2C2C38), width: 1)]
              : []),
      text: text ?? 'Double-click to edit',
      imagePath: imagePath,
    );

    nodes[id] = node;
    if (resolvedParent != null) {
      nodes[resolvedParent]?.children.add(id);
      if (nodes[resolvedParent]?.autoLayout.enabled == true) {
        applyAutoLayout(resolvedParent);
      }
    } else {
      activePage.rootIds.add(id);
      if (type == NodeType.frame && activePage.flowStartFrameId == null) {
        activePage.flowStartFrameId = id;
      }
    }

    selectedIds = {id};
    dirty = true;
    _pushHistory();
    notifyListeners();
    return node;
  }

  void addPresetFrame(FramePreset preset) {
    double nextX = 60;
    for (final id in activePage.rootIds) {
      final b = getAbsoluteBounds(id);
      nextX = max(nextX, b.right + 80);
    }
    createNode(
      type: NodeType.frame,
      name: preset.name,
      canvasRect: Rect.fromLTWH(nextX, 40, preset.width, preset.height),
    );
    setStatus('Added ${preset.name} (${preset.width.round()}×${preset.height.round()})');
  }

  void insertUiKitSnippet(String kind) {
    final targetParent = primarySelected != null && primarySelected!.isContainer
        ? primarySelected!.id
        : (activePage.rootIds.isNotEmpty ? activePage.rootIds.first : null);
    final basePos = targetParent != null
        ? getAbsolutePosition(targetParent) + const Offset(32, 80)
        : const Offset(120, 120);

    if (kind == 'Primary Button') {
      final btn = createNode(
        type: NodeType.frame,
        name: 'Primary Button',
        parentId: targetParent,
        canvasRect: Rect.fromLTWH(basePos.dx, basePos.dy, 200, 48),
      );
      btn.setUniformRadius(14);
      btn.fills = [
        FillPaint(
          kind: FillKind.linearGradient,
          color: const Color(0xFFE040FB),
          secondaryColor: const Color(0xFF7C4DFF),
        ),
      ];
      btn.strokes = [];
      btn.effects = [
        NodeEffect(
          kind: EffectKind.dropShadow,
          color: const Color(0x55E040FB),
          offsetY: 8,
          blurRadius: 20,
        ),
      ];
      _addChild(
        btn.id,
        DesignNode(
          id: _nextId('txt'),
          name: 'Label',
          type: NodeType.text,
          x: 20,
          y: 13,
          width: 160,
          height: 22,
          text: 'Continue',
          fontSize: 15,
          fontWeightIndex: 6,
          textAlign: TextAlign.center,
          fills: [FillPaint(color: Colors.white)],
        ),
      );
    } else if (kind == 'Glass Card') {
      final card = createNode(
        type: NodeType.frame,
        name: 'Glass Card',
        parentId: targetParent,
        canvasRect: Rect.fromLTWH(basePos.dx, basePos.dy, 280, 160),
      );
      card.setUniformRadius(20);
      card.fills = [FillPaint(color: const Color(0xFF20202A), opacity: 0.75)];
      card.strokes = [StrokePaint(color: const Color(0x33FFFFFF), width: 1)];
      card.effects = [
        NodeEffect(kind: EffectKind.backgroundBlur, blurRadius: 18),
        NodeEffect(
          kind: EffectKind.dropShadow,
          color: const Color(0x44000000),
          offsetY: 12,
          blurRadius: 28,
        ),
      ];
      _addChild(
        card.id,
        DesignNode(
          id: _nextId('txt'),
          name: 'Card Title',
          type: NodeType.text,
          x: 20,
          y: 20,
          width: 220,
          height: 28,
          text: 'Glassmorphism Card',
          fontSize: 18,
          fontWeightIndex: 6,
          fills: [FillPaint(color: Colors.white)],
        ),
      );
      _addChild(
        card.id,
        DesignNode(
          id: _nextId('txt'),
          name: 'Card Body',
          type: NodeType.text,
          x: 20,
          y: 56,
          width: 240,
          height: 60,
          text: 'Edit fills, blur & auto layout in the inspector.',
          fontSize: 13,
          fontWeightIndex: 3,
          fills: [FillPaint(color: const Color(0xFFAAAABC))],
        ),
      );
    } else if (kind == 'Text Input') {
      final inp = createNode(
        type: NodeType.frame,
        name: 'Text Input',
        parentId: targetParent,
        canvasRect: Rect.fromLTWH(basePos.dx, basePos.dy, 280, 46),
      );
      inp.setUniformRadius(12);
      inp.fills = [FillPaint(color: const Color(0xFF14141B))];
      inp.strokes = [StrokePaint(color: const Color(0xFF333344), width: 1.2)];
      _addChild(
        inp.id,
        DesignNode(
          id: _nextId('txt'),
          name: 'Placeholder',
          type: NodeType.text,
          x: 16,
          y: 13,
          width: 240,
          height: 22,
          text: 'Enter your email...',
          fontSize: 14,
          fontWeightIndex: 3,
          fills: [FillPaint(color: const Color(0xFF7A7A90))],
        ),
      );
    } else if (kind == 'Status Pill') {
      final pill = createNode(
        type: NodeType.frame,
        name: 'Status Pill',
        parentId: targetParent,
        canvasRect: Rect.fromLTWH(basePos.dx, basePos.dy, 112, 30),
      );
      pill.setUniformRadius(99);
      pill.fills = [FillPaint(color: const Color(0xFF69F0AE), opacity: 0.16)];
      pill.strokes = [StrokePaint(color: const Color(0xFF69F0AE), width: 1)];
      _addChild(
        pill.id,
        DesignNode(
          id: _nextId('txt'),
          name: 'Badge Text',
          type: NodeType.text,
          x: 10,
          y: 6,
          width: 92,
          height: 18,
          text: '● LIVE',
          fontSize: 11,
          fontWeightIndex: 6,
          textAlign: TextAlign.center,
          fills: [FillPaint(color: const Color(0xFF69F0AE))],
        ),
      );
    } else if (kind == 'Avatar') {
      createNode(
        type: NodeType.ellipse,
        name: 'User Avatar',
        parentId: targetParent,
        canvasRect: Rect.fromLTWH(basePos.dx, basePos.dy, 64, 64),
        fillColor: const Color(0xFF40C4FF),
      );
    }
    _pushHistory();
    notifyListeners();
  }

  // Bezier Pen Tool
  void addPenPoint(Offset canvasPos, {Offset? handleOut}) {
    if (activePenPoints.length >= 3 &&
        (canvasPos - activePenPoints.first.anchor).distance < 12.0 / activePage.zoom) {
      finishPenPath(closed: true);
      return;
    }
    activePenPoints.add(
      BezierPoint(
        anchor: canvasPos,
        handleIn: handleOut != null ? -handleOut : null,
        handleOut: handleOut,
      ),
    );
    notifyListeners();
  }

  void updateLastPenHandle(Offset handleOut) {
    if (activePenPoints.isEmpty) return;
    activePenPoints.last.handleOut = handleOut;
    activePenPoints.last.handleIn = -handleOut;
    notifyListeners();
  }

  void finishPenPath({required bool closed}) {
    if (activePenPoints.length < 2) {
      activePenPoints.clear();
      notifyListeners();
      return;
    }
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in activePenPoints) {
      minX = min(minX, p.anchor.dx);
      minY = min(minY, p.anchor.dy);
      maxX = max(maxX, p.anchor.dx);
      maxY = max(maxY, p.anchor.dy);
    }
    final localPts = activePenPoints
        .map((p) => BezierPoint(
              anchor: Offset(p.anchor.dx - minX, p.anchor.dy - minY),
              handleIn: p.handleIn,
              handleOut: p.handleOut,
            ))
        .toList();
    activePenPoints.clear();

    final node = createNode(
      type: NodeType.path,
      name: 'Vector Path',
      canvasRect: Rect.fromLTWH(minX, minY, max(8, maxX - minX), max(8, maxY - minY)),
    );
    node.pathPoints = localPts;
    node.pathClosed = closed;
    node.fills = closed
        ? [FillPaint(color: const Color(0xFFE040FB), opacity: 0.35)]
        : [];
    node.strokes = [StrokePaint(color: const Color(0xFFE040FB), width: 2.5)];
    activeTool = DevignTool.select;
    _pushHistory();
    notifyListeners();
  }

  Future<void> placeImageFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return;
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    imageCache[path] = img;
    final scale = img.width > 420 ? 420.0 / img.width : 1.0;
    createNode(
      type: NodeType.image,
      name: p.basename(path),
      canvasRect: Rect.fromLTWH(80, 80, img.width * scale, img.height * scale),
      imagePath: path,
    );
  }

  Future<void> ensureImageLoaded(String? path) async {
    if (path == null || imageCache.containsKey(path)) return;
    final file = File(path);
    if (!await file.exists()) return;
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      imageCache[path] = frame.image;
      notifyListeners();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Moving, Smart Snapping, Resizing, Rotating & Auto Layout
  // ---------------------------------------------------------------------------

  void moveSelectedBy(Offset delta, {bool computeSnapping = true}) {
    if (selectedIds.isEmpty) return;
    Offset adjusted = delta;
    activeSnapGuides = [];

    if (computeSnapping && snapToGuides && selectedIds.length == 1) {
      final id = selectedIds.first;
      final n = nodes[id];
      if (n != null && !n.locked) {
        final cur = getAbsoluteBounds(id).shift(delta);
        const tol = 5.0;
        double? snapDx;
        double? snapDy;

        final candidates = <Rect>[];
        if (n.parentId != null) {
          candidates.add(getAbsoluteBounds(n.parentId!));
          for (final sibId in nodes[n.parentId!]!.children) {
            if (sibId != id) candidates.add(getAbsoluteBounds(sibId));
          }
        } else {
          for (final rid in activePage.rootIds) {
            if (rid != id) candidates.add(getAbsoluteBounds(rid));
          }
        }

        for (final other in candidates) {
          for (final pair in [
            (cur.left, other.left),
            (cur.right, other.right),
            (cur.center.dx, other.center.dx),
            (cur.left, other.right),
            (cur.right, other.left),
          ]) {
            if ((pair.$1 - pair.$2).abs() <= tol && snapDx == null) {
              snapDx = pair.$2 - pair.$1;
              activeSnapGuides.add(SnapGuide(
                vertical: true,
                position: pair.$2,
                start: min(cur.top, other.top) - 12,
                end: max(cur.bottom, other.bottom) + 12,
              ));
            }
          }
          for (final pair in [
            (cur.top, other.top),
            (cur.bottom, other.bottom),
            (cur.center.dy, other.center.dy),
            (cur.top, other.bottom),
            (cur.bottom, other.top),
          ]) {
            if ((pair.$1 - pair.$2).abs() <= tol && snapDy == null) {
              snapDy = pair.$2 - pair.$1;
              activeSnapGuides.add(SnapGuide(
                vertical: false,
                position: pair.$2,
                start: min(cur.left, other.left) - 12,
                end: max(cur.right, other.right) + 12,
              ));
            }
          }
        }

        adjusted = Offset(
          delta.dx + (snapDx ?? 0.0),
          delta.dy + (snapDy ?? 0.0),
        );
      }
    }

    for (final id in selectedIds) {
      final n = nodes[id];
      if (n == null || n.locked) continue;
      n.x += adjusted.dx;
      n.y += adjusted.dy;
    }
    dirty = true;
    notifyListeners();
  }

  void commitTransform() {
    activeSnapGuides = [];
    for (final id in selectedIds) {
      final pId = nodes[id]?.parentId;
      if (pId != null && nodes[pId]?.autoLayout.enabled == true) {
        applyAutoLayout(pId);
      }
      if (nodes[id]?.type == NodeType.component) {
        syncComponentInstances(id);
      }
    }
    _pushHistory();
    notifyListeners();
  }

  void applyAutoLayout(String containerId) {
    final frame = nodes[containerId];
    if (frame == null || !frame.autoLayout.enabled) return;
    final cfg = frame.autoLayout;
    final kids = frame.children
        .map((id) => nodes[id])
        .whereType<DesignNode>()
        .where((c) => c.visible)
        .toList();
    if (kids.isEmpty) return;

    final isHoriz = cfg.direction == AutoLayoutDirection.horizontal;
    final totalKidMain = kids.fold<double>(
        0.0, (sum, c) => sum + (isHoriz ? c.width : c.height));
    final availMain = (isHoriz ? frame.width : frame.height) -
        (isHoriz ? cfg.paddingH * 2 : cfg.paddingV * 2);

    double gap = cfg.gap;
    double cursor = isHoriz ? cfg.paddingH : cfg.paddingV;

    if (cfg.primaryAlign == AutoLayoutAlign.spaceBetween && kids.length > 1) {
      gap = max(0.0, (availMain - totalKidMain) / (kids.length - 1));
    } else if (cfg.primaryAlign == AutoLayoutAlign.center) {
      final used = totalKidMain + gap * (kids.length - 1);
      cursor += max(0.0, (availMain - used) / 2);
    } else if (cfg.primaryAlign == AutoLayoutAlign.end) {
      final used = totalKidMain + gap * (kids.length - 1);
      cursor += max(0.0, availMain - used);
    }

    final availCross = (isHoriz ? frame.height : frame.width) -
        (isHoriz ? cfg.paddingV * 2 : cfg.paddingH * 2);

    for (final c in kids) {
      final crossSize = isHoriz ? c.height : c.width;
      double crossPos = isHoriz ? cfg.paddingV : cfg.paddingH;
      if (cfg.crossAlign == AutoLayoutAlign.center) {
        crossPos += (availCross - crossSize) / 2;
      } else if (cfg.crossAlign == AutoLayoutAlign.end) {
        crossPos += availCross - crossSize;
      }

      if (isHoriz) {
        c.x = cursor;
        c.y = crossPos;
        cursor += c.width + gap;
      } else {
        c.x = crossPos;
        c.y = cursor;
        cursor += c.height + gap;
      }
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Components, Grouping, Alignment, Layer Order, Copy/Paste/Delete
  // ---------------------------------------------------------------------------

  void createComponentFromSelection() {
    final n = primarySelected;
    if (n == null) return;
    n.type = NodeType.component;
    if (!n.name.startsWith('❖ ')) {
      n.name = '❖ ${n.name}';
    }
    _pushHistory();
    setStatus('Created Master Component "${n.name}"');
    notifyListeners();
  }

  void instantiateComponent(String masterId) {
    final master = nodes[masterId];
    if (master == null) return;
    final clonedId = _deepCloneSubtree(
      masterId,
      newParentId: null,
      offset: const Offset(40, 40),
      asInstanceOf: masterId,
    );
    if (clonedId != null) {
      activePage.rootIds.add(clonedId);
      selectedIds = {clonedId};
      _pushHistory();
      setStatus('Created Instance of "${master.name}"');
      notifyListeners();
    }
  }

  void syncComponentInstances(String masterId) {
    final master = nodes[masterId];
    if (master == null) return;
    for (final inst in nodes.values) {
      if (inst.type == NodeType.instance &&
          inst.masterComponentId == masterId) {
        inst.width = master.width;
        inst.height = master.height;
        inst.radiusTL = master.radiusTL;
        inst.radiusTR = master.radiusTR;
        inst.radiusBR = master.radiusBR;
        inst.radiusBL = master.radiusBL;
        inst.fills = master.fills.map((f) => f.clone()).toList();
        inst.strokes = master.strokes.map((s) => s.clone()).toList();
        inst.effects = master.effects.map((e) => e.clone()).toList();
      }
    }
  }

  void groupSelection() {
    if (selectedIds.length < 2) return;
    final bounds = getSelectionBounds();
    if (bounds == null) return;

    final firstParent = nodes[selectedIds.first]?.parentId;
    final parentPos =
        firstParent != null ? getAbsolutePosition(firstParent) : Offset.zero;
    final groupId = _nextId('group');
    final group = DesignNode(
      id: groupId,
      name: 'Group',
      type: NodeType.group,
      parentId: firstParent,
      x: bounds.left - parentPos.dx,
      y: bounds.top - parentPos.dy,
      width: bounds.width,
      height: bounds.height,
    );
    nodes[groupId] = group;

    for (final id in selectedIds.toList()) {
      final n = nodes[id];
      if (n == null) continue;
      final abs = getAbsolutePosition(id);
      _detachFromParent(id);
      n.parentId = groupId;
      n.x = abs.dx - bounds.left;
      n.y = abs.dy - bounds.top;
      group.children.add(id);
    }

    if (firstParent != null) {
      nodes[firstParent]?.children.add(groupId);
    } else {
      activePage.rootIds.add(groupId);
    }
    selectedIds = {groupId};
    _pushHistory();
    notifyListeners();
  }

  void ungroupSelection() {
    final g = primarySelected;
    if (g == null || g.type != NodeType.group) return;
    final parentId = g.parentId;
    final gAbs = getAbsolutePosition(g.id);
    final pAbs = parentId != null ? getAbsolutePosition(parentId) : Offset.zero;
    final kids = List<String>.from(g.children);

    _detachFromParent(g.id);
    nodes.remove(g.id);

    for (final cid in kids) {
      final c = nodes[cid];
      if (c == null) continue;
      c.parentId = parentId;
      c.x = (gAbs.dx + c.x) - pAbs.dx;
      c.y = (gAbs.dy + c.y) - pAbs.dy;
      if (parentId != null) {
        nodes[parentId]?.children.add(cid);
      } else {
        activePage.rootIds.add(cid);
      }
    }
    selectedIds = kids.toSet();
    _pushHistory();
    notifyListeners();
  }

  void alignSelected(String alignment) {
    final list = selectedNodes;
    if (list.isEmpty) return;

    Rect ref;
    if (list.length == 1 && list.first.parentId != null) {
      ref = getAbsoluteBounds(list.first.parentId!);
    } else if (list.length > 1) {
      ref = getSelectionBounds()!;
    } else {
      return;
    }

    for (final n in list) {
      if (n.locked) continue;
      final pAbs =
          n.parentId != null ? getAbsolutePosition(n.parentId!) : Offset.zero;
      switch (alignment) {
        case 'left':
          n.x = ref.left - pAbs.dx;
          break;
        case 'centerH':
          n.x = ref.center.dx - n.width / 2 - pAbs.dx;
          break;
        case 'right':
          n.x = ref.right - n.width - pAbs.dx;
          break;
        case 'top':
          n.y = ref.top - pAbs.dy;
          break;
        case 'centerV':
          n.y = ref.center.dy - n.height / 2 - pAbs.dy;
          break;
        case 'bottom':
          n.y = ref.bottom - n.height - pAbs.dy;
          break;
      }
    }
    _pushHistory();
    notifyListeners();
  }

  void distributeSelected({required bool horizontal}) {
    final list = selectedNodes;
    if (list.length < 3) return;
    list.sort((a, b) => horizontal
        ? getAbsoluteBounds(a.id).left.compareTo(getAbsoluteBounds(b.id).left)
        : getAbsoluteBounds(a.id).top.compareTo(getAbsoluteBounds(b.id).top));

    final firstRect = getAbsoluteBounds(list.first.id);
    final lastRect = getAbsoluteBounds(list.last.id);
    final totalSize = list.fold<double>(
        0, (s, n) => s + (horizontal ? n.width : n.height));
    final span = horizontal
        ? (lastRect.right - firstRect.left)
        : (lastRect.bottom - firstRect.top);
    final gap = (span - totalSize) / (list.length - 1);

    double cursor = horizontal ? firstRect.left : firstRect.top;
    for (final n in list) {
      final pAbs =
          n.parentId != null ? getAbsolutePosition(n.parentId!) : Offset.zero;
      if (horizontal) {
        n.x = cursor - pAbs.dx;
        cursor += n.width + gap;
      } else {
        n.y = cursor - pAbs.dy;
        cursor += n.height + gap;
      }
    }
    _pushHistory();
    notifyListeners();
  }

  void reorderNode(String id, int delta) {
    final n = nodes[id];
    if (n == null) return;
    final list = n.parentId != null
        ? nodes[n.parentId!]?.children
        : activePage.rootIds;
    if (list == null) return;
    final idx = list.indexOf(id);
    if (idx < 0) return;
    final target = (idx + delta).clamp(0, list.length - 1);
    if (target == idx) return;
    list.removeAt(idx);
    list.insert(target, id);
    if (n.parentId != null && nodes[n.parentId!]?.autoLayout.enabled == true) {
      applyAutoLayout(n.parentId!);
    }
    _pushHistory();
    notifyListeners();
  }

  void deleteSelected() {
    if (selectedIds.isEmpty) return;
    final parentsToRelayout = <String>{};
    for (final id in selectedIds.toList()) {
      final n = nodes[id];
      if (n == null) continue;
      if (n.parentId != null) parentsToRelayout.add(n.parentId!);
      _detachFromParent(id);
      _deleteSubtree(id);
    }
    selectedIds.clear();
    for (final pid in parentsToRelayout) {
      if (nodes[pid]?.autoLayout.enabled == true) {
        applyAutoLayout(pid);
      }
    }
    dirty = true;
    _pushHistory();
    notifyListeners();
  }

  void duplicateSelected() {
    if (selectedIds.isEmpty) return;
    final newIds = <String>{};
    for (final id in selectedIds.toList()) {
      final n = nodes[id];
      if (n == null) continue;
      final copyId = _deepCloneSubtree(
        id,
        newParentId: n.parentId,
        offset: const Offset(24, 24),
      );
      if (copyId != null) {
        if (n.parentId != null) {
          nodes[n.parentId!]?.children.add(copyId);
          if (nodes[n.parentId!]?.autoLayout.enabled == true) {
            applyAutoLayout(n.parentId!);
          }
        } else {
          activePage.rootIds.add(copyId);
        }
        newIds.add(copyId);
      }
    }
    selectedIds = newIds;
    _pushHistory();
    notifyListeners();
  }

  void copySelected() {
    _clipboardPayloads = selectedIds
        .map((id) => _serializeSubtree(id))
        .whereType<Map<String, dynamic>>()
        .toList();
    if (_clipboardPayloads.isNotEmpty) {
      setStatus('Copied ${_clipboardPayloads.length} layer(s)');
    }
  }

  void pasteClipboard() {
    if (_clipboardPayloads.isEmpty) return;
    final pasted = <String>{};
    for (final payload in _clipboardPayloads) {
      final id = _deserializeSubtree(payload, parentId: null, offset: const Offset(28, 28));
      if (id != null) {
        activePage.rootIds.add(id);
        pasted.add(id);
      }
    }
    selectedIds = pasted;
    _pushHistory();
    notifyListeners();
  }

  void addComment(Offset canvasPos, String message) {
    if (message.trim().isEmpty) return;
    activePage.comments.add(
      CanvasComment(
        id: _nextId('cmt'),
        position: canvasPos,
        message: message.trim(),
      ),
    );
    _pushHistory();
    notifyListeners();
  }

  void toggleCommentResolved(String id) {
    for (final c in activePage.comments) {
      if (c.id == id) {
        c.resolved = !c.resolved;
        break;
      }
    }
    notifyListeners();
  }

  void deleteComment(String id) {
    activePage.comments.removeWhere((c) => c.id == id);
    _pushHistory();
    notifyListeners();
  }

  void addColorToken(String name, Color color) {
    colorTokens.add(ColorToken(id: _nextId('tok'), name: name, color: color));
    _pushHistory();
    notifyListeners();
  }

  void mutateSelected(void Function(DesignNode node) fn, {bool commit = false}) {
    for (final n in selectedNodes) {
      fn(n);
      if (n.type == NodeType.component) {
        syncComponentInstances(n.id);
      }
      if (n.autoLayout.enabled) {
        applyAutoLayout(n.id);
      }
      if (n.parentId != null && nodes[n.parentId!]?.autoLayout.enabled == true) {
        applyAutoLayout(n.parentId!);
      }
    }
    dirty = true;
    if (commit) _pushHistory();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Undo / Redo & Save / Open .devign JSON
  // ---------------------------------------------------------------------------

  String _encodeDocumentJson() => jsonEncode({
        'version': 1,
        'title': documentTitle,
        'activePageIndex': activePageIndex,
        'pages': pages.map((p) => p.toJson()).toList(),
        'nodes': nodes.map((k, v) => MapEntry(k, v.toJson())),
        'colorTokens': colorTokens.map((t) => t.toJson()).toList(),
      });

  void _restoreDocumentJson(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    documentTitle = j['title'] as String? ?? 'Untitled Design';
    pages
      ..clear()
      ..addAll(((j['pages'] as List?) ?? [])
          .map((e) => DesignPage.fromJson(Map<String, dynamic>.from(e as Map))));
    if (pages.isEmpty) {
      pages.add(DesignPage(id: _nextId('page'), name: 'Page 1'));
    }
    activePageIndex =
        ((j['activePageIndex'] as num?)?.toInt() ?? 0).clamp(0, pages.length - 1);
    nodes = {};
    final rawNodes = j['nodes'];
    if (rawNodes is Map) {
      for (final e in rawNodes.entries) {
        nodes[e.key.toString()] =
            DesignNode.fromJson(Map<String, dynamic>.from(e.value as Map));
      }
    }
    colorTokens = ((j['colorTokens'] as List?) ?? [])
        .map((e) => ColorToken.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    selectedIds.removeWhere((id) => !nodes.containsKey(id));
  }

  void _pushHistory() {
    final snap = _encodeDocumentJson();
    if (_historyCursor < _undoStack.length - 1) {
      _undoStack.removeRange(_historyCursor + 1, _undoStack.length);
    }
    _undoStack.add(snap);
    if (_undoStack.length > maxHistory) {
      _undoStack.removeAt(0);
    }
    _historyCursor = _undoStack.length - 1;
  }

  void commitHistory() {
    _pushHistory();
    notifyListeners();
  }

  void undo() {
    if (!canUndo) return;
    _historyCursor--;
    _restoreDocumentJson(_undoStack[_historyCursor]);
    notifyListeners();
  }

  void redo() {
    if (!canRedo) return;
    _historyCursor++;
    _restoreDocumentJson(_undoStack[_historyCursor]);
    notifyListeners();
  }

  Future<void> saveProjectToPath(String path) async {
    final out = path.toLowerCase().endsWith('.devign') ? path : '$path.devign';
    await File(out).writeAsString(_encodeDocumentJson());
    filePath = out;
    documentTitle = p.basenameWithoutExtension(out);
    dirty = false;
    setStatus('Saved ${p.basename(out)}');
  }

  Future<void> openProjectFromPath(String path) async {
    final raw = await File(path).readAsString();
    _restoreDocumentJson(raw);
    filePath = path;
    dirty = false;
    _undoStack.clear();
    _historyCursor = -1;
    _pushHistory();
    for (final n in nodes.values) {
      if (n.type == NodeType.image && n.imagePath != null) {
        ensureImageLoaded(n.imagePath);
      }
    }
    setStatus('Opened ${p.basename(path)}');
    notifyListeners();
  }

  Future<void> exportSelectedSvg(String outputPath) async {
    final target = primarySelected ??
        (activePage.rootIds.isNotEmpty ? nodes[activePage.rootIds.first] : null);
    if (target == null) return;
    final svg = DevignExport.generateSvg(target, nodes);
    await File(outputPath).writeAsString(svg);
    setStatus('Exported SVG: ${p.basename(outputPath)}');
  }

  // ---------------------------------------------------------------------------
  // Internal Subtree Utilities
  // ---------------------------------------------------------------------------

  void _detachFromParent(String id) {
    final n = nodes[id];
    if (n == null) return;
    if (n.parentId != null) {
      nodes[n.parentId!]?.children.remove(id);
    } else {
      activePage.rootIds.remove(id);
    }
  }

  void _deleteSubtree(String id) {
    final n = nodes.remove(id);
    if (n == null) return;
    for (final cid in List<String>.from(n.children)) {
      _deleteSubtree(cid);
    }
  }

  String? _deepCloneSubtree(
    String id, {
    required String? newParentId,
    Offset offset = Offset.zero,
    String? asInstanceOf,
  }) {
    final orig = nodes[id];
    if (orig == null) return null;
    final copyId = _nextId(orig.type.name);
    final copy = orig.clone();
    final created = DesignNode.fromJson({
      ...copy.toJson(),
      'id': copyId,
      'parentId': newParentId,
      'children': <String>[],
      'x': orig.x + offset.dx,
      'y': orig.y + offset.dy,
      if (asInstanceOf != null) 'type': NodeType.instance.name,
      if (asInstanceOf != null) 'masterComponentId': asInstanceOf,
      if (asInstanceOf != null) 'name': orig.name.replaceFirst('❖ ', ''),
    });
    nodes[copyId] = created;

    for (final cid in orig.children) {
      final clonedChild = _deepCloneSubtree(cid, newParentId: copyId);
      if (clonedChild != null) created.children.add(clonedChild);
    }
    return copyId;
  }

  Map<String, dynamic>? _serializeSubtree(String id) {
    final n = nodes[id];
    if (n == null) return null;
    return {
      'node': n.toJson(),
      'kids': n.children
          .map(_serializeSubtree)
          .whereType<Map<String, dynamic>>()
          .toList(),
    };
  }

  String? _deserializeSubtree(
    Map<String, dynamic> data, {
    required String? parentId,
    Offset offset = Offset.zero,
  }) {
    final rawNode = Map<String, dynamic>.from(data['node'] as Map);
    final newId = _nextId(rawNode['type']?.toString() ?? 'node');
    rawNode['id'] = newId;
    rawNode['parentId'] = parentId;
    rawNode['children'] = <String>[];
    rawNode['x'] = ((rawNode['x'] as num?)?.toDouble() ?? 0) + offset.dx;
    rawNode['y'] = ((rawNode['y'] as num?)?.toDouble() ?? 0) + offset.dy;
    final node = DesignNode.fromJson(rawNode);
    nodes[newId] = node;
    for (final kid in (data['kids'] as List?) ?? []) {
      final cid = _deserializeSubtree(
        Map<String, dynamic>.from(kid as Map),
        parentId: newId,
      );
      if (cid != null) node.children.add(cid);
    }
    return newId;
  }

  String _defaultName(NodeType t) {
    switch (t) {
      case NodeType.frame:
        return 'Frame';
      case NodeType.group:
        return 'Group';
      case NodeType.rectangle:
        return 'Rectangle';
      case NodeType.ellipse:
        return 'Ellipse';
      case NodeType.polygon:
        return 'Polygon';
      case NodeType.star:
        return 'Star';
      case NodeType.line:
        return 'Line';
      case NodeType.arrow:
        return 'Arrow';
      case NodeType.path:
        return 'Path';
      case NodeType.text:
        return 'Text';
      case NodeType.image:
        return 'Image';
      case NodeType.component:
        return 'Component';
      case NodeType.instance:
        return 'Instance';
    }
  }

  void refresh() => notifyListeners();
}
