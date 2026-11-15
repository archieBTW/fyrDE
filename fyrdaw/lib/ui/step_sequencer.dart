import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/daw_clip.dart';
import 'package:fyrdaw/models/midi_note.dart';
import 'package:fyrdaw/models/track.dart';

class StepSequencerWidget extends StatefulWidget {
  final Track track;
  final MidiClip clip;
  final int bpm;
  final int timeSigTop;
  final double playheadPosition;
  final VoidCallback? onChangeStart;
  final VoidCallback onNotesChanged;
  final VoidCallback? onSwitchToPianoRoll;

  const StepSequencerWidget({
    super.key,
    required this.track,
    required this.clip,
    required this.bpm,
    required this.timeSigTop,
    required this.playheadPosition,
    this.onChangeStart,
    required this.onNotesChanged,
    this.onSwitchToPianoRoll,
  });

  @override
  State<StepSequencerWidget> createState() => _StepSequencerWidgetState();
}

class _StepSequencerWidgetState extends State<StepSequencerWidget> {
  int _stepsCount = 16;
  double _swing = 0.0; // 0.0..0.5 (shifts odd 16th steps late)
  final ScrollController _scrollController = ScrollController();

  double get _beatWidth => 100.0 * 60.0 / widget.bpm;
  double get _stepWidth => _beatWidth / 4.0; // 16th note

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double _stepStartTime(int step) {
    final swingOffset = step.isOdd ? (_swing * _stepWidth * 0.5) : 0.0;
    return widget.clip.startOffset + step * _stepWidth + swingOffset;
  }

  MidiNote? _findNoteAtStep(int midiPitch, int step) {
    final targetStart = widget.clip.startOffset + step * _stepWidth;
    final tol = _stepWidth * 0.45;
    for (final n in widget.clip.notes) {
      if (n.pitch == midiPitch && (n.start - targetStart).abs() <= tol) {
        return n;
      }
    }
    return null;
  }

  void _toggleStep(int padIndex, int step) {
    final pad = widget.track.samplerPads[padIndex];
    final midiPitch = pad?.midiNote ?? (36 + padIndex);
    widget.onChangeStart?.call();

    final existing = _findNoteAtStep(midiPitch, step);
    if (existing != null) {
      widget.clip.notes.remove(existing);
    } else {
      widget.clip.notes.add(
        MidiNote(
          pitch: midiPitch,
          start: _stepStartTime(step),
          length: max(8.0, _stepWidth * 0.85),
          velocity: 105,
        ),
      );
      pad?.play(105, widget.track.bus, widget.track.volume, widget.track.pan);
    }

    final neededLen = _stepsCount * _stepWidth;
    if (widget.clip.length < neededLen) {
      widget.clip.length = neededLen;
      if (widget.clip.originalLength < neededLen) {
        widget.clip.originalLength = neededLen;
      }
    }
    widget.onNotesChanged();
  }

  void _cycleStepVelocity(int padIndex, int step) {
    final pad = widget.track.samplerPads[padIndex];
    final midiPitch = pad?.midiNote ?? (36 + padIndex);
    final existing = _findNoteAtStep(midiPitch, step);
    if (existing == null) {
      _toggleStep(padIndex, step);
      return;
    }
    widget.onChangeStart?.call();
    if (existing.velocity < 80) {
      existing.velocity = 105;
    } else if (existing.velocity < 120) {
      existing.velocity = 127;
    } else {
      existing.velocity = 55;
    }
    widget.onNotesChanged();
  }

  void _applySwingToClip() {
    widget.onChangeStart?.call();
    for (int step = 0; step < _stepsCount; step++) {
      final baseStart = widget.clip.startOffset + step * _stepWidth;
      final swungStart = _stepStartTime(step);
      final tol = _stepWidth * 0.45;
      for (final n in widget.clip.notes) {
        if ((n.start - baseStart).abs() <= tol) {
          n.start = swungStart;
        }
      }
    }
    widget.onNotesChanged();
  }

