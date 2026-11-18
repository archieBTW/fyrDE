import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrmonitor/fyr_theme.dart';
import 'package:fyrmonitor/main.dart';
import 'package:fyrmonitor/tabs/open_apps_tab.dart';
import 'package:fyrmonitor/tabs/performance_tab.dart';
import 'package:fyrmonitor/tabs/processes_tab.dart';
import 'package:fyrmonitor/widgets/traffic_lights.dart';

void main() {
  setUpAll(() {
    FyrTheme.initialize(watch: false);
  });

  testWidgets('shell renders the title bar and all three tabs', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const FyrMonitorApp());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('fyrMonitor'), findsOneWidget);
    expect(find.text('Task Manager'), findsOneWidget);
    expect(find.text('Open Apps'), findsOneWidget);
    expect(find.text('Processes'), findsOneWidget);
    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('live · 1.5 s'), findsOneWidget);

    // Dispose the shell so the active tab's poll timer is cancelled before the
    // test framework checks for pending timers.
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('title bar shows traffic lights on the left', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const FyrMonitorApp());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(TrafficLights), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(find.byTooltip('Minimize'), findsOneWidget);
    expect(find.byTooltip('Maximize'), findsOneWidget);

    // Traffic lights sit before the app title, not at the right edge.
    final lightsX = tester.getCenter(find.byType(TrafficLights)).dx;
    final titleX = tester.getCenter(find.text('fyrMonitor')).dx;
    expect(lightsX, lessThan(titleX));

    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('lays out cleanly at the minimum window size', (tester) async {
    // 640x430 is the smallest size the window manager allows; overflow errors
    // surface as test exceptions, so this guards the compact layout.
    tester.view.physicalSize = const Size(640, 430);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const FyrMonitorApp());
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);

    for (final label in <String>['Processes', 'Performance', 'Open Apps']) {
      await tester.tap(find.text(label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull, reason: '$label overflowed');
    }

    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching tabs swaps the visible panel', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const FyrMonitorApp());
    await tester.pump(const Duration(milliseconds: 50));

    // IndexedStack keeps every child mounted but marks the hidden ones
    // offstage, so the finders need skipOffstage: false.
    expect(find.byType(OpenAppsTab), findsOneWidget);
    expect(
      find.byType(ProcessesTab, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byType(PerformanceTab, skipOffstage: false),
      findsOneWidget,
    );

    await tester.tap(find.text('Performance'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // IndexedStack keeps both tabs mounted, so 'CPU' shows up as the process
    // table header *and* the performance card title.
    expect(find.text('CPU'), findsWidgets);
    expect(find.text('MEMORY'), findsOneWidget);
    expect(find.text('DISK'), findsOneWidget);
    expect(find.text('NETWORK'), findsOneWidget);

    await tester.tap(find.text('Processes'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('NAME'), findsOneWidget);
    expect(find.text('PID'), findsOneWidget);
    expect(find.text('MEMORY'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('inactive tabs schedule no polling timer', (tester) async {
    // A passing test here is itself the assertion: flutter_test fails when a
    // Timer is still pending at teardown, so an inactive tab that started
    // polling would break this test.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final tab in <Widget>[
      const OpenAppsTab(active: false),
      const ProcessesTab(active: false),
      const PerformanceTab(active: false),
    ]) {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: tab)));
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    }

    // Nothing polled, so the open-apps list never populated.
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: OpenAppsTab(active: false))),
    );
    await tester.pump();
    expect(find.text('refreshed every 1.5 s'), findsOneWidget);
    expect(find.text('0 open windows'), findsOneWidget);
  });

  testWidgets('performance tab shows a placeholder before the first sample',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PerformanceTab(active: false))),
    );
    await tester.pump();
    expect(
      find.text('Waiting for the first /proc/stat sample…'),
      findsOneWidget,
    );
    // Swap is unknown until the first /proc/meminfo read.
    expect(find.text('not configured'), findsNothing);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('performance tab tiles have even sizes in two-column layout',
      (tester) async {
    tester.view.physicalSize = const Size(880, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PerformanceTab(active: false))),
    );
    await tester.pump();

    final cards = find.byType(
      // SectionCard is the outer container for CPU, MEMORY, DISK, NETWORK
      // ignore: invalid_use_of_protected_member
      tester.widget(find.ancestor(
        of: find.text('CPU'),
        matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == 'SectionCard'),
      )).runtimeType,
    );
    expect(cards, findsNWidgets(4));

    final sizes = [
      for (var i = 0; i < 4; i++) tester.getSize(cards.at(i)),
    ];
    for (final size in sizes) {
      expect(size.width, closeTo(sizes.first.width, 0.5));
      expect(size.height, closeTo(sizes.first.height, 0.5));
    }
  });
}
