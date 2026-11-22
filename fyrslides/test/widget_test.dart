import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:fyrslides/engine/slides_io.dart';
import 'package:fyrslides/main.dart';
import 'package:fyrslides/models/slide_models.dart';
import 'package:fyrslides/state/slides_controller.dart';

PresentationDeck _buildRoundTripTestDeck() {
  final theme = kDeckThemePresets.first;
  return PresentationDeck(
    id: 'test_deck_01',
    title: 'Test_Deck',
    author: 'Test Author',
    format: 'odp',
    aspectRatio: '16:9',
    theme: theme,
    slides: const [
      SlidePage(
        id: 'slide_1',
        title: 'Intro Slide',
        layout: SlideLayoutType.titleSlide,
        transition: SlideTransitionType.fade,
        speakerNotes: 'Opening speaker notes.',
        elements: [
          SlideElement(
            id: 's1_title',
            type: SlideElementType.text,
            x: 110,
            y: 205,
            width: 1360,
            height: 230,
            text: 'Deck Headline',
            subtitle: 'Deck Subtitle',
            fontSize: 64,
            bold: true,
          ),
        ],
      ),
      SlidePage(
        id: 'slide_2',
        title: 'Chart & Metrics',
        layout: SlideLayoutType.twoColumn,
        transition: SlideTransitionType.slideLeft,
        speakerNotes: 'Chart speaker notes.',
        elements: [
          SlideElement(
            id: 's2_metric',
            type: SlideElementType.metricCard,
            x: 100,
            y: 215,
            width: 440,
            height: 215,
            text: '100% ODF',
            subtitle: 'Standards Compliant',
            fontSize: 42,
            bold: true,
          ),
          SlideElement(
            id: 's2_chart',
            type: SlideElementType.chartCard,
            x: 830,
            y: 220,
            width: 670,
            height: 560,
            text: 'Sample Chart',
            subtitle: 'Test series',
            chartValues: [10, 20, 30, 40],
            chartLabels: ['Q1', 'Q2', 'Q3', 'Q4'],
            fontSize: 22,
            bold: true,
          ),
        ],
      ),
    ],
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('fyrSlides OpenDocument (.odp), PowerPoint (.pptx) & HTML5 Engine', () {
    test('round-trips .odp presentation preserving slides, elements, coordinates, and speaker notes', () {
      final original = _buildRoundTripTestDeck();
      final bytes = SlidesIO.encodeOdpBytes(original);
      expect(bytes.isNotEmpty, isTrue);

      final decoded = SlidesIO.decodeOdpBytes(bytes);
      expect(decoded.title, original.title);
      expect(decoded.slides.length, original.slides.length);

      expect(decoded.slides.first.title, 'Intro Slide');
      expect(decoded.slides.first.elements.length,
          original.slides.first.elements.length);
      expect(decoded.slides.first.speakerNotes,
          contains('Opening speaker notes.'));

      final secondSlide = decoded.slides[1];
      final chartEl = secondSlide.elements
          .firstWhere((e) => e.type == SlideElementType.chartCard);
      expect(chartEl.chartValues, [10.0, 20.0, 30.0, 40.0]);
      expect(chartEl.chartLabels, ['Q1', 'Q2', 'Q3', 'Q4']);
      expect(chartEl.x, closeTo(830.0, 0.5));
      expect(chartEl.y, closeTo(220.0, 0.5));
    });

    test('round-trips .pptx presentation preserving slides, shapes, coordinates, and speaker notes', () {
      final original = _buildRoundTripTestDeck();
      final bytes = SlidesIO.encodePptxBytes(original);
      expect(bytes.isNotEmpty, isTrue);

      final decoded = SlidesIO.decodePptxBytes(bytes);
      expect(decoded.title, original.title);
      expect(decoded.slides.length, original.slides.length);

      expect(decoded.slides[1].title, 'Chart & Metrics');
      expect(decoded.slides[1].elements.length,
          original.slides[1].elements.length);
      expect(decoded.slides[1].speakerNotes, contains('Chart speaker notes.'));

      final firstMetric = decoded.slides[1].elements[0];
      expect(firstMetric.type, SlideElementType.metricCard);
      expect(firstMetric.text, '100% ODF');
      expect(firstMetric.x, closeTo(100.0, 0.5));
      expect(firstMetric.width, closeTo(440.0, 0.5));
    });

    test('exports standalone HTML5 deck and saves/loads .odp and .pptx on disk', () async {
      final deck = _buildRoundTripTestDeck();
      final html = SlidesIO.toHtmlDeck(deck);
      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('Deck Headline'));

      final tmp = await Directory.systemTemp.createTemp('fyrslides_test_');
      try {
        final odpPath = '${tmp.path}/sample.odp';
        await SlidesIO.saveOdp(deck, odpPath);
        final loadedOdp = await SlidesIO.loadOdp(odpPath);
        expect(loadedOdp.slides.length, 2);

        final pptxPath = '${tmp.path}/sample.pptx';
        await SlidesIO.savePptx(deck, pptxPath);
        final loadedPptx = await SlidesIO.loadPptx(pptxPath);
        expect(loadedPptx.slides.length, 2);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('SlidesController starts with a clean blank slide and supports editing, theme switching, and undo/redo', () {
      final ctrl = SlidesController();
      expect(ctrl.deck.title, 'Untitled Presentation');
      expect(ctrl.deck.format, 'odp');
      expect(ctrl.slides.length, 1);
      expect(ctrl.activeSlide.elements, isEmpty);
      expect(ctrl.activeSlide.speakerNotes, isEmpty);

      ctrl.addSlide(SlideLayoutType.metricsCallout);
      expect(ctrl.slides.length, 2);

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

      ctrl.newDeck();
      expect(ctrl.slides.length, 1);
      expect(ctrl.activeSlide.elements, isEmpty);
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
      expect(find.text('Untitled Presentation.odp'), findsOneWidget);
      expect(find.text('Present'), findsOneWidget);
      expect(find.text('Add Slide'), findsOneWidget);
      expect(find.text('SLIDES (1)'), findsOneWidget);
      expect(find.text('Speaker Notes'), findsOneWidget);
      expect(find.text('fyrDE_2026_Keynote.odp'), findsNothing);
      ctrl.dispose();
    });
  });
}
