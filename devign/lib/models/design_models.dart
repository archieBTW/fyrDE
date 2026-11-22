import 'dart:ui' as ui;
import 'package:flutter/material.dart';

enum DevignTool {
  select,
  frame,
  rectangle,
  ellipse,
  polygon,
  star,
  line,
  arrow,
  pen,
  text,
  comment,
  hand,
}

enum NodeType {
  frame,
  group,
  rectangle,
  ellipse,
  polygon,
  star,
  line,
  arrow,
  path,
  text,
  image,
  component,
  instance,
}

enum FillKind { solid, linearGradient, radialGradient }

enum EffectKind { dropShadow, innerShadow, layerBlur, backgroundBlur }

enum AutoLayoutDirection { none, horizontal, vertical }

enum AutoLayoutAlign { start, center, end, spaceBetween }

enum PrototypeTransition { instant, dissolve, slideLeft, slideUp }

enum PrototypeAction { navigate, back, overlay }

class FillPaint {
  FillKind kind;
  Color color;
  Color secondaryColor;
  double gradientAngleDeg;
  double opacity;
  bool visible;

  FillPaint({
    this.kind = FillKind.solid,
    this.color = const Color(0xFF7C4DFF),
    this.secondaryColor = const Color(0xFFE040FB),
    this.gradientAngleDeg = 135.0,
    this.opacity = 1.0,
    this.visible = true,
  });

  FillPaint clone() => FillPaint(
        kind: kind,
        color: color,
        secondaryColor: secondaryColor,
        gradientAngleDeg: gradientAngleDeg,
        opacity: opacity,
        visible: visible,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'color': color.toARGB32(),
        'secondaryColor': secondaryColor.toARGB32(),
        'gradientAngleDeg': gradientAngleDeg,
        'opacity': opacity,
        'visible': visible,
      };

  factory FillPaint.fromJson(Map<String, dynamic> j) => FillPaint(
        kind: FillKind.values.firstWhere(
          (e) => e.name == j['kind'],
          orElse: () => FillKind.solid,
        ),
        color: Color((j['color'] as num?)?.toInt() ?? 0xFF7C4DFF),
        secondaryColor:
            Color((j['secondaryColor'] as num?)?.toInt() ?? 0xFFE040FB),
        gradientAngleDeg: (j['gradientAngleDeg'] as num?)?.toDouble() ?? 135.0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        visible: j['visible'] != false,
      );
}

class StrokePaint {
  Color color;
  double width;
  double opacity;
  bool dashed;
  double dashLength;
  bool visible;

  StrokePaint({
    this.color = const Color(0xFFFFFFFF),
    this.width = 1.5,
    this.opacity = 1.0,
    this.dashed = false,
    this.dashLength = 6.0,
    this.visible = true,
  });

  StrokePaint clone() => StrokePaint(
        color: color,
        width: width,
        opacity: opacity,
        dashed: dashed,
        dashLength: dashLength,
        visible: visible,
      );

  Map<String, dynamic> toJson() => {
        'color': color.toARGB32(),
        'width': width,
        'opacity': opacity,
        'dashed': dashed,
        'dashLength': dashLength,
        'visible': visible,
      };

  factory StrokePaint.fromJson(Map<String, dynamic> j) => StrokePaint(
        color: Color((j['color'] as num?)?.toInt() ?? 0xFFFFFFFF),
        width: (j['width'] as num?)?.toDouble() ?? 1.5,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        dashed: j['dashed'] == true,
        dashLength: (j['dashLength'] as num?)?.toDouble() ?? 6.0,
        visible: j['visible'] != false,
      );
}

class NodeEffect {
  EffectKind kind;
  Color color;
  double offsetX;
  double offsetY;
  double blurRadius;
  double spread;
  bool visible;

  NodeEffect({
    this.kind = EffectKind.dropShadow,
    this.color = const Color(0x66000000),
    this.offsetX = 0.0,
    this.offsetY = 8.0,
    this.blurRadius = 20.0,
    this.spread = 0.0,
    this.visible = true,
  });

  NodeEffect clone() => NodeEffect(
        kind: kind,
        color: color,
        offsetX: offsetX,
        offsetY: offsetY,
        blurRadius: blurRadius,
        spread: spread,
        visible: visible,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'color': color.toARGB32(),
        'offsetX': offsetX,
        'offsetY': offsetY,
        'blurRadius': blurRadius,
        'spread': spread,
        'visible': visible,
      };

