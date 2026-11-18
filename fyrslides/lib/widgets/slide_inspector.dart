import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/slide_models.dart';
import '../state/slides_controller.dart';

class SlideInspector extends StatefulWidget {
  const SlideInspector({super.key});

  @override
  State<SlideInspector> createState() => _SlideInspectorState();
}

class _SlideInspectorState extends State<SlideInspector> {
  late TextEditingController _textCtrl;
  late TextEditingController _subCtrl;
  late TextEditingController _bulletsCtrl;
  late TextEditingController _slideTitleCtrl;
  String? _boundElementId;
  String? _boundSlideId;

  static const List<String> _swatchHexes = [
    '#D040FF',
    '#00E5FF',
    '#10B981',
    '#FF6B35',
    '#FBBF24',
    '#38BDF8',
    '#F6F2FF',
    '#1D1433',
  ];

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController();
    _subCtrl = TextEditingController();
    _bulletsCtrl = TextEditingController();
    _slideTitleCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _subCtrl.dispose();
    _bulletsCtrl.dispose();
    _slideTitleCtrl.dispose();
    super.dispose();
  }

  void _syncControllers(SlidePage slide, SlideElement? el) {
    if (_boundSlideId != slide.id) {
      _boundSlideId = slide.id;
      _slideTitleCtrl.text = slide.title;
    }
    if (_boundElementId != el?.id) {
      _boundElementId = el?.id;
      _textCtrl.text = el?.text ?? '';
      _subCtrl.text = el?.subtitle ?? '';
      _bulletsCtrl.text = el?.bulletItems.join('\n') ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<SlidesController>();
    final slide = ctrl.activeSlide;
    final el = ctrl.selectedElement;
    _syncControllers(slide, el);

    return Container(
      width: 276,
      decoration: BoxDecoration(
        color: FyrTheme.sidebarColor,
        border: Border(left: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              children: [
                Icon(
                  el != null ? el.type.icon : Icons.tune_rounded,
                  size: 14,
                  color: FyrTheme.accentColor,
                ),
                const SizedBox(width: 7),
                Text(
                  el != null
                      ? 'INSPECTOR — ${el.type.label.toUpperCase()}'
                      : 'SLIDE PROPERTIES',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: FyrTheme.textColorMuted,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                if (el != null) ...[
                  _buildElementInspector(ctrl, el),
                  const SizedBox(height: 18),
                  Divider(color: FyrTheme.dividerColor, height: 1),
                  const SizedBox(height: 14),
                ],
                _buildSlideInspector(ctrl, slide),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildElementInspector(SlidesController ctrl, SlideElement el) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Content'),
        const SizedBox(height: 6),
        TextField(
          controller: _textCtrl,
          maxLines: el.type == SlideElementType.codeBlock ? 4 : 2,
          style: TextStyle(fontSize: 12, color: FyrTheme.textColor),
          decoration: _inputDecoration('Primary Text / Value'),
          onChanged: (v) => ctrl.updateElement(el.copyWith(text: v)),
        ),
        if (el.type == SlideElementType.text ||
            el.type == SlideElementType.metricCard ||
            el.type == SlideElementType.chartCard) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _subCtrl,
            maxLines: 2,
            style: TextStyle(fontSize: 12, color: FyrTheme.textColor),
            decoration: _inputDecoration('Subtitle / Caption'),
            onChanged: (v) => ctrl.updateElement(el.copyWith(subtitle: v)),
          ),
        ],
        if (el.type == SlideElementType.bulletList) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _bulletsCtrl,
            maxLines: 4,
            style: TextStyle(fontSize: 11.5, color: FyrTheme.textColor),
            decoration: _inputDecoration('Bullets (one per line)'),
            onChanged: (v) {
              final items = v
                  .split('\n')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              ctrl.updateElement(el.copyWith(bulletItems: items));
            },
          ),
        ],
        const SizedBox(height: 14),
        _sectionTitle('Typography & Alignment'),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                ),
                child: Slider(
                  value: el.fontSize.clamp(12.0, 88.0),
                  min: 12.0,
                  max: 88.0,
                  activeColor: FyrTheme.accentColor,
                  onChanged: (v) =>
                      ctrl.updateElement(el.copyWith(fontSize: v.roundToDouble())),
                ),
              ),
            ),
            Text(
              '${el.fontSize.round()}pt',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColor,
              ),
            ),
          ],
        ),
        Row(
          children: [
            _toggleChip(
              icon: Icons.format_bold_rounded,
              active: el.bold,
              onTap: () =>
                  ctrl.updateElement(el.copyWith(bold: !el.bold), recordUndo: true),
            ),
            const SizedBox(width: 6),
            _toggleChip(
              icon: Icons.format_italic_rounded,
              active: el.italic,
              onTap: () => ctrl.updateElement(
                  el.copyWith(italic: !el.italic),
                  recordUndo: true),
            ),
            const Spacer(),
            _toggleChip(
              icon: Icons.format_align_left_rounded,
              active: el.align == 'left',
              onTap: () =>
                  ctrl.updateElement(el.copyWith(align: 'left'), recordUndo: true),
            ),
            const SizedBox(width: 4),
            _toggleChip(
              icon: Icons.format_align_center_rounded,
              active: el.align == 'center',
              onTap: () => ctrl.updateElement(el.copyWith(align: 'center'),
                  recordUndo: true),
            ),
            const SizedBox(width: 4),
            _toggleChip(
              icon: Icons.format_align_right_rounded,
              active: el.align == 'right',
              onTap: () =>
                  ctrl.updateElement(el.copyWith(align: 'right'), recordUndo: true),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _sectionTitle('Accent & Border Swatch'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: _swatchHexes.map((hex) {
            final selected =
                el.borderColorHex.toUpperCase() == hex.toUpperCase();
            return GestureDetector(
              onTap: () => ctrl.updateElement(
                el.copyWith(borderColorHex: hex),
                recordUndo: true,
              ),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colorFromHex(hex),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected ? Colors.white : Colors.white24,
                    width: selected ? 2.2 : 1.0,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        _sectionTitle('Position & Dimensions (1600×900)'),
        const SizedBox(height: 6),
        Row(
          children: [
            _metricPill('X', '${el.x.round()}'),
            const SizedBox(width: 6),
            _metricPill('Y', '${el.y.round()}'),
            const SizedBox(width: 6),
            _metricPill('W', '${el.width.round()}'),
            const SizedBox(width: 6),
            _metricPill('H', '${el.height.round()}'),
          ],
        ),
      ],
    );
  }

  Widget _buildSlideInspector(SlidesController ctrl, SlidePage slide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Slide Title'),
        const SizedBox(height: 6),
        TextField(
          controller: _slideTitleCtrl,
          style: TextStyle(fontSize: 12, color: FyrTheme.textColor),
          decoration: _inputDecoration('Slide Title'),
          onChanged: ctrl.updateSlideTitle,
        ),
        const SizedBox(height: 12),
        _sectionTitle('Slide Layout'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: SlideLayoutType.values.map((layout) {
            final isCurrent = slide.layout == layout;
            return InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => ctrl.applySlideLayout(layout),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? FyrTheme.accentColor.withValues(alpha: 0.16)
                      : FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isCurrent
                        ? FyrTheme.accentColor
                        : FyrTheme.dividerColor,
                  ),
                ),
                child: Text(
                  layout.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight:
                        isCurrent ? FontWeight.w600 : FontWeight.w400,
                    color: isCurrent
                        ? FyrTheme.accentColor
                        : FyrTheme.textColor,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        _sectionTitle('Slide Transition'),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: SlideTransitionType.values.map((tr) {
            final active = slide.transition == tr;
            return InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => ctrl.updateSlideTransition(tr),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: active
                      ? FyrTheme.accentColor.withValues(alpha: 0.16)
                      : FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color:
                        active ? FyrTheme.accentColor : FyrTheme.dividerColor,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(tr.icon,
                        size: 12,
                        color: active
                            ? FyrTheme.accentColor
                            : FyrTheme.textColorMuted),
                    const SizedBox(width: 4),
                    Text(
                      tr.label,
                      style: TextStyle(
                        fontSize: 10.5,
                        color:
                            active ? FyrTheme.accentColor : FyrTheme.textColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
        color: FyrTheme.textColorMuted,
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 11, color: FyrTheme.textColorMuted),
      isDense: true,
      filled: true,
      fillColor: FyrTheme.cardColor,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: FyrTheme.dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: BorderSide(color: FyrTheme.accentColor),
      ),
    );
  }

  Widget _toggleChip({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        width: 30,
        height: 28,
        decoration: BoxDecoration(
          color: active
              ? FyrTheme.accentColor.withValues(alpha: 0.2)
              : FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? FyrTheme.accentColor : FyrTheme.dividerColor,
          ),
        ),
        child: Icon(
          icon,
          size: 15,
          color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted,
        ),
      ),
    );
  }

  Widget _metricPill(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 6),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: FyrTheme.textColorMuted,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
