import 'dart:async';
import 'package:flutter/foundation.dart';
import '../engine/slides_io.dart';
import '../models/slide_models.dart';

class SlidesController extends ChangeNotifier {
  PresentationDeck _deck;
  int _activeSlideIndex = 0;
  String? _selectedElementId;
  bool _isPresenting = false;
  bool _isGridView = false;
  bool _showSpeakerNotes = true;
  bool _showCanvasGrid = true;
  double _zoom = 1.0; // 0.4 .. 1.5
  String? _statusMessage;

  // Presenter timer
  Timer? _presenterTimer;
  int _presenterElapsedSeconds = 0;

  // Undo / Redo history
  final List<PresentationDeck> _undoStack = [];
  final List<PresentationDeck> _redoStack = [];
  static const int _maxHistory = 40;

  SlidesController({PresentationDeck? initialDeck})
      : _deck = initialDeck ?? buildBlankDeck() {
    if (_deck.slides.isNotEmpty && _deck.slides.first.elements.isNotEmpty) {
      _selectedElementId = _deck.slides.first.elements.first.id;
    }
  }

  PresentationDeck get deck => _deck;
  List<SlidePage> get slides => _deck.slides;
  int get activeSlideIndex =>
      _activeSlideIndex.clamp(0, _deck.slides.isEmpty ? 0 : _deck.slides.length - 1);
  SlidePage get activeSlide => _deck.slides[activeSlideIndex];
  String? get selectedElementId => _selectedElementId;
  bool get isPresenting => _isPresenting;
  bool get isGridView => _isGridView;
  bool get showSpeakerNotes => _showSpeakerNotes;
  bool get showCanvasGrid => _showCanvasGrid;
  double get zoom => _zoom;
  String? get statusMessage => _statusMessage;
  int get presenterElapsedSeconds => _presenterElapsedSeconds;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  SlideElement? get selectedElement {
    if (_selectedElementId == null) return null;
    for (final el in activeSlide.elements) {
      if (el.id == _selectedElementId) return el;
    }
    return null;
  }

