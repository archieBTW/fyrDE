import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrsettings/widgets/circle_crop_dialog.dart';

int _crc32(List<int> data) {
  int crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (int i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : (crc >> 1);
    }
  }
  return crc ^ 0xFFFFFFFF;
}

List<int> _pngChunk(String type, List<int> data) {
  final out = BytesBuilder();
  final len = ByteData(4)..setUint32(0, data.length);
  final typeBytes = type.codeUnits;
  final crcInput = [...typeBytes, ...data];
  final crc = ByteData(4)..setUint32(0, _crc32(crcInput));
  out.add(len.buffer.asUint8List());
  out.add(typeBytes);
  out.add(data);
  out.add(crc.buffer.asUint8List());
  return out.toBytes();
}

Uint8List _createValidTestPng(int width, int height) {
  final ihdr = BytesBuilder();
  final ihdrHeader = ByteData(8)
    ..setUint32(0, width)
    ..setUint32(4, height);
  ihdr.add(ihdrHeader.buffer.asUint8List());
  ihdr.add([8, 2, 0, 0, 0]); // 8-bit RGB

  final rawRows = BytesBuilder();
  for (int y = 0; y < height; y++) {
    rawRows.addByte(0); // filter type 0
    for (int x = 0; x < width; x++) {
      rawRows.add([128, 0, 128]);
    }
  }
  final idat = zlib.encode(rawRows.toBytes());

  final png = BytesBuilder();
  png.add([137, 80, 78, 71, 13, 10, 26, 10]);
  png.add(_pngChunk('IHDR', ihdr.toBytes()));
  png.add(_pngChunk('IDAT', idat));
  png.add(_pngChunk('IEND', const []));
  return png.toBytes();
}

void main() {
  testWidgets('CircleCropDialog supports zoom in, zoom out, reset, and save', (
    tester,
  ) async {
    final tempDir = Directory.systemTemp.createTempSync('crop_test_');
    final imgFile = File('${tempDir.path}/avatar.png');
    imgFile.writeAsBytesSync(_createValidTestPng(20, 20));

    CropRect? result;

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.push<CropRect>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CircleCropDialog(imagePath: imgFile.path),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      for (int i = 0; i < 20 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('crop_zoom_in')), findsOneWidget);
      expect(find.byKey(const Key('crop_zoom_out')), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      await tester.tap(find.byKey(const Key('crop_zoom_in')));
      await tester.pumpAndSettle();
      expect(find.text('125%'), findsOneWidget);

      await tester.tap(find.byKey(const Key('crop_zoom_out')));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);

      await tester.tap(find.byKey(const Key('crop_zoom_out')));
      await tester.pumpAndSettle();
      expect(find.text('80%'), findsOneWidget);

      await tester.tap(find.byKey(const Key('crop_zoom_reset')));
      await tester.pumpAndSettle();
      expect(find.text('100%'), findsOneWidget);

      await tester.tap(find.byKey(const Key('crop_zoom_in')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.width, greaterThan(0));
      expect(result!.height, greaterThan(0));
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });
}
