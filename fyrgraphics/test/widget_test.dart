import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:fyrgraphics/engine/pixel_ops.dart';
import 'package:fyrgraphics/engine/project_io.dart';
import 'package:fyrgraphics/main.dart';
import 'package:fyrgraphics/models/editor_types.dart';
import 'package:fyrgraphics/state/editor_controller.dart';

void main() {
  group('PixelOps Engine', () {
    test('createBlankRgba and createFilledRgba create expected buffers', () {
      final blank = PixelOps.createBlankRgba(10, 10);
      expect(blank.length, 400);
      expect(blank.every((b) => b == 0), isTrue);

      final red = PixelOps.createFilledRgba(4, 4, const Color(0xFFFF0000));
      expect(red[0], 255);
      expect(red[1], 0);
      expect(red[2], 0);
      expect(red[3], 255);
    });

    test('stampDab paints and erases pixels accurately', () {
      final buf = PixelOps.createBlankRgba(32, 32);
      PixelOps.stampDab(
        pixels: buf,
        width: 32,
        height: 32,
        cx: 16,
        cy: 16,
        radius: 6,
        hardness: 1.0,
        opacity: 1.0,
        color: const Color(0xFF00FF00),
        erase: false,
        hardPixelEdge: true,
      );
      final center = PixelOps.samplePixel(buf, 32, 32, 16, 16);
      expect((center.g * 255).round(), 255);
      expect((center.a * 255).round(), 255);
      final corner = PixelOps.samplePixel(buf, 32, 32, 0, 0);
      expect((corner.a * 255).round(), 0);

      PixelOps.stampDab(
        pixels: buf,
        width: 32,
        height: 32,
        cx: 16,
        cy: 16,
        radius: 6,
        hardness: 1.0,
        opacity: 1.0,
        color: Colors.black,
        erase: true,
        hardPixelEdge: true,
      );
      final erased = PixelOps.samplePixel(buf, 32, 32, 16, 16);
      expect((erased.a * 255).round(), 0);
    });

    test('floodFill respects boundaries and selection mask', () {
      final buf = PixelOps.createFilledRgba(16, 16, Colors.white);
      // Draw vertical black wall at x=8
      for (int y = 0; y < 16; y++) {
        final idx = (y * 16 + 8) * 4;
        buf[idx] = 0;
        buf[idx + 1] = 0;
        buf[idx + 2] = 0;
      }
      PixelOps.floodFill(
        pixels: buf,
        width: 16,
        height: 16,
        startX: 2,
        startY: 2,
        fillColor: const Color(0xFF0000FF),
        tolerance: 5,
        opacity: 1.0,
      );
      final leftSide = PixelOps.samplePixel(buf, 16, 16, 4, 8);
      final rightSide = PixelOps.samplePixel(buf, 16, 16, 12, 8);
      expect((leftSide.b * 255).round(), 255);
      expect((leftSide.r * 255).round(), 0);
      expect((rightSide.r * 255).round(), 255);
      expect((rightSide.g * 255).round(), 255);
    });

    test('magicWandMask selects contiguous region within tolerance', () {
      final buf = PixelOps.createFilledRgba(10, 10, const Color(0xFF102030));
      for (int y = 0; y < 10; y++) {
        final idx = (y * 10 + 5) * 4;
        buf[idx] = 250;
        buf[idx + 1] = 250;
        buf[idx + 2] = 250;
      }
      final mask = PixelOps.magicWandMask(
        pixels: buf,
        width: 10,
        height: 10,
        startX: 1,
        startY: 1,
        tolerance: 10,
        contiguous: true,
      );
      expect(mask[1 * 10 + 2], 255);
      expect(mask[1 * 10 + 5], 0);
      expect(mask[1 * 10 + 8], 0);
    });

    test('adjustments and filters modify pixels cleanly', () {
      final buf = PixelOps.createFilledRgba(16, 16, const Color(0xFF804020));
      final inv = PixelOps.invertColors(buf);
      expect(inv[0], 127);
      expect(inv[1], 191);
      expect(inv[2], 223);

      final gray = PixelOps.desaturate(buf);
      expect(gray[0], gray[1]);
      expect(gray[1], gray[2]);

      final blurred = PixelOps.gaussianBlur(buf, 16, 16, 3.0);
      expect(blurred.length, buf.length);
      expect(blurred[3], 255);

      final pix = PixelOps.pixelate(buf, 16, 16, 4);
      expect(pix.length, buf.length);
    });

    test('geometric transforms preserve dimensions and content', () {
      final buf = PixelOps.createBlankRgba(4, 2);
      // Set top-left pixel (0,0) to red
      buf[0] = 255;
      buf[3] = 255;

      final flippedH = PixelOps.flipHorizontal(buf, 4, 2);
      expect(flippedH[(0 * 4 + 3) * 4], 255);
      expect(flippedH[0], 0);

      final rotCW = PixelOps.rotate90CW(buf, 4, 2);
      // New dimensions are 2x4; (0,0) maps to (nx=1, ny=0)
      expect(rotCW[(0 * 2 + 1) * 4], 255);

      final resized = PixelOps.resizeBilinear(buf, 4, 2, 8, 4);
      expect(resized.length, 8 * 4 * 4);
    });

    test('selection mask outline path builds non-empty contour', () {
      final mask =
          PixelOps.buildRectSelectionMask(20, 20, const Rect.fromLTWH(4, 4, 8, 8));
      final bounds = PixelOps.computeMaskBounds(mask, 20, 20);
      expect(bounds, const Rect.fromLTWH(4, 4, 8, 8));
      final path = PixelOps.computeMaskOutlinePath(mask, 20, 20);
      expect(path.getBounds(), const Rect.fromLTWH(4, 4, 8, 8));
    });
  });

  group('ProjectIO (.fyrg & export)', () {
    test('saves and loads multi-layer .fyrg archive', () async {
      final tmpDir = await Directory.systemTemp.createTemp('fyrgraphics_test_');
      try {
        final w = 16;
        final h = 16;
        final p1 = PixelOps.createFilledRgba(w, h, const Color(0xFFFF0000));
        final p2 = PixelOps.createFilledRgba(w, h, const Color(0xFF00FF00));
        final doc = GraphicsDocument(
          id: 'doc1',
          title: 'TestProject',
          width: w,
          height: h,
          layers: [
            RasterLayer(
              id: 'l1',
              name: 'Base',
              width: w,
              height: h,
              pixels: p1,
            ),
            RasterLayer(
              id: 'l2',
              name: 'Overlay',
              blendMode: LayerBlendMode.multiply,
              opacity: 0.5,
              width: w,
              height: h,
              pixels: p2,
            ),
          ],
          activeLayerIndex: 1,
        );

        final fyrgPath = '${tmpDir.path}/sample.fyrg';
        await ProjectIO.saveFyrgProject(doc, fyrgPath);
        expect(File(fyrgPath).existsSync(), isTrue);

        final loaded = await ProjectIO.loadFyrgProject(fyrgPath);
        expect(loaded.width, w);
        expect(loaded.height, h);
        expect(loaded.layers.length, 2);
        expect(loaded.layers[0].name, 'Base');
        expect(loaded.layers[1].blendMode, LayerBlendMode.multiply);
        expect(loaded.layers[1].opacity, closeTo(0.5, 0.001));
        expect(loaded.layers[0].pixels[0], 255);
        expect(loaded.layers[1].pixels[1], 255);
      } finally {
        await tmpDir.delete(recursive: true);
      }
    });
  });

  group('FyrGraphics UI Smoke Test', () {
    testWidgets('renders EditorShell with tools, layers, and canvas',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final ctrl = EditorController();
      await tester.runAsync(() async {
        await ctrl.initialize();
      });

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: ctrl,
          child: const FyrGraphicsApp(),
        ),
      );
      await tester.pump();

      expect(find.text('fyrGraphics'), findsOneWidget);
      expect(find.text('Layers'), findsOneWidget);
      expect(find.text('Color'), findsOneWidget);
      expect(find.text('Export'), findsOneWidget);
      expect(find.text('1280 × 720 px'), findsOneWidget);
    });
  });
}
