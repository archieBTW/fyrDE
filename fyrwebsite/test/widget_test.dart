import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrwebsite/main.dart';

Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.4,
    duration: Duration.zero,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    FyrFonts.enableGoogleFonts = false;
  });

  test('catalog includes all 44 Fyr apps and valid compressed screenshots', () {
    final names = fyrAppsCatalog.map((app) => app.name).toSet();

    for (final expected in const [
      // Shell & Core
      'fyrTaskbar',
      'fyrDock',
      'fyrSearch',
      'fyrOverview',
      'fyrWindowOverview',
      'fyrClipboard',
      'fyrEmoji',
      'fyrHelp',
      // System & Daily
      'fyrFiles',
      'fyrTerm',
      'fyrSettings',
      'fyrMonitor',
      'fyrDisks',
      'fyrAV',
      'fyrStore',
      'fyrConnect',
      'fyrBrowser',
      'fyrJournal',
      'fyrCalculator',
      'fyrCalendar',
      'fyrClock',
      'fyrTorrent',
      // Creative Studio
      'fyrGraphics',
      'devign',
      'fyrDirector',
      'fyrDAW',
      'fyrPhotos',
      'fyrCamera',
      'fyrMusic',
      'fyrVideo',
      // Office Suite
      'fyrDocs',
      'fyrSheets',
      'fyrSlides',
      'fyrPDF',
      'fyrText',
      // Dev & Virtualization
      'fyrCode',
      'fyrAPI',
      'fyrDB',
      'fyrPods',
      'fyrVirt',
      'fyrEmu',
      // CLI & Mobile
      'fyrpak',
      'fyrAndroid',
      'fyrfetch',
    ]) {
      expect(names.contains(expected), isTrue, reason: 'Missing $expected');
    }

    for (final showcase in fyrDesktopShowcases) {
      final file = File(showcase.assetPath);
      expect(file.existsSync(), isTrue, reason: 'Missing ${file.path}');
    }

    for (final app in fyrAppsCatalog) {
      expect(
        app.screenshot,
        isNotNull,
        reason: 'Every app must have a screenshot (${app.name} is missing one)',
      );
      for (final assetPath in app.allScreenshotAssets) {
        final file = File(assetPath);
        expect(file.existsSync(), isTrue, reason: 'Missing ${file.path}');
        expect(
          file.lengthSync(),
          lessThan(800 * 1024),
          reason: 'Expected ${file.path} to be compressed (< 800 KB)',
        );
      }
    }

    // fyrEmu belongs under Creative & Media, not Dev & Virt.
    final fyrEmu = fyrAppsCatalog.firstWhere((a) => a.id == 'fyremu');
    expect(fyrEmu.category, FyrCategory.creative);
  });

  testWidgets(
    'desktop viewport renders hero, switches app tabs, searches, and shows latest apps',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const FyrWebsite());
      await tester.pumpAndSettle();

      // Hero & initial Shell & Core tab
      expect(find.text('frick your RAM.'), findsOneWidget);
      expect(find.text('Install Now'), findsOneWidget);
      expect(find.text('Explore Suite'), findsOneWidget);
      expect(find.text('fyrClipboard'), findsOneWidget);

      // Switch Desktop Showcase preview pill
      await _scrollAndTap(tester, find.text('Tiling'));
      expect(find.text('fyrDE · tiling layout'), findsOneWidget);

      // Switch to System & Daily -> verify fyrConnect
      await _scrollAndTap(tester, find.byKey(const Key('category-tab-system')));
      expect(find.text('fyrConnect'), findsOneWidget);

      // Switch to Creative Studio -> verify devign
      await _scrollAndTap(
        tester,
        find.byKey(const Key('category-tab-creative')),
      );
      expect(find.text('devign'), findsOneWidget);

      // Switch to Office Suite -> verify fyrPDF
      await _scrollAndTap(tester, find.byKey(const Key('category-tab-office')));
      expect(find.text('fyrPDF'), findsOneWidget);

      // Switch to Dev & Virt -> verify fyrCode & fyrDB
      await _scrollAndTap(tester, find.byKey(const Key('category-tab-dev')));
      expect(find.text('fyrCode'), findsOneWidget);
      expect(find.text('fyrDB'), findsOneWidget);

      // Switch to CLI & Mobile -> verify fyrpak & fyrAndroid
      await _scrollAndTap(
        tester,
        find.byKey(const Key('category-tab-cliMobile')),
      );
      expect(find.text('fyrpak'), findsOneWidget);
      expect(find.text('fyrAndroid'), findsOneWidget);

      // Search across all categories
      final searchField = find.byKey(const Key('app-explorer-search'));
      await Scrollable.ensureVisible(
        tester.element(searchField),
        alignment: 0.4,
        duration: Duration.zero,
      );
      await tester.pumpAndSettle();
      await tester.enterText(searchField, 'fyrPDF');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('app-card-fyrpdf')), findsOneWidget);

      // Switch Install tabs
      await _scrollAndTap(tester, find.byKey(const Key('install-tab-suites')));
      expect(
        find.text('./install_suite.sh --suite creative'),
        findsOneWidget,
      );

      await _scrollAndTap(tester, find.byKey(const Key('install-tab-fyrpak')));
      expect(find.text('fyrpak fyr update'), findsOneWidget);
    },
  );

  testWidgets(
    'mobile viewport renders cleanly without overflow and switches tabs',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const FyrWebsite());
      await tester.pumpAndSettle();

      expect(find.text('frick your RAM.'), findsOneWidget);
      expect(find.text('fyrClipboard'), findsOneWidget);

      // Tap System & Daily tab on mobile -> verify fyrConnect
      await _scrollAndTap(tester, find.byKey(const Key('category-tab-system')));
      expect(find.text('fyrConnect'), findsOneWidget);

      // Tap Creative Studio tab on mobile -> verify devign
      await _scrollAndTap(
        tester,
        find.byKey(const Key('category-tab-creative')),
      );
      expect(find.text('devign'), findsOneWidget);

      // Tap Office Suite tab on mobile -> verify fyrPDF
      await _scrollAndTap(tester, find.byKey(const Key('category-tab-office')));
      expect(find.text('fyrPDF'), findsOneWidget);

      // Tap CLI & Mobile tab on mobile -> verify fyrpak & fyrAndroid
      await _scrollAndTap(
        tester,
        find.byKey(const Key('category-tab-cliMobile')),
      );
      expect(find.text('fyrpak'), findsOneWidget);
      expect(find.text('fyrAndroid'), findsOneWidget);

      // Category filter pills wrap cleanly instead of hiding inside a horizontal scroll view.
      final firstPill = find.byKey(const Key('category-tab-shell'));
      expect(
        find.ancestor(of: firstPill, matching: find.byType(Wrap)),
        findsAtLeastNWidgets(1),
      );
    },
  );
}