  factory NodeEffect.fromJson(Map<String, dynamic> j) => NodeEffect(
        kind: EffectKind.values.firstWhere(
          (e) => e.name == j['kind'],
          orElse: () => EffectKind.dropShadow,
        ),
        color: Color((j['color'] as num?)?.toInt() ?? 0x66000000),
        offsetX: (j['offsetX'] as num?)?.toDouble() ?? 0.0,
        offsetY: (j['offsetY'] as num?)?.toDouble() ?? 8.0,
        blurRadius: (j['blurRadius'] as num?)?.toDouble() ?? 20.0,
        spread: (j['spread'] as num?)?.toDouble() ?? 0.0,
        visible: j['visible'] != false,
      );
}

class AutoLayoutConfig {
  AutoLayoutDirection direction;
  double gap;
  double paddingH;
  double paddingV;
  AutoLayoutAlign primaryAlign;
  AutoLayoutAlign crossAlign;

  AutoLayoutConfig({
    this.direction = AutoLayoutDirection.none,
    this.gap = 12.0,
    this.paddingH = 16.0,
    this.paddingV = 16.0,
    this.primaryAlign = AutoLayoutAlign.start,
    this.crossAlign = AutoLayoutAlign.start,
  });

  bool get enabled => direction != AutoLayoutDirection.none;

  AutoLayoutConfig clone() => AutoLayoutConfig(
        direction: direction,
        gap: gap,
        paddingH: paddingH,
        paddingV: paddingV,
        primaryAlign: primaryAlign,
        crossAlign: crossAlign,
      );

  Map<String, dynamic> toJson() => {
        'direction': direction.name,
        'gap': gap,
        'paddingH': paddingH,
        'paddingV': paddingV,
        'primaryAlign': primaryAlign.name,
        'crossAlign': crossAlign.name,
      };

  factory AutoLayoutConfig.fromJson(Map<String, dynamic> j) => AutoLayoutConfig(
        direction: AutoLayoutDirection.values.firstWhere(
          (e) => e.name == j['direction'],
          orElse: () => AutoLayoutDirection.none,
        ),
        gap: (j['gap'] as num?)?.toDouble() ?? 12.0,
        paddingH: (j['paddingH'] as num?)?.toDouble() ?? 16.0,
        paddingV: (j['paddingV'] as num?)?.toDouble() ?? 16.0,
        primaryAlign: AutoLayoutAlign.values.firstWhere(
          (e) => e.name == j['primaryAlign'],
          orElse: () => AutoLayoutAlign.start,
        ),
        crossAlign: AutoLayoutAlign.values.firstWhere(
          (e) => e.name == j['crossAlign'],
          orElse: () => AutoLayoutAlign.start,
        ),
      );
}

class BezierPoint {
  Offset anchor;
  Offset? handleIn;
  Offset? handleOut;

  BezierPoint({required this.anchor, this.handleIn, this.handleOut});

  BezierPoint clone() =>
      BezierPoint(anchor: anchor, handleIn: handleIn, handleOut: handleOut);

  Map<String, dynamic> toJson() => {
        'ax': anchor.dx,
        'ay': anchor.dy,
        if (handleIn != null) 'ix': handleIn!.dx,
        if (handleIn != null) 'iy': handleIn!.dy,
        if (handleOut != null) 'ox': handleOut!.dx,
        if (handleOut != null) 'oy': handleOut!.dy,
      };

  factory BezierPoint.fromJson(Map<String, dynamic> j) => BezierPoint(
        anchor: Offset(
          (j['ax'] as num?)?.toDouble() ?? 0,
          (j['ay'] as num?)?.toDouble() ?? 0,
        ),
        handleIn: j.containsKey('ix')
            ? Offset((j['ix'] as num).toDouble(), (j['iy'] as num).toDouble())
            : null,
        handleOut: j.containsKey('ox')
            ? Offset((j['ox'] as num).toDouble(), (j['oy'] as num).toDouble())
            : null,
      );
}

class PrototypeLink {
  PrototypeAction action;
  String? targetFrameId;
  PrototypeTransition transition;
  int durationMs;

  PrototypeLink({
    this.action = PrototypeAction.navigate,
    this.targetFrameId,
    this.transition = PrototypeTransition.slideLeft,
    this.durationMs = 280,
  });

  PrototypeLink clone() => PrototypeLink(
        action: action,
        targetFrameId: targetFrameId,
        transition: transition,
        durationMs: durationMs,
      );