  void _generateGroovePattern() {
    widget.onChangeStart?.call();
    widget.clip.notes.clear();
    final rng = Random();

    // Populate loaded pads (or pads 0..3 as default slots)
    final loadedPads = <int>[];
    for (int i = 0; i < 16; i++) {
      if (widget.track.samplerPads[i]?.filePath != null) {
        loadedPads.add(i);
      }
    }
    final activePads = loadedPads.isNotEmpty ? loadedPads : [0, 1, 2, 3];

    for (int idx = 0; idx < activePads.length; idx++) {
      final padIdx = activePads[idx];
      final midiPitch = widget.track.samplerPads[padIdx]?.midiNote ?? (36 + padIdx);
      final padLabelLower =
          (widget.track.samplerPads[padIdx]?.name ?? '').toLowerCase();
      final isKick = padIdx == 0 || padLabelLower.contains('kick');
      final isSnare =
          padIdx == 2 ||
          padLabelLower.contains('snare') ||
          (activePads.length <= 4 && idx == 1);
      final isHat =
          padIdx == 6 ||
          padLabelLower.contains('chh') ||
          padLabelLower.contains('closed hat') ||
          (activePads.length <= 4 && idx == 2);
      for (int s = 0; s < _stepsCount; s++) {
        bool hit = false;
        int vel = 100;
        if (isKick) {
          // Kick Euclidean 4-on-floor + occasional syncopation
          hit = (s % 4 == 0) || (s % 16 == 14 && rng.nextBool());
          vel = (s % 4 == 0) ? 122 : 90;
        } else if (isSnare) {
          // Snare backbeat
          hit = (s % 8 == 4);
          vel = 118;
        } else if (isHat) {
          // Hi-hat 8ths/16ths
          hit = (s % 2 == 0) || rng.nextDouble() < 0.35;
          vel = (s % 2 == 0) ? 95 : 65;
        } else if (rng.nextDouble() < 0.14) {
          hit = true;
          vel = 75 + rng.nextInt(35);
        }
        if (hit) {
          widget.clip.notes.add(
            MidiNote(
              pitch: midiPitch,
              start: _stepStartTime(s),
              length: max(8.0, _stepWidth * 0.85),
              velocity: vel,
            ),
          );
        }
      }
    }
    widget.onNotesChanged();
  }

