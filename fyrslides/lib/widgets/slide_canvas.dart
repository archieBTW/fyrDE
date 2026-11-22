import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/slide_models.dart';
import '../state/slides_controller.dart';

class SlideCanvas extends StatefulWidget {
  const SlideCanvas({super.key});

  @override
  State<SlideCanvas> createState() => _SlideCanvasState();
}

class _SlideCanvasState extends State<SlideCanvas> {
  late TextEditingController _notesController;
  String? _lastNotesSlideId;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SlidesController>();
    final slide = ctrl.activeSlide;

    if (_lastNotesSlideId != slide.id) {
      _lastNotesSlideId = slide.id;
      _notesController.text = slide.speakerNotes;
    }

    if (ctrl.isGridView) {
      return Expanded(child: _buildGridSorter(context, ctrl));
    }

    return Expanded(
      child: Container(
        color: FyrTheme.contentColor,
        child: Column(
          children: [
            // Main 16:9 Stage Area
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ctrl.selectElement(null),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: AspectRatio(
                      aspectRatio: ctrl.deck.aspectRatioValue,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: FyrTheme.accentColor.withValues(alpha: 0.45),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.55),
                              blurRadius: 28,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: _InteractiveSlideStage(
                            slide: slide,
                            theme: ctrl.deck.theme,
                            selectedElementId: ctrl.selectedElementId,
                            showGrid: ctrl.showCanvasGrid,
                            onSelectElement: ctrl.selectElement,
                            onMoveElement: (id, dx, dy) {
                              final el = slide.elements
                                  .firstWhere((e) => e.id == id);
                              ctrl.updateElementRect(
                                id,
                                x: el.x + dx,
                                y: el.y + dy,
                              );
                            },
                            onResizeElement: (id, dw, dh) {
                              final el = slide.elements
                                  .firstWhere((e) => e.id == id);
                              ctrl.updateElementRect(
                                id,
                                width: el.width + dw,
                                height: el.height + dh,
                              );
                            },
                            onGestureStart: ctrl.recordSnapshot,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Collapsible Speaker Notes Panel
            if (ctrl.showSpeakerNotes)
              Container(
                height: 112,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: FyrTheme.surfaceColor,
                  border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.speaker_notes_outlined,
                            size: 14, color: FyrTheme.accentColor),
                        const SizedBox(width: 6),
                        Text(
                          'SPEAKER NOTES — ${slide.title}',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                            color: FyrTheme.textColorMuted,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: TextField(
                        controller: _notesController,
                        maxLines: 3,
                        onChanged: ctrl.updateSpeakerNotes,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: FyrTheme.textColor,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText:
                              'Add speaker notes and talking cues for this slide...',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color:
                                FyrTheme.textColorMuted.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Bottom Status Bar
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: FyrTheme.bgColor,
                border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Slide ${ctrl.activeSlideIndex + 1} of ${ctrl.slides.length}  •  1600×900 (${ctrl.deck.aspectRatio})  •  Theme: ${ctrl.deck.theme.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: FyrTheme.textColorMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: ctrl.toggleCanvasGrid,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.grid_4x4_rounded,
                            size: 13,
                            color: ctrl.showCanvasGrid
                                ? FyrTheme.accentColor
                                : FyrTheme.textColorMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Guides',
                            style: TextStyle(
                              fontSize: 11,
                              color: ctrl.showCanvasGrid
                                  ? FyrTheme.accentColor
                                  : FyrTheme.textColorMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: ctrl.toggleSpeakerNotes,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.speaker_notes_rounded,
                            size: 13,
                            color: ctrl.showSpeakerNotes
                                ? FyrTheme.accentColor
                                : FyrTheme.textColorMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Speaker Notes',
                            style: TextStyle(
                              fontSize: 11,
                              color: ctrl.showSpeakerNotes
                                  ? FyrTheme.accentColor
                                  : FyrTheme.textColorMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridSorter(BuildContext context, SlidesController ctrl) {
    return Container(
      color: FyrTheme.contentColor,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.grid_view_rounded,
                  size: 18, color: FyrTheme.accentColor),
              const SizedBox(width: 8),
              Text(
                'Slide Sorter (${ctrl.slides.length} Slides)',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: FyrTheme.textColor,
                ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                onPressed: ctrl.toggleGridView,
                icon: const Icon(Icons.edit_rounded, size: 15),
                label: const Text('Back to Stage Editor',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 340,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.32,
              ),
              itemCount: ctrl.slides.length,
              itemBuilder: (context, idx) {
                final s = ctrl.slides[idx];
                final active = idx == ctrl.activeSlideIndex;
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    ctrl.selectSlide(idx);
                    ctrl.toggleGridView();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: FyrTheme.cardColor,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: active
                            ? FyrTheme.accentColor
                            : FyrTheme.dividerColor,
                        width: active ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'Slide ${idx + 1}',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: FyrTheme.accentColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: FyrTheme.textColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SlideStagePreview(
                              slide: s,
                              theme: ctrl.deck.theme,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Non-interactive 1600x900 FittedBox preview used in Filmstrip, Grid Sorter, and Presenter Mode.
class SlideStagePreview extends StatelessWidget {
  final SlidePage slide;
  final DeckThemePreset theme;

  const SlideStagePreview({
    super.key,
    required this.slide,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: SlideElement.canvasWidth,
        height: SlideElement.canvasHeight,
        child: _SlideBackgroundAndElements(
          slide: slide,
          theme: theme,
          selectedElementId: null,
          showGrid: false,
        ),
      ),
    );
  }
}

class _InteractiveSlideStage extends StatelessWidget {
  final SlidePage slide;
  final DeckThemePreset theme;
  final String? selectedElementId;
  final bool showGrid;
  final ValueChanged<String?> onSelectElement;
  final void Function(String id, double dx, double dy) onMoveElement;
  final void Function(String id, double dw, double dh) onResizeElement;
  final VoidCallback onGestureStart;

  const _InteractiveSlideStage({
    required this.slide,
    required this.theme,
    required this.selectedElementId,
    required this.showGrid,
    required this.onSelectElement,
    required this.onMoveElement,
    required this.onResizeElement,
    required this.onGestureStart,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaleX = constraints.maxWidth / SlideElement.canvasWidth;
        final scaleY = constraints.maxHeight / SlideElement.canvasHeight;
        final scale = math.min(scaleX, scaleY);

        return FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: SlideElement.canvasWidth,
            height: SlideElement.canvasHeight,
            child: _SlideBackgroundAndElements(
              slide: slide,
              theme: theme,
              selectedElementId: selectedElementId,
              showGrid: showGrid,
              scaleFactor: scale <= 0 ? 1.0 : scale,
              onSelectElement: onSelectElement,
              onMoveElement: onMoveElement,
              onResizeElement: onResizeElement,
              onGestureStart: onGestureStart,
            ),
          ),
        );
      },
    );
  }
}

class _SlideBackgroundAndElements extends StatelessWidget {
  final SlidePage slide;
  final DeckThemePreset theme;
  final String? selectedElementId;
  final bool showGrid;
  final double scaleFactor;
  final ValueChanged<String?>? onSelectElement;
  final void Function(String id, double dx, double dy)? onMoveElement;
  final void Function(String id, double dw, double dh)? onResizeElement;
  final VoidCallback? onGestureStart;

  const _SlideBackgroundAndElements({
    required this.slide,
    required this.theme,
    required this.selectedElementId,
    required this.showGrid,
    this.scaleFactor = 1.0,
    this.onSelectElement,
    this.onMoveElement,
    this.onResizeElement,
    this.onGestureStart,
  });

  @override
  Widget build(BuildContext context) {
    final bgStart = slide.bgOverrideHex != null
        ? colorFromHex(slide.bgOverrideHex!)
        : theme.bgStart;
    final bgEnd = theme.bgEnd;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bgStart, bgEnd],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Subtle ambient glow & grid guides
          if (showGrid)
            Positioned.fill(
              child: CustomPaint(
                painter: _CanvasGridPainter(
                  color: theme.accent.withValues(alpha: 0.08),
                ),
              ),
            ),

          // Decorative corner glow
          Positioned(
            right: -120,
            top: -120,
            child: Container(
              width: 440,
              height: 440,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    theme.accent.withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Slide Elements
          for (final el in slide.elements)
            Positioned(
              left: el.x,
              top: el.y,
              width: el.width,
              height: el.height,
              child: _buildElementBox(el),
            ),
        ],
      ),
    );
  }

  Widget _buildElementBox(SlideElement el) {
    final isSelected = el.id == selectedElementId;
    final content = Opacity(
      opacity: el.opacity.clamp(0.1, 1.0),
      child: _renderElementVisual(el),
    );

    if (onSelectElement == null) {
      return content;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelectElement?.call(el.id),
      onPanStart: (_) {
        onSelectElement?.call(el.id);
        onGestureStart?.call();
      },
      onPanUpdate: (details) {
        onMoveElement?.call(
          el.id,
          details.delta.dx / scaleFactor,
          details.delta.dy / scaleFactor,
        );
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: isSelected
                  ? BoxDecoration(
                      border: Border.all(
                        color: const Color(0xFFD040FF),
                        width: 2.5,
                      ),
                      borderRadius: BorderRadius.circular(el.borderRadius),
                    )
                  : null,
              child: content,
            ),
          ),
          if (isSelected) ...[
            // Bottom-Right Resize Handle
            Positioned(
              right: -8,
              bottom: -8,
              child: GestureDetector(
                onPanStart: (_) => onGestureStart?.call(),
                onPanUpdate: (d) {
                  onResizeElement?.call(
                    el.id,
                    d.delta.dx / scaleFactor,
                    d.delta.dy / scaleFactor,
                  );
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeUpLeftDownRight,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD040FF),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2.5),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _renderElementVisual(SlideElement el) {
    final textColor = colorFromHex(el.textColorHex, fallback: theme.textColor);
    final fillColor = colorFromHex(el.fillColorHex, fallback: theme.cardBg);
    final borderColor = colorFromHex(el.borderColorHex, fallback: theme.accent);

    switch (el.type) {
      case SlideElementType.badge:
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: fillColor.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(el.borderRadius),
            border: Border.all(color: borderColor, width: 2),
          ),
          child: Text(
            el.text,
            textAlign: el.textAlign,
            style: GoogleFonts.outfit(
              fontSize: el.fontSize,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: textColor,
            ),
          ),
        );

      case SlideElementType.text:
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            crossAxisAlignment: el.align == 'center'
                ? CrossAxisAlignment.center
                : el.align == 'right'
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  el.text,
                  textAlign: el.textAlign,
                  style: GoogleFonts.outfit(
                    fontSize: el.fontSize,
                    fontWeight: el.bold ? FontWeight.w700 : FontWeight.w500,
                    fontStyle:
                        el.italic ? FontStyle.italic : FontStyle.normal,
                    color: textColor,
                    height: 1.15,
                  ),
                ),
              ),
              if (el.subtitle.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  el.subtitle,
                  textAlign: el.textAlign,
                  style: GoogleFonts.inter(
                    fontSize: (el.fontSize * 0.46).clamp(16.0, 32.0),
                    color: textColor.withValues(alpha: 0.76),
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        );

      case SlideElementType.metricCard:
        return Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: fillColor.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(el.borderRadius),
            border: Border.all(
                color: borderColor.withValues(alpha: 0.75), width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                el.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: el.fontSize,
                  fontWeight: FontWeight.w800,
                  color: borderColor,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                el.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 21,
                  fontWeight: FontWeight.w500,
                  color: textColor.withValues(alpha: 0.88),
                ),
              ),
            ],
          ),
        );

      case SlideElementType.bulletList:
        return Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: fillColor.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(el.borderRadius),
            border: Border.all(
                color: borderColor.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (el.text.isNotEmpty) ...[
                Text(
                  el.text,
                  style: GoogleFonts.outfit(
                    fontSize: el.fontSize + 4,
                    fontWeight: FontWeight.w700,
                    color: borderColor,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: el.bulletItems.map((item) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 10, right: 14),
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: borderColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            item,
                            style: GoogleFonts.inter(
                              fontSize: el.fontSize,
                              color: textColor,
                              height: 1.32,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );

      case SlideElementType.codeBlock:
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF080510),
            borderRadius: BorderRadius.circular(el.borderRadius),
            border: Border.all(
                color: borderColor.withValues(alpha: 0.65), width: 1.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 11,
                    height: 11,
                    decoration: const BoxDecoration(
                        color: Color(0xFFFF5F56), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    width: 11,
                    height: 11,
                    decoration: const BoxDecoration(
                        color: Color(0xFFFFBD2E), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 7),
                  Container(
                    width: 11,
                    height: 11,
                    decoration: const BoxDecoration(
                        color: Color(0xFF27C93F), shape: BoxShape.circle),
                  ),
                  const Spacer(),
                  Text(
                    el.codeLanguage.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: borderColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Text(
                  el.text,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: el.fontSize,
                    color: textColor,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        );

      case SlideElementType.chartCard:
        final values =
            el.chartValues.isEmpty ? const [410.0, 920.0, 1240.0] : el.chartValues;
        final labels =
            el.chartLabels.isEmpty ? const ['fyrDE', 'KDE', 'GNOME'] : el.chartLabels;
        final maxVal = values.fold<double>(1.0, math.max);

        return Container(
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: fillColor.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(el.borderRadius),
            border: Border.all(
                color: borderColor.withValues(alpha: 0.55), width: 1.8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                el.text,
                style: GoogleFonts.outfit(
                  fontSize: el.fontSize + 4,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              if (el.subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  el.subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 17,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(values.length, (i) {
                    final v = values[i];
                    final ratio = (v / maxVal).clamp(0.12, 1.0);
                    final lbl = i < labels.length ? labels[i] : 'Item ${i + 1}';
                    final isFirst = i == 0;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              v.round().toString(),
                              style: GoogleFonts.outfit(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: isFirst ? borderColor : textColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: ratio,
                                  widthFactor: 0.68,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        colors: isFirst
                                            ? [
                                                borderColor,
                                                borderColor.withValues(alpha: 0.45)
                                              ]
                                            : [
                                                textColor.withValues(alpha: 0.42),
                                                textColor.withValues(alpha: 0.18)
                                              ],
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              lbl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight:
                                    isFirst ? FontWeight.w700 : FontWeight.w500,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );

      case SlideElementType.shape:
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: fillColor.withValues(alpha: 0.85),
            shape: el.shapeKind == ShapeKind.circle
                ? BoxShape.circle
                : BoxShape.rectangle,
            borderRadius: el.shapeKind == ShapeKind.circle
                ? null
                : BorderRadius.circular(
                    el.shapeKind == ShapeKind.pill ? 999 : el.borderRadius,
                  ),
            border: Border.all(color: borderColor, width: 2.5),
          ),
          child: Text(
            el.text,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: el.fontSize,
              fontWeight: FontWeight.w700,
              color: textColor,
            ),
          ),
        );
    }
  }
}

class _CanvasGridPainter extends CustomPainter {
  final Color color;
  const _CanvasGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    const step = 100.0;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Full-window Presenter Mode overlay shown when `ctrl.isPresenting == true`.
class PresentationOverlay extends StatelessWidget {
  const PresentationOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SlidesController>();
    final slide = ctrl.activeSlide;

    return Material(
      color: const Color(0xFF040208),
      child: Stack(
        children: [
          // Animated Slide Stage
          Positioned.fill(
            child: GestureDetector(
              onTap: ctrl.nextSlide,
              child: Center(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 46),
                  child: AspectRatio(
                    aspectRatio: ctrl.deck.aspectRatioValue,
                    child: AnimatedSwitcher(
                      duration:
                          Duration(milliseconds: slide.transitionDurationMs),
                      transitionBuilder: (child, anim) {
                        switch (slide.transition) {
                          case SlideTransitionType.slideLeft:
                            return SlideTransition(
                              position: Tween<Offset>(
                                begin: const Offset(0.18, 0),
                                end: Offset.zero,
                              ).animate(CurvedAnimation(
                                parent: anim,
                                curve: Curves.easeOutCubic,
                              )),
                              child: FadeTransition(opacity: anim, child: child),
                            );
                          case SlideTransitionType.zoomIn:
                          case SlideTransitionType.flip:
                            return ScaleTransition(
                              scale: Tween<double>(begin: 0.88, end: 1.0)
                                  .animate(CurvedAnimation(
                                parent: anim,
                                curve: Curves.easeOutBack,
                              )),
                              child: FadeTransition(opacity: anim, child: child),
                            );
                          case SlideTransitionType.none:
                          case SlideTransitionType.fade:
                            return FadeTransition(opacity: anim, child: child);
                        }
                      },
                      child: ClipRRect(
                        key: ValueKey(slide.id),
                        borderRadius: BorderRadius.circular(14),
                        child: SlideStagePreview(
                          slide: slide,
                          theme: ctrl.deck.theme,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Presenter Top HUD Bar
          Positioned(
            top: 12,
            left: 24,
            right: 24,
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_outlined,
                          size: 15, color: FyrTheme.accentColor),
                      const SizedBox(width: 6),
                      Text(
                        ctrl.formattedPresenterTimer,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Slide ${ctrl.activeSlideIndex + 1} / ${ctrl.slides.length} — ${slide.title}',
                        style: const TextStyle(
                            fontSize: 12.5, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: ctrl.prevSlide,
                  icon: const Icon(Icons.chevron_left_rounded,
                      color: Colors.white),
                  tooltip: 'Previous Slide (←)',
                ),
                IconButton(
                  onPressed: ctrl.nextSlide,
                  icon: const Icon(Icons.chevron_right_rounded,
                      color: Colors.white),
                  tooltip: 'Next Slide (→ / Space)',
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.85),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: ctrl.stopPresentation,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Exit (Esc)',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