  String get formattedPresenterTimer {
    final mins = (_presenterElapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_presenterElapsedSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  void _pushUndo() {
    _undoStack.add(_deck.copyWith());
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void recordSnapshot() {
    _pushUndo();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_deck.copyWith());
    _deck = _undoStack.removeLast();
    _activeSlideIndex =
        _activeSlideIndex.clamp(0, _deck.slides.isEmpty ? 0 : _deck.slides.length - 1);
    _statusMessage = 'Undid last action';
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_deck.copyWith());
    _deck = _redoStack.removeLast();
    _activeSlideIndex =
        _activeSlideIndex.clamp(0, _deck.slides.isEmpty ? 0 : _deck.slides.length - 1);
    _statusMessage = 'Redid action';
    notifyListeners();
  }

  void setZoom(double value) {
    _zoom = value.clamp(0.4, 1.5);
    notifyListeners();
  }

  void toggleGridView() {
    _isGridView = !_isGridView;
    notifyListeners();
  }

  void toggleSpeakerNotes() {
    _showSpeakerNotes = !_showSpeakerNotes;
    notifyListeners();
  }

  void toggleCanvasGrid() {
    _showCanvasGrid = !_showCanvasGrid;
    notifyListeners();
  }

  void selectSlide(int index) {
    if (index < 0 || index >= _deck.slides.length) return;
    _activeSlideIndex = index;
    final elems = activeSlide.elements;
    _selectedElementId = elems.isNotEmpty ? elems.first.id : null;
    notifyListeners();
  }

  void selectElement(String? elementId) {
    _selectedElementId = elementId;
    notifyListeners();
  }

  void nextSlide() {
    if (_activeSlideIndex < _deck.slides.length - 1) {
      selectSlide(_activeSlideIndex + 1);
    }
  }

  void prevSlide() {
    if (_activeSlideIndex > 0) {
      selectSlide(_activeSlideIndex - 1);
    }
  }

  void startPresentation({bool fromBeginning = false}) {
    if (fromBeginning) {
      _activeSlideIndex = 0;
    }
    _isPresenting = true;
    _presenterElapsedSeconds = 0;
    _presenterTimer?.cancel();
    _presenterTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _presenterElapsedSeconds++;
      notifyListeners();
    });
    _statusMessage = 'Presenting slide ${activeSlideIndex + 1} of ${_deck.slides.length}';
    notifyListeners();
  }

  void stopPresentation() {
    _isPresenting = false;
    _presenterTimer?.cancel();
    _presenterTimer = null;
    _statusMessage = null;
    notifyListeners();
  }

  void setAspectRatio(String ratio) {
    _pushUndo();
    _deck = _deck.copyWith(aspectRatio: ratio);
    _statusMessage = 'Aspect ratio set to $ratio';
    notifyListeners();
  }

  void renameDeck(String title) {
    if (title.trim().isEmpty) return;
    _pushUndo();
    _deck = _deck.copyWith(title: title.trim());
    notifyListeners();
  }

  void applyThemePreset(DeckThemePreset preset) {
    _pushUndo();
    final updatedSlides = _deck.slides.map((s) {
      final updatedElems = s.elements.map((el) {
        return el.copyWith(
          textColorHex: preset.textHex,
          fillColorHex: preset.cardBgHex,
          borderColorHex: preset.accentHex,
        );
      }).toList();
      return s.copyWith(elements: updatedElems);
    }).toList();

    _deck = _deck.copyWith(theme: preset, slides: updatedSlides);
    _statusMessage = 'Applied theme "${preset.name}"';
    notifyListeners();
  }

  void addSlide([SlideLayoutType layout = SlideLayoutType.titleAndContent]) {
    _pushUndo();
    final newIdx = _deck.slides.length + 1;
    final theme = _deck.theme;
    final newSlide = _createSlideFromLayout(
      id: 'slide_${DateTime.now().microsecondsSinceEpoch}',
      index: newIdx,
      layout: layout,
      theme: theme,
    );

    final updated = List<SlidePage>.from(_deck.slides);
    final insertAt = (_activeSlideIndex + 1).clamp(0, updated.length);
    updated.insert(insertAt, newSlide);
    _deck = _deck.copyWith(slides: updated);
    _activeSlideIndex = insertAt;
    _selectedElementId =
        newSlide.elements.isNotEmpty ? newSlide.elements.first.id : null;
    _statusMessage = 'Added ${layout.label} slide';
    notifyListeners();
  }

  void duplicateSlide([int? index]) {
    final targetIdx = index ?? activeSlideIndex;
    if (targetIdx < 0 || targetIdx >= _deck.slides.length) return;
    _pushUndo();
    final orig = _deck.slides[targetIdx];
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final copy = orig.copyWith(
      id: 'slide_$stamp',
      title: '${orig.title} (Copy)',
      elements: orig.elements
          .asMap()
          .entries
          .map((e) => e.value.copyWith(id: 'el_${stamp}_${e.key}'))
          .toList(),
    );
    final updated = List<SlidePage>.from(_deck.slides);
    updated.insert(targetIdx + 1, copy);
    _deck = _deck.copyWith(slides: updated);
    _activeSlideIndex = targetIdx + 1;
    _statusMessage = 'Duplicated slide ${targetIdx + 1}';
    notifyListeners();
  }

  void deleteSlide([int? index]) {
    if (_deck.slides.length <= 1) {
      _statusMessage = 'Deck must contain at least 1 slide';
      notifyListeners();
      return;
    }
    final targetIdx = index ?? activeSlideIndex;
    if (targetIdx < 0 || targetIdx >= _deck.slides.length) return;
    _pushUndo();
    final updated = List<SlidePage>.from(_deck.slides)..removeAt(targetIdx);
    _deck = _deck.copyWith(slides: updated);
    _activeSlideIndex = _activeSlideIndex.clamp(0, updated.length - 1);
    _selectedElementId =
        activeSlide.elements.isNotEmpty ? activeSlide.elements.first.id : null;
    _statusMessage = 'Deleted slide ${targetIdx + 1}';
    notifyListeners();
  }

  void moveSlideUp([int? index]) {
    final idx = index ?? activeSlideIndex;
    if (idx <= 0 || idx >= _deck.slides.length) return;
    _pushUndo();
    final updated = List<SlidePage>.from(_deck.slides);
    final item = updated.removeAt(idx);
    updated.insert(idx - 1, item);
    _deck = _deck.copyWith(slides: updated);
    _activeSlideIndex = idx - 1;
    notifyListeners();
  }

  void moveSlideDown([int? index]) {
    final idx = index ?? activeSlideIndex;
    if (idx < 0 || idx >= _deck.slides.length - 1) return;
    _pushUndo();
    final updated = List<SlidePage>.from(_deck.slides);
    final item = updated.removeAt(idx);
    updated.insert(idx + 1, item);
    _deck = _deck.copyWith(slides: updated);
    _activeSlideIndex = idx + 1;
    notifyListeners();
  }

  void applySlideLayout(SlideLayoutType layout) {
    _pushUndo();
    final slide = activeSlide;
    final updatedSlide = slide.copyWith(layout: layout);
    _replaceActiveSlide(updatedSlide);
    _statusMessage = 'Slide layout changed to ${layout.label}';
    notifyListeners();
  }

  void updateSlideTitle(String title) {
    final slide = activeSlide;
    _replaceActiveSlide(slide.copyWith(title: title));
    notifyListeners();
  }

  void updateSlideTransition(SlideTransitionType transition, {int? durationMs}) {
    _pushUndo();
    final slide = activeSlide;
    _replaceActiveSlide(
      slide.copyWith(
        transition: transition,
        transitionDurationMs: durationMs ?? slide.transitionDurationMs,
      ),
    );
    _statusMessage = 'Transition set to ${transition.label}';
    notifyListeners();
  }

  void updateSpeakerNotes(String notes) {
    final slide = activeSlide;
    _replaceActiveSlide(slide.copyWith(speakerNotes: notes));
    notifyListeners();
  }

  void addElement(SlideElementType type) {
    _pushUndo();
    final theme = _deck.theme;
    final id = 'el_${DateTime.now().microsecondsSinceEpoch}';
    late final SlideElement newEl;

    switch (type) {
      case SlideElementType.text:
        newEl = SlideElement(
          id: id,
          type: SlideElementType.text,
          x: 160,
          y: 220,
          width: 680,
          height: 130,
          text: 'Click to edit headline or body copy',
          subtitle: 'Supporting architectural context',
          fontSize: 32,
          bold: true,
          textColorHex: theme.textHex,
          fillColorHex: theme.cardBgHex,
          borderColorHex: theme.accentHex,
        );
        break;
      case SlideElementType.bulletList:
        newEl = SlideElement(
          id: id,
          type: SlideElementType.bulletList,
          x: 140,
          y: 240,
          width: 660,
          height: 360,
          text: 'Key Engineering Takeaways',
          bulletItems: const [
            'Zero-copy Wayland surface compositing via SwayFX',
            'Shared FyrTheme live reactive accent & glass tokens',
            'Native ODF (.odp) and OpenXML (.pptx) round-trip engine',
          ],
          fontSize: 24,
          textColorHex: theme.textHex,
          fillColorHex: theme.cardBgHex,
          borderColorHex: theme.accentHex,
        );
        break;
      case SlideElementType.shape:
        newEl = SlideElement(
          id: id,
          type: SlideElementType.shape,
          x: 520,
          y: 300,
          width: 360,
          height: 180,
          text: 'Wayland IPC Bridge',
          fontSize: 24,
          bold: true,
          align: 'center',
          shapeKind: ShapeKind.roundedRect,
          textColorHex: theme.textHex,
          fillColorHex: theme.cardBgHex,
          borderColorHex: theme.accentHex,
        );
        break;
      case SlideElementType.metricCard:
        newEl = SlideElement(
          id: id,
          type: SlideElementType.metricCard,
          x: 180,
          y: 260,
          width: 400,
          height: 210,
          text: '99.4%',
          subtitle: 'Frame Pacing Stability @ 144Hz',
          fontSize: 54,
          bold: true,
          textColorHex: theme.textHex,
          fillColorHex: theme.cardBgHex,
          borderColorHex: theme.accentHex,
        );
        break;
      case SlideElementType.codeBlock:
        newEl = SlideElement(
          id: id,
          type: SlideElementType.codeBlock,
          x: 160,
          y: 250,
          width: 760,
          height: 360,
          text: 'final deck = await SlidesIO.loadOdp("keynote.odp");\n'
              'await SlidesIO.savePptx(deck, "keynote_export.pptx");\n'
              'print("Exported \${deck.slides.length} slides!");',
          codeLanguage: 'dart',
          fontSize: 21,
          textColorHex: theme.textHex,
          fillColorHex: '#090612',
          borderColorHex: theme.secondaryAccentHex,
        );
        break;
      case SlideElementType.chartCard:
        newEl = SlideElement(
          id: id,
          type: SlideElementType.chartCard,
          x: 820,
          y: 240,
          width: 640,
          height: 420,
          text: 'Memory Footprint Comparison (MB)',
          subtitle: 'Lower is better • Cold start desktop session',
          chartValues: const [410, 890, 1420, 1950],
          chartLabels: const ['fyrDE', 'GNOME', 'KDE', 'Electron'],
          fontSize: 22,
          bold: true,
          textColorHex: theme.textHex,
          fillColorHex: theme.cardBgHex,
          borderColorHex: theme.accentHex,
        );
        break;
      case SlideElementType.badge:
        newEl = SlideElement(
          id: id,
          type: SlideElementType.badge,
          x: 120,
          y: 110,
          width: 310,
          height: 54,
          text: 'FYROFFICE SUITE • 2026',
          fontSize: 16,
          bold: true,
          align: 'center',
          textColorHex: theme.accentHex,
          fillColorHex: theme.cardBgHex,
          borderColorHex: theme.accentHex,
          borderRadius: 99,
        );
        break;
    }

    final elems = List<SlideElement>.from(activeSlide.elements)..add(newEl);
    _replaceActiveSlide(activeSlide.copyWith(elements: elems));
    _selectedElementId = newEl.id;
    _statusMessage = 'Inserted ${type.label}';
    notifyListeners();
  }

  void updateElementRect(
    String elementId, {
    double? x,
    double? y,
    double? width,
    double? height,
  }) {
    final elems = activeSlide.elements.map((el) {
      if (el.id != elementId) return el;
      final nx = (x ?? el.x).clamp(0.0, SlideElement.canvasWidth - 60.0);
      final ny = (y ?? el.y).clamp(0.0, SlideElement.canvasHeight - 40.0);
      final nw = (width ?? el.width).clamp(60.0, SlideElement.canvasWidth);
      final nh = (height ?? el.height).clamp(36.0, SlideElement.canvasHeight);
      return el.copyWith(x: nx, y: ny, width: nw, height: nh);
    }).toList();
    _replaceActiveSlide(activeSlide.copyWith(elements: elems));
    notifyListeners();
  }

  void updateElement(SlideElement updated, {bool recordUndo = false}) {
    if (recordUndo) _pushUndo();
    final elems = activeSlide.elements
        .map((el) => el.id == updated.id ? updated : el)
        .toList();
    _replaceActiveSlide(activeSlide.copyWith(elements: elems));
    notifyListeners();
  }

  void duplicateSelectedElement() {
    final sel = selectedElement;
    if (sel == null) return;
    _pushUndo();
    final copy = sel.copyWith(
      id: 'el_${DateTime.now().microsecondsSinceEpoch}',
      x: (sel.x + 36).clamp(0.0, SlideElement.canvasWidth - sel.width),
      y: (sel.y + 36).clamp(0.0, SlideElement.canvasHeight - sel.height),
    );
    final elems = List<SlideElement>.from(activeSlide.elements)..add(copy);
    _replaceActiveSlide(activeSlide.copyWith(elements: elems));
    _selectedElementId = copy.id;
    _statusMessage = 'Duplicated ${sel.type.label}';
    notifyListeners();
  }

  void deleteSelectedElement() {
    if (_selectedElementId == null) return;
    _pushUndo();
    final elems = activeSlide.elements
        .where((el) => el.id != _selectedElementId)
        .toList();
    _replaceActiveSlide(activeSlide.copyWith(elements: elems));
    _selectedElementId = elems.isNotEmpty ? elems.last.id : null;
    _statusMessage = 'Deleted element';
    notifyListeners();
  }

  void bringToFront([String? elementId]) {
    final targetId = elementId ?? _selectedElementId;
    if (targetId == null) return;
    _pushUndo();
    final elems = List<SlideElement>.from(activeSlide.elements);
    final idx = elems.indexWhere((e) => e.id == targetId);
    if (idx == -1 || idx == elems.length - 1) return;
    final item = elems.removeAt(idx);
    elems.add(item);
    _replaceActiveSlide(activeSlide.copyWith(elements: elems));
    notifyListeners();
  }

  void sendToBack([String? elementId]) {
    final targetId = elementId ?? _selectedElementId;
    if (targetId == null) return;
    _pushUndo();
    final elems = List<SlideElement>.from(activeSlide.elements);
    final idx = elems.indexWhere((e) => e.id == targetId);
    if (idx <= 0) return;
    final item = elems.removeAt(idx);
    elems.insert(0, item);
    _replaceActiveSlide(activeSlide.copyWith(elements: elems));
    notifyListeners();
  }

  void newDeck() {
    _pushUndo();
    _deck = buildBlankDeck();
    _activeSlideIndex = 0;
    _selectedElementId = _deck.slides.isNotEmpty &&
            _deck.slides.first.elements.isNotEmpty
        ? _deck.slides.first.elements.first.id
        : null;
    _statusMessage = 'Created new presentation deck';
    notifyListeners();
  }

  Future<void> openDeck(String path) async {
    try {
      final lower = path.toLowerCase();
      late final PresentationDeck loaded;
      if (lower.endsWith('.pptx')) {
        loaded = await SlidesIO.loadPptx(path);
      } else {
        loaded = await SlidesIO.loadOdp(path);
      }
      _pushUndo();
      _deck = loaded;
      _activeSlideIndex = 0;
      _selectedElementId = _deck.slides.isNotEmpty &&
              _deck.slides.first.elements.isNotEmpty
          ? _deck.slides.first.elements.first.id
          : null;
      _statusMessage = 'Opened ${path.split('/').last} (${_deck.slides.length} slides)';
      notifyListeners();
    } catch (e) {
      _statusMessage = 'Failed to open presentation: $e';
      notifyListeners();
    }
  }

  Future<void> saveDeck(String path) async {
    try {
      final lower = path.toLowerCase();
      if (lower.endsWith('.pptx')) {
        await SlidesIO.savePptx(_deck, path);
        _deck = _deck.copyWith(filePath: path, format: 'pptx');
        _statusMessage = 'Saved PowerPoint (.pptx) to ${path.split('/').last}';
      } else if (lower.endsWith('.html')) {
        await SlidesIO.exportHtml(_deck, path);
        _statusMessage = 'Exported HTML5 presentation to ${path.split('/').last}';
      } else {
        final outPath = lower.endsWith('.odp') ? path : '$path.odp';
        await SlidesIO.saveOdp(_deck, outPath);
        _deck = _deck.copyWith(filePath: outPath, format: 'odp');
        _statusMessage = 'Saved OpenDocument (.odp) to ${outPath.split('/').last}';
      }
      notifyListeners();
    } catch (e) {
      _statusMessage = 'Save error: $e';
      notifyListeners();
    }
  }

  void _replaceActiveSlide(SlidePage updatedSlide) {
    final updated = List<SlidePage>.from(_deck.slides);
    updated[activeSlideIndex] = updatedSlide;
    _deck = _deck.copyWith(slides: updated);
  }

  static SlidePage _createSlideFromLayout({
    required String id,
    required int index,
    required SlideLayoutType layout,
    required DeckThemePreset theme,
  }) {
    switch (layout) {
      case SlideLayoutType.blank:
        return SlidePage(
          id: id,
          title: 'Slide $index',
          layout: layout,
          transition: SlideTransitionType.none,
          elements: const [],
          speakerNotes: '',
        );
      case SlideLayoutType.titleSlide:
        return SlidePage(
          id: id,
          title: 'Slide $index — Title',
          layout: layout,
          elements: [
            SlideElement(
              id: '${id}_title',
              type: SlideElementType.text,
              x: 110,
              y: 260,
              width: 1380,
              height: 220,
              text: 'Click to add title',
              subtitle: 'Click to add subtitle',
              fontSize: 58,
              bold: true,
              textColorHex: theme.textHex,
              fillColorHex: theme.cardBgHex,
              borderColorHex: theme.accentHex,
            ),
          ],
          speakerNotes: '',
        );
      case SlideLayoutType.metricsCallout:
        return SlidePage(
          id: id,
          title: 'Slide $index — Key Metrics',
          layout: layout,
          elements: [
            SlideElement(
              id: '${id}_hdr',
              type: SlideElementType.text,
              x: 100,
              y: 80,
              width: 1400,
              height: 110,
              text: 'Performance & Telemetry Benchmarks',
              subtitle: 'Measured on Arch Linux + SwayFX Wayland session',
              fontSize: 42,
              bold: true,
              textColorHex: theme.textHex,
              fillColorHex: theme.cardBgHex,
              borderColorHex: theme.accentHex,
            ),
            SlideElement(
              id: '${id}_m1',
              type: SlideElementType.metricCard,
              x: 100,
              y: 240,
              width: 440,
              height: 230,
              text: '100% Native',
              subtitle: 'ODF (.odp) & OpenXML (.pptx)',
              fontSize: 48,
              bold: true,
              textColorHex: theme.textHex,
              fillColorHex: theme.cardBgHex,
              borderColorHex: theme.accentHex,
            ),
            SlideElement(
              id: '${id}_m2',
              type: SlideElementType.metricCard,
              x: 580,
              y: 240,
              width: 440,
              height: 230,
              text: '< 16ms',
              subtitle: '60/144Hz Flutter Impeller Frame Time',
              fontSize: 48,
              bold: true,
              textColorHex: theme.textHex,
              fillColorHex: theme.cardBgHex,
              borderColorHex: theme.secondaryAccentHex,
            ),
            SlideElement(
              id: '${id}_m3',
              type: SlideElementType.metricCard,
              x: 1060,
              y: 240,
              width: 440,
              height: 230,
              text: '0 Electron',
              subtitle: 'Pure AOT Compiled Dart Desktop',
              fontSize: 48,
              bold: true,
              textColorHex: theme.textHex,
              fillColorHex: theme.cardBgHex,
              borderColorHex: theme.accentHex,
            ),
          ],
          speakerNotes: 'Highlight the three main telemetry numbers.',
        );
      default:
        return SlidePage(
          id: id,
          title: 'Slide $index — ${layout.label}',
          layout: layout,
          elements: [
            SlideElement(
              id: '${id}_title',
              type: SlideElementType.text,
              x: 100,
              y: 80,
              width: 1400,
              height: 110,
              text: 'Slide $index Headline',
              subtitle: 'Key takeaway and architectural context',
              fontSize: 42,
              bold: true,
              textColorHex: theme.textHex,
              fillColorHex: theme.cardBgHex,
              borderColorHex: theme.accentHex,
            ),
            SlideElement(
              id: '${id}_bullets',
              type: SlideElementType.bulletList,
              x: 100,
              y: 230,
              width: 1380,
              height: 520,
              text: 'Core Highlights',
              bulletItems: const [
                'First talking point with crisp typography and clear hierarchy',
                'Second talking point explaining system integration and workflows',
                'Third talking point summarizing next steps and deliverables',
              ],
              fontSize: 26,
              textColorHex: theme.textHex,
              fillColorHex: theme.cardBgHex,
              borderColorHex: theme.accentHex,
            ),
          ],
          speakerNotes: 'Speaker notes for Slide $index.',
        );
    }
  }

  /// Clean 1-slide blank presentation (`Untitled Presentation.odp`).
  static PresentationDeck buildBlankDeck() {
    final theme = kDeckThemePresets.first;
    return PresentationDeck(
      id: 'deck_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Untitled Presentation',
      author: '',
      format: 'odp',
      aspectRatio: '16:9',
      theme: theme,
      slides: const [
        SlidePage(
          id: 'slide_1',
          title: 'Slide 1',
          layout: SlideLayoutType.blank,
          transition: SlideTransitionType.none,
          elements: [],
          speakerNotes: '',
        ),
      ],
    );
  }

  @override
  void dispose() {
    _presenterTimer?.cancel();
    super.dispose();
  }
}
