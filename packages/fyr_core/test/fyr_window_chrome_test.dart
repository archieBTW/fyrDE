import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyr_core/fyr_core.dart';

void main() {
  testWidgets('FyrTitleBar triggers window control callbacks and drag', (tester) async {
    var closed = false;
    var minimized = false;
    var maximized = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FyrTitleBar(
            onClose: () => closed = true,
            onMinimize: () => minimized = true,
            onMaximize: () => maximized = true,
            title: const Text('Test App'),
          ),
        ),
      ),
    );

    expect(find.text('Test App'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.tap(find.byTooltip('Minimize'));
    await tester.tap(find.byTooltip('Maximize / Restore'));
    await tester.pump();

    expect(closed, isTrue);
    expect(minimized, isTrue);
    expect(maximized, isTrue);
  });

  testWidgets('showFyrInputDialog autofocuses input and submits on Enter', (tester) async {
    String? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showFyrInputDialog(
                context: context,
                title: 'New Folder',
                hintText: 'Folder name',
                confirmLabel: 'Create',
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.autofocus, isTrue);

    await tester.enterText(find.byType(TextField), '  docs  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(result, equals('docs'));
  });
}
