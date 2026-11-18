import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrmonitor/fyr_theme.dart';
import 'package:fyrmonitor/widgets/fyr_tab_bar.dart';
import 'package:fyrmonitor/widgets/smooth_area_chart.dart';

void main() {
  setUpAll(() {
    // Avoid the filesystem watcher touching ~/.config/fyr during tests.
    FyrTheme.initialize(watch: false);
  });

  testWidgets('FyrTabBar reports the tapped tab', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => FyrTabBar(
              items: const [
                FyrTabItem(label: 'Open Apps', icon: Icons.grid_view_rounded),
                FyrTabItem(label: 'Processes', icon: Icons.memory_rounded),
                FyrTabItem(label: 'Performance', icon: Icons.insights_rounded),
              ],
              index: selected,
              onChanged: (index) => setState(() => selected = index),
            ),
          ),
        ),
      ),
    );

    expect(find.text('Open Apps'), findsOneWidget);
    expect(find.text('Performance'), findsOneWidget);

    await tester.tap(find.text('Performance'));
    await tester.pumpAndSettle();
    expect(selected, 2);
  });

  testWidgets('SmoothAreaChart renders without samples', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SmoothAreaChart(
            series: [ChartSeries(label: 'CPU', color: Colors.purple, values: [])],
            maxValue: 100,
          ),
        ),
      ),
    );
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SmoothAreaChart renders a full 60 second buffer', (tester) async {
    final values = List<double>.generate(kChartSamples, (i) => i.toDouble());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SmoothAreaChart(
            series: [
              ChartSeries(label: 'CPU', color: Colors.purple, values: values),
              ChartSeries(
                label: 'Cached',
                color: Colors.teal,
                values: values.reversed.toList(),
              ),
            ],
            maxValue: 100,
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
  });

  test('kChartSamples matches a 60 second window at 1.5 s polling', () {
    expect(kChartSamples * 1.5, 60);
  });
}
