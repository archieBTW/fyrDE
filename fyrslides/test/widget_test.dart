import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:fyrslides/engine/slides_io.dart';
import 'package:fyrslides/main.dart';
import 'package:fyrslides/models/slide_models.dart';
import 'package:fyrslides/state/slides_controller.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('fyrSlides OpenDocument (.odp), PowerPoint (.pptx) & HTML5 Engine', () {
    test('round-trips .odp presentation preserving slides, elements, coordinates, and speaker notes', () {
      final original = SlidesController.buildDefaultKeynoteDeck();
      final bytes = SlidesIO.encodeOdpBytes(original);
      expect(bytes.isNotEmpty, isTrue);

      final decoded = SlidesIO.decodeOdpBytes(bytes);
      expect(decoded.title, original.title);
      expect(decoded.slides.length, original.slides.length);

      expect(decoded.slides.first.title, 'fyrDE 2026: Frick Your RAM');
      expect(decoded.slides.first.elements.length,
          original.slides.first.elements.length);
      expect(decoded.slides.first.speakerNotes,
          contains('fyrDE 2026 Architecture Keynote'));

      final secondSlide = decoded.slides[1];
      final chartEl = secondSlide.elements
          .firstWhere((e) => e.type == SlideElementType.chartCard);
      expect(chartEl.chartValues, [410.0, 920.0, 1180.0, 1740.0]);
      expect(chartEl.chartLabels, ['fyrDE', 'KDE 6', 'GNOME 47', 'Win 11']);
      expect(chartEl.x, closeTo(830.0, 0.5));
      expect(chartEl.y, closeTo(220.0, 0.5));
    });

    test('round-trips .pptx presentation preserving slides, shapes, coordinates, and speaker notes', () {
      final original = SlidesController.buildDefaultKeynoteDeck();
      final bytes = SlidesIO.encodePptxBytes(original);
      expect(bytes.isNotEmpty, isTrue);

      final decoded = SlidesIO.decodePptxBytes(bytes);
      expect(decoded.title, original.title);
      expect(decoded.slides.length, original.slides.length);

      expect(decoded.slides[2].title, 'fyrOffice Native OpenDocument Engine');
      expect(decoded.slides[2].elements.length,
          original.slides[2].elements.length);
      expect(decoded.slides[2].speakerNotes,
          contains('fyrDocs, fyrSheets, and fyrSlides'));

      final firstMetric = decoded.slides[2].elements[1];
      expect(firstMetric.type, SlideElementType.metricCard);
      expect(firstMetric.text, '100% ODF/OOXML');
      expect(firstMetric.x, closeTo(100.0, 0.5));
      expect(firstMetric.width, closeTo(440.0, 0.5));
    });

    test('exports standalone HTML5 deck and saves/loads .odp and .pptx on disk', () async {
      final deck = SlidesController.buildDefaultKeynoteDeck();
      final html = SlidesIO.toHtmlDeck(deck);
      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('fyrDE: Frick Your RAM'));

      final tmp = await Directory.systemTemp.createTemp('fyrslides_test_');
      try {
        final odpPath = '${tmp.path}/keynote.odp';
        await SlidesIO.saveOdp(deck, odpPath);
        final loadedOdp = await SlidesIO.loadOdp(odpPath);
        expect(loadedOdp.slides.length, 5);

        final pptxPath = '${tmp.path}/keynote.pptx';
        await SlidesIO.savePptx(deck, pptxPath);
        final loadedPptx = await SlidesIO.loadPptx(pptxPath);
        expect(loadedPptx.slides.length, 5);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('SlidesController supports slide creation, element editing, theme switching, and undo/redo', () {
      final ctrl = SlidesController();
      expect(ctrl.slides.length, 5);

      ctrl.addSlide(SlideLayoutType.metricsCallout);
      expect(ctrl.slides.length, 6);

      final initialElems = ctrl.activeSlide.elements.length;
      ctrl.addElement(SlideElementType.codeBlock);
      expect(ctrl.activeSlide.elements.length, initialElems + 1);

      ctrl.applyThemePreset(kDeckThemePresets[1]); // Midnight Neon
      expect(ctrl.deck.theme.id, 'midnight_neon');

      ctrl.undo(); // Undo theme
      expect(ctrl.deck.theme.id, 'fyr_cyber_purple');

      ctrl.undo(); // Undo addElement
      expect(ctrl.activeSlide.elements.length, initialElems);

      ctrl.redo(); // Redo addElement
      expect(ctrl.activeSlide.elements.length, initialElems + 1);
      ctrl.dispose();
    });
  });

  group('fyrSlides UI Smoke Test', () {
    testWidgets('renders TopBar, ElementToolbar, SlideFilmstrip, SlideCanvas, and SlideInspector',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1440, 880);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final ctrl = SlidesController();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: ctrl,
          child: const FyrSlidesApp(),
        ),
      );
      await tester.pump();

      expect(find.text('fyrSlides'), findsOneWidget);
      expect(find.text('fyrOffice'), findsOneWidget);
      expect(find.text('Present'), findsOneWidget);
      expect(find.text('Add Slide'), findsOneWidget);
      expect(find.text('SLIDES (5)'), findsOneWidget);
      expect(find.text('Speaker Notes'), findsOneWidget);
      ctrl.dispose();
    });
  });
}
