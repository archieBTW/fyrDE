import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/editor_types.dart';
import 'pixel_ops.dart';

class ProjectIO {
  /// Renders a [TextLayerData] onto a fresh [width] x [height] straight-RGBA buffer.
  static Future<Uint8List> renderTextToRgba(
    TextLayerData data,
    int width,
    int height, {
    Offset origin = const Offset(20, 20),
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );
    final painter = TextPainter(
      text: TextSpan(
        text: data.text,
        style: TextStyle(
          color: data.color,
          fontFamily: data.fontFamily,
          fontSize: data.fontSize,
          fontWeight: data.bold ? FontWeight.bold : FontWeight.normal,
          fontStyle: data.italic ? FontStyle.italic : FontStyle.normal,
        ),
      ),
      textAlign: data.align,
      textDirection: TextDirection.ltr,
    );
    painter.layout(maxWidth: max(100.0, width - origin.dx - 16.0));
    painter.paint(canvas, origin);

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(width, height);
    final byteData =
        await rendered.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    rendered.dispose();
    if (byteData == null) return PixelOps.createBlankRgba(width, height);
    return byteData.buffer.asUint8List();
  }

  /// Rasterizes a vector shape into a straight-RGBA overlay and composites onto [target].
  static Future<Uint8List> renderShapeOverlay({
    required int width,
    required int height,
    required ShapeKind kind,
    required Offset start,
    required Offset end,
    required Color fillColor,
    required Color strokeColor,
    required double strokeWidth,
    required bool hasFill,
    required bool hasStroke,
    double cornerRadius = 12.0,
    int polygonSides = 5,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    final rect = Rect.fromPoints(start, end);
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    void paintPath(Path path) {
      if (hasFill) canvas.drawPath(path, fillPaint);
      if (hasStroke && strokeWidth > 0) canvas.drawPath(path, strokePaint);
    }

    switch (kind) {
      case ShapeKind.rectangle:
        if (hasFill) canvas.drawRect(rect, fillPaint);
        if (hasStroke && strokeWidth > 0) canvas.drawRect(rect, strokePaint);
        break;
      case ShapeKind.roundedRect:
        final rr = RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius));
        if (hasFill) canvas.drawRRect(rr, fillPaint);
        if (hasStroke && strokeWidth > 0) canvas.drawRRect(rr, strokePaint);
        break;
      case ShapeKind.ellipse:
        if (hasFill) canvas.drawOval(rect, fillPaint);
        if (hasStroke && strokeWidth > 0) canvas.drawOval(rect, strokePaint);
        break;
      case ShapeKind.line:
        canvas.drawLine(start, end, strokePaint);
        break;
      case ShapeKind.arrow:
        canvas.drawLine(start, end, strokePaint);
        final angle = atan2(end.dy - start.dy, end.dx - start.dx);
        final headLen = max(14.0, strokeWidth * 3.5);
        const spread = 0.48;
        final p1 = Offset(
          end.dx - headLen * cos(angle - spread),
          end.dy - headLen * sin(angle - spread),
        );
        final p2 = Offset(
          end.dx - headLen * cos(angle + spread),
          end.dy - headLen * sin(angle + spread),
        );
        final arrowPath = Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(end.dx, end.dy)
          ..lineTo(p2.dx, p2.dy);
        canvas.drawPath(arrowPath, strokePaint);
        break;
      case ShapeKind.polygon:
        final sides = polygonSides.clamp(3, 16);
        final center = rect.center;
        final rx = rect.width / 2.0;
        final ry = rect.height / 2.0;
        final path = Path();
        for (int i = 0; i < sides; i++) {
          final a = -pi / 2 + (2 * pi * i) / sides;
          final pt = Offset(center.dx + rx * cos(a), center.dy + ry * sin(a));
          if (i == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        path.close();
        paintPath(path);
        break;
      case ShapeKind.star:
        final points = polygonSides.clamp(3, 16);
        final center = rect.center;
        final rx = rect.width / 2.0;
        final ry = rect.height / 2.0;
        final path = Path();
        for (int i = 0; i < points * 2; i++) {
          final a = -pi / 2 + (pi * i) / points;
          final factor = i.isEven ? 1.0 : 0.45;
          final pt = Offset(
            center.dx + rx * factor * cos(a),
            center.dy + ry * factor * sin(a),
          );
          if (i == 0) {
            path.moveTo(pt.dx, pt.dy);
          } else {
            path.lineTo(pt.dx, pt.dy);
          }
        }
        path.close();
        paintPath(path);
        break;
    }

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(width, height);
    final byteData =
        await rendered.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    rendered.dispose();
    if (byteData == null) return PixelOps.createBlankRgba(width, height);
    return byteData.buffer.asUint8List();
  }

  /// Composites [overlay] onto [base] straight-RGBA buffer respecting [selectionMask].
  static void compositeOverlayOntoLayer({
    required Uint8List base,
    required Uint8List overlay,
    required int width,
    required int height,
    Uint8List? selectionMask,
    int selectionWidth = 0,
    int selectionHeight = 0,
    double layerOffsetX = 0.0,
    double layerOffsetY = 0.0,
  }) {
    for (int y = 0; y < height; y++) {
      final sy = (y + layerOffsetY).round();
      for (int x = 0; x < width; x++) {
        final idx = (y * width + x) * 4;
        final oa = overlay[idx + 3];
        if (oa == 0) continue;

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

        final srcA = (oa / 255.0) * sel;
        final da = base[idx + 3] / 255.0;
        if (srcA >= 0.999 || da <= 0.0) {
          base[idx] = overlay[idx];
          base[idx + 1] = overlay[idx + 1];
          base[idx + 2] = overlay[idx + 2];
          base[idx + 3] = ((srcA + da * (1 - srcA)) * 255).round().clamp(0, 255);
        } else {
          final inv = 1.0 - srcA;
          final outA = srcA + da * inv;
          final daInv = da * inv;
          base[idx] = ((overlay[idx] * srcA + base[idx] * daInv) / outA)
              .round()
              .clamp(0, 255);
          base[idx + 1] =
              ((overlay[idx + 1] * srcA + base[idx + 1] * daInv) / outA)
                  .round()
                  .clamp(0, 255);
          base[idx + 2] =
              ((overlay[idx + 2] * srcA + base[idx + 2] * daInv) / outA)
                  .round()
                  .clamp(0, 255);
          base[idx + 3] = (outA * 255).round().clamp(0, 255);
        }
      }
    }
  }

  /// Flattens a list of [RasterLayer]s onto a [width] x [height] canvas using
  /// hardware/Skia blend modes so exported output matches the viewport identically.
  static Future<Uint8List> flattenLayers(
    List<RasterLayer> layers,
    int width,
    int height, {
    Color? backgroundFill,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    );

    if (backgroundFill != null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        Paint()..color = backgroundFill,
      );
    }

    for (final layer in layers) {
      if (!layer.visible || layer.opacity <= 0.0) continue;
      final uiImg = layer.cachedImage ??
          await PixelOps.decodeStraightRgbaToUiImage(
            layer.pixels,
            layer.width,
            layer.height,
          );
      final paint = Paint()
        ..color = Color.fromRGBO(255, 255, 255, layer.opacity.clamp(0.0, 1.0))
        ..blendMode = layer.blendMode.uiBlendMode
        ..filterQuality = FilterQuality.none;
      canvas.drawImage(uiImg, Offset(layer.offsetX, layer.offsetY), paint);
      if (layer.cachedImage == null) {
        uiImg.dispose();
      }
    }

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(width, height);
    final byteData =
        await rendered.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    rendered.dispose();
    if (byteData == null) return PixelOps.createBlankRgba(width, height);
    return byteData.buffer.asUint8List();
  }

