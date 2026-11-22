import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrgraphics/engine/pro_pixel_ops.dart';
import 'package:fyrgraphics/models/editor_types.dart';

void main() {
  test('expandSymmetrySegments generates correct mirrored and radial segments', () {
    final segV = ProPixelOps.expandSymmetrySegments(
      const Offset(20, 30),
      const Offset(40, 50),
      100,
      100,
      SymmetryMode.vertical,
    );
    expect(segV.length, 2);
    expect(segV[1].$1, const Offset(80, 30));

    final segQ = ProPixelOps.expandSymmetrySegments(
      const Offset(20, 30),
      const Offset(40, 50),
      100,
      100,
      SymmetryMode.quadrant,
    );
    expect(segQ.length, 4);

    final segR8 = ProPixelOps.expandSymmetrySegments(
      const Offset(60, 50),
      const Offset(70, 50),
      100,
      100,
      SymmetryMode.radial8,
    );
    expect(segR8.length, 8);
  });

  test('buildCurveLut identity and lift blacks behave smoothly', () {
    final identity = ProPixelOps.buildCurveLut(
      const [Offset(0, 0), Offset(0.5, 0.5), Offset(1, 1)],
    );
    expect(identity.length, 256);
    expect(identity[0], 0);
    expect(identity[128], closeTo(128, 2));
    expect(identity[255], 255);

    final lifted = ProPixelOps.buildCurveLut(
      const [Offset(0, 0.2), Offset(1, 1)],
    );
    expect(lifted[0], closeTo(51, 2));
    expect(lifted[255], 255);
  });

  test('computeHistogram and adjustDevelop process RGBA buffers accurately', () {
    final px = Uint8List.fromList([
      100, 120, 140, 255,
      100, 120, 140, 255,
      200, 50, 80, 255,
      0, 0, 0, 0,
    ]);
    final hist = ProPixelOps.computeHistogram(px);
    expect(hist.r[100], 2);
    expect(hist.r[200], 1);

    final brighter = ProPixelOps.adjustDevelop(px, exposure: 0.8);
    expect(brighter[0], greaterThan(px[0]));
    expect(brighter[15], 0); // transparent pixel untouched
  });

  test('generateColorHarmonies returns full designer color scheme sets', () {
    final h = ProPixelOps.generateColorHarmonies(const Color(0xFFE040FB));
    expect(h['Complementary']!.length, 2);
    expect(h['Triadic']!.length, 3);
    expect(h['Tetradic']!.length, 4);
    expect(h['Tints & Shades']!.length, 7);
  });
}
