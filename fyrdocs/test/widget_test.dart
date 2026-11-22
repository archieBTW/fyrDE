import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:fyrdocs/engine/doc_io.dart';
import 'package:fyrdocs/main.dart';
import 'package:fyrdocs/models/doc_models.dart';
import 'package:fyrdocs/state/docs_controller.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('fyrDocs OpenDocument (.odt) & Word (.docx) Engine', () {
    test('round-trips .odt archive preserving headings, paragraphs, lists, and tables', () {
      final original = DocsController.buildArchitectureRfcTemplate();
      final bytes = DocIO.encodeOdtBytes(original);
      expect(bytes.isNotEmpty, isTrue);

      final decoded = DocIO.decodeOdtBytes(bytes);
      expect(decoded.title, original.title);
      expect(decoded.blocks.length, original.blocks.length);

      expect(decoded.blocks.first.type, DocBlockType.title);
      expect(decoded.blocks.first.text,
          'fyrDE Desktop & fyrOffice Suite Architecture');

      final tableBlock =
          decoded.blocks.firstWhere((b) => b.type == DocBlockType.table);
      expect(tableBlock.tableRows.length, 4);
      expect(tableBlock.tableRows[1][0], 'fyrDocs');
      expect(tableBlock.tableRows[1][2], '.odt, .docx, .md');

      final listBlock =
          decoded.blocks.firstWhere((b) => b.type == DocBlockType.bulletList);
      expect(listBlock.listItems.length, 4);
    });

    test('round-trips .docx archive preserving headings, formatting, lists, and tables', () {
      final original = DocsController.buildArchitectureRfcTemplate();
      original.blocks[3].bold = true;
      original.blocks[3].italic = true;
      original.blocks[3].underline = true;

      final bytes = DocIO.encodeDocxBytes(original);
      expect(bytes.isNotEmpty, isTrue);

      final decoded = DocIO.decodeDocxBytes(bytes);
      expect(decoded.title, original.title);
      expect(decoded.blocks.length, original.blocks.length);
      expect(decoded.blocks[3].bold, isTrue);
      expect(decoded.blocks[3].italic, isTrue);
      expect(decoded.blocks[3].underline, isTrue);

      final tableBlock =
          decoded.blocks.firstWhere((b) => b.type == DocBlockType.table);
      expect(tableBlock.tableRows.length, 4);
      expect(tableBlock.tableRows[2][0], 'fyrSheets');
    });

    test('exports valid PDF 1.4, Markdown, HTML, and saves/loads via file dispatcher', () async {
      final doc = DocsController.buildArchitectureRfcTemplate();
      final pdfBytes = DocIO.encodePdfBytes(doc);
      final pdfHeader = ascii.decode(pdfBytes.sublist(0, 8));
      expect(pdfHeader, '%PDF-1.4');

      final md = DocIO.toMarkdown(doc);
      expect(md, contains('# fyrDE Desktop & fyrOffice Suite Architecture'));
      final parsedMd = DocIO.fromMarkdown(md, title: 'MD_Doc');
      expect(parsedMd.blocks.isNotEmpty, isTrue);

      final html = DocIO.toHtml(doc);
      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('<table>'));

      final tmp = await Directory.systemTemp.createTemp('fyrdocs_test_');
      try {
        final odtPath = '${tmp.path}/sample.odt';
        await DocIO.saveToFile(doc, odtPath);
        final loadedOdt = await DocIO.loadFromFile(odtPath);
        expect(loadedOdt.blocks.length, doc.blocks.length);

        final docxPath = '${tmp.path}/sample.docx';
        await DocIO.saveToFile(doc, docxPath);
        final loadedDocx = await DocIO.loadFromFile(docxPath);
        expect(loadedDocx.blocks.length, doc.blocks.length);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('DocsController starts with a clean blank document and supports editing, find/replace, and undo/redo', () {
      final ctrl = DocsController();
      expect(ctrl.document.title, 'Untitled Document');
      expect(ctrl.document.format, 'odt');
      expect(ctrl.document.blocks.length, 1);
      expect(ctrl.document.blocks.first.type, DocBlockType.paragraph);
      expect(ctrl.document.blocks.first.text, isEmpty);
      expect(ctrl.document.comments, isEmpty);
      expect(ctrl.document.wordCount, 0);

      final initialCount = ctrl.document.blocks.length;

      final added = ctrl.addBlock(
        type: DocBlockType.paragraph,
        text: 'Custom paragraph with Wayland protocol notes and Wayland tips.',
      );
      expect(ctrl.document.blocks.length, initialCount + 1);

      ctrl.selectBlock(added.id);
      ctrl.toggleBold();
      expect(ctrl.selectedBlock?.bold, isTrue);

      final replaced = ctrl.replaceAll('Wayland', 'SwayFX Wayland');
      expect(replaced, 2);

      ctrl.undo();
      ctrl.undo();
      ctrl.undo();
      expect(ctrl.document.blocks.length, initialCount);

      ctrl.redo();
      expect(ctrl.document.blocks.length, initialCount + 1);

      ctrl.newDocument();
      expect(ctrl.document.title, 'Untitled Document');
      expect(ctrl.document.blocks.length, 1);
      expect(ctrl.document.blocks.first.text, isEmpty);
      ctrl.dispose();
    });
  });

  group('fyrDocs UI Smoke Test', () {
    testWidgets('renders TopBar, FormattingRibbon, LeftPanel, DocumentCanvas, and RightInspector',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 880);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final ctrl = DocsController();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: ctrl,
          child: const FyrDocsApp(),
        ),
      );
      await tester.pump();

      expect(find.text('fyrDocs'), findsOneWidget);
      expect(find.text('fyrOffice'), findsOneWidget);
      expect(find.text('Untitled Document.odt'), findsOneWidget);
      expect(find.text('0 words'), findsOneWidget);
      expect(find.text('fyrDE_Architecture_RFC.odt'), findsNothing);
      expect(find.text('Outline'), findsOneWidget);
      expect(find.text('Templates'), findsOneWidget);
      expect(find.text('Export PDF'), findsOneWidget);
      expect(find.text('Inspector'), findsOneWidget);
      expect(find.text('DOCUMENT METRICS'), findsOneWidget);
      ctrl.dispose();
    });
  });
}