  /// Converts straight RGBA8888 [Uint8List] to a [package:image] Image.
  static img.Image rgbaToPackageImage(Uint8List rgba, int width, int height) {
    return img.Image.fromBytes(
      width: width,
      height: height,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
  }

  /// Converts a [package:image] Image into straight RGBA8888 [Uint8List].
  static Uint8List packageImageToRgba(img.Image src) {
    final converted = src.convert(numChannels: 4, format: img.Format.uint8);
    final out = Uint8List(converted.width * converted.height * 4);
    int i = 0;
    for (final pixel in converted) {
      out[i++] = pixel.r.toInt().clamp(0, 255);
      out[i++] = pixel.g.toInt().clamp(0, 255);
      out[i++] = pixel.b.toInt().clamp(0, 255);
      out[i++] = pixel.a.toInt().clamp(0, 255);
    }
    return out;
  }

  /// Loads any supported image file into `(width, height, straightRgba)`.
  static Future<({int width, int height, Uint8List rgba})> loadImageFile(
    String path,
  ) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded != null) {
      return (
        width: decoded.width,
        height: decoded.height,
        rgba: packageImageToRgba(decoded),
      );
    }
    // Fallback to Flutter's codec (handles WebP, HEIF/platform formats)
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final byteData =
        await frame.image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    final w = frame.image.width;
    final h = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    if (byteData == null) {
      throw Exception('Unable to decode image file: $path');
    }
    return (width: w, height: h, rgba: byteData.buffer.asUint8List());
  }

  /// Exports a flattened [GraphicsDocument] to PNG, JPG, BMP, TGA, or GIF.
  static Future<void> exportImageFile({
    required GraphicsDocument doc,
    required String outputPath,
    required String format, // png, jpg, bmp, tga, gif
    int jpgQuality = 92,
    double scale = 1.0,
  }) async {
    final fmt = format.toLowerCase();
    final bgFill = (fmt == 'jpg' || fmt == 'jpeg') ? Colors.white : null;
    var rgba = await flattenLayers(
      doc.layers,
      doc.width,
      doc.height,
      backgroundFill: bgFill,
    );
    var outW = doc.width;
    var outH = doc.height;

    if ((scale - 1.0).abs() > 0.01) {
      outW = max(1, (doc.width * scale).round());
      outH = max(1, (doc.height * scale).round());
      rgba = PixelOps.resizeBilinear(rgba, doc.width, doc.height, outW, outH);
    }

    final image = rgbaToPackageImage(rgba, outW, outH);
    late Uint8List encoded;
    switch (fmt) {
      case 'jpg':
      case 'jpeg':
        encoded = Uint8List.fromList(img.encodeJpg(image, quality: jpgQuality));
        break;
      case 'bmp':
        encoded = Uint8List.fromList(img.encodeBmp(image));
        break;
      case 'tga':
        encoded = Uint8List.fromList(img.encodeTga(image));
        break;
      case 'gif':
        encoded = Uint8List.fromList(img.encodeGif(image));
        break;
      case 'png':
      default:
        encoded = Uint8List.fromList(img.encodePng(image));
        break;
    }
    await File(outputPath).writeAsBytes(encoded);
  }

  /// Saves a multi-layer `.fyrg` project file (ZIP archive with manifest + PNG layers).
  static Future<void> saveFyrgProject(
    GraphicsDocument doc,
    String outputPath,
  ) async {
    final archive = Archive();
    final layersMeta = <Map<String, dynamic>>[];

    for (int i = 0; i < doc.layers.length; i++) {
      final layer = doc.layers[i];
      final filename = 'layers/layer_$i.png';
      final layerImg = rgbaToPackageImage(layer.pixels, layer.width, layer.height);
      final pngBytes = Uint8List.fromList(img.encodePng(layerImg));
      archive.addFile(ArchiveFile(filename, pngBytes.length, pngBytes));

      layersMeta.add({
        'id': layer.id,
        'name': layer.name,
        'visible': layer.visible,
        'locked': layer.locked,
        'opacity': layer.opacity,
        'blendMode': layer.blendMode.name,
        'offsetX': layer.offsetX,
        'offsetY': layer.offsetY,
        'width': layer.width,
        'height': layer.height,
        'file': filename,
        if (layer.textData != null) 'textData': layer.textData!.toJson(),
      });
    }

    final manifest = jsonEncode({
      'version': 1,
      'title': doc.title,
      'width': doc.width,
      'height': doc.height,
      'activeLayerIndex': doc.activeLayerIndex,
      'layers': layersMeta,
    });
    final manifestBytes = utf8.encode(manifest);
    archive.addFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );

    final zipBytes = ZipEncoder().encode(archive);
    await File(outputPath).writeAsBytes(zipBytes);
  }

  /// Loads a `.fyrg` layered project file.
  static Future<GraphicsDocument> loadFyrgProject(String inputPath) async {
    final bytes = await File(inputPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final manifestFile = archive.findFile('manifest.json');
    if (manifestFile == null) {
      throw Exception('Invalid .fyrg project: missing manifest.json');
    }
    final manifest =
        jsonDecode(utf8.decode(manifestFile.content as List<int>))
            as Map<String, dynamic>;

    final width = manifest['width'] as int? ?? 1280;
    final height = manifest['height'] as int? ?? 720;
    final title = manifest['title'] as String? ?? 'Untitled';
    final activeIdx = manifest['activeLayerIndex'] as int? ?? 0;
    final layersJson = (manifest['layers'] as List<dynamic>? ?? []);

    final layers = <RasterLayer>[];
    for (final raw in layersJson) {
      final map = raw as Map<String, dynamic>;
      final fileRef = map['file'] as String?;
      final lw = map['width'] as int? ?? width;
      final lh = map['height'] as int? ?? height;
      Uint8List pixels;
      if (fileRef != null) {
        final af = archive.findFile(fileRef);
        if (af != null) {
          final decoded = img.decodePng(Uint8List.fromList(af.content as List<int>));
          if (decoded != null) {
            pixels = packageImageToRgba(decoded);
          } else {
            pixels = PixelOps.createBlankRgba(lw, lh);
          }
        } else {
          pixels = PixelOps.createBlankRgba(lw, lh);
        }
      } else {
        pixels = PixelOps.createBlankRgba(lw, lh);
      }

      final bmName = map['blendMode'] as String? ?? 'normal';
      final bm = LayerBlendMode.values.firstWhere(
        (e) => e.name == bmName,
        orElse: () => LayerBlendMode.normal,
      );

      final cachedImg =
          await PixelOps.decodeStraightRgbaToUiImage(pixels, lw, lh);

      layers.add(
        RasterLayer(
          id: map['id'] as String? ??
              DateTime.now().microsecondsSinceEpoch.toString(),
          name: map['name'] as String? ?? 'Layer',
          visible: map['visible'] as bool? ?? true,
          locked: map['locked'] as bool? ?? false,
          opacity: (map['opacity'] as num?)?.toDouble() ?? 1.0,
          blendMode: bm,
          offsetX: (map['offsetX'] as num?)?.toDouble() ?? 0.0,
          offsetY: (map['offsetY'] as num?)?.toDouble() ?? 0.0,
          width: lw,
          height: lh,
          pixels: pixels,
          cachedImage: cachedImg,
          textData: map['textData'] != null
              ? TextLayerData.fromJson(
                  map['textData'] as Map<String, dynamic>,
                )
              : null,
        ),
      );
    }

    if (layers.isEmpty) {
      final blank = PixelOps.createBlankRgba(width, height);
      layers.add(
        RasterLayer(
          id: 'layer_0',
          name: 'Layer 1',
          width: width,
          height: height,
          pixels: blank,
          cachedImage:
              await PixelOps.decodeStraightRgbaToUiImage(blank, width, height),
        ),
      );
    }

    return GraphicsDocument(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      filePath: inputPath,
      width: width,
      height: height,
      layers: layers,
      activeLayerIndex: activeIdx.clamp(0, layers.length - 1),
    );
  }
}
