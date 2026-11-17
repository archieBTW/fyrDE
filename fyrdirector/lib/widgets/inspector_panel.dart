import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/director_types.dart';
import '../state/director_controller.dart';

class InspectorPanel extends StatefulWidget {
  const InspectorPanel({super.key});

  @override
  State<InspectorPanel> createState() => _InspectorPanelState();
}

class _InspectorPanelState extends State<InspectorPanel> {
  final TextEditingController _titleTextCtrl = TextEditingController();
  String? _lastClipId;

  @override
  void dispose() {
    _titleTextCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DirectorController>();
    final clip = ctrl.selectedClip;

    if (clip != null && clip.id != _lastClipId) {
      _lastClipId = clip.id;
      if (clip.titleStyle != null) {
        _titleTextCtrl.text = clip.titleStyle!.text;
      }
    } else if (clip == null) {
      _lastClipId = null;
    }

    return Container(
      width: 292,
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
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: FyrTheme.contentColor,
              border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Text(
              clip == null ? 'Inspector' : 'Clip Inspector • ${clip.name}',
              style: GoogleFonts.outfit(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: clip == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'Select a clip on the timeline to adjust Transform, Color, Speed, Audio, Transitions, or Text.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: FyrTheme.textColorMuted),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (clip.type == MediaType.title &&
                          clip.titleStyle != null) ...[
                        _sectionTitle('Title & Caption'),
                        TextField(
                          controller: _titleTextCtrl,
                          maxLines: 3,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: OutlineInputBorder(),
                            labelText: 'Text',
                          ),
                          onChanged: (v) {
                            clip.titleStyle!.text = v;
                            ctrl.refresh();
                          },
                        ),
                        const SizedBox(height: 8),
                        _slider(
                          'Font Size',
                          '${clip.titleStyle!.fontSize.round()}px',
                          clip.titleStyle!.fontSize,
                          18,
                          140,
                          (v) {
                            clip.titleStyle!.fontSize = v;
                            ctrl.refresh();
                          },
                          (_) => ctrl.commitEffectChange(),
                        ),
                        _slider(
                          'Vertical Pos',
                          '${(clip.titleStyle!.posYRatio * 100).round()}%',
                          clip.titleStyle!.posYRatio,
                          0.05,
                          0.95,
                          (v) {
                            clip.titleStyle!.posYRatio = v;
                            ctrl.refresh();
                          },
                          (_) => ctrl.commitEffectChange(),
                        ),
                        _slider(
                          'Backdrop Opacity',
                          '${(clip.titleStyle!.bgOpacity * 100).round()}%',
                          clip.titleStyle!.bgOpacity,
                          0.0,
                          1.0,
                          (v) {
                            clip.titleStyle!.bgOpacity = v;
                            ctrl.refresh();
                          },
                          (_) => ctrl.commitEffectChange(),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (clip.type != MediaType.audio) ...[
                        _sectionTitle('Transform'),
                        _slider(
                          'Scale',
                          '${(clip.effects.scale * 100).round()}%',
                          clip.effects.scale,
                          0.2,
                          2.5,
                          (v) {
                            clip.effects.scale = v;
                            ctrl.refresh();
                          },
                          (_) => ctrl.commitEffectChange(),
                        ),
                        _slider(
                          'Position X',
                          '${(clip.effects.offsetX * 100).round()}%',
                          clip.effects.offsetX,
                          -0.8,
                          0.8,
                          (v) {
                            clip.effects.offsetX = v;
                            ctrl.refresh();
                          },
                          (_) => ctrl.commitEffectChange(),
                        ),
                        _slider(
                          'Position Y',
                          '${(clip.effects.offsetY * 100).round()}%',
                          clip.effects.offsetY,
                          -0.8,
                          0.8,
                          (v) {
                            clip.effects.offsetY = v;
                            ctrl.refresh();
                          },
                          (_) => ctrl.commitEffectChange(),
                        ),
                        _slider(
                          'Rotation',
                          '${clip.effects.rotationDeg.round()}°',
                          clip.effects.rotationDeg,
                          -180,
                          180,
                          (v) {
                            clip.effects.rotationDeg = v;
                            ctrl.refresh();
                          },
                          (_) => ctrl.commitEffectChange(),
                        ),
                        _slider(
                          'Opacity',
                          '${(clip.effects.opacity * 100).round()}%',
                          clip.effects.opacity,
                          0.0,
                          1.0,
                          (v) {
                            clip.effects.opacity = v;
                            ctrl.refresh();
                          },
                          (_) => ctrl.commitEffectChange(),
                        ),
                        const SizedBox(height: 10),
                        _sectionTitle('Color & Blur'),
                        _slider(
                          'Brightness',
                          clip.effects.brightness.toStringAsFixed(2),
                          clip.effects.brightness,
                          -0.5,
                          0.5,
                          (v) {
                            clip.effects.brightness = v;
                            ctrl.refresh();
                          },
                          (_) => ctrl.commitEffectChange(),
                        ),
                        _slider(
                          'Contrast',
                          clip.effects.contrast.toStringAsFixed(2),
                          clip.effects.contrast,
                          0.3,
                          2.0,
                          (v) {
                            clip.effects.contrast = v;
                            ctrl.refresh();
                          },
                          (_) => ctrl.commitEffectChange(),
                        ),
                        _slider(
                          'Saturation',
                          clip.effects.saturation.toStringAsFixed(2),
                          clip.effects.saturation,
                          0.0,
                          2.0,
                          (v) {
                            clip.effects.saturation = v;
                            ctrl.refresh();
                          },
                          (_) => ctrl.commitEffectChange(),
                        ),
                        _slider(
                          'Blur',
                          clip.effects.blur.toStringAsFixed(1),
                          clip.effects.blur,
                          0.0,
                          16.0,
                          (v) {
                            clip.effects.blur = v;
                            ctrl.refresh();
                          },
                          (_) => ctrl.commitEffectChange(),
                        ),
                        const SizedBox(height: 10),
                      ],
                      _sectionTitle('Timing, Audio & Fades'),
                      _slider(
                        'Speed',
                        '${clip.effects.speed.toStringAsFixed(2)}x',
                        clip.effects.speed,
                        0.25,
                        3.0,
                        (v) {
                          clip.effects.speed = v;
                          ctrl.refresh();
                        },
                        (_) => ctrl.commitEffectChange(),
                      ),
                      if (clip.type == MediaType.video ||
                          clip.type == MediaType.audio)
                        _slider(
                          'Volume',
                          '${(clip.effects.volume * 100).round()}%',
                          clip.effects.volume,
                          0.0,
                          2.0,
                          (v) {
                            clip.effects.volume = v;
                            ctrl.refresh();
                          },
                          (_) => ctrl.commitEffectChange(),
                        ),
                      _slider(
                        'Fade In',
                        '${clip.effects.fadeInSec.toStringAsFixed(1)}s',
                        clip.effects.fadeInSec,
                        0.0,
                        4.0,
                        (v) {
                          clip.effects.fadeInSec = v;
                          ctrl.refresh();
                        },
                        (_) => ctrl.commitEffectChange(),
                      ),
                      _slider(
                        'Fade Out',
                        '${clip.effects.fadeOutSec.toStringAsFixed(1)}s',
                        clip.effects.fadeOutSec,
                        0.0,
                        4.0,
                        (v) {
                          clip.effects.fadeOutSec = v;
                          ctrl.refresh();
                        },
                        (_) => ctrl.commitEffectChange(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
          color: FyrTheme.accentColor,
        ),
      ),
    );
  }

  Widget _slider(
    String label,
    String valText,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    ValueChanged<double> onChangeEnd,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: FyrTheme.textColorMuted)),
            Text(valText,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: FyrTheme.textColor)),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 9),
            activeTrackColor: FyrTheme.accentColor,
            thumbColor: FyrTheme.accentColor,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ),
      ],
    );
  }
}
