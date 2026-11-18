import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../state/slides_controller.dart';
import 'slide_canvas.dart';

class SlideFilmstrip extends StatelessWidget {
  const SlideFilmstrip({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SlidesController>();
    final slides = ctrl.slides;

    return Container(
      width: 224,
      decoration: BoxDecoration(
        color: FyrTheme.sidebarColor,
        border: Border(right: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              children: [
                Text(
                  'SLIDES (${slides.length})',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
                const Spacer(),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  icon: Icon(Icons.add_circle_outline_rounded,
                      size: 15, color: FyrTheme.accentColor),
                  tooltip: 'New Slide',
                  onPressed: ctrl.addSlide,
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  icon: Icon(Icons.copy_rounded,
                      size: 13.5, color: FyrTheme.textColorMuted),
                  tooltip: 'Duplicate Slide',
                  onPressed: ctrl.duplicateSlide,
                ),
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  icon: Icon(Icons.delete_outline_rounded,
                      size: 14.5, color: FyrTheme.textColorMuted),
                  tooltip: 'Delete Slide',
                  onPressed: slides.length > 1 ? ctrl.deleteSlide : null,
                ),
              ],
            ),
          ),
          // Slide Thumbnails List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              itemCount: slides.length,
              itemBuilder: (context, idx) {
                final slide = slides[idx];
                final isSelected = idx == ctrl.activeSlideIndex;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => ctrl.selectSlide(idx),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? FyrTheme.accentColor.withValues(alpha: 0.14)
                            : FyrTheme.cardColor,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: isSelected
                              ? FyrTheme.accentColor
                              : FyrTheme.dividerColor,
                          width: isSelected ? 1.6 : 1.0,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? FyrTheme.accentColor
                                      : FyrTheme.surfaceColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${idx + 1}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? FyrTheme.getContrastingColor(
                                            FyrTheme.accentColor)
                                        : FyrTheme.textColorMuted,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  slide.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: FyrTheme.textColor,
                                  ),
                                ),
                              ),
                              Icon(
                                slide.transition.icon,
                                size: 12,
                                color: FyrTheme.textColorMuted
                                    .withValues(alpha: 0.65),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          // Miniature 16:9 Live Preview
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: IgnorePointer(
                                child: SlideStagePreview(
                                  slide: slide,
                                  theme: ctrl.deck.theme,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // Reorder Footer
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 26),
                  ),
                  onPressed: ctrl.activeSlideIndex > 0 ? ctrl.moveSlideUp : null,
                  icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 15),
                  label: const Text('Move Up', style: TextStyle(fontSize: 11)),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 26),
                  ),
                  onPressed: ctrl.activeSlideIndex < slides.length - 1
                      ? ctrl.moveSlideDown
                      : null,
                  icon:
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 15),
                  label:
                      const Text('Move Down', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
