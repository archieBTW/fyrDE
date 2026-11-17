import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/editor_types.dart';

class PixelOps {
  static Uint8List createBlankRgba(int width, int height) {
    return Uint8List(width * height * 4);
  }

  static Uint8List createFilledRgba(int width, int height, Color color) {
    final out = Uint8List(width * height * 4);
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    final a = (color.a * 255).round().clamp(0, 255);
    if (a == 0) return out;
    for (int i = 0; i < out.length; i += 4) {
      out[i] = r;
      out[i + 1] = g;
      out[i + 2] = b;
      out[i + 3] = a;
    }
    return out;
  }

  /// Converts straight RGBA8888 bytes to premultiplied RGBA8888 and uploads
  /// to a GPU-backed [ui.Image].
  static Future<ui.Image> decodeStraightRgbaToUiImage(
    Uint8List straightRgba,
    int width,
    int height,
  ) {
    final premul = Uint8List(straightRgba.length);
    for (int i = 0; i < straightRgba.length; i += 4) {
      final a = straightRgba[i + 3];
      if (a == 0) {
        continue;
      } else if (a == 255) {
        premul[i] = straightRgba[i];
        premul[i + 1] = straightRgba[i + 1];
        premul[i + 2] = straightRgba[i + 2];
        premul[i + 3] = 255;
      } else {
        premul[i] = (straightRgba[i] * a + 127) ~/ 255;
        premul[i + 1] = (straightRgba[i + 1] * a + 127) ~/ 255;
        premul[i + 2] = (straightRgba[i + 2] * a + 127) ~/ 255;
        premul[i + 3] = a;
      }
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      premul,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (img) => completer.complete(img),
    );
    return completer.future;
  }

  static Color samplePixel(Uint8List pixels, int width, int height, int x, int y) {
    if (x < 0 || x >= width || y < 0 || y >= height) {
      return Colors.transparent;
    }
    final idx = (y * width + x) * 4;
    return Color.fromARGB(
      pixels[idx + 3],
      pixels[idx],
      pixels[idx + 1],
      pixels[idx + 2],
    );
  }

  /// Composites a single straight-RGBA pixel over destination straight-RGBA.
  static void _blendPixelOver(
    Uint8List dst,
    int idx,
    int sr,
    int sg,
    int sb,
    double sa,
  ) {
    if (sa <= 0.0) return;
    final da = dst[idx + 3] / 255.0;
    if (sa >= 0.999 || da <= 0.0) {
      final outA = sa + da * (1.0 - sa);
      if (outA <= 0.0001) {
        dst[idx] = 0;
        dst[idx + 1] = 0;
        dst[idx + 2] = 0;
        dst[idx + 3] = 0;
        return;
      }
      if (sa >= 0.999) {
        dst[idx] = sr;
        dst[idx + 1] = sg;
        dst[idx + 2] = sb;
        dst[idx + 3] = 255;
      } else {
        dst[idx] = sr;
        dst[idx + 1] = sg;
        dst[idx + 2] = sb;
        dst[idx + 3] = (outA * 255.0).round().clamp(0, 255);
      }
      return;
    }

    final invSa = 1.0 - sa;
    final outA = sa + da * invSa;
    if (outA <= 0.0001) {
      dst[idx + 3] = 0;
      return;
    }
    final dr = dst[idx];
    final dg = dst[idx + 1];
    final db = dst[idx + 2];
    final daInv = da * invSa;
    dst[idx] = ((sr * sa + dr * daInv) / outA).round().clamp(0, 255);
    dst[idx + 1] = ((sg * sa + dg * daInv) / outA).round().clamp(0, 255);
    dst[idx + 2] = ((sb * sa + db * daInv) / outA).round().clamp(0, 255);
    dst[idx + 3] = (outA * 255.0).round().clamp(0, 255);
  }

  /// Stamps a single circular dab (Brush, Pencil, or Eraser) into [pixels].
  static void stampDab({
    required Uint8List pixels,
    required int width,
    required int height,
    required double cx,
    required double cy,
    required double radius,
    required double hardness,
    required double opacity,
    required Color color,
    required bool erase,
    required bool hardPixelEdge,
    Uint8List? selectionMask,
    int selectionWidth = 0,
    int selectionHeight = 0,
    double layerOffsetX = 0.0,
    double layerOffsetY = 0.0,
  }) {
    final effectiveRadius = max(0.5, radius);
    final minX = (cx - effectiveRadius - 1).floor().clamp(0, width - 1);
    final maxX = (cx + effectiveRadius + 1).ceil().clamp(0, width - 1);
    final minY = (cy - effectiveRadius - 1).floor().clamp(0, height - 1);
    final maxY = (cy + effectiveRadius + 1).ceil().clamp(0, height - 1);

    final sr = (color.r * 255).round().clamp(0, 255);
    final sg = (color.g * 255).round().clamp(0, 255);
    final sb = (color.b * 255).round().clamp(0, 255);
    final baseOpacity = opacity.clamp(0.0, 1.0) * color.a;
    final h = hardness.clamp(0.0, 1.0);

    for (int y = minY; y <= maxY; y++) {
      final dy = y + 0.5 - cy;
      final sy = (y + layerOffsetY).round();
      for (int x = minX; x <= maxX; x++) {
        final dx = x + 0.5 - cx;
        final dist = sqrt(dx * dx + dy * dy);

        double cov;
        if (hardPixelEdge) {
          if (dist > effectiveRadius) continue;
          cov = 1.0;
        } else {
          if (dist >= effectiveRadius + 0.5) continue;
          if (h >= 0.99) {
            cov = (effectiveRadius + 0.5 - dist).clamp(0.0, 1.0);
          } else {
            final hardR = effectiveRadius * h;
            if (dist <= hardR) {
              cov = 1.0;
            } else {
              final t = ((dist - hardR) / max(0.001, effectiveRadius - hardR))
                  .clamp(0.0, 1.0);
              // Smooth cubic falloff
              cov = (1.0 - t) * (1.0 - t) * (1.0 + 2.0 * t);
              cov = (1.0 - t * t);
              cov = cov * cov;
            }
          }
        }

        if (selectionMask != null) {
          final sx = (x + layerOffsetX).round();
          if (sx < 0 ||
              sx >= selectionWidth ||
              sy < 0 ||
              sy >= selectionHeight) {
            continue;
          }
          final sel = selectionMask[sy * selectionWidth + sx] / 255.0;
          if (sel <= 0.0) continue;
          cov *= sel;
        }

        final effA = cov * baseOpacity;
        if (effA <= 0.001) continue;

        final idx = (y * width + x) * 4;
        if (erase) {
          final curA = pixels[idx + 3] / 255.0;
          final nextA = (curA * (1.0 - effA)).clamp(0.0, 1.0);
          pixels[idx + 3] = (nextA * 255.0).round();
          if (pixels[idx + 3] == 0) {
            pixels[idx] = 0;
            pixels[idx + 1] = 0;
            pixels[idx + 2] = 0;
          }
        } else {
          _blendPixelOver(pixels, idx, sr, sg, sb, effA);
        }
      }
    }
  }

