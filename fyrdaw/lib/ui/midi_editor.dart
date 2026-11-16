import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/models/daw_clip.dart';
import 'package:fyrdaw/models/track.dart';
import 'package:fyrdaw/models/midi_note.dart';
import 'package:fyrdaw/ui/painters.dart';
import 'package:fyrdaw/ui/step_sequencer.dart';
import 'package:fyrdaw/ui/synth_rack_panel.dart';
import 'package:fyrdaw/utils/audio_utils.dart';

const Map<String, List<int>> kMidiScales = {
  'Off': [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
  'Major': [0, 2, 4, 5, 7, 9, 11],
  'Minor': [0, 2, 3, 5, 7, 8, 10],
  'Harmonic Min': [0, 2, 3, 5, 7, 8, 11],
  'Dorian': [0, 2, 3, 5, 7, 9, 10],
  'Pentatonic': [0, 3, 5, 7, 10],
  'Blues': [0, 3, 5, 6, 7, 10],
};

const List<String> kRootNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

class MidiEditorWidget extends StatefulWidget {
  final Track? track;
  final MidiClip clip;
  final bool snapToGrid;
  final double snapResolution;
  final double zoomX;
  final int bpm;
  final int timeSigTop;
  final List<MidiNote> selectedMidiNotes;
  final List<MidiNote> ghostNotes;
  final ValueChanged<List<MidiNote>> onSelectionChanged;
  final VoidCallback onNotesChanged;
  final VoidCallback? onChangeStart;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final double playheadPosition;
  final ValueChanged<double> onPlayheadChanged;
  final List<MidiDevice> midiDevices;
  final VoidCallback onCopy;
  final VoidCallback onPaste;
  final VoidCallback onInstrumentDialogRequested;
  final VoidCallback onMidiInputDialogRequested;
  final VoidCallback? onSynthSettingsChanged;
  final List<AudioClip> grooveAudioClips;
  final VoidCallback? onImportMidi;
  final VoidCallback? onExportMidi;

  const MidiEditorWidget({
    super.key,
    required this.track,
    required this.clip,
    required this.snapToGrid,
    required this.snapResolution,
    required this.zoomX,
    required this.bpm,
    required this.timeSigTop,
    required this.selectedMidiNotes,
    this.ghostNotes = const [],
    required this.onSelectionChanged,
    required this.onNotesChanged,
    this.onChangeStart,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.playheadPosition,
    required this.onPlayheadChanged,
    required this.midiDevices,
    required this.onCopy,
    required this.onPaste,
    required this.onInstrumentDialogRequested,
    required this.onMidiInputDialogRequested,
    this.onSynthSettingsChanged,
    this.grooveAudioClips = const [],
    this.onImportMidi,
    this.onExportMidi,
  });

  @override
  State<MidiEditorWidget> createState() => _MidiEditorWidgetState();
}

class _MidiEditorWidgetState extends State<MidiEditorWidget> {
  final double _pitchHeight = 20.0;
  final int _velocity = 100;
  final ScrollController _verticalController1 = ScrollController();
  final ScrollController _verticalController2 = ScrollController();

  bool _isSelecting = false;
  double? _selStartX, _selStartY;
  double? _selEndX, _selEndY;

  String _scaleName = 'Off';
  int _rootPitchClass = 0;
  bool _scaleLock = false;
  bool _showGhostNotes = true;
  bool _showVelocityLane = true;
  bool _stepSequencerMode = false;
  bool _showSynthRack = false;
  bool _showArpBar = false;

  final Map<MidiNote, int> _dragInitialPitches = {};
  List<MidiNote> _activeDragNotes = [];
  double _dragTotalDy = 0.0;
  final Map<int, SoundHandle> _previewKeyHandles = {};

  Set<int>? get _activeScalePitchClasses {
    if (_scaleName == 'Off') return null;
    final intervals = kMidiScales[_scaleName] ?? kMidiScales['Off']!;
    return intervals.map((i) => (_rootPitchClass + i) % 12).toSet();
  }

  int _snapPitchToScale(int midiPitch) {
    final scaleSet = _activeScalePitchClasses;
    if (scaleSet == null || !_scaleLock) return midiPitch;
    if (scaleSet.contains(midiPitch % 12)) return midiPitch;
    for (int offset = 1; offset <= 6; offset++) {
      if (midiPitch + offset <= 127 &&
          scaleSet.contains((midiPitch + offset) % 12)) {
        return midiPitch + offset;
      }
      if (midiPitch - offset >= 0 &&
          scaleSet.contains((midiPitch - offset) % 12)) {
        return midiPitch - offset;
      }
    }
    return midiPitch;
  }

  int get _numRows => widget.track?.type == TrackType.sampler ? 16 : 128;

  String _getInstrumentName(int index) => getInstrumentName(index);

  int _getMidiPitchFromRow(int row) {
    if (widget.track?.type == TrackType.sampler) {
      int padIndex = 15 - row;
      if (padIndex < 0 || padIndex > 15) return -1;
      return widget.track!.samplerPads[padIndex]?.midiNote ?? (36 + padIndex);
    }
    return 127 - row;
  }

  int _getRowFromMidiPitch(int pitch) {
    if (widget.track?.type == TrackType.sampler) {
      for (int i = 0; i < 16; i++) {
        if ((widget.track!.samplerPads[i]?.midiNote ?? (36 + i)) == pitch) {
          return 15 - i;
        }
      }
      return -1;
    }
    return 127 - pitch;
  }

  @override
  void initState() {
    super.initState();
    _verticalController1.addListener(() {
      if (_verticalController2.hasClients &&
          !_verticalController1.position.outOfRange &&
          _verticalController1.offset != _verticalController2.offset) {
        _verticalController2.jumpTo(_verticalController1.offset);
      }
    });
    _verticalController2.addListener(() {
      if (_verticalController1.hasClients &&
          !_verticalController2.position.outOfRange &&
          _verticalController2.offset != _verticalController1.offset) {
        _verticalController1.jumpTo(_verticalController2.offset);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_verticalController1.hasClients) {
        if (widget.track?.type == TrackType.sampler) {
          _verticalController1.jumpTo(0);
        } else {
          _verticalController1.jumpTo(60 * _pitchHeight);
        }
      }
    });
  }

  @override
  void dispose() {
    if (widget.track != null) {
      final releaseMs = getInstrumentPreset(
        widget.track!.instrumentIndex,
      ).releaseMs;
      for (final h in _previewKeyHandles.values) {
        releaseInstrumentNote(h, releaseMs: releaseMs);
      }
    }
    _previewKeyHandles.clear();
    _verticalController1.dispose();
    _verticalController2.dispose();
    super.dispose();
  }

  void _startPreviewKey(int midiPitch) {
    if (widget.track == null || !SoLoud.instance.isInitialized) return;
    _stopPreviewKey(midiPitch);
    if (widget.track!.type == TrackType.sampler) {
      var pad = widget.track!.samplerPads.values
          .where((p) => p.midiNote == midiPitch)
          .firstOrNull;
      if (pad != null) {
        pad.play(
          _velocity.toDouble(),
          widget.track!.bus,
          widget.track!.volume,
          widget.track!.pan,
        );
      }
    } else {
      final h = triggerInstrumentNote(widget.track!, midiPitch, _velocity);
      if (h != null) {
        _previewKeyHandles[midiPitch] = h;
      }
    }
  }

  void _stopPreviewKey(int midiPitch) {
    final h = _previewKeyHandles.remove(midiPitch);
    if (h != null && widget.track != null) {
      final releaseMs = getInstrumentPreset(
        widget.track!.instrumentIndex,
      ).releaseMs;
      releaseInstrumentNote(h, releaseMs: releaseMs);
    }
  }

  void _addNoteAt(Offset localPosition) {
    double realX = localPosition.dx / widget.zoomX;
    if (realX < 0) return;

    int row = (localPosition.dy / _pitchHeight).floor();
    int midiPitch = _getMidiPitchFromRow(row);
    if (midiPitch == -1) return;
    if (widget.track?.type != TrackType.sampler) {
      midiPitch = _snapPitchToScale(midiPitch);
    }

    double start = widget.snapToGrid
        ? (realX / widget.snapResolution).floor() * widget.snapResolution
        : realX;
    final double noteLen = 100.0 * 60.0 / widget.bpm;
    widget.onChangeStart?.call();
    if (start + noteLen > widget.clip.length) {
      final double barLen = noteLen * max(1, widget.timeSigTop);
      final double needed =
          ((start + noteLen) / barLen).ceil() * barLen;
      widget.clip.length = max(widget.clip.length, needed);
      if (widget.clip.startOffset + widget.clip.length >
          widget.clip.originalLength) {
        widget.clip.originalLength =
            widget.clip.startOffset + widget.clip.length;
      }
    }
    widget.clip.notes.add(
      MidiNote(
        pitch: midiPitch,
        start: start,
        length: noteLen,
        velocity: _velocity,
      ),
    );
    widget.onNotesChanged();

    if (widget.track != null && SoLoud.instance.isInitialized) {
      if (widget.track!.type == TrackType.sampler) {
        var pad = widget.track!.samplerPads.values
            .where((p) => p.midiNote == midiPitch)
            .firstOrNull;
        if (pad != null) {
          pad.play(
            _velocity.toDouble(),
            widget.track!.bus,
            widget.track!.volume,
            widget.track!.pan,
          );
        }
      } else {
        final handle = triggerInstrumentNote(
          widget.track!,
          midiPitch,
          _velocity,
        );
        if (handle != null) {
          final preset = getInstrumentPreset(widget.track!.instrumentIndex);
          final int dur = max((60000 / widget.bpm).round(), 350);
          Timer(Duration(milliseconds: dur), () {
            releaseInstrumentNote(handle, releaseMs: preset.releaseMs);
          });
        }
      }
    }
  }

  void _showNoteMenu(Offset pos, MidiNote note) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        PopupMenuItem(value: 'copy', child: Text('Copy')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('Delete Note')),
        PopupMenuItem(value: 'split', child: Text('Split in Half')),
      ],
    );
    if (result == 'copy') {
      widget.onCopy();
    } else if (result == 'delete') {
      setState(() {
        widget.onChangeStart?.call();
        widget.clip.notes.remove(note);
        widget.onNotesChanged();
      });
    } else if (result == 'split') {
      double localPh = widget.playheadPosition - widget.clip.start;
      if (localPh > note.start && localPh < note.start + note.length) {
        setState(() {
          widget.onChangeStart?.call();
          double newLen1 = localPh - note.start;
          double newLen2 = note.length - newLen1;
          note.length = newLen1;
          widget.clip.notes.add(
            MidiNote(
              pitch: note.pitch,
              start: note.start + newLen1,
              length: newLen2,
              velocity: note.velocity,
            ),
          );
          widget.onNotesChanged();
        });
      }
    }
  }

  void _showEmptyMenu(Offset pos) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [PopupMenuItem(value: 'paste', child: Text('Paste'))],
    );
    if (result == 'paste') {
      widget.onPaste();
    }
  }

  void _applyChordOrTransform(String op) {
    final beatW = 100.0 * 60.0 / widget.bpm;
    if (op == 'transpose_up' || op == 'transpose_down') {
      final delta = op == 'transpose_up' ? 12 : -12;
      final targets = widget.selectedMidiNotes.isNotEmpty
          ? widget.selectedMidiNotes
          : widget.clip.notes;
      if (targets.isEmpty) return;
      widget.onChangeStart?.call();
      for (final n in targets) {
        n.pitch = (n.pitch + delta).clamp(0, 127);
      }
      widget.onNotesChanged();
      return;
    }

    if (op == 'strum') {
      final notesToStrum = widget.selectedMidiNotes.isNotEmpty
          ? List<MidiNote>.from(widget.selectedMidiNotes)
          : List<MidiNote>.from(widget.clip.notes);
      if (notesToStrum.isEmpty) return;
      widget.onChangeStart?.call();
      // Group notes starting within 5 timeline units and stagger upward by 3 units (~30ms)
      notesToStrum.sort((a, b) {
        final dt = a.start.compareTo(b.start);
        return dt != 0 ? dt : a.pitch.compareTo(b.pitch);
      });
      int chordPos = 0;
      double prevStart = notesToStrum.first.start;
      for (final n in notesToStrum) {
        if ((n.start - prevStart).abs() <= 5.0) {
          n.start = prevStart + chordPos * 3.0;
          chordPos++;
        } else {
          prevStart = n.start;
          chordPos = 1;
        }
      }
      widget.onNotesChanged();
      return;
    }

    if (op.startsWith('prog_')) {
      widget.onChangeStart?.call();
      final rootBase = 60 + _rootPitchClass;
      final barLen = beatW * widget.timeSigTop;
      final progression = switch (op) {
        'prog_pop' => [
          [0, 4, 7],
          [7, 11, 14],
          [9, 12, 16],
          [5, 9, 12],
        ],
        'prog_lofi' => [
          [2, 5, 9, 12],
          [7, 11, 14, 17],
          [0, 4, 7, 11],
          [0, 4, 7, 11],
        ],
        'prog_andalusian' => [
          [9, 12, 16],
          [7, 11, 14],
          [5, 9, 12],
          [4, 8, 11],
        ],
        'prog_neosoul' => [
          [0, 3, 7, 10, 14],
          [5, 8, 12, 15, 19],
          [10, 14, 17, 20, 24],
          [7, 11, 14, 17, 20],
        ],
        _ => [
          [0, 4, 7],
        ],
      };
      for (int c = 0; c < progression.length; c++) {
        final chordStart = c * barLen;
        if (chordStart >= widget.clip.length) break;
        final chordLen = min(barLen * 0.96, widget.clip.length - chordStart);
        for (final iv in progression[c]) {
          widget.clip.notes.add(
            MidiNote(
              pitch: (rootBase + iv).clamp(0, 127),
              start: chordStart,
              length: max(12.0, chordLen),
              velocity: 92,
            ),
          );
        }
      }
      widget.onNotesChanged();
      return;
    }

    final intervals = switch (op) {
      'major' => [0, 4, 7],
      'minor' => [0, 3, 7],
      'dom7' => [0, 4, 7, 10],
      'sus4' => [0, 5, 7],
      'arp_up' => [0, 4, 7, 12],
      _ => [0, 4, 7],
    };

    widget.onChangeStart?.call();
    if (widget.selectedMidiNotes.isNotEmpty) {
      final roots = List<MidiNote>.from(widget.selectedMidiNotes);
      for (final root in roots) {
        if (op == 'arp_up') {
          final stepLen = max(12.0, root.length / intervals.length);
          root.length = stepLen;
          for (int i = 1; i < intervals.length; i++) {
            widget.clip.notes.add(
              MidiNote(
                pitch: (root.pitch + intervals[i]).clamp(0, 127),
                start: root.start + stepLen * i,
                length: stepLen,
                velocity: root.velocity,
              ),
            );
          }
        } else {
          for (int i = 1; i < intervals.length; i++) {
            widget.clip.notes.add(
              MidiNote(
                pitch: (root.pitch + intervals[i]).clamp(0, 127),
                start: root.start,
                length: root.length,
                velocity: root.velocity,
              ),
            );
          }
        }
      }
    } else {
      final basePitch = 60 + _rootPitchClass;
      final localPh = (widget.playheadPosition - widget.clip.start)
          .clamp(0.0, max<double>(0.0, widget.clip.length - beatW))
          .toDouble();
      final double start = widget.snapToGrid
          ? (localPh / widget.snapResolution).round() * widget.snapResolution
          : localPh;
      if (op == 'arp_up') {
        final stepLen = beatW / 2.0;
        for (int i = 0; i < intervals.length; i++) {
          widget.clip.notes.add(
            MidiNote(
              pitch: (basePitch + intervals[i]).clamp(0, 127),
              start: start + stepLen * i,
              length: stepLen,
              velocity: 95,
            ),
          );
        }
      } else {
        for (final iv in intervals) {
          widget.clip.notes.add(
            MidiNote(
              pitch: (basePitch + iv).clamp(0, 127),
              start: start,
              length: beatW * 2,
              velocity: 95,
            ),
          );
        }
      }
    }
    widget.onNotesChanged();
  }

  void _paintVelocityAt(Offset localPos, double laneHeight) {
    final xUnits = localPos.dx / widget.zoomX;
    final newVel =
        ((1.0 - (localPos.dy / laneHeight)).clamp(0.05, 1.0) * 127.0).round();
    final tol = max(18.0, widget.snapResolution * 0.65);
    bool changed = false;
    for (final n in widget.clip.notes) {
      if ((n.start - xUnits).abs() <= tol ||
          (xUnits >= n.start && xUnits <= n.start + n.length)) {
        if (n.velocity != newVel) {
          n.velocity = newVel;
          changed = true;
        }
      }
    }
    if (changed) widget.onNotesChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_stepSequencerMode && widget.track?.type == TrackType.sampler) {
      return StepSequencerWidget(
        track: widget.track!,
        clip: widget.clip,
        bpm: widget.bpm,
        timeSigTop: widget.timeSigTop,
        playheadPosition: widget.playheadPosition,
        onChangeStart: widget.onChangeStart,
        onNotesChanged: widget.onNotesChanged,
        onSwitchToPianoRoll: () => setState(() => _stepSequencerMode = false),
      );
    }
    double beatW = 100.0 * 60.0 / widget.bpm * widget.zoomX;
    final double gridW = max(2000.0, widget.clip.length * widget.zoomX + 800.0);
    return Column(
      children: [
        Container(
          height: 40,
          width: double.infinity,
          color: panelDark,
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
              if (widget.track != null &&
                  widget.track!.type != TrackType.sampler) ...[
                Text('Instrument: ', style: TextStyle(color: textMuted)),
                SizedBox(width: 8),
                InkWell(
                  onTap: widget.onInstrumentDialogRequested,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: panelLight,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: borderMain),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _getInstrumentName(widget.track!.instrumentIndex),
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          Icons.keyboard_arrow_down,
                          color: textMuted,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 16),
              ],
              Text('MIDI Input: ', style: TextStyle(color: textMuted)),
              SizedBox(width: 8),
              InkWell(
                onTap: widget.onMidiInputDialogRequested,
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: panelLight,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: borderMain),
                  ),
                  child: Row(
                    children: [
                      Text(
                        widget.track!.midiInputId == null
                            ? 'All Inputs'
                            : 'Midi Device',
                        style: TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      SizedBox(width: 8),
                      Icon(
                        Icons.keyboard_arrow_down,
                        color: textMuted,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.track?.type == TrackType.sampler) ...[
                TextButton.icon(
                  onPressed: () => setState(() => _stepSequencerMode = true),
                  icon: Icon(Icons.grid_view, size: 14, color: lavenderAccent),
                  label: Text(
                    'Step Sequencer',
                    style: TextStyle(color: lavenderLight, fontSize: 11),
                  ),
                ),
                SizedBox(width: 8),
              ] else ...[
                DropdownButton<int>(
                  value: _rootPitchClass,
                  underline: SizedBox(),
                  dropdownColor: panelDark,
                  style: TextStyle(color: textMain, fontSize: 11),
                  items: List.generate(
                    12,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text(kRootNames[i]),
                    ),
                  ),
                  onChanged: (v) {
                    if (v != null) setState(() => _rootPitchClass = v);
                  },
                ),
                DropdownButton<String>(
                  value: _scaleName,
                  underline: SizedBox(),
                  dropdownColor: panelDark,
                  style: TextStyle(color: textMain, fontSize: 11),
                  items: kMidiScales.keys
                      .map(
                        (s) => DropdownMenuItem(value: s, child: Text(s)),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _scaleName = v);
                  },
                ),
                if (_scaleName != 'Off')
                  Tooltip(
                    message: 'Snap new & dragged notes to scale',
                    child: InkWell(
                      onTap: () => setState(() => _scaleLock = !_scaleLock),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: _scaleLock
                              ? lavenderAccent.withValues(alpha: 0.35)
                              : panelLight,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: _scaleLock ? lavenderAccent : borderMain,
                          ),
                        ),
                        child: Text(
                          'Lock',
                          style: TextStyle(
                            color: _scaleLock ? Colors.white : textMuted,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                SizedBox(width: 6),
                PopupMenuButton<String>(
                  tooltip: 'Chord & Arp Tools',
                  onSelected: _applyChordOrTransform,
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'major', child: Text('Stamp Major Chord')),
                    PopupMenuItem(value: 'minor', child: Text('Stamp Minor Chord')),
                    PopupMenuItem(value: 'dom7', child: Text('Stamp Dom 7th')),
                    PopupMenuItem(value: 'sus4', child: Text('Stamp Sus4')),
                    PopupMenuItem(value: 'arp_up', child: Text('Arpeggiate Up')),
                    PopupMenuItem(value: 'strum', child: Text('Strum Chords')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'prog_pop', child: Text('Progression: Pop (I-V-vi-IV)')),
                    PopupMenuItem(value: 'prog_lofi', child: Text('Progression: Lo-Fi (ii7-V7-Imaj7)')),
                    PopupMenuItem(value: 'prog_andalusian', child: Text('Progression: Minor Descent')),
                    PopupMenuItem(value: 'prog_neosoul', child: Text('Progression: Neo-Soul 9ths')),
                    PopupMenuDivider(),
                    PopupMenuItem(value: 'transpose_up', child: Text('Transpose +1 Oct')),
                    PopupMenuItem(value: 'transpose_down', child: Text('Transpose -1 Oct')),
                  ],
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: panelLight,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: borderMain),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.auto_fix_high, size: 13, color: lavenderAccent),
                        SizedBox(width: 4),
                        Text('Chords', style: TextStyle(color: textMain, fontSize: 11)),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 6),
                Tooltip(
                  message: 'Toggle Ghost Notes from other MIDI tracks',
                  child: IconButton(
                    icon: Icon(
                      Icons.layers_outlined,
                      size: 17,
                      color: _showGhostNotes ? Colors.cyanAccent : textMuted,
                    ),
                    onPressed: () =>
                        setState(() => _showGhostNotes = !_showGhostNotes),
                  ),
                ),
              ],
              if (widget.track != null &&
                  widget.track!.type != TrackType.sampler) ...[
                TextButton.icon(
                  onPressed: () => setState(() => _showSynthRack = !_showSynthRack),
                  icon: Icon(
                    Icons.tune,
                    size: 14,
                    color: _showSynthRack ? Colors.cyanAccent : textMuted,
                  ),
                  label: Text(
                    'Synth',
                    style: TextStyle(
                      color: _showSynthRack ? Colors.cyanAccent : textMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => _showArpBar = !_showArpBar),
                  icon: Icon(
                    Icons.grain,
                    size: 14,
                    color: (widget.track!.arpSettings.enabled || _showArpBar)
                        ? Colors.amberAccent
                        : textMuted,
                  ),
                  label: Text(
                    'Arp',
                    style: TextStyle(
                      color: (widget.track!.arpSettings.enabled || _showArpBar)
                          ? Colors.amberAccent
                          : textMuted,
                      fontSize: 11,
                    ),
                  ),
                ),
                SizedBox(width: 4),
              ],
              Tooltip(
                message: 'Toggle Velocity Lane',
                child: IconButton(
                  icon: Icon(
                    Icons.equalizer,
                    size: 17,
                    color: _showVelocityLane ? lavenderAccent : textMuted,
                  ),
                  onPressed: () =>
                      setState(() => _showVelocityLane = !_showVelocityLane),
                ),
              ),
              SizedBox(width: 12),
              if (widget.selectedMidiNotes.isNotEmpty) ...[
                Text(
                  'Velocity:',
                  style: TextStyle(color: textMuted, fontSize: 10),
                ),
                SizedBox(
                  width: 100,
                  child: Slider(
                    value: widget.selectedMidiNotes.first.velocity.toDouble(),
                    min: 0,
                    max: 127,
                    activeColor: lavenderAccent,
                    onChangeStart: (_) => widget.onChangeStart?.call(),
                    onChanged: (v) {
                      for (var n in widget.selectedMidiNotes) {
                        n.velocity = v.toInt();
                      }
                      widget.onNotesChanged();
                    },
                  ),
                ),
                SizedBox(width: 8),
              ],
              TextButton(
                onPressed: () {
                  widget.onChangeStart?.call();
                  for (var n in widget.clip.notes) {
                    n.start =
                        (n.start / widget.snapResolution).round() *
                        widget.snapResolution;
                    n.length = max(
                      10.0,
                      (n.length / widget.snapResolution).round() *
                          widget.snapResolution,
                    );
                  }
                  widget.onNotesChanged();
                },
                child: Text('Quantize', style: TextStyle(color: lavenderLight)),
              ),
              SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  widget.onChangeStart?.call();
                  humanizeMidiNotes(widget.clip.notes);
                  widget.onNotesChanged();
                },
                child: Text('Humanize', style: TextStyle(color: lavenderLight)),
              ),
              if (widget.grooveAudioClips.isNotEmpty)
                PopupMenuButton<AudioClip>(
                  tooltip: 'Extract Groove from Audio Clip Transients',
                  color: panelDark,
                  onSelected: (ac) async {
                    final transients = await detectAudioTransients(
                      ac.filePath,
                      maxSlices: 16,
                    );
                    if (transients.isNotEmpty) {
                      widget.onChangeStart?.call();
                      applyGrooveToMidiNotes(
                        widget.clip.notes,
                        transients,
                        widget.clip.length,
                      );
                      widget.onNotesChanged();
                    }
                  },
                  itemBuilder: (_) => widget.grooveAudioClips
                      .map(
                        (ac) => PopupMenuItem<AudioClip>(
                          value: ac,
                          child: Text(
                            ac.name.isNotEmpty ? ac.name : 'Audio Groove',
                          ),
                        ),
                      )
                      .toList(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Text(
                      'Groove',
                      style: TextStyle(color: Colors.cyanAccent, fontSize: 12),
                    ),
                  ),
                ),
              if (widget.onImportMidi != null)
                TextButton.icon(
                  onPressed: widget.onImportMidi,
                  icon: Icon(Icons.file_open, size: 13, color: textMuted),
                  label: Text(
                    'Import .mid',
                    style: TextStyle(color: textMuted, fontSize: 11),
                  ),
                ),
              if (widget.onExportMidi != null)
                TextButton.icon(
                  onPressed: widget.onExportMidi,
                  icon: Icon(Icons.download, size: 13, color: textMuted),
                  label: Text(
                    'Export .mid',
                    style: TextStyle(color: textMuted, fontSize: 11),
                  ),
                ),
              SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.zoom_out, color: textMuted, size: 20),
                onPressed: widget.onZoomOut,
              ),
              IconButton(
                icon: Icon(Icons.zoom_in, color: textMuted, size: 20),
                onPressed: widget.onZoomIn,
              ),
            ],
            ),
          ),
        ),
        if (_showSynthRack &&
            widget.track != null &&
            widget.track!.type != TrackType.sampler)
          SynthRackPanel(
            track: widget.track!,
            onChangeStart: widget.onChangeStart,
            onChanged: () {
              widget.onSynthSettingsChanged?.call();
              widget.onNotesChanged();
            },
          ),
        if (_showArpBar &&
            widget.track != null &&
            widget.track!.type != TrackType.sampler)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: bgDark,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    'ARP FX:',
                    style: TextStyle(
                      color: Colors.amberAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Switch(
                    value: widget.track!.arpSettings.enabled,
                    activeThumbColor: Colors.amberAccent,
                    onChanged: (v) {
                      widget.onChangeStart?.call();
                      setState(() => widget.track!.arpSettings.enabled = v);
                      widget.onNotesChanged();
                    },
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<ArpMode>(
                    value: widget.track!.arpSettings.mode,
                    isDense: true,
                    dropdownColor: panelDark,
                    underline: const SizedBox(),
                    style: TextStyle(color: textMain, fontSize: 11),
                    items: const [
                      DropdownMenuItem(value: ArpMode.up, child: Text('Up')),
                      DropdownMenuItem(value: ArpMode.down, child: Text('Down')),
                      DropdownMenuItem(value: ArpMode.upDown, child: Text('Up/Down')),
                      DropdownMenuItem(value: ArpMode.random, child: Text('Random')),
                    ],
                    onChanged: (m) {
                      if (m != null) {
                        widget.onChangeStart?.call();
                        setState(() => widget.track!.arpSettings.mode = m);
                        widget.onNotesChanged();
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<double>(
                    value: [1.0, 0.5, 0.25, 0.125].contains(
                            widget.track!.arpSettings.rateBeats)
                        ? widget.track!.arpSettings.rateBeats
                        : 0.25,
                    isDense: true,
                    dropdownColor: panelDark,
                    underline: const SizedBox(),
                    style: TextStyle(color: Colors.cyanAccent, fontSize: 11),
                    items: const [
                      DropdownMenuItem(value: 1.0, child: Text('1/4')),
                      DropdownMenuItem(value: 0.5, child: Text('1/8')),
                      DropdownMenuItem(value: 0.25, child: Text('1/16')),
                      DropdownMenuItem(value: 0.125, child: Text('1/32')),
                    ],
                    onChanged: (r) {
                      if (r != null) {
                        widget.onChangeStart?.call();
                        setState(() => widget.track!.arpSettings.rateBeats = r);
                        widget.onNotesChanged();
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<int>(
                    value: widget.track!.arpSettings.octaves.clamp(1, 3),
                    isDense: true,
                    dropdownColor: panelDark,
                    underline: const SizedBox(),
                    style: TextStyle(color: lavenderLight, fontSize: 11),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 Oct')),
                      DropdownMenuItem(value: 2, child: Text('2 Oct')),
                      DropdownMenuItem(value: 3, child: Text('3 Oct')),
                    ],
                    onChanged: (o) {
                      if (o != null) {
                        widget.onChangeStart?.call();
                        setState(() => widget.track!.arpSettings.octaves = o);
                        widget.onNotesChanged();
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  Text('Gate:', style: TextStyle(color: textMuted, fontSize: 10)),
                  SizedBox(
                    width: 84,
                    child: Slider(
                      value: widget.track!.arpSettings.gate.clamp(0.2, 1.0),
                      min: 0.2,
                      max: 1.0,
                      activeColor: Colors.amberAccent,
                      onChanged: (g) {
                        setState(() => widget.track!.arpSettings.gate = g);
                        widget.onNotesChanged();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 60,
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        width: 60,
                        color: bgDark,
                        child: SingleChildScrollView(
                          controller: _verticalController1,
                          child: Column(
                            children: List.generate(_numRows, (index) {
                              int row = index;
                              int midiPitch = _getMidiPitchFromRow(row);
                              if (widget.track?.type == TrackType.sampler) {
                                return Container(
                                  height: _pitchHeight,
                                  decoration: BoxDecoration(
                                    color: panelDark,
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Padding(
                                      padding: EdgeInsets.only(right: 4.0),
                                      child: Text(
                                        'Pad ${15 - row + 1}',
                                        style: TextStyle(
                                          color: textMuted,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              int pitchClass = midiPitch % 12;
                              bool isBlack = [1, 3, 6, 8, 10].contains(pitchClass);
                              bool isPressed = _previewKeyHandles.containsKey(
                                midiPitch,
                              );
                              return GestureDetector(
                                onTapDown: (_) {
                                  _startPreviewKey(midiPitch);
                                  setState(() {});
                                },
                                onTapUp: (_) {
                                  _stopPreviewKey(midiPitch);
                                  setState(() {});
                                },
                                onTapCancel: () {
                                  _stopPreviewKey(midiPitch);
                                  setState(() {});
                                },
                                child: Container(
                                  height: _pitchHeight,
                                  decoration: BoxDecoration(
                                    color: isPressed
                                        ? lavenderAccent
                                        : (isBlack ? Colors.black : Colors.white),
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Colors.grey,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                  child: pitchClass == 0
                                      ? Align(
                                          alignment: Alignment.centerRight,
                                          child: Padding(
                                            padding: EdgeInsets.only(right: 4.0),
                                            child: Text(
                                              'C${(midiPitch ~/ 12) - 1}',
                                              style: TextStyle(
                                                color: isPressed
                                                    ? Colors.white
                                                    : Colors.red,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              );
                            }),
                          ),
                        ),
                      ),
                    ),
                    if (_showVelocityLane)
                      Container(
                        width: 60,
                        height: 68,
                        decoration: BoxDecoration(
                          color: panelDark,
                          border: Border(
                            top: BorderSide(color: borderMain, width: 1.5),
                            right: BorderSide(color: borderMain),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Vel',
                            style: TextStyle(
                              color: textMuted,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: gridW,
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _verticalController2,
                            child: Container(
                              width: gridW,
                              height: _numRows * _pitchHeight,
                              color: panelDark,
                              child: Stack(
                                children: [
                                  CustomPaint(
                                    painter: GridPainter(
                                      pitchHeight: _pitchHeight,
                                      beatWidth: beatW,
                                      timeSigTop: widget.timeSigTop,
                                      scalePitchClasses:
                                          _activeScalePitchClasses,
                                      rootPitchClass: _rootPitchClass,
                                      isSampler:
                                          widget.track?.type ==
                                          TrackType.sampler,
                                    ),
                                    size: Size(gridW, _numRows * _pitchHeight),
                                  ),
                                  if (_showGhostNotes &&
                                      widget.ghostNotes.isNotEmpty)
                                    ...widget.ghostNotes
                                        .where(
                                          (n) =>
                                              _getRowFromMidiPitch(n.pitch) !=
                                              -1,
                                        )
                                        .map(
                                          (gn) => Positioned(
                                            left: gn.start * widget.zoomX,
                                            top:
                                                _getRowFromMidiPitch(gn.pitch) *
                                                    _pitchHeight +
                                                2,
                                            width: max(
                                              4.0,
                                              gn.length * widget.zoomX,
                                            ),
                                            height: _pitchHeight - 4,
                                            child: IgnorePointer(
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  color: Colors.cyanAccent
                                                      .withValues(alpha: 0.16),
                                                  borderRadius:
                                                      BorderRadius.circular(2),
                                                  border: Border.all(
                                                    color: Colors.cyanAccent
                                                        .withValues(alpha: 0.25),
                                                    width: 0.5,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            width: widget.clip.length * widget.zoomX,
                            child: IgnorePointer(
                              child: Container(
                                color: lavenderAccent.withOpacity(0.08),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: GestureDetector(
                              supportedDevices: {
                                PointerDeviceKind.mouse,
                                PointerDeviceKind.touch,
                                PointerDeviceKind.stylus,
                                PointerDeviceKind.invertedStylus,
                              },
                              onTapDown: (d) {
                                double newLocal =
                                    d.localPosition.dx / widget.zoomX;
                                widget.onPlayheadChanged(
                                  widget.clip.start + newLocal,
                                );
                              },
                              onSecondaryTapUp: (d) {
                                double newLocal =
                                    d.localPosition.dx / widget.zoomX;
                                widget.onPlayheadChanged(
                                  widget.clip.start + newLocal,
                                );
                                _showEmptyMenu(d.globalPosition);
                              },
                              onDoubleTapDown: (d) =>
                                  _addNoteAt(d.localPosition),
                              onPanStart: (d) => setState(() {
                                _isSelecting = true;
                                _selStartX = d.localPosition.dx;
                                _selStartY = d.localPosition.dy;
                                _selEndX = d.localPosition.dx;
                                _selEndY = d.localPosition.dy;
                                widget.onSelectionChanged([]);
                              }),
                              onPanUpdate: (d) => setState(() {
                                _selEndX = d.localPosition.dx;
                                _selEndY = d.localPosition.dy;
                                List<MidiNote> newSelection = [];
                                double minX =
                                    min(_selStartX!, _selEndX!) / widget.zoomX;
                                double maxX =
                                    max(_selStartX!, _selEndX!) / widget.zoomX;
                                double minY = min(_selStartY!, _selEndY!);
                                double maxY = max(_selStartY!, _selEndY!);
                                for (var n in widget.clip.notes) {
                                  double nx = n.start;
                                  int r = _getRowFromMidiPitch(n.pitch);
                                  if (r == -1) continue;
                                  double ny = r * _pitchHeight;
                                  if (nx + n.length > minX &&
                                      nx < maxX &&
                                      ny + _pitchHeight > minY &&
                                      ny < maxY) {
                                    newSelection.add(n);
                                  }
                                }
                                widget.onSelectionChanged(newSelection);
                              }),
                              onPanEnd: (d) =>
                                  setState(() => _isSelecting = false),
                              behavior: HitTestBehavior.opaque,
                            ),
                          ),
                          ...widget.clip.notes
                              .where((n) => _getRowFromMidiPitch(n.pitch) != -1)
                              .map((note) {
                                bool isSel = widget.selectedMidiNotes.contains(
                                  note,
                                );
                                return Positioned(
                                  key: ObjectKey(note),
                                  left: note.start * widget.zoomX,
                                  top:
                                      _getRowFromMidiPitch(note.pitch) *
                                      _pitchHeight,
                                  width: note.length * widget.zoomX,
                                  height: _pitchHeight,
                                  child: GestureDetector(
                                    onTap: () => setState(
                                      () => widget.onSelectionChanged([note]),
                                    ),
                                    onSecondaryTapUp: (d) =>
                                        _showNoteMenu(d.globalPosition, note),
                                    onPanStart: (d) {
                                      widget.onChangeStart?.call();
                                      _dragInitialPitches.clear();
                                      _dragTotalDy = 0.0;
                                      final List<MidiNote> sourceTargets =
                                          widget.selectedMidiNotes.contains(
                                            note,
                                          )
                                          ? [...widget.selectedMidiNotes]
                                          : [note];
                                      List<MidiNote> targets = sourceTargets;
                                      if (HardwareKeyboard.instance.isAltPressed) {
                                        targets = [
                                          for (final orig in sourceTargets)
                                            MidiNote.fromJson(orig.toJson()),
                                        ];
                                        widget.clip.notes.addAll(targets);
                                        widget.onSelectionChanged(targets);
                                      }
                                      _activeDragNotes = targets;
                                      for (var n in targets) {
                                        _dragInitialPitches[n] = n.pitch;
                                      }
                                      if (HardwareKeyboard.instance.isAltPressed) {
                                        widget.onNotesChanged();
                                      }
                                    },
                                    onPanUpdate: (d) {
                                      setState(() {
                                        _dragTotalDy += d.delta.dy;
                                        int rowDelta =
                                            (_dragTotalDy / _pitchHeight)
                                                .round();
                                        List<MidiNote> targets =
                                            _activeDragNotes.isNotEmpty
                                            ? _activeDragNotes
                                            : (widget.selectedMidiNotes
                                                      .contains(note)
                                                  ? widget.selectedMidiNotes
                                                  : [note]);
                                        for (var n in targets) {
                                          n.start +=
                                              (d.delta.dx / widget.zoomX);
                                          if (n.start < 0) n.start = 0;
                                          if (_dragInitialPitches.containsKey(
                                            n,
                                          )) {
                                            int oldPitch =
                                                _dragInitialPitches[n]!;
                                            int oldRow = _getRowFromMidiPitch(
                                              oldPitch,
                                            );
                                            if (oldRow != -1) {
                                              int newRow = (oldRow + rowDelta)
                                                  .clamp(0, _numRows - 1);
                                              int newPitch =
                                                  _getMidiPitchFromRow(newRow);
                                              if (widget.track?.type !=
                                                  TrackType.sampler) {
                                                newPitch = _snapPitchToScale(
                                                  newPitch,
                                                );
                                              }
                                              if (newPitch != n.pitch &&
                                                  newPitch != -1) {
                                                n.pitch = newPitch;
                                                try {
                                                  if (widget.track != null &&
                                                      SoLoud
                                                          .instance
                                                          .isInitialized &&
                                                      targets.length == 1) {
                                                    if (widget.track!.type ==
                                                        TrackType.sampler) {
                                                      var pad = widget
                                                          .track!
                                                          .samplerPads
                                                          .values
                                                          .where(
                                                            (p) =>
                                                                p.midiNote ==
                                                                newPitch,
                                                          )
                                                          .firstOrNull;
                                                      if (pad != null) {
                                                        pad.play(
                                                          100.0,
                                                          widget.track!.bus,
                                                          widget.track!.volume,
                                                          widget.track!.pan,
                                                        );
                                                      }
                                                    } else {
                                                      final handle =
                                                          triggerInstrumentNote(
                                                            widget.track!,
                                                            newPitch,
                                                            85,
                                                          );
                                                      if (handle != null) {
                                                        final preset =
                                                            getInstrumentPreset(
                                                              widget
                                                                  .track!
                                                                  .instrumentIndex,
                                                            );
                                                        Timer(
                                                          const Duration(
                                                            milliseconds: 140,
                                                          ),
                                                          () {
                                                            releaseInstrumentNote(
                                                              handle,
                                                              releaseMs: preset
                                                                  .releaseMs,
                                                            );
                                                          },
                                                        );
                                                      }
                                                    }
                                                  }
                                                } catch (_) {}
                                              }
                                            }
                                          }
                                        }
                                      });
                                    },
                                    onPanEnd: (d) {
                                      final List<MidiNote> targets =
                                          _activeDragNotes.isNotEmpty
                                          ? _activeDragNotes
                                          : (widget.selectedMidiNotes.contains(
                                                  note,
                                                )
                                                ? widget.selectedMidiNotes
                                                : [note]);
                                      setState(() {
                                        if (widget.snapToGrid) {
                                          for (var n in targets) {
                                            n.start =
                                                (n.start /
                                                        widget.snapResolution)
                                                    .round() *
                                                widget.snapResolution;
                                          }
                                        }
                                        _activeDragNotes = [];
                                        _dragInitialPitches.clear();
                                      });
                                      widget.onNotesChanged();
                                    },
                                    onPanCancel: () {
                                      _activeDragNotes = [];
                                      _dragInitialPitches.clear();
                                    },
                                    child: Container(
                                      margin: EdgeInsets.all(1),
                                      decoration: BoxDecoration(
                                        color: isSel
                                            ? textMain
                                            : (widget.track?.color ??
                                                    lavenderAccent)
                                                .withValues(
                                                  alpha: (0.4 +
                                                          (note.velocity /
                                                                  127.0) *
                                                              0.6)
                                                      .clamp(0.3, 1.0),
                                                ),
                                        borderRadius: BorderRadius.circular(2),
                                        border: Border.all(
                                          color: isSel
                                              ? Colors.blueAccent
                                              : Colors.white.withValues(
                                                  alpha: 0.25,
                                                ),
                                          width: isSel ? 2 : 0.7,
                                        ),
                                      ),
                                      child: Stack(
                                        children: [
                                          Positioned(
                                            right: 0,
                                            top: 0,
                                            bottom: 0,
                                            width: 10,
                                            child: MouseRegion(
                                              cursor: SystemMouseCursors
                                                  .resizeLeftRight,
                                              child: GestureDetector(
                                                onPanStart: (d) => widget.onChangeStart?.call(),
                                                onPanUpdate: (d) => setState(
                                                  () {
                                                    List<MidiNote> targets =
                                                        widget.selectedMidiNotes
                                                            .contains(note)
                                                        ? widget
                                                              .selectedMidiNotes
                                                        : [note];
                                                    for (var n in targets) {
                                                      n.length +=
                                                          (d.delta.dx /
                                                          widget.zoomX);
                                                      if (n.length < 10) {
                                                        n.length = 10;
                                                      }
                                                    }
                                                  },
                                                ),
                                                onPanEnd: (d) => setState(() {
                                                  if (widget.snapToGrid) {
                                                    List<MidiNote> targets =
                                                        widget.selectedMidiNotes
                                                            .contains(note)
                                                        ? widget
                                                              .selectedMidiNotes
                                                        : [note];
                                                    for (var n in targets) {
                                                      n.length = max(
                                                        10.0,
                                                        (n.length /
                                                                    widget
                                                                        .snapResolution)
                                                                .round() *
                                                            widget
                                                                .snapResolution,
                                                      );
                                                    }
                                                  }
                                                  widget.onNotesChanged();
                                                }),
                                                child: Container(
                                                  color: Colors.transparent,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                          if (_isSelecting &&
                              _selStartX != null &&
                              _selEndX != null)
                            Positioned(
                              left: min(_selStartX!, _selEndX!),
                              top: min(_selStartY!, _selEndY!),
                              width: (_selEndX! - _selStartX!).abs(),
                              height: (_selEndY! - _selStartY!).abs(),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.blueAccent.withOpacity(0.3),
                                  border: Border.all(color: Colors.blueAccent),
                                ),
                              ),
                            ),
                          if (widget.playheadPosition >= widget.clip.start &&
                              widget.playheadPosition <=
                                  widget.clip.start + widget.clip.length)
                            Positioned(
                              left:
                                  (widget.playheadPosition -
                                      widget.clip.start) *
                                  widget.zoomX,
                              top: 0,
                              bottom: 0,
                              width: 2,
                              child: IgnorePointer(
                                child: Container(color: Colors.red),
                              ),
                            ),
                          Positioned(
                            key: const Key('midi_clip_end_handle'),
                            left: max(0.0, widget.clip.length * widget.zoomX - 6),
                            top: 0,
                            bottom: 0,
                            width: 14,
                            child: Tooltip(
                              message: 'Drag to resize MIDI clip length',
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeLeftRight,
                                child: GestureDetector(
                                  supportedDevices: const {
                                    PointerDeviceKind.mouse,
                                    PointerDeviceKind.touch,
                                    PointerDeviceKind.stylus,
                                  },
                                  behavior: HitTestBehavior.opaque,
                                  onHorizontalDragStart: (_) =>
                                      widget.onChangeStart?.call(),
                                  onHorizontalDragUpdate: (d) {
                                    setState(() {
                                      widget.clip.length = max(
                                        20.0,
                                        widget.clip.length +
                                            d.delta.dx / widget.zoomX,
                                      );
                                      if (widget.clip.startOffset +
                                              widget.clip.length >
                                          widget.clip.originalLength) {
                                        widget.clip.originalLength =
                                            widget.clip.startOffset +
                                            widget.clip.length;
                                      }
                                    });
                                    widget.onNotesChanged();
                                  },
                                  onHorizontalDragEnd: (_) {
                                    if (widget.snapToGrid) {
                                      setState(() {
                                        widget.clip.length = max(
                                          20.0,
                                          (widget.clip.length /
                                                      widget.snapResolution)
                                                  .round() *
                                              widget.snapResolution,
                                        );
                                        if (widget.clip.startOffset +
                                                widget.clip.length >
                                            widget.clip.originalLength) {
                                          widget.clip.originalLength =
                                              widget.clip.startOffset +
                                              widget.clip.length;
                                        }
                                      });
                                    }
                                    widget.onNotesChanged();
                                  },
                                  child: Stack(
                                    children: [
                                      Positioned(
                                        left: 6,
                                        top: 0,
                                        bottom: 0,
                                        child: Container(
                                          width: 2,
                                          color: lavenderAccent,
                                        ),
                                      ),
                                      Positioned(
                                        left: 1,
                                        top: 0,
                                        child: Container(
                                          width: 12,
                                          height: 12,
                                          decoration: BoxDecoration(
                                            color: lavenderAccent,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (_showVelocityLane)
                  Container(
                    height: 68,
                    width: gridW,
                    decoration: BoxDecoration(
                      color: bgDark,
                      border: Border(
                        top: BorderSide(color: borderMain, width: 1.5),
                      ),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onPanStart: (d) {
                        widget.onChangeStart?.call();
                        _paintVelocityAt(d.localPosition, 68.0);
                      },
                      onPanUpdate: (d) =>
                          _paintVelocityAt(d.localPosition, 68.0),
                      onTapDown: (d) {
                        widget.onChangeStart?.call();
                        _paintVelocityAt(d.localPosition, 68.0);
                      },
                      child: Stack(
                        children: [
                          Positioned(
                            left: 6,
                            top: 4,
                            child: Text(
                              'VELOCITY (drag to draw)',
                              style: TextStyle(
                                color: textFaint,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          ...widget.clip.notes.map((n) {
                            final h = ((n.velocity / 127.0) * 56.0).clamp(
                              4.0,
                              56.0,
                            );
                            final isSel = widget.selectedMidiNotes.contains(n);
                            final barColor = isSel
                                ? Colors.cyanAccent
                                : (widget.track?.color ?? lavenderAccent);
                            return Positioned(
                              left: n.start * widget.zoomX,
                              bottom: 2,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: barColor,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Container(
                                    width: 2.5,
                                    height: h,
                                    color: barColor.withValues(alpha: 0.85),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ],
  ),
),
],
);
}
}