  Map<String, dynamic> toJson() => {
        'action': action.name,
        'targetFrameId': targetFrameId,
        'transition': transition.name,
        'durationMs': durationMs,
      };

  factory PrototypeLink.fromJson(Map<String, dynamic> j) => PrototypeLink(
        action: PrototypeAction.values.firstWhere(
          (e) => e.name == j['action'],
          orElse: () => PrototypeAction.navigate,
        ),
        targetFrameId: j['targetFrameId'] as String?,
        transition: PrototypeTransition.values.firstWhere(
          (e) => e.name == j['transition'],
          orElse: () => PrototypeTransition.slideLeft,
        ),
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 280,
      );
}

class CanvasComment {
  final String id;
  Offset position;
  String author;
  String message;
  bool resolved;
  DateTime timestamp;

  CanvasComment({
    required this.id,
    required this.position,
    this.author = 'Designer',
    required this.message,
    this.resolved = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  CanvasComment clone() => CanvasComment(
        id: id,
        position: position,
        author: author,
        message: message,
        resolved: resolved,
        timestamp: timestamp,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'x': position.dx,
        'y': position.dy,
        'author': author,
        'message': message,
        'resolved': resolved,
        'timestamp': timestamp.toIso8601String(),
      };

  factory CanvasComment.fromJson(Map<String, dynamic> j) => CanvasComment(
        id: j['id'] as String? ?? '',
        position: Offset(
          (j['x'] as num?)?.toDouble() ?? 0,
          (j['y'] as num?)?.toDouble() ?? 0,
        ),
        author: j['author'] as String? ?? 'Designer',
        message: j['message'] as String? ?? '',
        resolved: j['resolved'] == true,
        timestamp:
            DateTime.tryParse(j['timestamp'] as String? ?? '') ?? DateTime.now(),
      );
}

class ColorToken {
  final String id;
  String name;
  Color color;

  ColorToken({required this.id, required this.name, required this.color});

  ColorToken clone() => ColorToken(id: id, name: name, color: color);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': color.toARGB32(),
      };

  factory ColorToken.fromJson(Map<String, dynamic> j) => ColorToken(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? 'Token',
        color: Color((j['color'] as num?)?.toInt() ?? 0xFF7C4DFF),
      );
}

class DesignNode {
  final String id;
  String name;
  NodeType type;
  String? parentId;
  List<String> children;
  String? masterComponentId;

  double x;
  double y;
  double width;
  double height;
  double rotationDeg;
  double opacity;
  bool visible;
  bool locked;
  bool clipContent;
  ui.BlendMode blendMode;

  double radiusTL;
  double radiusTR;
  double radiusBR;
  double radiusBL;
  bool independentCorners;

  List<FillPaint> fills;
  List<StrokePaint> strokes;
  List<NodeEffect> effects;
  AutoLayoutConfig autoLayout;

  // Shape / Path / Text / Image specific
  int polygonSides;
  double starInnerRatio;
  List<BezierPoint> pathPoints;
  bool pathClosed;

  String text;
  String fontFamily;
  double fontSize;
  int fontWeightIndex; // 0..8 -> FontWeight.values
  bool italic;
  double letterSpacing;
  double lineHeight;
  TextAlign textAlign;

  String? imagePath;
  PrototypeLink? prototypeLink;

  DesignNode({
    required this.id,
    required this.name,
    required this.type,
    this.parentId,
    List<String>? children,
    this.masterComponentId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.rotationDeg = 0.0,
    this.opacity = 1.0,
    this.visible = true,
    this.locked = false,
    this.clipContent = false,
    this.blendMode = ui.BlendMode.srcOver,
    this.radiusTL = 0.0,
    this.radiusTR = 0.0,
    this.radiusBR = 0.0,
    this.radiusBL = 0.0,
    this.independentCorners = false,
    List<FillPaint>? fills,
    List<StrokePaint>? strokes,
    List<NodeEffect>? effects,
    AutoLayoutConfig? autoLayout,
    this.polygonSides = 6,
    this.starInnerRatio = 0.45,
    List<BezierPoint>? pathPoints,
    this.pathClosed = false,
    this.text = 'Heading',
    this.fontFamily = 'Inter',
    this.fontSize = 20.0,
    this.fontWeightIndex = 5, // w600
    this.italic = false,
    this.letterSpacing = 0.0,
    this.lineHeight = 1.25,
    this.textAlign = TextAlign.left,
    this.imagePath,
    this.prototypeLink,
  })  : children = children ?? [],
        fills = fills ?? [],
        strokes = strokes ?? [],
        effects = effects ?? [],
        autoLayout = autoLayout ?? AutoLayoutConfig(),
        pathPoints = pathPoints ?? [];