  /// Draws an interpolated stroke between [from] and [to] in layer-local coords.
  static void drawStrokeSegment({
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
    Uint8List? selectionMask,
    int selectionWidth = 0,
    int selectionHeight = 0,
    double layerOffsetX = 0.0,
    double layerOffsetY = 0.0,
  }) {
    final dist = (to - from).distance;
    final spacing = hardPixelEdge ? 0.8 : max(1.0, radius * 0.25);
    final steps = max(1, (dist / spacing).ceil());
    // Per-dab opacity compensation so continuous strokes don't over-saturate
    final perDabOpacity = steps > 1 && opacity < 0.98
        ? (1.0 - pow(1.0 - opacity, 1.0 / min(4.0, max(1.0, radius * 0.3))))
            .clamp(0.02, 1.0)
        : opacity;

    for (int i = 0; i <= steps; i++) {
      final t = steps == 0 ? 0.0 : i / steps;
      final cx = from.dx + (to.dx - from.dx) * t;
      final cy = from.dy + (to.dy - from.dy) * t;
      stampDab(
        pixels: pixels,
        width: width,
        height: height,
        cx: cx,
        cy: cy,
        radius: radius,
        hardness: hardness,
        opacity: perDabOpacity,
        color: color,
        erase: erase,
        hardPixelEdge: hardPixelEdge,
        selectionMask: selectionMask,
        selectionWidth: selectionWidth,
        selectionHeight: selectionHeight,
        layerOffsetX: layerOffsetX,
        layerOffsetY: layerOffsetY,
      );
    }
  }