  @override
  Widget build(BuildContext context) {
    final localPlayhead =
        widget.playheadPosition - widget.clip.start + widget.clip.startOffset;
    final currentStep = (localPlayhead >= 0 && localPlayhead < _stepsCount * _stepWidth)
        ? ((localPlayhead - widget.clip.startOffset) / _stepWidth).floor()
        : -1;

    return Column(
      children: [
        Container(
          height: 36,
          width: double.infinity,
          color: panelLight,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
              Icon(Icons.grid_view, size: 14, color: widget.track.color),
              const SizedBox(width: 6),
              Text(
                'Step Sequencer',
                style: TextStyle(
                  color: textMain,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 12),
              if (widget.onSwitchToPianoRoll != null)
                TextButton.icon(
                  onPressed: widget.onSwitchToPianoRoll,
                  icon: Icon(Icons.piano, size: 14, color: lavenderAccent),
                  label: Text(
                    'Piano Roll',
                    style: TextStyle(color: lavenderLight, fontSize: 11),
                  ),
                ),
              const SizedBox(width: 8),
              ToggleButtons(
                isSelected: [_stepsCount == 16, _stepsCount == 32],
                onPressed: (idx) {
                  setState(() => _stepsCount = idx == 0 ? 16 : 32);
                },
                constraints: const BoxConstraints(minHeight: 24, minWidth: 36),
                borderRadius: BorderRadius.circular(4),
                selectedColor: Colors.white,
                fillColor: lavenderAccent.withValues(alpha: 0.45),
                color: textMuted,
                children: const [
                  Text('16', style: TextStyle(fontSize: 11)),
                  Text('32', style: TextStyle(fontSize: 11)),
                ],
              ),
              const SizedBox(width: 16),
              Text('Swing:', style: TextStyle(color: textMuted, fontSize: 11)),
              SizedBox(
                width: 90,
                child: Slider(
                  value: _swing,
                  min: 0.0,
                  max: 0.6,
                  activeColor: lavenderAccent,
                  onChanged: (v) => setState(() => _swing = v),
                  onChangeEnd: (_) => _applySwingToClip(),
                ),
              ),
              Text(
                '${(_swing * 100).round()}%',
                style: TextStyle(color: textMuted, fontSize: 10),
              ),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: _generateGroovePattern,
                icon: Icon(Icons.auto_awesome, size: 14, color: Colors.amberAccent),
                label: Text(
                  'Fill Groove',
                  style: TextStyle(color: textMain, fontSize: 11),
                ),
              ),
              TextButton(
                onPressed: () {
                  widget.onChangeStart?.call();
                  widget.clip.notes.clear();
                  widget.onNotesChanged();
                },
                child: Text(
                  'Clear',
                  style: TextStyle(color: Colors.redAccent, fontSize: 11),
                ),
              ),
            ],
            ),
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: ListView.builder(
              controller: _scrollController,
              itemCount: 16,
              itemBuilder: (context, rowIdx) {
                final padIndex = rowIdx;
                final pad = widget.track.samplerPads[padIndex];
                final midiPitch = pad?.midiNote ?? (36 + padIndex);
                final rawName = pad?.filePath?.split(RegExp(r'[/\\]')).last;
                final padLabel =
                    pad?.name ??
                    (rawName != null && rawName.isNotEmpty
                        ? rawName.replaceAll(RegExp(r'\.[^.]+$'), '')
                        : 'Pad ${padIndex + 1}');

                return Container(
                  height: 28,
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: borderMain, width: 0.5),
                    ),
                    color: rowIdx.isEven
                        ? bgDark
                        : panelDark.withValues(alpha: 0.6),
                  ),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: () => pad?.play(
                          110,
                          widget.track.bus,
                          widget.track.volume,
                          widget.track.pan,
                          widget.track.samplerPads.values,
                        ),
                        child: Container(
                          width: 130,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          decoration: BoxDecoration(
                            color: panelDark,
                            border: Border(
                              right: BorderSide(color: borderMain),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 14,
                                decoration: BoxDecoration(
                                  color: pad?.filePath != null
                                      ? widget.track.color
                                      : textFaint,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  padLabel,
                                  style: TextStyle(
                                    color: pad?.filePath != null
                                        ? textMain
                                        : textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: Row(
                          children: List.generate(_stepsCount, (step) {
                            final note = _findNoteAtStep(midiPitch, step);
                            final isOn = note != null;
                            final isBeatGroupEven = ((step ~/ 4) % 2) == 0;
                            final isCurrent = step == currentStep;
                            final velRatio = isOn
                                ? (note.velocity / 127.0).clamp(0.25, 1.0)
                                : 0.0;

                            return Expanded(
                              child: GestureDetector(
                                onTap: () => _toggleStep(padIndex, step),
                                onSecondaryTap: () =>
                                    _cycleStepVelocity(padIndex, step),
                                child: Container(
                                  margin: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    color: isOn
                                        ? widget.track.color.withValues(
                                            alpha: 0.35 + velRatio * 0.65,
                                          )
                                        : (isBeatGroupEven
                                              ? panelLight.withValues(alpha: 0.7)
                                              : panelDark.withValues(alpha: 0.7)),
                                    borderRadius: BorderRadius.circular(3),
                                    border: Border.all(
                                      color: isCurrent
                                          ? Colors.cyanAccent
                                          : (isOn
                                                ? Colors.white.withValues(
                                                    alpha: 0.6,
                                                  )
                                                : borderMain),
                                      width: isCurrent ? 1.5 : 0.8,
                                    ),
                                  ),
                                  child: isOn
                                      ? Align(
                                          alignment: Alignment.bottomCenter,
                                          child: FractionallySizedBox(
                                            heightFactor: velRatio,
                                            widthFactor: 1.0,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.28,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(2),
                                              ),
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
