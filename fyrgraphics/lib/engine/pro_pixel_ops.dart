import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/editor_types.dart';
import 'pixel_ops.dart';

class HistogramData {
  final List<int> r;
  final List<int> g;
  final List<int> b;
  final List<int> luma;
  final int maxCount;

  const HistogramData({
    required this.r,
    required this.g,
    required this.b,
    required this.luma,
    required this.maxCount,
  });
}

enum ColorLookPreset {
  warmFilm('Warm Film', 'Golden highlights, lifted matte shadows'),
  cinematicTeal('Cinematic Teal', 'Cool shadows with warm skin/highlights'),
  matteFade('Matte Fade', 'Soft faded blacks and muted pastel tones'),
  moodyNoir('Moody Noir', 'High-contrast silver monochrome'),
  goldenHour('Golden Hour', 'Rich sunset warmth & vibrance'),
  cyberNeon('Cyber Neon', 'Vibrant magenta/cyan contrast pop'),
  coolEditorial('Cool Editorial', 'Crisp studio coolness & clarity'),
  vintageSepia('Vintage Sepia', 'Warm nostalgic darkroom sepia');

  final String label;
  final String subtitle;
  const ColorLookPreset(this.label, this.subtitle);
}

class ProPixelOps {
  static final Random _rng = Random(42);

  // ---------------------------------------------------------------------------
  // Symmetry Point Transform Generator
  // ---------------------------------------------------------------------------

  static List<(Offset, Offset)> expandSymmetrySegments(
    Offset from,
    Offset to,
    int docWidth,
    int docHeight,
    SymmetryMode mode,
  ) {
    if (mode == SymmetryMode.off) return [(from, to)];
    final cx = docWidth / 2.0;
    final cy = docHeight / 2.0;

    Offset mirrorX(Offset p) => Offset(docWidth - p.dx, p.dy);
    Offset mirrorY(Offset p) => Offset(p.dx, docHeight - p.dy);
    Offset mirrorXY(Offset p) => Offset(docWidth - p.dx, docHeight - p.dy);

    switch (mode) {
      case SymmetryMode.off:
        return [(from, to)];
      case SymmetryMode.vertical:
        return [(from, to), (mirrorX(from), mirrorX(to))];
      case SymmetryMode.horizontal:
        return [(from, to), (mirrorY(from), mirrorY(to))];
      case SymmetryMode.quadrant:
        return [
          (from, to),
          (mirrorX(from), mirrorX(to)),
          (mirrorY(from), mirrorY(to)),
          (mirrorXY(from), mirrorXY(to)),
        ];
      case SymmetryMode.radial6:
      case SymmetryMode.radial8:
        final count = mode == SymmetryMode.radial6 ? 6 : 8;
        final out = <(Offset, Offset)>[];
        for (int i = 0; i < count; i++) {
          final theta = (2 * pi * i) / count;
          final c = cos(theta);
          final s = sin(theta);
          Offset rot(Offset p) {
            final dx = p.dx - cx;
            final dy = p.dy - cy;
            return Offset(cx + dx * c - dy * s, cy + dx * s + dy * c);
          }

          out.add((rot(from), rot(to)));
        }
        return out;
    }
  }

  // ---------------------------------------------------------------------------
  // Pro Brush Stroke (Alpha Lock + Calligraphic Nib + Scatter + Spacing)
  // ---------------------------------------------------------------------------