  /// Clone stamp dab reading from [sourcePixels] at offset `(srcDx, srcDy)`.
  static void stampCloneDab({
    required Uint8List dstPixels,
    required Uint8List sourcePixels,
    required int width,
    required int height,
    required double cx,
    required double cy,
    required double srcOffsetX,
    required double srcOffsetY,
    required double radius,
    required double hardness,
    required double opacity,
    Uint8List? selectionMask,
    int selectionWidth = 0,
    int selectionHeight = 0,
    double layerOffsetX = 0.0,
    double layerOffsetY = 0.0,
  }) {
    final effectiveRadius = max(1.0, radius);
    final minX = (cx - effectiveRadius - 1).floor().clamp(0, width - 1);
    final maxX = (cx + effectiveRadius + 1).ceil().clamp(0, width - 1);
    final minY = (cy - effectiveRadius - 1).floor().clamp(0, height - 1);
    final maxY = (cy + effectiveRadius + 1).ceil().clamp(0, height - 1);
    final h = hardness.clamp(0.0, 1.0);

    for (int y = minY; y <= maxY; y++) {
      final dy = y + 0.5 - cy;
      final sy = (y + srcOffsetY).round();
      if (sy < 0 || sy >= height) continue;
      final selY = (y + layerOffsetY).round();

      for (int x = minX; x <= maxX; x++) {
        final dx = x + 0.5 - cx;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist >= effectiveRadius + 0.5) continue;

        final sx = (x + srcOffsetX).round();
        if (sx < 0 || sx >= width) continue;

        double cov;
        if (h >= 0.99) {
          cov = (effectiveRadius + 0.5 - dist).clamp(0.0, 1.0);
        } else {
          final hardR = effectiveRadius * h;
          if (dist <= hardR) {
            cov = 1.0;
          } else {
            final t = ((dist - hardR) / max(0.001, effectiveRadius - hardR))
                .clamp(0.0, 1.0);
            cov = (1.0 - t * t);
            cov *= cov;
          }
        }

        if (selectionMask != null) {
          final selX = (x + layerOffsetX).round();
          if (selX < 0 ||
              selX >= selectionWidth ||
              selY < 0 ||
              selY >= selectionHeight) {
            continue;
          }
          cov *= selectionMask[selY * selectionWidth + selX] / 255.0;
        }

        final sIdx = (sy * width + sx) * 4;
        final srcA = (sourcePixels[sIdx + 3] / 255.0) * cov * opacity;
        if (srcA <= 0.001) continue;

        final dIdx = (y * width + x) * 4;
        _blendPixelOver(
          dstPixels,
          dIdx,
          sourcePixels[sIdx],
          sourcePixels[sIdx + 1],
          sourcePixels[sIdx + 2],
          srcA,
        );
      }
    }
  }

  /// Blur or smudge dab along the brush path.
  static void applyLocalBlurOrSmudge({
    required Uint8List pixels,
    required int width,
    required int height,
    required Offset from,
    required Offset to,
    required double radius,
    required double strength,
    required bool smudge,
    Uint8List? selectionMask,
    int selectionWidth = 0,
    int selectionHeight = 0,
    double layerOffsetX = 0.0,
    double layerOffsetY = 0.0,
  }) {
    final effectiveRadius = max(2.0, radius);
    final cx = to.dx;
    final cy = to.dy;
    final minX = (cx - effectiveRadius).floor().clamp(1, width - 2);
    final maxX = (cx + effectiveRadius).ceil().clamp(1, width - 2);
    final minY = (cy - effectiveRadius).floor().clamp(1, height - 2);
    final maxY = (cy + effectiveRadius).ceil().clamp(1, height - 2);
    if (minX > maxX || minY > maxY) return;

    final copy = Uint8List.fromList(pixels);
    final dirX = to.dx - from.dx;
    final dirY = to.dy - from.dy;

    for (int y = minY; y <= maxY; y++) {
      final dy = y + 0.5 - cy;
      final selY = (y + layerOffsetY).round();
      for (int x = minX; x <= maxX; x++) {
        final dx = x + 0.5 - cx;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist >= effectiveRadius) continue;

        double falloff = 1.0 - (dist / effectiveRadius);
        falloff = falloff * falloff * strength.clamp(0.05, 0.95);

        if (selectionMask != null) {
          final selX = (x + layerOffsetX).round();
          if (selX < 0 ||
              selX >= selectionWidth ||
              selY < 0 ||
              selY >= selectionHeight) {
            continue;
          }
          falloff *= selectionMask[selY * selectionWidth + selX] / 255.0;
        }
        if (falloff <= 0.001) continue;

        final idx = (y * width + x) * 4;
        if (smudge) {
          final sx = (x - dirX * 0.65).round().clamp(0, width - 1);
          final sy = (y - dirY * 0.65).round().clamp(0, height - 1);
          final sIdx = (sy * width + sx) * 4;
          for (int c = 0; c < 4; c++) {
            pixels[idx + c] =
                (copy[idx + c] * (1.0 - falloff) + copy[sIdx + c] * falloff)
                    .round()
                    .clamp(0, 255);
          }
        } else {
          // 3x3 box blur weighted by falloff
          int sumR = 0, sumG = 0, sumB = 0, sumA = 0;
          for (int ky = -1; ky <= 1; ky++) {
            for (int kx = -1; kx <= 1; kx++) {
              final kIdx = ((y + ky) * width + (x + kx)) * 4;
              sumR += copy[kIdx];
              sumG += copy[kIdx + 1];
              sumB += copy[kIdx + 2];
              sumA += copy[kIdx + 3];
            }
          }
          pixels[idx] =
              (copy[idx] * (1.0 - falloff) + (sumR / 9.0) * falloff)
                  .round()
                  .clamp(0, 255);
          pixels[idx + 1] =
              (copy[idx + 1] * (1.0 - falloff) + (sumG / 9.0) * falloff)
                  .round()
                  .clamp(0, 255);
          pixels[idx + 2] =
              (copy[idx + 2] * (1.0 - falloff) + (sumB / 9.0) * falloff)
                  .round()
                  .clamp(0, 255);
          pixels[idx + 3] =
              (copy[idx + 3] * (1.0 - falloff) + (sumA / 9.0) * falloff)
                  .round()
                  .clamp(0, 255);
        }
      }
    }
  }

  /// Iterative BFS flood fill (Paint Bucket).
  static void floodFill({
    required Uint8List pixels,
    required int width,
    required int height,
    required int startX,
    required int startY,
    required Color fillColor,
    required int tolerance,
    required double opacity,
    Uint8List? selectionMask,
    int selectionWidth = 0,
    int selectionHeight = 0,
    double layerOffsetX = 0.0,
    double layerOffsetY = 0.0,
  }) {
    if (startX < 0 || startX >= width || startY < 0 || startY >= height) return;
    if (selectionMask != null) {
      final sx = (startX + layerOffsetX).round();
      final sy = (startY + layerOffsetY).round();
      if (sx < 0 ||
          sx >= selectionWidth ||
          sy < 0 ||
          sy >= selectionHeight ||
          selectionMask[sy * selectionWidth + sx] == 0) {
        return;
      }
    }

    final startIdx = (startY * width + startX) * 4;
    final tr = pixels[startIdx];
    final tg = pixels[startIdx + 1];
    final tb = pixels[startIdx + 2];
    final ta = pixels[startIdx + 3];

    final fr = (fillColor.r * 255).round().clamp(0, 255);
    final fg = (fillColor.g * 255).round().clamp(0, 255);
    final fb = (fillColor.b * 255).round().clamp(0, 255);
    final fa = (fillColor.a * opacity * 255).round().clamp(0, 255);

    if (tolerance == 0 &&
        tr == fr &&
        tg == fg &&
        tb == fb &&
        ta == fa &&
        opacity >= 0.99) {
      return;
    }

    final visited = Uint8List(width * height);
    final queue = Int32List(width * height);
    int head = 0;
    int tail = 0;
    final startPos = startY * width + startX;
    queue[tail++] = startPos;
    visited[startPos] = 1;

    bool matches(int pIdx) {
      final dr = (pixels[pIdx] - tr).abs();
      final dg = (pixels[pIdx + 1] - tg).abs();
      final db = (pixels[pIdx + 2] - tb).abs();
      final da = (pixels[pIdx + 3] - ta).abs();
      return max(max(dr, dg), max(db, da)) <= tolerance;
    }

    while (head < tail) {
      final pos = queue[head++];
      final x = pos % width;
      final y = pos ~/ width;
      final pIdx = pos * 4;

      double selFactor = 1.0;
      if (selectionMask != null) {
        final sx = (x + layerOffsetX).round();
        final sy = (y + layerOffsetY).round();
        if (sx < 0 ||
            sx >= selectionWidth ||
            sy < 0 ||
            sy >= selectionHeight) {
          continue;
        }
        selFactor = selectionMask[sy * selectionWidth + sx] / 255.0;
        if (selFactor <= 0.0) continue;
      }

      final blendA = (fa / 255.0) * selFactor;
      if (blendA >= 0.999 && opacity >= 0.999) {
        pixels[pIdx] = fr;
        pixels[pIdx + 1] = fg;
        pixels[pIdx + 2] = fb;
        pixels[pIdx + 3] = 255;
      } else {
        _blendPixelOver(pixels, pIdx, fr, fg, fb, blendA);
      }

      if (x > 0) {
        final n = pos - 1;
        if (visited[n] == 0 && matches(n * 4)) {
          visited[n] = 1;
          queue[tail++] = n;
        }
      }
      if (x + 1 < width) {
        final n = pos + 1;
        if (visited[n] == 0 && matches(n * 4)) {
          visited[n] = 1;
          queue[tail++] = n;
        }
      }
      if (y > 0) {
        final n = pos - width;
        if (visited[n] == 0 && matches(n * 4)) {
          visited[n] = 1;
          queue[tail++] = n;
        }
      }
      if (y + 1 < height) {
        final n = pos + width;
        if (visited[n] == 0 && matches(n * 4)) {
          visited[n] = 1;
          queue[tail++] = n;
        }
      }
    }
  }

  /// Magic Wand selection on [pixels], returning an alpha mask (`width * height`).
  static Uint8List magicWandMask({
    required Uint8List pixels,
    required int width,
    required int height,
    required int startX,
    required int startY,
    required int tolerance,
    bool contiguous = true,
  }) {
    final mask = Uint8List(width * height);
    if (startX < 0 || startX >= width || startY < 0 || startY >= height) {
      return mask;
    }
    final startIdx = (startY * width + startX) * 4;
    final tr = pixels[startIdx];
    final tg = pixels[startIdx + 1];
    final tb = pixels[startIdx + 2];
    final ta = pixels[startIdx + 3];

    bool matches(int pIdx) {
      final dr = (pixels[pIdx] - tr).abs();
      final dg = (pixels[pIdx + 1] - tg).abs();
      final db = (pixels[pIdx + 2] - tb).abs();
      final da = (pixels[pIdx + 3] - ta).abs();
      return max(max(dr, dg), max(db, da)) <= tolerance;
    }

    if (!contiguous) {
      for (int i = 0; i < width * height; i++) {
        if (matches(i * 4)) mask[i] = 255;
      }
      return mask;
    }

    final visited = Uint8List(width * height);
    final queue = Int32List(width * height);
    int head = 0;
    int tail = 0;
    final startPos = startY * width + startX;
    queue[tail++] = startPos;
    visited[startPos] = 1;

    while (head < tail) {
      final pos = queue[head++];
      mask[pos] = 255;
      final x = pos % width;
      final y = pos ~/ width;

      if (x > 0) {
        final n = pos - 1;
        if (visited[n] == 0 && matches(n * 4)) {
          visited[n] = 1;
          queue[tail++] = n;
        }
      }
      if (x + 1 < width) {
        final n = pos + 1;
        if (visited[n] == 0 && matches(n * 4)) {
          visited[n] = 1;
          queue[tail++] = n;
        }
      }
      if (y > 0) {
        final n = pos - width;
        if (visited[n] == 0 && matches(n * 4)) {
          visited[n] = 1;
          queue[tail++] = n;
        }
      }
      if (y + 1 < height) {
        final n = pos + width;
        if (visited[n] == 0 && matches(n * 4)) {
          visited[n] = 1;
          queue[tail++] = n;
        }
      }
    }
    return mask;
  }

  /// Applies a Linear or Radial gradient across [pixels], clipped to [selectionMask].
  static void applyGradient({
    required Uint8List pixels,
    required int width,
    required int height,
    required Offset start,
    required Offset end,
    required Color startColor,
    required Color endColor,
    required GradientKind kind,
    required double opacity,
    Uint8List? selectionMask,
    int selectionWidth = 0,
    int selectionHeight = 0,
    double layerOffsetX = 0.0,
    double layerOffsetY = 0.0,
  }) {
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final lenSq = dx * dx + dy * dy;
    final len = sqrt(lenSq);
    if (len < 1.0) return;

    final r1 = (startColor.r * 255).round();
    final g1 = (startColor.g * 255).round();
    final b1 = (startColor.b * 255).round();
    final a1 = startColor.a;

    final r2 = kind == GradientKind.fgToTransparent
        ? r1
        : (endColor.r * 255).round();
    final g2 = kind == GradientKind.fgToTransparent
        ? g1
        : (endColor.g * 255).round();
    final b2 = kind == GradientKind.fgToTransparent
        ? b1
        : (endColor.b * 255).round();
    final a2 = kind == GradientKind.fgToTransparent ? 0.0 : endColor.a;

    for (int y = 0; y < height; y++) {
      final selY = (y + layerOffsetY).round();
      for (int x = 0; x < width; x++) {
        double selFactor = 1.0;
        if (selectionMask != null) {
          final selX = (x + layerOffsetX).round();
          if (selX < 0 ||
              selX >= selectionWidth ||
              selY < 0 ||
              selY >= selectionHeight) {
            continue;
          }
          selFactor = selectionMask[selY * selectionWidth + selX] / 255.0;
          if (selFactor <= 0.0) continue;
        }

        double t;
        if (kind == GradientKind.radial) {
          final px = x - start.dx;
          final py = y - start.dy;
          t = (sqrt(px * px + py * py) / len).clamp(0.0, 1.0);
        } else {
          final px = x - start.dx;
          final py = y - start.dy;
          t = ((px * dx + py * dy) / lenSq).clamp(0.0, 1.0);
        }

        final r = (r1 + (r2 - r1) * t).round().clamp(0, 255);
        final g = (g1 + (g2 - g1) * t).round().clamp(0, 255);
        final b = (b1 + (b2 - b1) * t).round().clamp(0, 255);
        final a = ((a1 + (a2 - a1) * t) * opacity * selFactor).clamp(0.0, 1.0);
        _blendPixelOver(pixels, (y * width + x) * 4, r, g, b, a);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Selection Mask Construction & Contour Path
  // ---------------------------------------------------------------------------

  static Uint8List buildRectSelectionMask(int w, int h, Rect rect) {
    final mask = Uint8List(w * h);
    final x0 = rect.left.round().clamp(0, w);
    final y0 = rect.top.round().clamp(0, h);
    final x1 = rect.right.round().clamp(0, w);
    final y1 = rect.bottom.round().clamp(0, h);
    for (int y = y0; y < y1; y++) {
      final row = y * w;
      for (int x = x0; x < x1; x++) {
        mask[row + x] = 255;
      }
    }
    return mask;
  }

  static Uint8List buildEllipseSelectionMask(int w, int h, Rect rect) {
    final mask = Uint8List(w * h);
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final rx = max(0.5, rect.width / 2.0);
    final ry = max(0.5, rect.height / 2.0);
    final x0 = rect.left.floor().clamp(0, w - 1);
    final x1 = rect.right.ceil().clamp(0, w - 1);
    final y0 = rect.top.floor().clamp(0, h - 1);
    final y1 = rect.bottom.ceil().clamp(0, h - 1);
    for (int y = y0; y <= y1; y++) {
      final ny = (y + 0.5 - cy) / ry;
      for (int x = x0; x <= x1; x++) {
        final nx = (x + 0.5 - cx) / rx;
        if (nx * nx + ny * ny <= 1.0) {
          mask[y * w + x] = 255;
        }
      }
    }
    return mask;
  }

  static Uint8List buildPolygonSelectionMask(
      int w, int h, List<Offset> points) {
    final mask = Uint8List(w * h);
    if (points.length < 3) return mask;
    double minX = double.infinity,
        minY = double.infinity,
        maxX = double.negativeInfinity,
        maxY = double.negativeInfinity;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    final x0 = minX.floor().clamp(0, w - 1);
    final x1 = maxX.ceil().clamp(0, w - 1);
    final y0 = minY.floor().clamp(0, h - 1);
    final y1 = maxY.ceil().clamp(0, h - 1);

    // Scanline polygon fill
    for (int y = y0; y <= y1; y++) {
      final py = y + 0.5;
      final intersections = <double>[];
      for (int i = 0; i < points.length; i++) {
        final a = points[i];
        final b = points[(i + 1) % points.length];
        if ((a.dy <= py && b.dy > py) || (b.dy <= py && a.dy > py)) {
          final t = (py - a.dy) / (b.dy - a.dy);
          intersections.add(a.dx + t * (b.dx - a.dx));
        }
      }
      intersections.sort();
      for (int i = 0; i + 1 < intersections.length; i += 2) {
        final sx = intersections[i].ceil().clamp(x0, x1);
        final ex = intersections[i + 1].floor().clamp(x0, x1);
        for (int x = sx; x <= ex; x++) {
          mask[y * w + x] = 255;
        }
      }
    }
    return mask;
  }

  static Uint8List combineSelectionMasks(
    Uint8List? existing,
    Uint8List next,
    SelectionMode mode,
  ) {
    if (existing == null || mode == SelectionMode.replace) {
      return next;
    }
    final out = Uint8List(next.length);
    for (int i = 0; i < next.length; i++) {
      final a = existing[i];
      final b = next[i];
      switch (mode) {
        case SelectionMode.replace:
          out[i] = b;
          break;
        case SelectionMode.add:
          out[i] = max(a, b);
          break;
        case SelectionMode.subtract:
          out[i] = max(0, a - b);
          break;
        case SelectionMode.intersect:
          out[i] = min(a, b);
          break;
      }
    }
    return out;
  }

  static Uint8List invertSelectionMask(Uint8List mask) {
    final out = Uint8List(mask.length);
    for (int i = 0; i < mask.length; i++) {
      out[i] = 255 - mask[i];
    }
    return out;
  }

  static Rect? computeMaskBounds(Uint8List mask, int w, int h) {
    int minX = w, minY = h, maxX = -1, maxY = -1;
    for (int y = 0; y < h; y++) {
      final row = y * w;
      for (int x = 0; x < w; x++) {
        if (mask[row + x] > 0) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < minX || maxY < minY) return null;
    return Rect.fromLTRB(
      minX.toDouble(),
      minY.toDouble(),
      (maxX + 1).toDouble(),
      (maxY + 1).toDouble(),
    );
  }

  /// Builds a crisp boundary [ui.Path] around the selected pixels (`mask > 127`)
  /// using boundary edge segments so marching ants render cleanly on arbitrary masks.
  static ui.Path computeMaskOutlinePath(Uint8List mask, int w, int h) {
    final path = ui.Path();
    // Horizontal runs on top/bottom edges
    for (int y = 0; y <= h; y++) {
      int runStart = -1;
      for (int x = 0; x < w; x++) {
        final above = y > 0 && mask[(y - 1) * w + x] > 127;
        final below = y < h && mask[y * w + x] > 127;
        final edge = above != below;
        if (edge && runStart == -1) {
          runStart = x;
        } else if (!edge && runStart != -1) {
          path.moveTo(runStart.toDouble(), y.toDouble());
          path.lineTo(x.toDouble(), y.toDouble());
          runStart = -1;
        }
      }
      if (runStart != -1) {
        path.moveTo(runStart.toDouble(), y.toDouble());
        path.lineTo(w.toDouble(), y.toDouble());
      }
    }
    // Vertical runs on left/right edges
    for (int x = 0; x <= w; x++) {
      int runStart = -1;
      for (int y = 0; y < h; y++) {
        final left = x > 0 && mask[y * w + x - 1] > 127;
        final right = x < w && mask[y * w + x] > 127;
        final edge = left != right;
        if (edge && runStart == -1) {
          runStart = y;
        } else if (!edge && runStart != -1) {
          path.moveTo(x.toDouble(), runStart.toDouble());
          path.lineTo(x.toDouble(), y.toDouble());
          runStart = -1;
        }
      }
      if (runStart != -1) {
        path.moveTo(x.toDouble(), runStart.toDouble());
        path.lineTo(x.toDouble(), h.toDouble());
      }
    }
    return path;
  }

  static void clearPixelsWithSelection({
    required Uint8List pixels,
    required int width,
    required int height,
    Uint8List? selectionMask,
    int selectionWidth = 0,
    int selectionHeight = 0,
    double layerOffsetX = 0.0,
    double layerOffsetY = 0.0,
  }) {
    if (selectionMask == null) {
      pixels.fillRange(0, pixels.length, 0);
      return;
    }
    for (int y = 0; y < height; y++) {
      final sy = (y + layerOffsetY).round();
      if (sy < 0 || sy >= selectionHeight) continue;
      for (int x = 0; x < width; x++) {
        final sx = (x + layerOffsetX).round();
        if (sx < 0 || sx >= selectionWidth) continue;
        final sel = selectionMask[sy * selectionWidth + sx];
        if (sel == 0) continue;
        final idx = (y * width + x) * 4;
        if (sel == 255) {
          pixels[idx] = 0;
          pixels[idx + 1] = 0;
          pixels[idx + 2] = 0;
          pixels[idx + 3] = 0;
        } else {
          pixels[idx + 3] =
              ((pixels[idx + 3] * (255 - sel)) / 255.0).round().clamp(0, 255);
        }
      }
    }
  }

  static void fillLayerWithSelection({
    required Uint8List pixels,
    required int width,
    required int height,
    required Color color,
    Uint8List? selectionMask,
    int selectionWidth = 0,
    int selectionHeight = 0,
    double layerOffsetX = 0.0,
    double layerOffsetY = 0.0,
  }) {
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    final a = color.a;
    for (int y = 0; y < height; y++) {
      final sy = (y + layerOffsetY).round();
      for (int x = 0; x < width; x++) {
        double sel = 1.0;
        if (selectionMask != null) {
          final sx = (x + layerOffsetX).round();
          if (sx < 0 ||
              sx >= selectionWidth ||
              sy < 0 ||
              sy >= selectionHeight) {
            continue;
          }
          sel = selectionMask[sy * selectionWidth + sx] / 255.0;
          if (sel <= 0.0) continue;
        }
        _blendPixelOver(pixels, (y * width + x) * 4, r, g, b, a * sel);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Adjustments
  // ---------------------------------------------------------------------------

  static Uint8List adjustBrightnessContrast(
    Uint8List src,
    int width,
    int height, {
    double brightness = 0.0, // -100 .. +100
    double contrast = 0.0, // -100 .. +100
    Uint8List? selectionMask,
  }) {
    final out = Uint8List.fromList(src);
    final bOffset = brightness * 2.55;
    final cVal = (contrast * 2.55).clamp(-254.0, 254.0);
    final factor = (259.0 * (cVal + 255.0)) / (255.0 * (259.0 - cVal));

    for (int i = 0, p = 0; i < out.length; i += 4, p++) {
      if (out[i + 3] == 0) continue;
      final sel = selectionMask == null ? 1.0 : selectionMask[p] / 255.0;
      if (sel <= 0.0) continue;

      for (int c = 0; c < 3; c++) {
        final v = out[i + c].toDouble();
        final adj = (factor * ((v + bOffset) - 128.0) + 128.0).clamp(0.0, 255.0);
        out[i + c] = (v * (1.0 - sel) + adj * sel).round().clamp(0, 255);
      }
    }
    return out;
  }

  static Uint8List adjustHsl(
    Uint8List src,
    int width,
    int height, {
    double hueShift = 0.0, // -180 .. 180
    double saturation = 0.0, // -100 .. 100
    double lightness = 0.0, // -100 .. 100
    Uint8List? selectionMask,
  }) {
    final out = Uint8List.fromList(src);
    final satScale = 1.0 + saturation / 100.0;
    final lightDelta = lightness / 100.0;

    for (int i = 0, p = 0; i < out.length; i += 4, p++) {
      if (out[i + 3] == 0) continue;
      final sel = selectionMask == null ? 1.0 : selectionMask[p] / 255.0;
      if (sel <= 0.0) continue;

      final hsl = HSLColor.fromColor(
        Color.fromARGB(255, out[i], out[i + 1], out[i + 2]),
      );
      final newH = (hsl.hue + hueShift) % 360.0;
      final newS = (hsl.saturation * satScale).clamp(0.0, 1.0);
      final newL = (hsl.lightness + lightDelta).clamp(0.0, 1.0);
      final rgb = HSLColor.fromAHSL(1.0, newH < 0 ? newH + 360.0 : newH, newS, newL)
          .toColor();

      final nr = (rgb.r * 255).round();
      final ng = (rgb.g * 255).round();
      final nb = (rgb.b * 255).round();
      out[i] = (out[i] * (1.0 - sel) + nr * sel).round().clamp(0, 255);
      out[i + 1] = (out[i + 1] * (1.0 - sel) + ng * sel).round().clamp(0, 255);
      out[i + 2] = (out[i + 2] * (1.0 - sel) + nb * sel).round().clamp(0, 255);
    }
    return out;
  }

  static Uint8List adjustLevels(
    Uint8List src, {
    int blackPoint = 0, // 0..254
    double gamma = 1.0, // 0.1..4.0
    int whitePoint = 255, // 1..255
    Uint8List? selectionMask,
  }) {
    final out = Uint8List.fromList(src);
    final bp = blackPoint.clamp(0, 253);
    final wp = max(bp + 1, whitePoint.clamp(1, 255));
    final range = (wp - bp).toDouble();
    final invGamma = 1.0 / gamma.clamp(0.1, 5.0);

    final lut = Uint8List(256);
    for (int v = 0; v < 256; v++) {
      final norm = ((v - bp) / range).clamp(0.0, 1.0);
      lut[v] = (pow(norm, invGamma) * 255.0).round().clamp(0, 255);
    }

    for (int i = 0, p = 0; i < out.length; i += 4, p++) {
      if (out[i + 3] == 0) continue;
      final sel = selectionMask == null ? 1.0 : selectionMask[p] / 255.0;
      if (sel <= 0.0) continue;
      for (int c = 0; c < 3; c++) {
        final v = out[i + c];
        out[i + c] =
            (v * (1.0 - sel) + lut[v] * sel).round().clamp(0, 255);
      }
    }
    return out;
  }

  static Uint8List adjustColorBalance(
    Uint8List src, {
    double cyanRed = 0.0, // -100..100
    double magentaGreen = 0.0,
    double yellowBlue = 0.0,
    Uint8List? selectionMask,
  }) {
    final out = Uint8List.fromList(src);
    final dr = cyanRed * 1.28;
    final dg = magentaGreen * 1.28;
    final db = yellowBlue * 1.28;
    for (int i = 0, p = 0; i < out.length; i += 4, p++) {
      if (out[i + 3] == 0) continue;
      final sel = selectionMask == null ? 1.0 : selectionMask[p] / 255.0;
      if (sel <= 0.0) continue;
      out[i] = (out[i] + dr * sel).round().clamp(0, 255);
      out[i + 1] = (out[i + 1] + dg * sel).round().clamp(0, 255);
      out[i + 2] = (out[i + 2] + db * sel).round().clamp(0, 255);
    }
    return out;
  }

  static Uint8List invertColors(Uint8List src, {Uint8List? selectionMask}) {
    final out = Uint8List.fromList(src);
    for (int i = 0, p = 0; i < out.length; i += 4, p++) {
      if (out[i + 3] == 0) continue;
      final sel = selectionMask == null ? 1.0 : selectionMask[p] / 255.0;
      if (sel <= 0.0) continue;
      for (int c = 0; c < 3; c++) {
        final v = out[i + c];
        out[i + c] = (v * (1.0 - sel) + (255 - v) * sel).round().clamp(0, 255);
      }
    }
    return out;
  }

  static Uint8List desaturate(Uint8List src, {Uint8List? selectionMask}) {
    final out = Uint8List.fromList(src);
    for (int i = 0, p = 0; i < out.length; i += 4, p++) {
      if (out[i + 3] == 0) continue;
      final sel = selectionMask == null ? 1.0 : selectionMask[p] / 255.0;
      if (sel <= 0.0) continue;
      final lum =
          (0.2126 * out[i] + 0.7152 * out[i + 1] + 0.0722 * out[i + 2]).round();
      for (int c = 0; c < 3; c++) {
        out[i + c] =
            (out[i + c] * (1.0 - sel) + lum * sel).round().clamp(0, 255);
      }
    }
    return out;
  }

  static Uint8List posterize(Uint8List src, int levels,
      {Uint8List? selectionMask}) {
    final out = Uint8List.fromList(src);
    final lv = levels.clamp(2, 64);
    final step = 255.0 / (lv - 1);
    for (int i = 0, p = 0; i < out.length; i += 4, p++) {
      if (out[i + 3] == 0) continue;
      final sel = selectionMask == null ? 1.0 : selectionMask[p] / 255.0;
      if (sel <= 0.0) continue;
      for (int c = 0; c < 3; c++) {
        final q = ((out[i + c] / step).round() * step).round().clamp(0, 255);
        out[i + c] =
            (out[i + c] * (1.0 - sel) + q * sel).round().clamp(0, 255);
      }
    }
    return out;
  }

  static Uint8List threshold(Uint8List src, int level,
      {Uint8List? selectionMask}) {
    final out = Uint8List.fromList(src);
    for (int i = 0, p = 0; i < out.length; i += 4, p++) {
      if (out[i + 3] == 0) continue;
      final sel = selectionMask == null ? 1.0 : selectionMask[p] / 255.0;
      if (sel <= 0.0) continue;
      final lum = 0.2126 * out[i] + 0.7152 * out[i + 1] + 0.0722 * out[i + 2];
      final val = lum >= level ? 255 : 0;
      for (int c = 0; c < 3; c++) {
        out[i + c] =
            (out[i + c] * (1.0 - sel) + val * sel).round().clamp(0, 255);
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Filters
  // ---------------------------------------------------------------------------

  /// Fast O(W*H) separable 3-pass box blur approximating Gaussian blur.
  static Uint8List gaussianBlur(
    Uint8List src,
    int width,
    int height,
    double radius, {
    Uint8List? selectionMask,
  }) {
    final r = radius.round().clamp(0, 80);
    if (r == 0) return Uint8List.fromList(src);

    // Work in premultiplied float buffers so transparent edges don't bleed black
    final n = width * height;
    var bufA = Float64List(n * 4);
    var bufB = Float64List(n * 4);

    for (int i = 0; i < n; i++) {
      final idx = i * 4;
      final a = src[idx + 3] / 255.0;
      bufA[idx] = src[idx] * a;
      bufA[idx + 1] = src[idx + 1] * a;
      bufA[idx + 2] = src[idx + 2] * a;
      bufA[idx + 3] = src[idx + 3].toDouble();
    }

    final boxes = _boxesForGauss(radius, 3);
    for (final b in boxes) {
      final half = (b - 1) ~/ 2;
      if (half <= 0) continue;
      _boxBlurH(bufA, bufB, width, height, half);
      _boxBlurV(bufB, bufA, width, height, half);
    }

    final out = Uint8List.fromList(src);
    for (int i = 0; i < n; i++) {
      final sel = selectionMask == null ? 1.0 : selectionMask[i] / 255.0;
      if (sel <= 0.0) continue;
      final idx = i * 4;
      final outA = bufA[idx + 3].clamp(0.0, 255.0);
      int rr = 0, gg = 0, bb = 0;
      if (outA > 0.5) {
        final aNorm = outA / 255.0;
        rr = (bufA[idx] / aNorm).round().clamp(0, 255);
        gg = (bufA[idx + 1] / aNorm).round().clamp(0, 255);
        bb = (bufA[idx + 2] / aNorm).round().clamp(0, 255);
      }
      final aa = outA.round().clamp(0, 255);
      if (sel >= 0.999) {
        out[idx] = rr;
        out[idx + 1] = gg;
        out[idx + 2] = bb;
        out[idx + 3] = aa;
      } else {
        out[idx] = (src[idx] * (1 - sel) + rr * sel).round().clamp(0, 255);
        out[idx + 1] =
            (src[idx + 1] * (1 - sel) + gg * sel).round().clamp(0, 255);
        out[idx + 2] =
            (src[idx + 2] * (1 - sel) + bb * sel).round().clamp(0, 255);
        out[idx + 3] =
            (src[idx + 3] * (1 - sel) + aa * sel).round().clamp(0, 255);
      }
    }
    return out;
  }

  static List<int> _boxesForGauss(double sigma, int n) {
    final wIdeal = sqrt((12 * sigma * sigma / n) + 1);
    int wl = wIdeal.floor();
    if (wl % 2 == 0) wl--;
    final wu = wl + 2;
    final mIdeal = (12 * sigma * sigma - n * wl * wl - 4 * n * wl - 3 * n) /
        (-4 * wl - 4);
    final m = mIdeal.round();
    return List<int>.generate(n, (i) => i < m ? wl : wu);
  }

  static void _boxBlurH(
      Float64List src, Float64List dst, int w, int h, int r) {
    final inv = 1.0 / (r + r + 1);
    for (int y = 0; y < h; y++) {
      final row = y * w * 4;
      double sr = 0, sg = 0, sb = 0, sa = 0;
      for (int kx = -r; kx <= r; kx++) {
        final cx = kx.clamp(0, w - 1);
        final idx = row + cx * 4;
        sr += src[idx];
        sg += src[idx + 1];
        sb += src[idx + 2];
        sa += src[idx + 3];
      }
      for (int x = 0; x < w; x++) {
        final dIdx = row + x * 4;
        dst[dIdx] = sr * inv;
        dst[dIdx + 1] = sg * inv;
        dst[dIdx + 2] = sb * inv;
        dst[dIdx + 3] = sa * inv;

        final addX = (x + r + 1).clamp(0, w - 1);
        final remX = (x - r).clamp(0, w - 1);
        final aIdx = row + addX * 4;
        final rIdx = row + remX * 4;
        sr += src[aIdx] - src[rIdx];
        sg += src[aIdx + 1] - src[rIdx + 1];
        sb += src[aIdx + 2] - src[rIdx + 2];
        sa += src[aIdx + 3] - src[rIdx + 3];
      }
    }
  }

  static void _boxBlurV(
      Float64List src, Float64List dst, int w, int h, int r) {
    final inv = 1.0 / (r + r + 1);
    for (int x = 0; x < w; x++) {
      double sr = 0, sg = 0, sb = 0, sa = 0;
      for (int ky = -r; ky <= r; ky++) {
        final cy = ky.clamp(0, h - 1);
        final idx = (cy * w + x) * 4;
        sr += src[idx];
        sg += src[idx + 1];
        sb += src[idx + 2];
        sa += src[idx + 3];
      }
      for (int y = 0; y < h; y++) {
        final dIdx = (y * w + x) * 4;
        dst[dIdx] = sr * inv;
        dst[dIdx + 1] = sg * inv;
        dst[dIdx + 2] = sb * inv;
        dst[dIdx + 3] = sa * inv;

        final addY = (y + r + 1).clamp(0, h - 1);
        final remY = (y - r).clamp(0, h - 1);
        final aIdx = (addY * w + x) * 4;
        final rIdx = (remY * w + x) * 4;
        sr += src[aIdx] - src[rIdx];
        sg += src[aIdx + 1] - src[rIdx + 1];
        sb += src[aIdx + 2] - src[rIdx + 2];
        sa += src[aIdx + 3] - src[rIdx + 3];
      }
    }
  }

  static Uint8List sharpen(
    Uint8List src,
    int width,
    int height, {
    double amount = 1.0, // 0.0 .. 5.0
    Uint8List? selectionMask,
  }) {
    final blurred = gaussianBlur(src, width, height, 1.5);
    final out = Uint8List.fromList(src);
    for (int i = 0, p = 0; i < out.length; i += 4, p++) {
      if (out[i + 3] == 0) continue;
      final sel = selectionMask == null ? 1.0 : selectionMask[p] / 255.0;
      if (sel <= 0.0) continue;
      for (int c = 0; c < 3; c++) {
        final v = src[i + c] + amount * (src[i + c] - blurred[i + c]);
        out[i + c] = (src[i + c] * (1.0 - sel) + v.clamp(0, 255) * sel)
            .round()
            .clamp(0, 255);
      }
    }
    return out;
  }

  static Uint8List pixelate(
    Uint8List src,
    int width,
    int height,
    int cellSize, {
    Uint8List? selectionMask,
  }) {
    final cs = cellSize.clamp(2, 128);
    final out = Uint8List.fromList(src);
    for (int by = 0; by < height; by += cs) {
      for (int bx = 0; bx < width; bx += cs) {
        final sx = min(bx + cs ~/ 2, width - 1);
        final sy = min(by + cs ~/ 2, height - 1);
        final sIdx = (sy * width + sx) * 4;
        final r = src[sIdx], g = src[sIdx + 1], b = src[sIdx + 2], a = src[sIdx + 3];
        final yEnd = min(by + cs, height);
        final xEnd = min(bx + cs, width);
        for (int y = by; y < yEnd; y++) {
          for (int x = bx; x < xEnd; x++) {
            final p = y * width + x;
            if (selectionMask != null && selectionMask[p] == 0) continue;
            final dIdx = p * 4;
            out[dIdx] = r;
            out[dIdx + 1] = g;
            out[dIdx + 2] = b;
            out[dIdx + 3] = a;
          }
        }
      }
    }
    return out;
  }

  static Uint8List addNoise(
    Uint8List src,
    int width,
    int height, {
    double amount = 25.0,
    bool monochrome = false,
    Uint8List? selectionMask,
  }) {
    final rng = Random(42);
    final out = Uint8List.fromList(src);
    for (int i = 0, p = 0; i < out.length; i += 4, p++) {
      if (out[i + 3] == 0) continue;
      final sel = selectionMask == null ? 1.0 : selectionMask[p] / 255.0;
      if (sel <= 0.0) continue;
      if (monochrome) {
        final delta = (rng.nextDouble() * 2.0 - 1.0) * amount * sel;
        for (int c = 0; c < 3; c++) {
          out[i + c] = (out[i + c] + delta).round().clamp(0, 255);
        }
      } else {
        for (int c = 0; c < 3; c++) {
          final delta = (rng.nextDouble() * 2.0 - 1.0) * amount * sel;
          out[i + c] = (out[i + c] + delta).round().clamp(0, 255);
        }
      }
    }
    return out;
  }

  static Uint8List vignette(
    Uint8List src,
    int width,
    int height, {
    double intensity = 0.65,
    double radius = 0.75,
  }) {
    final out = Uint8List.fromList(src);
    final cx = width / 2.0;
    final cy = height / 2.0;
    final maxR = sqrt(cx * cx + cy * cy);
    final inner = maxR * radius.clamp(0.1, 0.95);
    for (int y = 0; y < height; y++) {
      final dy = y - cy;
      for (int x = 0; x < width; x++) {
        final dx = x - cx;
        final dist = sqrt(dx * dx + dy * dy);
        if (dist <= inner) continue;
        final t = ((dist - inner) / max(1.0, maxR - inner)).clamp(0.0, 1.0);
        final darken = (1.0 - t * t * intensity).clamp(0.0, 1.0);
        final idx = (y * width + x) * 4;
        out[idx] = (out[idx] * darken).round();
        out[idx + 1] = (out[idx + 1] * darken).round();
        out[idx + 2] = (out[idx + 2] * darken).round();
      }
    }
    return out;
  }

  static Uint8List sobelEdgeDetect(Uint8List src, int width, int height) {
    final out = Uint8List.fromList(src);
    double lum(int x, int y) {
      final cx = x.clamp(0, width - 1);
      final cy = y.clamp(0, height - 1);
      final i = (cy * width + cx) * 4;
      return 0.2126 * src[i] + 0.7152 * src[i + 1] + 0.0722 * src[i + 2];
    }

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 4;
        if (src[idx + 3] == 0) continue;
        final gx = -lum(x - 1, y - 1) -
            2 * lum(x - 1, y) -
            lum(x - 1, y + 1) +
            lum(x + 1, y - 1) +
            2 * lum(x + 1, y) +
            lum(x + 1, y + 1);
        final gy = -lum(x - 1, y - 1) -
            2 * lum(x, y - 1) -
            lum(x + 1, y - 1) +
            lum(x - 1, y + 1) +
            2 * lum(x, y + 1) +
            lum(x + 1, y + 1);
        final mag = sqrt(gx * gx + gy * gy).round().clamp(0, 255);
        out[idx] = mag;
        out[idx + 1] = mag;
        out[idx + 2] = mag;
      }
    }
    return out;
  }

  static Uint8List emboss(Uint8List src, int width, int height) {
    final out = Uint8List.fromList(src);
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 4;
        if (src[idx + 3] == 0) continue;
        final x0 = (x - 1).clamp(0, width - 1);
        final y0 = (y - 1).clamp(0, height - 1);
        final x1 = (x + 1).clamp(0, width - 1);
        final y1 = (y + 1).clamp(0, height - 1);
        final i0 = (y0 * width + x0) * 4;
        final i1 = (y1 * width + x1) * 4;
        for (int c = 0; c < 3; c++) {
          out[idx + c] = (src[i1 + c] - src[i0 + c] + 128).clamp(0, 255);
        }
      }
    }
    return out;
  }

  static Uint8List dropShadow(
    Uint8List src,
    int width,
    int height, {
    int dx = 8,
    int dy = 8,
    double blurRadius = 8.0,
    Color shadowColor = const Color(0xCC000000),
  }) {
    final shadowMask = Uint8List(width * height * 4);
    final sr = (shadowColor.r * 255).round().clamp(0, 255);
    final sg = (shadowColor.g * 255).round().clamp(0, 255);
    final sb = (shadowColor.b * 255).round().clamp(0, 255);
    final sa = shadowColor.a;

    for (int y = 0; y < height; y++) {
      final sy = y - dy;
      if (sy < 0 || sy >= height) continue;
      for (int x = 0; x < width; x++) {
        final sx = x - dx;
        if (sx < 0 || sx >= width) continue;
        final a = src[(sy * width + sx) * 4 + 3];
        if (a == 0) continue;
        final dIdx = (y * width + x) * 4;
        shadowMask[dIdx] = sr;
        shadowMask[dIdx + 1] = sg;
        shadowMask[dIdx + 2] = sb;
        shadowMask[dIdx + 3] = (a * sa).round().clamp(0, 255);
      }
    }

    final blurred = gaussianBlur(shadowMask, width, height, blurRadius);
    for (int i = 0; i < blurred.length; i += 4) {
      final saTop = src[i + 3] / 255.0;
      if (saTop > 0.0) {
        _blendPixelOver(blurred, i, src[i], src[i + 1], src[i + 2], saTop);
      }
    }
    return blurred;
  }

  // ---------------------------------------------------------------------------
  // Geometric Transforms
  // ---------------------------------------------------------------------------

  static Uint8List flipHorizontal(Uint8List src, int w, int h) {
    final out = Uint8List(src.length);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final s = (y * w + (w - 1 - x)) * 4;
        final d = (y * w + x) * 4;
        out[d] = src[s];
        out[d + 1] = src[s + 1];
        out[d + 2] = src[s + 2];
        out[d + 3] = src[s + 3];
      }
    }
    return out;
  }

  static Uint8List flipVertical(Uint8List src, int w, int h) {
    final out = Uint8List(src.length);
    final rowBytes = w * 4;
    for (int y = 0; y < h; y++) {
      final sOff = (h - 1 - y) * rowBytes;
      final dOff = y * rowBytes;
      out.setRange(dOff, dOff + rowBytes, src, sOff);
    }
    return out;
  }

  static Uint8List rotate90CW(Uint8List src, int w, int h) {
    final out = Uint8List(src.length);
    final nw = h;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final nx = h - 1 - y;
        final ny = x;
        final s = (y * w + x) * 4;
        final d = (ny * nw + nx) * 4;
        out[d] = src[s];
        out[d + 1] = src[s + 1];
        out[d + 2] = src[s + 2];
        out[d + 3] = src[s + 3];
      }
    }
    return out;
  }

  static Uint8List rotate90CCW(Uint8List src, int w, int h) {
    final out = Uint8List(src.length);
    final nw = h;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final nx = y;
        final ny = w - 1 - x;
        final s = (y * w + x) * 4;
        final d = (ny * nw + nx) * 4;
        out[d] = src[s];
        out[d + 1] = src[s + 1];
        out[d + 2] = src[s + 2];
        out[d + 3] = src[s + 3];
      }
    }
    return out;
  }

  static Uint8List rotate180(Uint8List src, int w, int h) {
    final out = Uint8List(src.length);
    final n = w * h;
    for (int i = 0; i < n; i++) {
      final s = (n - 1 - i) * 4;
      final d = i * 4;
      out[d] = src[s];
      out[d + 1] = src[s + 1];
      out[d + 2] = src[s + 2];
      out[d + 3] = src[s + 3];
    }
    return out;
  }

  static Uint8List resizeBilinear(
    Uint8List src,
    int srcW,
    int srcH,
    int dstW,
    int dstH,
  ) {
    if (srcW == dstW && srcH == dstH) return Uint8List.fromList(src);
    final out = Uint8List(dstW * dstH * 4);
    final scaleX = srcW / dstW;
    final scaleY = srcH / dstH;

    for (int y = 0; y < dstH; y++) {
      final gy = ((y + 0.5) * scaleY - 0.5).clamp(0.0, (srcH - 1).toDouble());
      final y0 = gy.floor();
      final y1 = min(y0 + 1, srcH - 1);
      final fy = gy - y0;

      for (int x = 0; x < dstW; x++) {
        final gx = ((x + 0.5) * scaleX - 0.5).clamp(0.0, (srcW - 1).toDouble());
        final x0 = gx.floor();
        final x1 = min(x0 + 1, srcW - 1);
        final fx = gx - x0;

        final i00 = (y0 * srcW + x0) * 4;
        final i10 = (y0 * srcW + x1) * 4;
        final i01 = (y1 * srcW + x0) * 4;
        final i11 = (y1 * srcW + x1) * 4;

        final w00 = (1 - fx) * (1 - fy);
        final w10 = fx * (1 - fy);
        final w01 = (1 - fx) * fy;
        final w11 = fx * fy;

        final d = (y * dstW + x) * 4;
        for (int c = 0; c < 4; c++) {
          out[d + c] = (src[i00 + c] * w00 +
                  src[i10 + c] * w10 +
                  src[i01 + c] * w01 +
                  src[i11 + c] * w11)
              .round()
              .clamp(0, 255);
        }
      }
    }
    return out;
  }

  static Uint8List cropOrPadLayer(
    Uint8List src,
    int srcW,
    int srcH,
    double offsetX,
    double offsetY,
    Rect cropRect,
  ) {
    final nw = max(1, cropRect.width.round());
    final nh = max(1, cropRect.height.round());
    final out = Uint8List(nw * nh * 4);
    final ox = (offsetX - cropRect.left).round();
    final oy = (offsetY - cropRect.top).round();

    for (int y = 0; y < srcH; y++) {
      final dy = y + oy;
      if (dy < 0 || dy >= nh) continue;
      for (int x = 0; x < srcW; x++) {
        final dx = x + ox;
        if (dx < 0 || dx >= nw) continue;
        final s = (y * srcW + x) * 4;
        final d = (dy * nw + dx) * 4;
        out[d] = src[s];
        out[d + 1] = src[s + 1];
        out[d + 2] = src[s + 2];
        out[d + 3] = src[s + 3];
      }
    }
    return out;
  }
}
