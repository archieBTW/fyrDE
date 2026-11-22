import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/slide_models.dart';
import '../state/slides_controller.dart';

class ElementToolbar extends StatelessWidget {
  const ElementToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SlidesController>();
    final slide = ctrl.activeSlide;
    final hasSelection = ctrl.selectedElement != null;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: FyrTheme.surfaceColor,
        border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
          // Add Slide with Layout Menu
          PopupMenuButton<SlideLayoutType>(
            tooltip: 'Add New Slide with Layout',
            onSelected: ctrl.addSlide,
            itemBuilder: (_) => SlideLayoutType.values
                .map(
                  (layout) => PopupMenuItem(
                    value: layout,
                    child: Row(
                      children: [
                        Icon(layout.icon, size: 15, color: FyrTheme.accentColor),
                        const SizedBox(width: 8),
                        Text(layout.label, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                )
                .toList(),
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: FyrTheme.accentColor.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: FyrTheme.accentColor.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 15, color: FyrTheme.accentColor),
                  const SizedBox(width: 4),
                  Text(
                    'Add Slide',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.accentColor,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_drop_down_rounded,
                      size: 15, color: FyrTheme.accentColor),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _vDivider(),
          const SizedBox(width: 8),
          // Insert Element Buttons
          _insertBtn(
            icon: Icons.text_fields_rounded,
            label: 'Text',
            onTap: () => ctrl.addElement(SlideElementType.text),
          ),
          const SizedBox(width: 5),
          _insertBtn(
            icon: Icons.format_list_bulleted_rounded,
            label: 'List',
            onTap: () => ctrl.addElement(SlideElementType.bulletList),
          ),
          const SizedBox(width: 5),
          _insertBtn(
            icon: Icons.speed_rounded,
            label: 'Metric',
            onTap: () => ctrl.addElement(SlideElementType.metricCard),
          ),
          const SizedBox(width: 5),
          _insertBtn(
            icon: Icons.bar_chart_rounded,
            label: 'Chart',
            onTap: () => ctrl.addElement(SlideElementType.chartCard),
          ),
          const SizedBox(width: 5),
          _insertBtn(
            icon: Icons.terminal_rounded,
            label: 'Code',
            onTap: () => ctrl.addElement(SlideElementType.codeBlock),
          ),
          const SizedBox(width: 5),
          _insertBtn(
            icon: Icons.category_outlined,
            label: 'Shape',
            onTap: () => ctrl.addElement(SlideElementType.shape),
          ),
          const SizedBox(width: 5),
          _insertBtn(
            icon: Icons.label_important_outline_rounded,
            label: 'Badge',
            onTap: () => ctrl.addElement(SlideElementType.badge),
          ),
          const SizedBox(width: 10),
          _vDivider(),
          const SizedBox(width: 10),
          // Deck Theme Preset Selector
          PopupMenuButton<DeckThemePreset>(
            tooltip: 'Presentation Theme Preset',
            onSelected: ctrl.applyThemePreset,
            itemBuilder: (_) => kDeckThemePresets
                .map(
                  (preset) => PopupMenuItem(
                    value: preset,
                    child: Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [preset.bgStart, preset.accent],
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(preset.name, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                )
                .toList(),
            child: Container(
              height: 27,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: FyrTheme.cardColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: ctrl.deck.theme.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    ctrl.deck.theme.name,
                    style: TextStyle(fontSize: 11, color: FyrTheme.textColor),
                  ),
                  const SizedBox(width: 3),
                  Icon(Icons.expand_more_rounded,
                      size: 14, color: FyrTheme.textColorMuted),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Slide Transition Selector
          PopupMenuButton<SlideTransitionType>(
            tooltip: 'Slide Transition Effect',
            onSelected: ctrl.updateSlideTransition,
            itemBuilder: (_) => SlideTransitionType.values
                .map(
                  (tr) => PopupMenuItem(
                    value: tr,
                    child: Row(
                      children: [
                        Icon(tr.icon, size: 15, color: FyrTheme.accentColor),
                        const SizedBox(width: 8),
                        Text(tr.label, style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                )
                .toList(),
            child: Container(
              height: 27,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: FyrTheme.cardColor,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(slide.transition.icon,
                      size: 13, color: FyrTheme.accentColor),
                  const SizedBox(width: 5),
                  Text(
                    'Transition: ${slide.transition.label}',
                    style: TextStyle(fontSize: 11, color: FyrTheme.textColor),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Layer & Selection Actions
          IconButton(
            icon: Icon(
              Icons.flip_to_front_rounded,
              size: 15,
              color: hasSelection
                  ? FyrTheme.textColor
                  : FyrTheme.textColorMuted.withValues(alpha: 0.35),
            ),
            tooltip: 'Bring to Front',
            onPressed: hasSelection ? ctrl.bringToFront : null,
          ),
          IconButton(
            icon: Icon(
              Icons.flip_to_back_rounded,
              size: 15,
              color: hasSelection
                  ? FyrTheme.textColor
                  : FyrTheme.textColorMuted.withValues(alpha: 0.35),
            ),
            tooltip: 'Send to Back',
            onPressed: hasSelection ? ctrl.sendToBack : null,
          ),
          IconButton(
            icon: Icon(
              Icons.copy_all_rounded,
              size: 15,
              color: hasSelection
                  ? FyrTheme.textColor
                  : FyrTheme.textColorMuted.withValues(alpha: 0.35),
            ),
            tooltip: 'Duplicate Element (Ctrl+D)',
            onPressed: hasSelection ? ctrl.duplicateSelectedElement : null,
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 16,
              color: hasSelection
                  ? Colors.redAccent
                  : FyrTheme.textColorMuted.withValues(alpha: 0.35),
            ),
            tooltip: 'Delete Selected Element (Del)',
            onPressed: hasSelection ? ctrl.deleteSelectedElement : null,
          ),
        ],
      ),
      ),
    );
  }

  Widget _vDivider() {
    return Container(width: 1, height: 20, color: FyrTheme.dividerColor);
  }

  Widget _insertBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        height: 27,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13.5, color: FyrTheme.accentColor),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: FyrTheme.textColor),
            ),
          ],
        ),
      ),
    );
  }
}
