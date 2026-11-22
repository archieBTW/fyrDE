import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrpdf/fyr_theme.dart';
import 'package:fyrpdf/main.dart';
import 'package:fyrpdf/models/pdf_models.dart';
import 'package:fyrpdf/services/pdf_storage_service.dart';
import 'package:fyrpdf/state/pdf_app_controller.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('fyrpdf_test_');
    FyrTheme.themeModeNotifier.value = ThemeMode.dark;
    FyrTheme.accentColorNotifier.value = Colors.purpleAccent;
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('PdfStorageService', () {
    test('persists recent files, deduplicates, caps at 10, and filters missing files',
        () async {
      final storage = PdfStorageService(configDirOverride: tempDir.path);

      // Create 12 dummy PDF files
      final paths = <String>[];
      for (var i = 1; i <= 12; i++) {
        final f = File(p.join(tempDir.path, 'doc_$i.pdf'))..writeAsStringSync('%PDF');
        paths.add(f.path);
        await storage.recordRecentFile(f.path, pageCount: i * 2);
      }

      // Capped at 10, most recent first
      var recent = await storage.loadRecentFiles();
      expect(recent.length, 10);
      expect(recent.first.fileName, 'doc_12.pdf');
      expect(recent.first.pageCount, 24);
      expect(recent.last.fileName, 'doc_3.pdf');

      // Re-opening an older file bumps it to top without duplicating
      await storage.recordRecentFile(paths[4]); // doc_5.pdf
      recent = await storage.loadRecentFiles();
      expect(recent.length, 10);
      expect(recent.first.fileName, 'doc_5.pdf');
      expect(recent.where((e) => e.fileName == 'doc_5.pdf').length, 1);

      // Deleting a file on disk prunes it on load when checkExists is true
      File(paths[4]).deleteSync();
      recent = await storage.loadRecentFiles(checkExists: true);
      expect(recent.any((e) => e.fileName == 'doc_5.pdf'), isFalse);

      // Clear history empties persisted list
      await storage.clearRecentFiles();
      expect(await storage.loadRecentFiles(), isEmpty);
    });

    test('persists per-PDF bookmarks sorted by page number', () async {
      final storage = PdfStorageService(configDirOverride: tempDir.path);
      final docPath = p.join(tempDir.path, 'handbook.pdf');

      await storage.saveAllBookmarks({
        docPath: [
          PdfBookmarkEntry(
            pageNumber: 15,
            label: 'Appendix',
            createdAt: DateTime(2026, 1, 2),
          ),
          PdfBookmarkEntry(
            pageNumber: 3,
            label: 'Intro',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      });

      final loaded = await storage.loadAllBookmarks();
      expect(loaded[docPath], isNotNull);
      expect(loaded[docPath]!.map((b) => b.pageNumber).toList(), [3, 15]);
      expect(loaded[docPath]!.first.label, 'Intro');
    });
  });

  group('PdfAppController', () {
    test('manages sidebar, dark reading mode, bookmarks, and recent files',
        () async {
      final storage = PdfStorageService(configDirOverride: tempDir.path);
      final samplePdf = File(p.join(tempDir.path, 'manual.pdf'))
        ..writeAsStringSync('%PDF-1.7');
      await storage.recordRecentFile(samplePdf.path, pageCount: 12);

      final ctrl = PdfAppController(storage: storage);
      await ctrl.initialize();

      expect(ctrl.hasOpenDocument, isFalse);
      expect(ctrl.recentFiles.length, 1);
      expect(ctrl.recentFiles.first.fileName, 'manual.pdf');

      // Sidebar controls
      expect(ctrl.sidebarVisible, isTrue);
      ctrl.toggleSidebar();
      expect(ctrl.sidebarVisible, isFalse);
      ctrl.setSidebarTab(SidebarTab.outline);
      expect(ctrl.sidebarVisible, isTrue);
      expect(ctrl.sidebarTab, SidebarTab.outline);

      // Dark reading mode toggle
      expect(ctrl.darkReadingMode, isFalse);
      ctrl.toggleDarkReadingMode();
      expect(ctrl.darkReadingMode, isTrue);

      // Bookmarks persistence through controller
      await ctrl.addBookmark(samplePdf.path, 7, label: 'Chapter 2');
      await ctrl.addBookmark(samplePdf.path, 2, label: 'Summary');
      expect(
        ctrl.bookmarksForFile(samplePdf.path).map((b) => b.pageNumber).toList(),
        [2, 7],
      );
      await ctrl.removeBookmark(samplePdf.path, 2);
      expect(
        ctrl.bookmarksForFile(samplePdf.path).map((b) => b.pageNumber).toList(),
        [7],
      );

      ctrl.dispose();
    });
  });

  group('FyrPdfApp Widget Tests', () {
    testWidgets('renders welcome screen, recent files, and clears history',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 820);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final storage = PdfStorageService(configDirOverride: tempDir.path);
      final samplePdf = File(p.join(tempDir.path, 'quarterly_report.pdf'))
        ..writeAsStringSync('%PDF-1.7');
      final ctrl = PdfAppController(storage: storage);
      await tester.runAsync(() async {
        await storage.recordRecentFile(samplePdf.path, pageCount: 18);
        await ctrl.initialize();
      });
      addTearDown(ctrl.dispose);

      await tester.pumpWidget(FyrPdfApp(controller: ctrl));
      await tester.pump();

      // Welcome branding, Open PDF CTA, and drag-and-drop hint
      expect(find.text('fyrPDF'), findsWidgets);
      expect(find.text('Open PDF'), findsWidgets);
      expect(
        find.textContaining('Drag and drop any .pdf file'),
        findsOneWidget,
      );

      // Recent file entry displayed with page count
      expect(find.text('Recent Files'), findsOneWidget);
      expect(find.text('quarterly_report.pdf'), findsOneWidget);
      expect(find.text('18 pp'), findsOneWidget);

      // Clear History removes recent files section
      await tester.tap(find.text('Clear History'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();

      expect(find.text('quarterly_report.pdf'), findsNothing);
      expect(ctrl.recentFiles, isEmpty);

      // Flush the transient status toast timer before test teardown
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