  static void drawProStrokeSegment({
    required Uint8List pixels,
    required int width,
    required int height,
    required Offset from,
    required Offset to,
    required double radius,
    required double hardness,
    required double opacity,
    required Color color,
    required bool erase,
    required bool hardPixelEdge,
    required bool alphaLock,
    double spacing = 0.18,
    double scatter = 0.0,
    double roundness = 1.0,
    double angleDeg = 0.0,
    Uint8List? selectionMask,
    int selectionWidth = 0,
    int selectionHeight = 0,
    double layerOffsetX = 0,
    double layerOffsetY = 0,
  }) {
    final dist = (to - from).distance;
    final step = max(1.0, radius * spacing.clamp(0.08, 1.0));
    final steps = max(1, (dist / step).ceil());
    final angleRad = angleDeg * pi / 180.0;
    final cosA = cos(-angleRad);
    final sinA = sin(-angleRad);
    final safeRound = roundness.clamp(0.15, 1.0);

    final srcR = (color.r * 255).round().clamp(0, 255);
    final srcG = (color.g * 255).round().clamp(0, 255);
    final srcB = (color.b * 255).round().clamp(0, 255);

    for (int i = 0; i <= steps; i++) {
      final t = steps == 0 ? 0.0 : i / steps;
      double cx = from.dx + (to.dx - from.dx) * t;
      double cy = from.dy + (to.dy - from.dy) * t;

      if (scatter > 0.001) {
        final spread = radius * scatter * 2.0;
        cx += (_rng.nextDouble() - 0.5) * spread;
        cy += (_rng.nextDouble() - 0.5) * spread;
      }

      if (roundness >= 0.98 && !alphaLock) {
        PixelOps.stampDab(
          pixels: pixels,
          width: width,
          height: height,
          cx: cx,
          cy: cy,
          radius: radius,
          hardness: hardness,
          opacity: opacity,
          color: color,
          erase: erase,
          hardPixelEdge: hardPixelEdge,
          selectionMask: selectionMask,
          selectionWidth: selectionWidth,
          selectionHeight: selectionHeight,
          layerOffsetX: layerOffsetX,
          layerOffsetY: layerOffsetY,
        );
        continue;
      }

      // Custom elliptical / calligraphic / alpha-locked dab
      final r = max(0.5, radius);
      final minX = max(0, (cx - r - 1).floor());
      final maxX = min(width - 1, (cx + r + 1).ceil());
      final minY = max(0, (cy - r - 1).floor());
      final maxY = min(height - 1, (cy + r + 1).ceil());
      final h = hardness.clamp(0.0, 1.0);

      for (int y = minY; y <= maxY; y++) {
        for (int x = minX; x <= maxX; x++) {
          final dx = x + 0.5 - cx;
          final dy = y + 0.5 - cy;
          final rx = dx * cosA - dy * sinA;
          final ry = (dx * sinA + dy * cosA) / safeRound;
          final d = sqrt(rx * rx + ry * ry) / r;
          if (d > 1.0) continue;

          double falloff;
          if (hardPixelEdge || h >= 0.99) {
            falloff = 1.0;
          } else if (d <= h) {
            falloff = 1.0;
          } else {
            final u = (d - h) / (1.0 - h);
            falloff = 0.5 * (1.0 + cos(pi * u));
          }

          double selFactor = 1.0;
          if (selectionMask != null && selectionWidth > 0 && selectionHeight > 0) {
            final sx = (x + layerOffsetX).round();
            final sy = (y + layerOffsetY).round();
            if (sx < 0 || sy < 0 || sx >= selectionWidth || sy >= selectionHeight) {
              continue;
            }
            final m = selectionMask[sy * selectionWidth + sx];
            if (m == 0) continue;
            selFactor = m / 255.0;
          }

          final effAlpha = (opacity * falloff * selFactor).clamp(0.0, 1.0);
          if (effAlpha <= 0.001) continue;

          final idx = (y * width + x) * 4;
          final dstA = pixels[idx + 3] / 255.0;

          if (alphaLock) {
            if (dstA <= 0.001) continue;
            if (!erase) {
              pixels[idx] =
                  (pixels[idx] + (srcR - pixels[idx]) * effAlpha).round().clamp(0, 255);
              pixels[idx + 1] =
                  (pixels[idx + 1] + (srcG - pixels[idx + 1]) * effAlpha)
                      .round()
                      .clamp(0, 255);
              pixels[idx + 2] =
                  (pixels[idx + 2] + (srcB - pixels[idx + 2]) * effAlpha)
                      .round()
                      .clamp(0, 255);
            }
            continue;
          }

          if (erase) {
            final newA = (dstA * (1.0 - effAlpha)).clamp(0.0, 1.0);
            pixels[idx + 3] = (newA * 255).round();
            if (pixels[idx + 3] == 0) {
              pixels[idx] = 0;
              pixels[idx + 1] = 0;
              pixels[idx + 2] = 0;
            }
          } else {
            final outA = effAlpha + dstA * (1.0 - effAlpha);
            if (outA <= 0.0001) continue;
            final inv = 1.0 / outA;
            pixels[idx] =
                ((srcR * effAlpha + pixels[idx] * dstA * (1.0 - effAlpha)) * inv)
                    .round()
                    .clamp(0, 255);
            pixels[idx + 1] =
                ((srcG * effAlpha + pixels[idx + 1] * dstA * (1.0 - effAlpha)) * inv)
                    .round()
                    .clamp(0, 255);
            pixels[idx + 2] =
                ((srcB * effAlpha + pixels[idx + 2] * dstA * (1.0 - effAlpha)) * inv)
                    .round()
                    .clamp(0, 255);
            pixels[idx + 3] = (outA * 255).round().clamp(0, 255);
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Dodge / Burn / Sponge / Sharpen / Healing Retouch Brushes
  // ---------------------------------------------------------------------------

  static void applyToneBrush({
    required Uint8List pixels,
    required int width,
    required int height,
    required Offset from,
    required Offset to,
    required double radius,
    required double strength,
    required String mode, // 'dodge', 'burn', 'saturate', 'desaturate'
    Uint8List? selectionMask,
    int selectionWidth = 0,
    int selectionHeight = 0,
    double layerOffsetX = 0,
    double layerOffsetY = 0,
  }) {
    final dist = (to - from).distance;
    final step = max(2.0, radius * 0.35);
    final steps = max(1, (dist / step).ceil());
    final r = max(1.0, radius);

    for (int s = 0; s <= steps; s++) {
      final t = steps == 0 ? 0.0 : s / steps;
      final cx = from.dx + (to.dx - from.dx) * t;
      final cy = from.dy + (to.dy - from.dy) * t;
      final minX = max(0, (cx - r).floor());
      final maxX = min(width - 1, (cx + r).ceil());
      final minY = max(0, (cy - r).floor());
      final maxY = min(height - 1, (cy + r).ceil());

      for (int y = minY; y <= maxY; y++) {
        for (int x = minX; x <= maxX; x++) {
          final dx = x + 0.5 - cx;
          final dy = y + 0.5 - cy;
          final d = sqrt(dx * dx + dy * dy) / r;
          if (d >= 1.0) continue;

          if (selectionMask != null && selectionWidth > 0 && selectionHeight > 0) {
            final sx = (x + layerOffsetX).round();
            final sy = (y + layerOffsetY).round();
            if (sx < 0 || sy < 0 || sx >= selectionWidth || sy >= selectionHeight) {
              continue;
            }
            if (selectionMask[sy * selectionWidth + sx] == 0) continue;
          }

          final idx = (y * width + x) * 4;
          if (pixels[idx + 3] == 0) continue;

          final falloff = 0.5 * (1.0 + cos(pi * d));
          final amt = (strength * falloff * 0.22).clamp(0.0, 0.5);

          double pr = pixels[idx].toDouble();
          double pg = pixels[idx + 1].toDouble();
          double pb = pixels[idx + 2].toDouble();

          if (mode == 'dodge') {
            pr += (255.0 - pr) * amt;
            pg += (255.0 - pg) * amt;
            pb += (255.0 - pb) * amt;
          } else if (mode == 'burn') {
            pr *= (1.0 - amt);
            pg *= (1.0 - amt);
            pb *= (1.0 - amt);
          } else {
            final luma = 0.299 * pr + 0.587 * pg + 0.114 * pb;
            final factor = mode == 'saturate' ? (1.0 + amt * 1.4) : (1.0 - amt * 1.4);
            pr = luma + (pr - luma) * factor;
            pg = luma + (pg - luma) * factor;
            pb = luma + (pb - luma) * factor;
          }

          pixels[idx] = pr.round().clamp(0, 255);
          pixels[idx + 1] = pg.round().clamp(0, 255);
          pixels[idx + 2] = pb.round().clamp(0, 255);
        }
      }
    }
  }

  static void applySharpenBrush({
    required Uint8List pixels,
    required int width,
    required int height,
    required Offset from,
    required Offset to,
    required double radius,
    required double strength,
    Uint8List? selectionMask,
    int selectionWidth = 0,
    int selectionHeight = 0,
    double layerOffsetX = 0,
    double layerOffsetY = 0,
  }) {
    final copy = Uint8List.fromList(pixels);
    final dist = (to - from).distance;
    final step = max(2.0, radius * 0.4);
    final steps = max(1, (dist / step).ceil());
    final r = max(1.0, radius);

    for (int s = 0; s <= steps; s++) {
      final t = steps == 0 ? 0.0 : s / steps;
      final cx = from.dx + (to.dx - from.dx) * t;
      final cy = from.dy + (to.dy - from.dy) * t;
      final minX = max(1, (cx - r).floor());
      final maxX = min(width - 2, (cx + r).ceil());
      final minY = max(1, (cy - r).floor());
      final maxY = min(height - 2, (cy + r).ceil());

      for (int y = minY; y <= maxY; y++) {
        for (int x = minX; x <= maxX; x++) {
          final dx = x + 0.5 - cx;
          final dy = y + 0.5 - cy;
          final d = sqrt(dx * dx + dy * dy) / r;
          if (d >= 1.0) continue;

          if (selectionMask != null && selectionWidth > 0 && selectionHeight > 0) {
            final sx = (x + layerOffsetX).round();
            final sy = (y + layerOffsetY).round();
            if (sx < 0 || sy < 0 || sx >= selectionWidth || sy >= selectionHeight) {
              continue;
            }
            if (selectionMask[sy * selectionWidth + sx] == 0) continue;
          }

          final falloff = 0.5 * (1.0 + cos(pi * d));
          final amt = strength * falloff * 0.45;
          final idx = (y * width + x) * 4;
          if (copy[idx + 3] == 0) continue;

          for (int c = 0; c < 3; c++) {
            final center = copy[idx + c];
            final avg = (copy[((y - 1) * width + x) * 4 + c] +
                    copy[((y + 1) * width + x) * 4 + c] +
                    copy[(y * width + x - 1) * 4 + c] +
                    copy[(y * width + x + 1) * 4 + c]) *
                0.25;
            final sharp = center + (center - avg) * amt;
            pixels[idx + c] = sharp.round().clamp(0, 255);
          }
        }
      }
    }
  }

  static void applySpotHeal({
    required Uint8List pixels,
    required int width,
    required int height,
    required Offset center,
    required double radius,
    Uint8List? selectionMask,
    int selectionWidth = 0,
    int selectionHeight = 0,
    double layerOffsetX = 0,
    double layerOffsetY = 0,
  }) {
    // Sample perimeter ring colors around the spot and smoothly interpolate inward
    final r = max(2.0, radius);
    final ringR = r + 3.0;
    final sampleCount = 24;
    final ringColors = <List<double>>[];

    for (int i = 0; i < sampleCount; i++) {
      final a = (2 * pi * i) / sampleCount;
      final sx = (center.dx + cos(a) * ringR).round().clamp(0, width - 1);
      final sy = (center.dy + sin(a) * ringR).round().clamp(0, height - 1);
      final si = (sy * width + sx) * 4;
      if (pixels[si + 3] > 20) {
        ringColors.add([
          sx.toDouble(),
          sy.toDouble(),
          pixels[si].toDouble(),
          pixels[si + 1].toDouble(),
          pixels[si + 2].toDouble(),
        ]);
      }
    }
    if (ringColors.isEmpty) return;

    final minX = max(0, (center.dx - r).floor());
    final maxX = min(width - 1, (center.dx + r).ceil());
    final minY = max(0, (center.dy - r).floor());
    final maxY = min(height - 1, (center.dy + r).ceil());

    for (int y = minY; y <= maxY; y++) {
      for (int x = minX; x <= maxX; x++) {
        final dx = x + 0.5 - center.dx;
        final dy = y + 0.5 - center.dy;
        final d = sqrt(dx * dx + dy * dy) / r;
        if (d >= 1.0) continue;

        if (selectionMask != null && selectionWidth > 0 && selectionHeight > 0) {
          final sx = (x + layerOffsetX).round();
          final sy = (y + layerOffsetY).round();
          if (sx < 0 || sy < 0 || sx >= selectionWidth || sy >= selectionHeight) {
            continue;
          }
          if (selectionMask[sy * selectionWidth + sx] == 0) continue;
        }

        double sumW = 0, rr = 0, gg = 0, bb = 0;
        for (final sc in ringColors) {
          final ddx = x - sc[0];
          final ddy = y - sc[1];
          final w = 1.0 / (ddx * ddx + ddy * ddy + 4.0);
          sumW += w;
          rr += sc[2] * w;
          gg += sc[3] * w;
          bb += sc[4] * w;
        }
        if (sumW <= 0) continue;

        final blend = 0.5 * (1.0 + cos(pi * d));
        final idx = (y * width + x) * 4;
        if (pixels[idx + 3] == 0) continue;
        pixels[idx] =
            (pixels[idx] + ((rr / sumW) - pixels[idx]) * blend).round().clamp(0, 255);
        pixels[idx + 1] =
            (pixels[idx + 1] + ((gg / sumW) - pixels[idx + 1]) * blend)
                .round()
                .clamp(0, 255);
        pixels[idx + 2] =
            (pixels[idx + 2] + ((bb / sumW) - pixels[idx + 2]) * blend)
                .round()
                .clamp(0, 255);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Tone Curves (Monotone Cubic Hermite Spline -> 256-entry LUT)
  // ---------------------------------------------------------------------------

  static Uint8List buildCurveLut(List<Offset> controlPoints) {
    final pts = List<Offset>.from(controlPoints)
      ..sort((a, b) => a.dx.compareTo(b.dx));
    if (pts.isEmpty) {
      return Uint8List.fromList(List.generate(256, (i) => i));
    }

    final n = pts.length;
    final xs = pts.map((p) => p.dx.clamp(0.0, 1.0)).toList();
    final ys = pts.map((p) => p.dy.clamp(0.0, 1.0)).toList();

    // Fritsch-Carlson monotone cubic interpolation
    final slopes = List<double>.filled(max(1, n - 1), 0.0);
    for (int i = 0; i < n - 1; i++) {
      final dx = max(1e-5, xs[i + 1] - xs[i]);
      slopes[i] = (ys[i + 1] - ys[i]) / dx;
    }

    final tangents = List<double>.filled(n, 0.0);
    if (n >= 2) {
      tangents[0] = slopes[0];
      tangents[n - 1] = slopes[n - 2];
      for (int i = 1; i < n - 1; i++) {
        if (slopes[i - 1] * slopes[i] <= 0) {
          tangents[i] = 0.0;
        } else {
          tangents[i] = (slopes[i - 1] + slopes[i]) * 0.5;
        }
      }
    }

    final lut = Uint8List(256);
    for (int i = 0; i < 256; i++) {
      final x = i / 255.0;
      if (x <= xs.first) {
        lut[i] = (ys.first * 255.0).round().clamp(0, 255);
        continue;
      }
      if (x >= xs.last) {
        lut[i] = (ys.last * 255.0).round().clamp(0, 255);
        continue;
      }
      int seg = 0;
      for (int k = 0; k < n - 1; k++) {
        if (x >= xs[k] && x <= xs[k + 1]) {
          seg = k;
          break;
        }
      }
      final h = max(1e-5, xs[seg + 1] - xs[seg]);
      final t = (x - xs[seg]) / h;
      final t2 = t * t;
      final t3 = t2 * t;
      final y = (2 * t3 - 3 * t2 + 1) * ys[seg] +
          (t3 - 2 * t2 + t) * h * tangents[seg] +
          (-2 * t3 + 3 * t2) * ys[seg + 1] +
          (t3 - t2) * h * tangents[seg + 1];
      lut[i] = (y * 255.0).round().clamp(0, 255);
    }
    return lut;
  }

  static Uint8List applyCurvesLut(
    Uint8List src, {
    required Uint8List masterLut,
    required Uint8List rLut,
    required Uint8List gLut,
    required Uint8List bLut,
    Uint8List? selectionMask,
  }) {
    final dst = Uint8List.fromList(src);
    final total = src.length ~/ 4;
    for (int i = 0; i < total; i++) {
      if (selectionMask != null && selectionMask[i] == 0) continue;
      final o = i * 4;
      if (src[o + 3] == 0) continue;
      dst[o] = masterLut[rLut[src[o]]];
      dst[o + 1] = masterLut[gLut[src[o + 1]]];
      dst[o + 2] = masterLut[bLut[src[o + 2]]];
    }
    return dst;
  }

  // ---------------------------------------------------------------------------
  // Develop Panel (Exposure, Contrast, Highlights, Shadows, Temp, Tint, Vibrance)
  // ---------------------------------------------------------------------------

  static Uint8List adjustDevelop(
    Uint8List src, {
    double exposure = 0.0, // -2.0 .. +2.0 EV
    double contrast = 0.0, // -1.0 .. +1.0
    double highlights = 0.0, // -1.0 .. +1.0
    double shadows = 0.0, // -1.0 .. +1.0
    double temperature = 0.0, // -1.0 .. +1.0 (cool .. warm)
    double tint = 0.0, // -1.0 .. +1.0 (green .. magenta)
    double vibrance = 0.0, // -1.0 .. +1.0
    double saturation = 0.0, // -1.0 .. +1.0
    Uint8List? selectionMask,
  }) {
    final dst = Uint8List.fromList(src);
    final expMult = pow(2.0, exposure).toDouble();
    final contrastFactor = 1.0 + contrast * 0.85;
    final total = src.length ~/ 4;

    for (int i = 0; i < total; i++) {
      if (selectionMask != null && selectionMask[i] == 0) continue;
      final o = i * 4;
      if (src[o + 3] == 0) continue;

      double r = src[o] / 255.0;
      double g = src[o + 1] / 255.0;
      double b = src[o + 2] / 255.0;

      // Exposure
      r *= expMult;
      g *= expMult;
      b *= expMult;

      // Temperature & Tint
      r += temperature * 0.14 + tint * 0.07;
      g -= tint * 0.10;
      b -= temperature * 0.14 - tint * 0.07;

      // Highlights & Shadows
      final luma = (0.299 * r + 0.587 * g + 0.114 * b).clamp(0.0, 1.0);
      if (shadows.abs() > 0.001) {
        final shadowMask = pow(1.0 - luma, 2.0).toDouble();
        final delta = shadows * 0.35 * shadowMask;
        r += delta;
        g += delta;
        b += delta;
      }
      if (highlights.abs() > 0.001) {
        final hiMask = pow(luma, 2.0).toDouble();
        final delta = highlights * 0.35 * hiMask;
        r += delta;
        g += delta;
        b += delta;
      }

      // Contrast around 0.5 midpoint
      r = (r - 0.5) * contrastFactor + 0.5;
      g = (g - 0.5) * contrastFactor + 0.5;
      b = (b - 0.5) * contrastFactor + 0.5;

      // Vibrance (smart saturation boosting less-saturated colors more) & Saturation
      if (vibrance.abs() > 0.001 || saturation.abs() > 0.001) {
        final mx = max(r, max(g, b));
        final mn = min(r, min(g, b));
        final satNow = (mx - mn).clamp(0.0, 1.0);
        final avg = (r + g + b) / 3.0;
        final vibScale = vibrance * (1.0 - satNow) * 0.85;
        final totalScale = (1.0 + saturation + vibScale).clamp(0.0, 2.5);
        r = avg + (r - avg) * totalScale;
        g = avg + (g - avg) * totalScale;
        b = avg + (b - avg) * totalScale;
      }

      dst[o] = (r * 255.0).round().clamp(0, 255);
      dst[o + 1] = (g * 255.0).round().clamp(0, 255);
      dst[o + 2] = (b * 255.0).round().clamp(0, 255);
    }
    return dst;
  }

  // ---------------------------------------------------------------------------
  // Photo Looks / Color Grading LUT Presets
  // ---------------------------------------------------------------------------

  static Uint8List applyColorLookPreset(
    Uint8List src,
    ColorLookPreset preset, {
    double intensity = 1.0,
    Uint8List? selectionMask,
  }) {
    final dst = Uint8List.fromList(src);
    final mix = intensity.clamp(0.0, 1.0);
    final total = src.length ~/ 4;

    for (int i = 0; i < total; i++) {
      if (selectionMask != null && selectionMask[i] == 0) continue;
      final o = i * 4;
      if (src[o + 3] == 0) continue;

      final sr = src[o] / 255.0;
      final sg = src[o + 1] / 255.0;
      final sb = src[o + 2] / 255.0;
      double r = sr, g = sg, b = sb;
      final luma = 0.299 * sr + 0.587 * sg + 0.114 * sb;

      switch (preset) {
        case ColorLookPreset.warmFilm:
          r = 0.04 + sr * 0.96 + 0.06 * luma;
          g = 0.03 + sg * 0.94 + 0.02 * luma;
          b = 0.05 + sb * 0.84;
          break;
        case ColorLookPreset.cinematicTeal:
          final shadow = 1.0 - luma;
          r = (sr - 0.5) * 1.18 + 0.5 + luma * 0.09 - shadow * 0.07;
          g = (sg - 0.5) * 1.12 + 0.5 + shadow * 0.02;
          b = (sb - 0.5) * 1.15 + 0.5 + shadow * 0.11 - luma * 0.07;
          break;
        case ColorLookPreset.matteFade:
          r = 0.09 + sr * 0.82;
          g = 0.09 + sg * 0.82;
          b = 0.11 + sb * 0.80;
          break;
        case ColorLookPreset.moodyNoir:
          final bw = ((luma - 0.5) * 1.45 + 0.48).clamp(0.0, 1.0);
          r = bw * 0.98;
          g = bw;
          b = bw * 1.03;
          break;
        case ColorLookPreset.goldenHour:
          r = sr * 1.14 + 0.04;
          g = sg * 1.04 + 0.02;
          b = sb * 0.82;
          break;
        case ColorLookPreset.cyberNeon:
          r = (sr - 0.5) * 1.32 + 0.52 + (1.0 - sg) * 0.08;
          g = (sg - 0.5) * 1.18 + 0.48;
          b = (sb - 0.5) * 1.35 + 0.55;
          break;
        case ColorLookPreset.coolEditorial:
          r = (sr - 0.5) * 1.12 + 0.48;
          g = (sg - 0.5) * 1.10 + 0.50;
          b = (sb - 0.5) * 1.14 + 0.55;
          break;
        case ColorLookPreset.vintageSepia:
          r = (sr * 0.393 + sg * 0.769 + sb * 0.189);
          g = (sr * 0.349 + sg * 0.686 + sb * 0.168);
          b = (sr * 0.272 + sg * 0.534 + sb * 0.131);
          break;
      }

      dst[o] = ((sr + (r - sr) * mix) * 255.0).round().clamp(0, 255);
      dst[o + 1] = ((sg + (g - sg) * mix) * 255.0).round().clamp(0, 255);
      dst[o + 2] = ((sb + (b - sb) * mix) * 255.0).round().clamp(0, 255);
    }
    return dst;
  }

  // ---------------------------------------------------------------------------
  // Auto Levels & Auto White Balance
  // ---------------------------------------------------------------------------

  static Uint8List autoLevels(Uint8List src, {Uint8List? selectionMask}) {
    final hist = computeHistogram(src);
    int totalOpaque = 0;
    for (final c in hist.luma) {
      totalOpaque += c;
    }
    if (totalOpaque < 10) return Uint8List.fromList(src);

    int findPercentile(List<int> bins, double pct) {
      final target = (totalOpaque * pct).round();
      int acc = 0;
      for (int i = 0; i < 256; i++) {
        acc += bins[i];
        if (acc >= target) return i;
      }
      return 255;
    }

    final loR = findPercentile(hist.r, 0.01);
    final hiR = max(loR + 1, findPercentile(hist.r, 0.99));
    final loG = findPercentile(hist.g, 0.01);
    final hiG = max(loG + 1, findPercentile(hist.g, 0.99));
    final loB = findPercentile(hist.b, 0.01);
    final hiB = max(loB + 1, findPercentile(hist.b, 0.99));

    final dst = Uint8List.fromList(src);
    final total = src.length ~/ 4;
    for (int i = 0; i < total; i++) {
      if (selectionMask != null && selectionMask[i] == 0) continue;
      final o = i * 4;
      if (src[o + 3] == 0) continue;
      dst[o] = (((src[o] - loR) * 255) ~/ (hiR - loR)).clamp(0, 255);
      dst[o + 1] = (((src[o + 1] - loG) * 255) ~/ (hiG - loG)).clamp(0, 255);
      dst[o + 2] = (((src[o + 2] - loB) * 255) ~/ (hiB - loB)).clamp(0, 255);
    }
    return dst;
  }

  static Uint8List autoWhiteBalance(Uint8List src, {Uint8List? selectionMask}) {
    double sumR = 0, sumG = 0, sumB = 0;
    int count = 0;
    final total = src.length ~/ 4;
    for (int i = 0; i < total; i++) {
      final o = i * 4;
      if (src[o + 3] < 20) continue;
      sumR += src[o];
      sumG += src[o + 1];
      sumB += src[o + 2];
      count++;
    }
    if (count < 10) return Uint8List.fromList(src);

    final avgR = max(1.0, sumR / count);
    final avgG = max(1.0, sumG / count);
    final avgB = max(1.0, sumB / count);
    final gray = (avgR + avgG + avgB) / 3.0;
    final gainR = (gray / avgR).clamp(0.6, 1.6);
    final gainG = (gray / avgG).clamp(0.6, 1.6);
    final gainB = (gray / avgB).clamp(0.6, 1.6);

    final dst = Uint8List.fromList(src);
    for (int i = 0; i < total; i++) {
      if (selectionMask != null && selectionMask[i] == 0) continue;
      final o = i * 4;
      if (src[o + 3] == 0) continue;
      dst[o] = (src[o] * gainR).round().clamp(0, 255);
      dst[o + 1] = (src[o + 1] * gainG).round().clamp(0, 255);
      dst[o + 2] = (src[o + 2] * gainB).round().clamp(0, 255);
    }
    return dst;
  }

  // ---------------------------------------------------------------------------
  // Pro Filters: Motion Blur, Radial Blur, Unsharp Mask, Chromatic Aberration, Halftone
  // ---------------------------------------------------------------------------

  static Uint8List motionBlur(
    Uint8List src,
    int width,
    int height, {
    required double distance,
    required double angleDeg,
  }) {
    final samples = distance.round().clamp(2, 60);
    final rad = angleDeg * pi / 180.0;
    final dx = cos(rad);
    final dy = sin(rad);
    final dst = Uint8List(src.length);
    final half = samples / 2.0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        double r = 0, g = 0, b = 0, a = 0;
        for (int k = 0; k < samples; k++) {
          final offset = k - half;
          final sx = (x + dx * offset).round().clamp(0, width - 1);
          final sy = (y + dy * offset).round().clamp(0, height - 1);
          final si = (sy * width + sx) * 4;
          r += src[si];
          g += src[si + 1];
          b += src[si + 2];
          a += src[si + 3];
        }
        final di = (y * width + x) * 4;
        dst[di] = (r / samples).round().clamp(0, 255);
        dst[di + 1] = (g / samples).round().clamp(0, 255);
        dst[di + 2] = (b / samples).round().clamp(0, 255);
        dst[di + 3] = (a / samples).round().clamp(0, 255);
      }
    }
    return dst;
  }

  static Uint8List radialZoomBlur(
    Uint8List src,
    int width,
    int height, {
    required double strength, // 0.01 .. 0.35
  }) {
    final dst = Uint8List(src.length);
    final cx = width / 2.0;
    final cy = height / 2.0;
    const samples = 14;
    final amt = strength.clamp(0.01, 0.4);

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final vx = x - cx;
        final vy = y - cy;
        double r = 0, g = 0, b = 0, a = 0;
        for (int k = 0; k < samples; k++) {
          final scale = 1.0 - amt * (k / (samples - 1));
          final sx = (cx + vx * scale).round().clamp(0, width - 1);
          final sy = (cy + vy * scale).round().clamp(0, height - 1);
          final si = (sy * width + sx) * 4;
          r += src[si];
          g += src[si + 1];
          b += src[si + 2];
          a += src[si + 3];
        }
        final di = (y * width + x) * 4;
        dst[di] = (r / samples).round().clamp(0, 255);
        dst[di + 1] = (g / samples).round().clamp(0, 255);
        dst[di + 2] = (b / samples).round().clamp(0, 255);
        dst[di + 3] = (a / samples).round().clamp(0, 255);
      }
    }
    return dst;
  }

  static Uint8List unsharpMask(
    Uint8List src,
    int width,
    int height, {
    required double amount, // 0.2 .. 3.0
    required double radius, // 1.0 .. 12.0
    int threshold = 4,
  }) {
    final blurred = PixelOps.gaussianBlur(src, width, height, radius);
    final dst = Uint8List.fromList(src);
    final total = src.length ~/ 4;
    for (int i = 0; i < total; i++) {
      final o = i * 4;
      if (src[o + 3] == 0) continue;
      for (int c = 0; c < 3; c++) {
        final diff = src[o + c] - blurred[o + c];
        if (diff.abs() >= threshold) {
          dst[o + c] = (src[o + c] + diff * amount).round().clamp(0, 255);
        }
      }
    }
    return dst;
  }

  static Uint8List chromaticAberration(
    Uint8List src,
    int width,
    int height, {
    required int shiftPx,
  }) {
    final dst = Uint8List.fromList(src);
    final s = shiftPx.clamp(-40, 40);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final di = (y * width + x) * 4;
        final rx = (x - s).clamp(0, width - 1);
        final bx = (x + s).clamp(0, width - 1);
        dst[di] = src[(y * width + rx) * 4];
        dst[di + 1] = src[di + 1];
        dst[di + 2] = src[(y * width + bx) * 4 + 2];
        dst[di + 3] = src[di + 3];
      }
    }
    return dst;
  }

  static Uint8List halftoneDots(
    Uint8List src,
    int width,
    int height, {
    required int cellSize,
    bool colorMode = true,
  }) {
    final cell = cellSize.clamp(4, 32);
    final dst = Uint8List(src.length);
    for (int cy = 0; cy < height; cy += cell) {
      for (int cx = 0; cx < width; cx += cell) {
        double sumR = 0, sumG = 0, sumB = 0, sumA = 0;
        int cnt = 0;
        final endY = min(height, cy + cell);
        final endX = min(width, cx + cell);
        for (int y = cy; y < endY; y++) {
          for (int x = cx; x < endX; x++) {
            final i = (y * width + x) * 4;
            sumR += src[i];
            sumG += src[i + 1];
            sumB += src[i + 2];
            sumA += src[i + 3];
            cnt++;
          }
        }
        if (cnt == 0) continue;
        final r = sumR / cnt;
        final g = sumG / cnt;
        final b = sumB / cnt;
        final a = (sumA / cnt).round().clamp(0, 255);
        final luma = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0;
        final maxRad = cell * 0.52;
        final dotRad = maxRad * (1.0 - luma * 0.85);
        final midX = cx + cell / 2.0;
        final midY = cy + cell / 2.0;

        for (int y = cy; y < endY; y++) {
          for (int x = cx; x < endX; x++) {
            final di = (y * width + x) * 4;
            final dist = sqrt(pow(x + 0.5 - midX, 2) + pow(y + 0.5 - midY, 2));
            if (dist <= dotRad) {
              if (colorMode) {
                dst[di] = r.round().clamp(0, 255);
                dst[di + 1] = g.round().clamp(0, 255);
                dst[di + 2] = b.round().clamp(0, 255);
              } else {
                dst[di] = 20;
                dst[di + 1] = 20;
                dst[di + 2] = 24;
              }
              dst[di + 3] = a;
            } else {
              dst[di] = 245;
              dst[di + 1] = 243;
              dst[di + 2] = 238;
              dst[di + 3] = a;
            }
          }
        }
      }
    }
    return dst;
  }

  // ---------------------------------------------------------------------------
  // Selection Feather, Expand/Contract & Stroke
  // ---------------------------------------------------------------------------

  static Uint8List featherSelectionMask(
    Uint8List mask,
    int width,
    int height,
    double radius,
  ) {
    // Expand 1-channel mask into RGBA, run gaussianBlur, extract channel
    final rgba = Uint8List(width * height * 4);
    for (int i = 0; i < width * height; i++) {
      final v = mask[i];
      rgba[i * 4] = v;
      rgba[i * 4 + 3] = 255;
    }
    final blurred = PixelOps.gaussianBlur(rgba, width, height, radius);
    final out = Uint8List(width * height);
    for (int i = 0; i < width * height; i++) {
      out[i] = blurred[i * 4];
    }
    return out;
  }

  static Uint8List morphSelectionMask(
    Uint8List mask,
    int width,
    int height,
    int deltaPx, // positive = expand, negative = contract
  ) {
    if (deltaPx == 0) return Uint8List.fromList(mask);
    final expand = deltaPx > 0;
    final steps = deltaPx.abs().clamp(1, 30);
    var cur = Uint8List.fromList(mask);

    for (int s = 0; s < steps; s++) {
      final next = Uint8List(cur.length);
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          int val = cur[y * width + x];
          for (int dy = -1; dy <= 1; dy++) {
            final ny = y + dy;
            if (ny < 0 || ny >= height) continue;
            for (int dx = -1; dx <= 1; dx++) {
              final nx = x + dx;
              if (nx < 0 || nx >= width) continue;
              final nb = cur[ny * width + nx];
              if (expand) {
                if (nb > val) val = nb;
              } else {
                if (nb < val) val = nb;
              }
            }
          }
          next[y * width + x] = val;
        }
      }
      cur = next;
    }
    return cur;
  }

