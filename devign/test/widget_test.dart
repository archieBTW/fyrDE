import 'package:devign/engine/devign_export.dart';
import 'package:devign/main.dart';
import 'package:devign/models/design_models.dart';
import 'package:devign/state/devign_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DevignController initializes starter showcase with frames, auto-layout & prototype links', () {
    final ctrl = DevignController();
    expect(ctrl.pages.length, 1);
    expect(ctrl.activePage.rootIds.length, 2);

    final frames = ctrl.getTopLevelFrames();
    expect(frames.length, 2);
    expect(frames.first.name, contains('Welcome Screen'));

    final masters = ctrl.getMasterComponents();
    expect(masters.isNotEmpty, isTrue);
    expect(masters.first.prototypeLink, isNotNull);
    expect(masters.first.prototypeLink!.targetFrameId, frames[1].id);

    // Create a new node and test undo/redo
    final beforeCount = ctrl.nodes.length;
    final created = ctrl.createNode(
      type: NodeType.rectangle,
      name: 'Test Rect',
      canvasRect: const Rect.fromLTWH(50, 50, 120, 80),
    );
    expect(ctrl.nodes.length, beforeCount + 1);

    // Code export verification
    final css = DevignExport.generateCss(created);
    expect(css, contains('width: 120px;'));
    final flutterCode = DevignExport.generateFlutterCode(created);
    expect(flutterCode, contains('Container('));
    final svg = DevignExport.generateSvg(frames.first, ctrl.nodes);
    expect(svg, contains('<svg'));

    ctrl.undo();
    expect(ctrl.nodes.length, beforeCount);
    ctrl.redo();
    expect(ctrl.nodes.length, beforeCount + 1);
  });

  testWidgets('DevignApp renders studio shell, toolbars, canvas, and inspector tabs', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    await tester.pumpWidget(const DevignApp());
    await tester.pump();

    expect(find.text('devign'), findsOneWidget);
    expect(find.text('Layers'), findsOneWidget);
    expect(find.text('Assets'), findsOneWidget);
    expect(find.text('Tokens'), findsOneWidget);
    expect(find.text('Design'), findsOneWidget);
    expect(find.text('Prototype'), findsOneWidget);
    expect(find.text('Code'), findsOneWidget);
    expect(find.text('Present'), findsOneWidget);
    expect(find.text('Export'), findsOneWidget);

    // Switch to Prototype tab
    await tester.tap(find.text('Prototype'));
    await tester.pump();
    expect(find.text('FLOW STARTING FRAME'), findsOneWidget);

    // Switch to Code tab
    await tester.tap(find.text('Code'));
    await tester.pump();
    expect(find.text('FLUTTER WIDGET'), findsOneWidget);
    expect(find.text('CSS STYLES'), findsOneWidget);
  });
}