  bool get isContainer =>
      type == NodeType.frame ||
      type == NodeType.group ||
      type == NodeType.component ||
      type == NodeType.instance;

  FontWeight get fontWeight =>
      FontWeight.values[fontWeightIndex.clamp(0, FontWeight.values.length - 1)];

  void setUniformRadius(double r) {
    radiusTL = r;
    radiusTR = r;
    radiusBR = r;
    radiusBL = r;
  }

  RRect toRRect(Rect rect) => RRect.fromRectAndCorners(
        rect,
        topLeft: Radius.circular(radiusTL),
        topRight: Radius.circular(radiusTR),
        bottomRight: Radius.circular(radiusBR),
        bottomLeft: Radius.circular(radiusBL),
      );

  DesignNode clone() => DesignNode(
        id: id,
        name: name,
        type: type,
        parentId: parentId,
        children: List<String>.from(children),
        masterComponentId: masterComponentId,
        x: x,
        y: y,
        width: width,
        height: height,
        rotationDeg: rotationDeg,
        opacity: opacity,
        visible: visible,
        locked: locked,
        clipContent: clipContent,
        blendMode: blendMode,
        radiusTL: radiusTL,
        radiusTR: radiusTR,
        radiusBR: radiusBR,
        radiusBL: radiusBL,
        independentCorners: independentCorners,
        fills: fills.map((f) => f.clone()).toList(),
        strokes: strokes.map((s) => s.clone()).toList(),
        effects: effects.map((e) => e.clone()).toList(),
        autoLayout: autoLayout.clone(),
        polygonSides: polygonSides,
        starInnerRatio: starInnerRatio,
        pathPoints: pathPoints.map((p) => p.clone()).toList(),
        pathClosed: pathClosed,
        text: text,
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeightIndex: fontWeightIndex,
        italic: italic,
        letterSpacing: letterSpacing,
        lineHeight: lineHeight,
        textAlign: textAlign,
        imagePath: imagePath,
        prototypeLink: prototypeLink?.clone(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'parentId': parentId,
        'children': children,
        'masterComponentId': masterComponentId,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'rotationDeg': rotationDeg,
        'opacity': opacity,
        'visible': visible,
        'locked': locked,
        'clipContent': clipContent,
        'blendMode': blendMode.index,
        'radiusTL': radiusTL,
        'radiusTR': radiusTR,
        'radiusBR': radiusBR,
        'radiusBL': radiusBL,
        'independentCorners': independentCorners,
        'fills': fills.map((f) => f.toJson()).toList(),
        'strokes': strokes.map((s) => s.toJson()).toList(),
        'effects': effects.map((e) => e.toJson()).toList(),
        'autoLayout': autoLayout.toJson(),
        'polygonSides': polygonSides,
        'starInnerRatio': starInnerRatio,
        'pathPoints': pathPoints.map((p) => p.toJson()).toList(),
        'pathClosed': pathClosed,
        'text': text,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'fontWeightIndex': fontWeightIndex,
        'italic': italic,
        'letterSpacing': letterSpacing,
        'lineHeight': lineHeight,
        'textAlign': textAlign.index,
        'imagePath': imagePath,
        'prototypeLink': prototypeLink?.toJson(),
      };

  factory DesignNode.fromJson(Map<String, dynamic> j) => DesignNode(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? 'Layer',
        type: NodeType.values.firstWhere(
          (e) => e.name == j['type'],
          orElse: () => NodeType.rectangle,
        ),
        parentId: j['parentId'] as String?,
        children: (j['children'] as List?)?.cast<String>() ?? [],
        masterComponentId: j['masterComponentId'] as String?,
        x: (j['x'] as num?)?.toDouble() ?? 0,
        y: (j['y'] as num?)?.toDouble() ?? 0,
        width: (j['width'] as num?)?.toDouble() ?? 100,
        height: (j['height'] as num?)?.toDouble() ?? 100,
        rotationDeg: (j['rotationDeg'] as num?)?.toDouble() ?? 0,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1,
        visible: j['visible'] != false,
        locked: j['locked'] == true,
        clipContent: j['clipContent'] == true,
        blendMode: ui.BlendMode.values[((j['blendMode'] as num?)?.toInt() ?? 3)
            .clamp(0, ui.BlendMode.values.length - 1)],
        radiusTL: (j['radiusTL'] as num?)?.toDouble() ?? 0,
        radiusTR: (j['radiusTR'] as num?)?.toDouble() ?? 0,
        radiusBR: (j['radiusBR'] as num?)?.toDouble() ?? 0,
        radiusBL: (j['radiusBL'] as num?)?.toDouble() ?? 0,
        independentCorners: j['independentCorners'] == true,
        fills: ((j['fills'] as List?) ?? [])
            .map((e) => FillPaint.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        strokes: ((j['strokes'] as List?) ?? [])
            .map(
                (e) => StrokePaint.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        effects: ((j['effects'] as List?) ?? [])
            .map(
                (e) => NodeEffect.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        autoLayout: j['autoLayout'] is Map
            ? AutoLayoutConfig.fromJson(
                Map<String, dynamic>.from(j['autoLayout'] as Map))
            : AutoLayoutConfig(),
        polygonSides: (j['polygonSides'] as num?)?.toInt() ?? 6,
        starInnerRatio: (j['starInnerRatio'] as num?)?.toDouble() ?? 0.45,
        pathPoints: ((j['pathPoints'] as List?) ?? [])
            .map(
                (e) => BezierPoint.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        pathClosed: j['pathClosed'] == true,
        text: j['text'] as String? ?? 'Text',
        fontFamily: j['fontFamily'] as String? ?? 'Inter',
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 20,
        fontWeightIndex: (j['fontWeightIndex'] as num?)?.toInt() ?? 5,
        italic: j['italic'] == true,
        letterSpacing: (j['letterSpacing'] as num?)?.toDouble() ?? 0,
        lineHeight: (j['lineHeight'] as num?)?.toDouble() ?? 1.25,
        textAlign: TextAlign.values[((j['textAlign'] as num?)?.toInt() ?? 0)
            .clamp(0, TextAlign.values.length - 1)],
        imagePath: j['imagePath'] as String?,
        prototypeLink: j['prototypeLink'] is Map
            ? PrototypeLink.fromJson(
                Map<String, dynamic>.from(j['prototypeLink'] as Map))
            : null,
      );
}

class DesignPage {
  final String id;
  String name;
  List<String> rootIds;
  List<CanvasComment> comments;
  String? flowStartFrameId;
  double zoom;
  Offset pan;

  DesignPage({
    required this.id,
    required this.name,
    List<String>? rootIds,
    List<CanvasComment>? comments,
    this.flowStartFrameId,
    this.zoom = 0.72,
    this.pan = Offset.zero,
  })  : rootIds = rootIds ?? [],
        comments = comments ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'rootIds': rootIds,
        'comments': comments.map((c) => c.toJson()).toList(),
        'flowStartFrameId': flowStartFrameId,
        'zoom': zoom,
        'panX': pan.dx,
        'panY': pan.dy,
      };

  factory DesignPage.fromJson(Map<String, dynamic> j) => DesignPage(
        id: j['id'] as String? ?? '',
        name: j['name'] as String? ?? 'Page 1',
        rootIds: (j['rootIds'] as List?)?.cast<String>() ?? [],
        comments: ((j['comments'] as List?) ?? [])
            .map((e) =>
                CanvasComment.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        flowStartFrameId: j['flowStartFrameId'] as String?,
        zoom: (j['zoom'] as num?)?.toDouble() ?? 0.75,
        pan: Offset(
          (j['panX'] as num?)?.toDouble() ?? 0,
          (j['panY'] as num?)?.toDouble() ?? 0,
        ),
      );
}

class FramePreset {
  final String name;
  final String category;
  final double width;
  final double height;
  const FramePreset(this.name, this.category, this.width, this.height);
}

const List<FramePreset> kFramePresets = [
  FramePreset('iPhone 15 Pro', 'Mobile', 393, 852),
  FramePreset('Android Pixel', 'Mobile', 412, 915),
  FramePreset('iPad Pro 11"', 'Tablet', 834, 1194),
  FramePreset('Desktop 1440', 'Desktop', 1440, 900),
  FramePreset('MacBook Air', 'Desktop', 1280, 832),
  FramePreset('Slide 16:9', 'Presentation', 1920, 1080),
  FramePreset('Instagram Post', 'Social', 1080, 1080),
  FramePreset('Open Graph Card', 'Social', 1200, 630),
];
