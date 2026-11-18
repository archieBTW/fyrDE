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
      : _deck = initialDeck ?? buildDefaultKeynoteDeck() {
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
    final theme = kDeckThemePresets.first;
    final firstSlide = _createSlideFromLayout(
      id: 'slide_1',
      index: 1,
      layout: SlideLayoutType.titleSlide,
      theme: theme,
    );
    _deck = PresentationDeck(
      id: 'deck_${DateTime.now().millisecondsSinceEpoch}',
      title: 'Untitled_Presentation',
      format: 'odp',
      theme: theme,
      slides: [firstSlide],
    );
    _activeSlideIndex = 0;
    _selectedElementId = firstSlide.elements.first.id;
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
      case SlideLayoutType.titleSlide:
        return SlidePage(
          id: id,
          title: 'Slide $index — Title',
          layout: layout,
          elements: [
            SlideElement(
              id: '${id}_badge',
              type: SlideElementType.badge,
              x: 110,
              y: 150,
              width: 310,
              height: 52,
              text: 'FYRDE PRESENTATION',
              fontSize: 16,
              bold: true,
              align: 'center',
              textColorHex: theme.accentHex,
              fillColorHex: theme.cardBgHex,
              borderColorHex: theme.accentHex,
              borderRadius: 99,
            ),
            SlideElement(
              id: '${id}_title',
              type: SlideElementType.text,
              x: 110,
              y: 230,
              width: 1280,
              height: 220,
              text: 'Presentation Title Goes Here',
              subtitle: 'Subtitle, presenter name, and architectural overview',
              fontSize: 58,
              bold: true,
              textColorHex: theme.textHex,
              fillColorHex: theme.cardBgHex,
              borderColorHex: theme.accentHex,
            ),
          ],
          speakerNotes: 'Introduce the core vision and agenda for this session.',
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

  /// Rich 5-slide default deck (`fyrDE_2026_Keynote.odp`).
  static PresentationDeck buildDefaultKeynoteDeck() {
    final theme = kDeckThemePresets.first; // Fyr Cyber Purple
    return PresentationDeck(
      id: 'fyrde_2026_keynote',
      title: 'fyrDE_2026_Keynote',
      author: 'FyrDE Core Team',
      format: 'odp',
      aspectRatio: '16:9',
      theme: theme,
      slides: [
        // Slide 1: Title Slide
        SlidePage(
          id: 'slide_1',
          title: 'fyrDE 2026: Frick Your RAM',
          layout: SlideLayoutType.titleSlide,
          transition: SlideTransitionType.fade,
          speakerNotes:
              'Welcome everyone to the fyrDE 2026 Architecture Keynote. Emphasize how our SwayFX + Flutter desktop suite eliminates Electron bloat while delivering 34 integrated apps.',
          elements: [
            const SlideElement(
              id: 's1_badge',
              type: SlideElementType.badge,
              x: 110,
              y: 120,
              width: 370,
              height: 52,
              text: 'FYRDE 2026 ARCHITECTURE KEYNOTE',
              fontSize: 15,
              bold: true,
              align: 'center',
              textColorHex: '#D040FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#D040FF',
              borderRadius: 99,
            ),
            const SlideElement(
              id: 's1_title',
              type: SlideElementType.text,
              x: 110,
              y: 205,
              width: 1360,
              height: 230,
              text: 'fyrDE: Frick Your RAM',
              subtitle:
                  'A Unified Wayland Desktop & 34-App Native Suite Built with SwayFX and Flutter Linux',
              fontSize: 64,
              bold: true,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#D040FF',
            ),
            const SlideElement(
              id: 's1_m1',
              type: SlideElementType.metricCard,
              x: 110,
              y: 510,
              width: 420,
              height: 230,
              text: '34 Apps',
              subtitle: 'Cohesive Native Desktop Ecosystem',
              fontSize: 50,
              bold: true,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#D040FF',
            ),
            const SlideElement(
              id: 's1_m2',
              type: SlideElementType.metricCard,
              x: 570,
              y: 510,
              width: 420,
              height: 230,
              text: '410 MB',
              subtitle: 'Cold-Boot Idle RAM Footprint',
              fontSize: 50,
              bold: true,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#00E5FF',
            ),
            const SlideElement(
              id: 's1_m3',
              type: SlideElementType.metricCard,
              x: 1030,
              y: 510,
              width: 440,
              height: 230,
              text: '100% ODF',
              subtitle: 'Native .odt, .ods, .odp & Office XML',
              fontSize: 50,
              bold: true,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#D040FF',
            ),
          ],
        ),

        // Slide 2: Compositor & Flutter Shell Architecture
        SlidePage(
          id: 'slide_2',
          title: 'Compositor & Flutter Shell Architecture',
          layout: SlideLayoutType.twoColumn,
          transition: SlideTransitionType.slideLeft,
          speakerNotes:
              'Walk through how SwayFX handles blurred Wayland layer-shell surfaces while fyr_core synchronizes accent colors and GTK3/GTK4 themes in under 2 milliseconds.',
          elements: [
            const SlideElement(
              id: 's2_hdr',
              type: SlideElementType.text,
              x: 100,
              y: 72,
              width: 1400,
              height: 110,
              text: 'Compositor & Flutter Shell Architecture',
              subtitle:
                  'Zero-latency IPC between SwayFX Wayland compositor and Flutter desktop surfaces',
              fontSize: 42,
              bold: true,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#D040FF',
            ),
            const SlideElement(
              id: 's2_left',
              type: SlideElementType.bulletList,
              x: 100,
              y: 220,
              width: 680,
              height: 560,
              text: 'SwayFX + Layer-Shell Pipeline',
              bulletItems: [
                'Real-time dual-Kawase background blur & rounded corners',
                'Atomic drop-in config reload via ~/.config/sway/conf.d/',
                'Live inotify theme synchronization across all 34 apps',
                'Damage-tracked surface rendering at 144Hz refresh rates',
              ],
              fontSize: 25,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#D040FF',
            ),
            const SlideElement(
              id: 's2_right',
              type: SlideElementType.chartCard,
              x: 830,
              y: 220,
              width: 670,
              height: 560,
              text: 'Desktop Cold-Boot RAM Usage (MB)',
              subtitle: 'Measured with taskbar, dock, notifications & file manager',
              chartValues: [410, 920, 1180, 1740],
              chartLabels: ['fyrDE', 'KDE 6', 'GNOME 47', 'Win 11'],
              fontSize: 22,
              bold: true,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#00E5FF',
            ),
          ],
        ),

        // Slide 3: fyrOffice Native OpenDocument Engine
        SlidePage(
          id: 'slide_3',
          title: 'fyrOffice Native OpenDocument Engine',
          layout: SlideLayoutType.metricsCallout,
          transition: SlideTransitionType.zoomIn,
          speakerNotes:
              'fyrDocs, fyrSheets, and fyrSlides read and write real OASIS OpenDocument (.odt, .ods, .odp) and Microsoft OpenXML (.docx, .xlsx, .pptx) archives in pure Dart.',
          elements: [
            const SlideElement(
              id: 's3_hdr',
              type: SlideElementType.text,
              x: 100,
              y: 70,
              width: 1400,
              height: 110,
              text: 'fyrOffice: Native OpenDocument & OpenXML Engine',
              subtitle:
                  'fyrDocs (.odt/.docx) • fyrSheets (.ods/.xlsx) • fyrSlides (.odp/.pptx)',
              fontSize: 40,
              bold: true,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#D040FF',
            ),
            const SlideElement(
              id: 's3_m1',
              type: SlideElementType.metricCard,
              x: 100,
              y: 215,
              width: 440,
              height: 215,
              text: '100% ODF/OOXML',
              subtitle: 'Lossless ZIP + XML Standards Compliance',
              fontSize: 42,
              bold: true,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#D040FF',
            ),
            const SlideElement(
              id: 's3_m2',
              type: SlideElementType.metricCard,
              x: 580,
              y: 215,
              width: 440,
              height: 215,
              text: '< 18ms Load',
              subtitle: 'Instant Deck & Spreadsheet Parsing',
              fontSize: 42,
              bold: true,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#00E5FF',
            ),
            const SlideElement(
              id: 's3_m3',
              type: SlideElementType.metricCard,
              x: 1060,
              y: 215,
              width: 440,
              height: 215,
              text: 'Zero Bloat',
              subtitle: 'No Java Runtime or Chromium Helper Processes',
              fontSize: 42,
              bold: true,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#D040FF',
            ),
            const SlideElement(
              id: 's3_list',
              type: SlideElementType.bulletList,
              x: 100,
              y: 470,
              width: 1400,
              height: 330,
              text: 'Interoperability Across Every Suite',
              bulletItems: [
                'fyrDocs: Rich WYSIWYG .odt/.docx/.md/HTML/PDF document processor with outline & stats',
                'fyrSheets: Multi-sheet .ods/.xlsx/.csv formula engine (SUM, AVERAGE, IF, VLOOKUP, STDEV)',
                'fyrSlides: Interactive 16:9 stage, speaker notes, presenter HUD, and .odp/.pptx/.html export',
              ],
              fontSize: 24,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#D040FF',
            ),
          ],
        ),

        // Slide 4: Developer Ecosystem
        SlidePage(
          id: 'slide_4',
          title: 'Developer Ecosystem: fyrCode, fyrDB & fyrPods',
          layout: SlideLayoutType.codeShowcase,
          transition: SlideTransitionType.slideLeft,
          speakerNotes:
              'Demonstrate how developers can build, query SQLite databases in fyrDB, inspect containers in fyrPods, and export slides directly from Dart.',
          elements: [
            const SlideElement(
              id: 's4_hdr',
              type: SlideElementType.text,
              x: 100,
              y: 72,
              width: 1400,
              height: 110,
              text: 'Developer Powerhouse: fyrCode, fyrDB & fyrPods',
              subtitle:
                  'First-class SQLite studio, Podman/Docker orchestrator, and REST client',
              fontSize: 40,
              bold: true,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#D040FF',
            ),
            const SlideElement(
              id: 's4_code',
              type: SlideElementType.codeBlock,
              x: 100,
              y: 220,
              width: 740,
              height: 560,
              text: '// Pure-Dart ODP & PPTX Presentation Pipeline\n'
                  'final deck = await SlidesIO.loadOdp("fyrDE_2026.odp");\n\n'
                  'for (final slide in deck.slides) {\n'
                  '  debugPrint("Slide: \${slide.title} (\${slide.elements.length} nodes)");\n'
                  '}\n\n'
                  '// Export simultaneously to PowerPoint & HTML5\n'
                  'await SlidesIO.savePptx(deck, "build/fyrDE_2026.pptx");\n'
                  'await SlidesIO.exportHtml(deck, "build/index.html");',
              codeLanguage: 'dart',
              fontSize: 21,
              textColorHex: '#F6F2FF',
              fillColorHex: '#090612',
              borderColorHex: '#00E5FF',
            ),
            const SlideElement(
              id: 's4_bullets',
              type: SlideElementType.bulletList,
              x: 880,
              y: 220,
              width: 620,
              height: 560,
              text: 'Integrated Dev Tooling',
              bulletItems: [
                'fyrDB: Live SQLite3 FFI schema inspector, ER diagram & SQL runner',
                'fyrPods: Rootless Podman & Docker container logs, stats & compose',
                'fyrAPI: Collections, bearer auth, latency charts & cURL generator',
                'fyrCode & fyrTerm: Syntax-highlighted IDE + GPU VTE terminal',
              ],
              fontSize: 24,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#D040FF',
            ),
          ],
        ),

        // Slide 5: Q4 Roadmap & Release Targets
        SlidePage(
          id: 'slide_5',
          title: 'Q4 Roadmap & Release Targets',
          layout: SlideLayoutType.titleAndContent,
          transition: SlideTransitionType.flip,
          speakerNotes:
              'Wrap up with Q4 milestones and invite contributors to test ISO images in fyrVirt.',
          elements: [
            const SlideElement(
              id: 's5_hdr',
              type: SlideElementType.text,
              x: 100,
              y: 72,
              width: 1400,
              height: 110,
              text: '2026 Roadmap & Release Targets',
              subtitle: 'Shipping the complete 34-application Linux desktop experience',
              fontSize: 42,
              bold: true,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#D040FF',
            ),
            const SlideElement(
              id: 's5_bullets',
              type: SlideElementType.bulletList,
              x: 100,
              y: 220,
              width: 1400,
              height: 540,
              text: 'Upcoming Milestones',
              bulletItems: [
                'M1 — Complete fyrOffice Suite (fyrDocs, fyrSheets, fyrSlides) with ODF 1.2 & OOXML',
                'M2 — Complete Developer Pro Pack (fyrDB SQLite Studio & fyrPods Container Engine)',
                'M3 — Automated Arch Linux + SwayFX single-command installer & SDDM theme',
                'M4 — Hardware-accelerated PipeWire screen studio & multi-monitor workspace rules',
              ],
              fontSize: 27,
              textColorHex: '#F6F2FF',
              fillColorHex: '#1D1433',
              borderColorHex: '#D040FF',
            ),
          ],
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