  static void strokeSelectionMask({
    required Uint8List pixels,
    required int width,
    required int height,
    required Uint8List selectionMask,
    required int selectionWidth,
    required int selectionHeight,
    required Color color,
    required int strokeWidth,
    double layerOffsetX = 0,
    double layerOffsetY = 0,
  }) {
    final expanded = morphSelectionMask(
      selectionMask,
      selectionWidth,
      selectionHeight,
      max(1, (strokeWidth / 2).ceil()),
    );
    final contracted = morphSelectionMask(
      selectionMask,
      selectionWidth,
      selectionHeight,
      -max(1, (strokeWidth / 2).floor()),
    );

    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    final a = (color.a * 255).round().clamp(0, 255);

    for (int y = 0; y < height; y++) {
      final sy = (y + layerOffsetY).round();
      if (sy < 0 || sy >= selectionHeight) continue;
      for (int x = 0; x < width; x++) {
        final sx = (x + layerOffsetX).round();
        if (sx < 0 || sx >= selectionWidth) continue;
        final si = sy * selectionWidth + sx;
        if (expanded[si] > 127 && contracted[si] <= 127) {
          final di = (y * width + x) * 4;
          pixels[di] = r;
          pixels[di + 1] = g;
          pixels[di + 2] = b;
          pixels[di + 3] = a;
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Histogram & Color Harmonies
  // ---------------------------------------------------------------------------

  static HistogramData computeHistogram(Uint8List pixels) {
    final r = List<int>.filled(256, 0);
    final g = List<int>.filled(256, 0);
    final b = List<int>.filled(256, 0);
    final luma = List<int>.filled(256, 0);

    final total = pixels.length ~/ 4;
    // Subsample large images cleanly for instant UI responsiveness
    final stride = total > 250000 ? (total ~/ 250000) : 1;
    for (int i = 0; i < total; i += stride) {
      final o = i * 4;
      if (pixels[o + 3] < 8) continue;
      final rv = pixels[o];
      final gv = pixels[o + 1];
      final bv = pixels[o + 2];
      final lv = (0.299 * rv + 0.587 * gv + 0.114 * bv).round().clamp(0, 255);
      r[rv]++;
      g[gv]++;
      b[bv]++;
      luma[lv]++;
    }

    int maxCount = 1;
    for (int i = 1; i < 255; i++) {
      if (r[i] > maxCount) maxCount = r[i];
      if (g[i] > maxCount) maxCount = g[i];
      if (b[i] > maxCount) maxCount = b[i];
      if (luma[i] > maxCount) maxCount = luma[i];
    }
    return HistogramData(r: r, g: g, b: b, luma: luma, maxCount: maxCount);
  }

  static Map<String, List<Color>> generateColorHarmonies(Color base) {
    final hsl = HSLColor.fromColor(base);
    Color rot(double deg) =>
        hsl.withHue((hsl.hue + deg) % 360.0).toColor();

    final tintsShades = <Color>[
      for (final l in [0.15, 0.28, 0.42, 0.55, 0.68, 0.80, 0.90])
        hsl.withLightness(l).toColor(),
    ];

    return {
      'Complementary': [base, rot(180)],
      'Analogous': [rot(330), base, rot(30)],
      'Triadic': [base, rot(120), rot(240)],
      'Split-Comp': [base, rot(150), rot(210)],
      'Tetradic': [base, rot(90), rot(180), rot(270)],
      'Tints & Shades': tintsShades,
    };
  }
}
