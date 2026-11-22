import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/design_models.dart';

class DevignExport {
  static String colorToHex(Color c, {bool includeAlpha = false}) {
    final argb = c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
    return includeAlpha ? '#$argb' : '#${argb.substring(2)}';
  }

  static String colorToRgbaCss(Color c, {double extraOpacity = 1.0}) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    final a = (c.a * extraOpacity).clamp(0.0, 1.0);
    if (a >= 0.995) return colorToHex(c);
    return 'rgba($r, $g, $b, ${a.toStringAsFixed(2)})';
  }

  // ---------------------------------------------------------------------------
  // Live CSS Code Generator (Dev Mode)
  // ---------------------------------------------------------------------------

  static String generateCss(DesignNode node) {
    final buf = StringBuffer()
      ..writeln('/* ${node.name} (${node.type.name}) */')
      ..writeln('.${_slug(node.name)} {')
      ..writeln('  width: ${node.width.round()}px;')
      ..writeln('  height: ${node.height.round()}px;');

    if (node.rotationDeg.abs() > 0.1) {
      buf.writeln('  transform: rotate(${node.rotationDeg.toStringAsFixed(1)}deg);');
    }
    if (node.opacity < 0.999) {
      buf.writeln('  opacity: ${node.opacity.toStringAsFixed(2)};');
    }

    if (node.type == NodeType.ellipse) {
      buf.writeln('  border-radius: 9999px;');
    } else if (node.radiusTL > 0 ||
        node.radiusTR > 0 ||
        node.radiusBR > 0 ||
        node.radiusBL > 0) {
      if (node.independentCorners) {
        buf.writeln(
          '  border-radius: ${node.radiusTL.round()}px ${node.radiusTR.round()}px ${node.radiusBR.round()}px ${node.radiusBL.round()}px;',
        );
      } else {
        buf.writeln('  border-radius: ${node.radiusTL.round()}px;');
      }
    }

    final visibleFills = node.fills.where((f) => f.visible).toList();
    if (visibleFills.isNotEmpty) {
      final f = visibleFills.last;
      if (node.type == NodeType.text) {
        buf.writeln('  color: ${colorToRgbaCss(f.color, extraOpacity: f.opacity)};');
      } else if (f.kind == FillKind.solid) {
        buf.writeln(
            '  background: ${colorToRgbaCss(f.color, extraOpacity: f.opacity)};');
      } else if (f.kind == FillKind.linearGradient) {
        buf.writeln(
          '  background: linear-gradient(${f.gradientAngleDeg.round()}deg, ${colorToRgbaCss(f.color, extraOpacity: f.opacity)}, ${colorToRgbaCss(f.secondaryColor, extraOpacity: f.opacity)});',
        );
      } else {
        buf.writeln(
          '  background: radial-gradient(circle, ${colorToRgbaCss(f.color, extraOpacity: f.opacity)}, ${colorToRgbaCss(f.secondaryColor, extraOpacity: f.opacity)});',
        );
      }
    }

    final visibleStrokes = node.strokes.where((s) => s.visible).toList();
    if (visibleStrokes.isNotEmpty) {
      final s = visibleStrokes.last;
      final style = s.dashed ? 'dashed' : 'solid';
      buf.writeln(
        '  border: ${s.width.toStringAsFixed(1)}px $style ${colorToRgbaCss(s.color, extraOpacity: s.opacity)};',
      );
    }

    if (node.type == NodeType.text) {
      buf.writeln("  font-family: '${node.fontFamily}', sans-serif;");
      buf.writeln('  font-size: ${node.fontSize.round()}px;');
      buf.writeln('  font-weight: ${(node.fontWeightIndex + 1) * 100};');
      if (node.italic) buf.writeln('  font-style: italic;');
      buf.writeln('  line-height: ${node.lineHeight.toStringAsFixed(2)};');
      if (node.letterSpacing.abs() > 0.05) {
        buf.writeln(
            '  letter-spacing: ${node.letterSpacing.toStringAsFixed(1)}px;');
      }
      buf.writeln('  text-align: ${node.textAlign.name};');
    }

    if (node.autoLayout.enabled) {
      buf.writeln('  display: flex;');
      buf.writeln(
        '  flex-direction: ${node.autoLayout.direction == AutoLayoutDirection.horizontal ? 'row' : 'column'};',
      );
      buf.writeln('  gap: ${node.autoLayout.gap.round()}px;');
      buf.writeln(
        '  padding: ${node.autoLayout.paddingV.round()}px ${node.autoLayout.paddingH.round()}px;',
      );
      buf.writeln('  justify-content: ${_cssAlign(node.autoLayout.primaryAlign)};');
      buf.writeln('  align-items: ${_cssAlign(node.autoLayout.crossAlign)};');
    }

    final shadows = node.effects
        .where((e) =>
            e.visible &&
            (e.kind == EffectKind.dropShadow ||
                e.kind == EffectKind.innerShadow))
        .toList();
    if (shadows.isNotEmpty) {
      final parts = shadows.map((e) {
        final inset = e.kind == EffectKind.innerShadow ? 'inset ' : '';
        return '$inset${e.offsetX.round()}px ${e.offsetY.round()}px ${e.blurRadius.round()}px ${e.spread.round()}px ${colorToRgbaCss(e.color)}';
      }).join(', ');
      buf.writeln('  box-shadow: $parts;');
    }

    for (final e in node.effects.where((e) => e.visible)) {
      if (e.kind == EffectKind.layerBlur) {
        buf.writeln('  filter: blur(${e.blurRadius.round()}px);');
      } else if (e.kind == EffectKind.backgroundBlur) {
        buf.writeln('  backdrop-filter: blur(${e.blurRadius.round()}px);');
      }
    }

    if (node.clipContent) {
      buf.writeln('  overflow: hidden;');
    }

    buf.writeln('}');
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Live Flutter Widget Code Generator (Dev Mode)
  // ---------------------------------------------------------------------------

  static String generateFlutterCode(DesignNode node) {
    final buf = StringBuffer()..writeln('// ${node.name}');
    if (node.type == NodeType.text) {
      final c = node.fills.isNotEmpty ? node.fills.last.color : Colors.white;
      buf.writeln("Text(");
      buf.writeln("  '${node.text.replaceAll("'", "\\'")}',");
      buf.writeln('  textAlign: TextAlign.${node.textAlign.name},');
      buf.writeln('  style: const TextStyle(');
      buf.writeln("    fontFamily: '${node.fontFamily}',");
      buf.writeln('    fontSize: ${node.fontSize.toStringAsFixed(1)},');
      buf.writeln('    fontWeight: FontWeight.w${(node.fontWeightIndex + 1) * 100},');
      buf.writeln('    color: Color(0x${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}),');
      buf.writeln('  ),');
      buf.writeln(')');
      return buf.toString();
    }

    buf.writeln('Container(');
    buf.writeln('  width: ${node.width.toStringAsFixed(1)},');
    buf.writeln('  height: ${node.height.toStringAsFixed(1)},');
    if (node.autoLayout.enabled) {
      buf.writeln(
        '  padding: const EdgeInsets.symmetric(horizontal: ${node.autoLayout.paddingH.round()}, vertical: ${node.autoLayout.paddingV.round()}),',
      );
    }
    buf.writeln('  decoration: BoxDecoration(');
    final visibleFills = node.fills.where((f) => f.visible).toList();
    if (visibleFills.isNotEmpty) {
      final f = visibleFills.last;
      final c1 =
          'Color(0x${f.color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()})';
      final c2 =
          'Color(0x${f.secondaryColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()})';
      if (f.kind == FillKind.solid) {
        buf.writeln('    color: $c1,');
      } else if (f.kind == FillKind.linearGradient) {
        buf.writeln('    gradient: const LinearGradient(colors: [$c1, $c2]),');
      } else {
        buf.writeln('    gradient: const RadialGradient(colors: [$c1, $c2]),');
      }
    }
    if (node.type == NodeType.ellipse) {
      buf.writeln('    shape: BoxShape.circle,');
    } else if (node.radiusTL > 0) {
      buf.writeln('    borderRadius: BorderRadius.circular(${node.radiusTL.round()}),');
    }
    final visibleStrokes = node.strokes.where((s) => s.visible).toList();
    if (visibleStrokes.isNotEmpty) {
      final s = visibleStrokes.last;
      final sc =
          'Color(0x${s.color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()})';
      buf.writeln('    border: Border.all(color: $sc, width: ${s.width.toStringAsFixed(1)}),');
    }
    final shadows = node.effects
        .where((e) => e.visible && e.kind == EffectKind.dropShadow)
        .toList();
    if (shadows.isNotEmpty) {
      buf.writeln('    boxShadow: const [');
      for (final s in shadows) {
        final sc =
            'Color(0x${s.color.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()})';
        buf.writeln(
          '      BoxShadow(color: $sc, blurRadius: ${s.blurRadius.round()}, offset: Offset(${s.offsetX.round()}, ${s.offsetY.round()})),',
        );
      }
      buf.writeln('    ],');
    }
    buf.writeln('  ),');
    buf.writeln(')');
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // Standalone SVG Generator & Exporter
  // ---------------------------------------------------------------------------

  static String generateSvg(
    DesignNode root,
    Map<String, DesignNode> nodes,
  ) {
    final defs = StringBuffer();
    final body = StringBuffer();
    int defCounter = 0;

    void writeNode(DesignNode n, double ox, double oy) {
      if (!n.visible) return;
      final x = n.x - ox;
      final y = n.y - oy;

      String fillAttr = 'none';
      double fillOpacity = n.opacity;
      final visFills = n.fills.where((f) => f.visible).toList();
      if (visFills.isNotEmpty) {
        final f = visFills.last;
        fillOpacity = (n.opacity * f.opacity).clamp(0.0, 1.0);
        if (f.kind == FillKind.solid) {
          fillAttr = colorToHex(f.color);
        } else {
          final gid = 'grad_${defCounter++}';
          if (f.kind == FillKind.linearGradient) {
            final rad = f.gradientAngleDeg * pi / 180.0;
            final x2 = (50 + 50 * cos(rad)).round();
            final y2 = (50 + 50 * sin(rad)).round();
            defs.writeln(
              '  <linearGradient id="$gid" x1="0%" y1="0%" x2="$x2%" y2="$y2%">'
              '<stop offset="0%" stop-color="${colorToHex(f.color)}"/>'
              '<stop offset="100%" stop-color="${colorToHex(f.secondaryColor)}"/>'
              '</linearGradient>',
            );
          } else {
            defs.writeln(
              '  <radialGradient id="$gid">'
              '<stop offset="0%" stop-color="${colorToHex(f.color)}"/>'
              '<stop offset="100%" stop-color="${colorToHex(f.secondaryColor)}"/>'
              '</radialGradient>',
            );
          }
          fillAttr = 'url(#$gid)';
        }
      }

      String strokeAttr = '';
      final visStrokes = n.strokes.where((s) => s.visible).toList();
      if (visStrokes.isNotEmpty) {
        final s = visStrokes.last;
        final dash = s.dashed ? ' stroke-dasharray="${s.dashLength} ${s.dashLength}"' : '';
        strokeAttr =
            ' stroke="${colorToHex(s.color)}" stroke-width="${s.width}"$dash';
      }

      final rot = n.rotationDeg.abs() > 0.1
          ? ' transform="rotate(${n.rotationDeg.toStringAsFixed(1)} ${(x + n.width / 2).toStringAsFixed(1)} ${(y + n.height / 2).toStringAsFixed(1)})"'
          : '';

      switch (n.type) {
        case NodeType.frame:
        case NodeType.component:
        case NodeType.instance:
        case NodeType.rectangle:
          body.writeln(
            '  <rect x="${x.toStringAsFixed(1)}" y="${y.toStringAsFixed(1)}" width="${n.width.toStringAsFixed(1)}" height="${n.height.toStringAsFixed(1)}" rx="${n.radiusTL.toStringAsFixed(1)}" fill="$fillAttr" fill-opacity="${fillOpacity.toStringAsFixed(2)}"$strokeAttr$rot/>',
          );
          break;
        case NodeType.ellipse:
          body.writeln(
            '  <ellipse cx="${(x + n.width / 2).toStringAsFixed(1)}" cy="${(y + n.height / 2).toStringAsFixed(1)}" rx="${(n.width / 2).toStringAsFixed(1)}" ry="${(n.height / 2).toStringAsFixed(1)}" fill="$fillAttr" fill-opacity="${fillOpacity.toStringAsFixed(2)}"$strokeAttr$rot/>',
          );
          break;
        case NodeType.line:
        case NodeType.arrow:
          body.writeln(
            '  <line x1="${x.toStringAsFixed(1)}" y1="${y.toStringAsFixed(1)}" x2="${(x + n.width).toStringAsFixed(1)}" y2="${(y + n.height).toStringAsFixed(1)}"$strokeAttr$rot/>',
          );
          break;
        case NodeType.polygon:
        case NodeType.star:
          final pts = _shapePolygonPoints(n, x, y)
              .map((p) => '${p.dx.toStringAsFixed(1)},${p.dy.toStringAsFixed(1)}')
              .join(' ');
          body.writeln(
            '  <polygon points="$pts" fill="$fillAttr" fill-opacity="${fillOpacity.toStringAsFixed(2)}"$strokeAttr$rot/>',
          );
          break;
        case NodeType.path:
          final d = _bezierToSvgPath(n, x, y);
          body.writeln(
            '  <path d="$d" fill="${n.pathClosed ? fillAttr : 'none'}" fill-opacity="${fillOpacity.toStringAsFixed(2)}"$strokeAttr$rot/>',
          );
          break;
        case NodeType.text:
          final escaped = n.text
              .replaceAll('&', '&amp;')
              .replaceAll('<', '&lt;')
              .replaceAll('>', '&gt;');
          body.writeln(
            '  <text x="${x.toStringAsFixed(1)}" y="${(y + n.fontSize).toStringAsFixed(1)}" font-family="${n.fontFamily}" font-size="${n.fontSize.round()}" font-weight="${(n.fontWeightIndex + 1) * 100}" fill="$fillAttr"$rot>$escaped</text>',
          );
          break;
        case NodeType.group:
        case NodeType.image:
          break;
      }

      for (final cid in n.children) {
        final child = nodes[cid];
        if (child != null) {
          writeNode(child, ox - (n.x - ox), oy - (n.y - oy));
        }
      }
    }

    writeNode(root, root.x, root.y);

    return '<svg xmlns="http://www.w3.org/2000/svg" width="${root.width.round()}" height="${root.height.round()}" viewBox="0 0 ${root.width.round()} ${root.height.round()}">\n'
        '${defs.isNotEmpty ? '<defs>\n$defs</defs>\n' : ''}'
        '$body'
        '</svg>\n';
  }

  static Future<void> exportNodeToPng({
    required DesignNode root,
    required Map<String, DesignNode> nodes,
    required String outputPath,
    required void Function(Canvas canvas, DesignNode root) paintCallback,
    double scale = 2.0,
  }) async {
    final w = max(1, (root.width * scale).round());
    final h = max(1, (root.height * scale).round());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.scale(scale);
    canvas.translate(-root.x, -root.y);
    paintCallback(canvas, root);
    final pic = recorder.endRecording();
    final img = await pic.toImage(w, h);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (bytes != null) {
      await File(outputPath).writeAsBytes(bytes.buffer.asUint8List());
    }
  }

  static List<Offset> _shapePolygonPoints(DesignNode n, double x, double y) {
    final cx = x + n.width / 2;
    final cy = y + n.height / 2;
    final rx = n.width / 2;
    final ry = n.height / 2;
    final pts = <Offset>[];
    if (n.type == NodeType.star) {
      final spikes = n.polygonSides.clamp(3, 16);
      for (int i = 0; i < spikes * 2; i++) {
        final a = -pi / 2 + (pi * i) / spikes;
        final factor = i.isEven ? 1.0 : n.starInnerRatio;
        pts.add(Offset(cx + rx * factor * cos(a), cy + ry * factor * sin(a)));
      }
    } else {
      final sides = n.polygonSides.clamp(3, 16);
      for (int i = 0; i < sides; i++) {
        final a = -pi / 2 + (2 * pi * i) / sides;
        pts.add(Offset(cx + rx * cos(a), cy + ry * sin(a)));
      }
    }
    return pts;
  }

  static String _bezierToSvgPath(DesignNode n, double ox, double oy) {
    if (n.pathPoints.isEmpty) return '';
    final b = StringBuffer();
    for (int i = 0; i < n.pathPoints.length; i++) {
      final p = n.pathPoints[i];
      final ax = ox + p.anchor.dx;
      final ay = oy + p.anchor.dy;
      if (i == 0) {
        b.write('M ${ax.toStringAsFixed(1)} ${ay.toStringAsFixed(1)} ');
      } else {
        final prev = n.pathPoints[i - 1];
        if (prev.handleOut != null || p.handleIn != null) {
          final c1 = prev.anchor + (prev.handleOut ?? Offset.zero);
          final c2 = p.anchor + (p.handleIn ?? Offset.zero);
          b.write(
            'C ${(ox + c1.dx).toStringAsFixed(1)} ${(oy + c1.dy).toStringAsFixed(1)}, '
            '${(ox + c2.dx).toStringAsFixed(1)} ${(oy + c2.dy).toStringAsFixed(1)}, '
            '${ax.toStringAsFixed(1)} ${ay.toStringAsFixed(1)} ',
          );
        } else {
          b.write('L ${ax.toStringAsFixed(1)} ${ay.toStringAsFixed(1)} ');
        }
      }
    }
    if (n.pathClosed) b.write('Z');
    return b.toString().trim();
  }

  static String _slug(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');

  static String _cssAlign(AutoLayoutAlign a) {
    switch (a) {
      case AutoLayoutAlign.start:
        return 'flex-start';
      case AutoLayoutAlign.center:
        return 'center';
      case AutoLayoutAlign.end:
        return 'flex-end';
      case AutoLayoutAlign.spaceBetween:
        return 'space-between';
    }
  }
}
