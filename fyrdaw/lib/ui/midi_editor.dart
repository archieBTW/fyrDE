import 'dart:ui';
import 'package:flutter/material.dart';
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

class MidiEditorWidget extends StatefulWidget {
  final Track? track;
  final MidiClip clip;
  final bool snapToGrid;
  final double snapResolution;
  final double zoomX;
  final int bpm;
  final int timeSigTop;
  final List<MidiNote> selectedMidiNotes;
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

  final Map<MidiNote, int> _dragInitialPitches = {};
  double _dragTotalDy = 0.0;

  int get _numRows => widget.track?.type == TrackType.sampler ? 16 : 128;

  String _getInstrumentName(int index) {
    switch (index) {
      case 0:
        return 'Square Lead';
      case 1:
        return 'Sawtooth Bass';
      case 2:
        return 'Sine Sub';
      case 3:
        return 'Piano';
      case 4:
        return 'Cello';
      case 5:
        return 'Violin';
      default:
        return 'Square Lead';
    }
  }

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
    _verticalController1.dispose();
    _verticalController2.dispose();
    super.dispose();
  }

  void _addNoteAt(Offset localPosition) {
    double realX = localPosition.dx / widget.zoomX;
    if (realX > widget.clip.length) return;

    int row = (localPosition.dy / _pitchHeight).floor();
    int midiPitch = _getMidiPitchFromRow(row);
    if (midiPitch == -1) return;

    double start = widget.snapToGrid
        ? (realX / widget.snapResolution).floor() * widget.snapResolution
        : realX;
    widget.onChangeStart?.call();
    widget.clip.notes.add(
      MidiNote(
        pitch: midiPitch,
        start: start,
        length: 100.0 * 60.0 / widget.bpm,
        velocity: _velocity,
      ),
    );
    widget.onNotesChanged();

    if (widget.track != null && SoLoud.instance.isInitialized) {
      if (widget.track!.type == TrackType.sampler) {
        var pad = widget.track!.samplerPads.values
            .where((p) => p.midiNote == midiPitch)
            .firstOrNull;
        if (pad != null) pad.play(_velocity.toDouble());
      } else {
        AudioSource src = widget.track!.synthSource ?? globalSynthSound!;
        if (widget.track!.synthSource == null) {
          if (widget.track!.instrumentIndex == 1) {
            src = globalSawSound!;
          } else if (widget.track!.instrumentIndex == 2)
            src = globalSineSound!;
          else if (widget.track!.instrumentIndex == 3)
            src = globalPianoSound!;
          else if (widget.track!.instrumentIndex == 4)
            src = globalCelloSound!;
          else if (widget.track!.instrumentIndex == 5)
            src = globalViolinSound!;
        }
        final handle = widget.track!.bus!.play(src, volume: _velocity / 127.0);
        int basePitch = 69;
        if (widget.track!.instrumentIndex == 3) {
          basePitch = 60;
        } else if (widget.track!.instrumentIndex == 4)
          basePitch = 48;
        else if (widget.track!.instrumentIndex == 5)
          basePitch = 60;
        double speed = pow(2.0, (midiPitch - basePitch) / 12.0) as double;
        SoLoud.instance.setRelativePlaySpeed(handle, speed);
        int dur = max(400, 50);
        Timer(Duration(milliseconds: dur), () {
          if (SoLoud.instance.isInitialized) {
            SoLoud.instance.fadeVolume(handle, 0.0, Duration(milliseconds: 20));
            Timer(
              Duration(milliseconds: 20),
              () => SoLoud.instance.stop(handle),
            );
          }
        });
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

  @override
  Widget build(BuildContext context) {
    double beatW = 100.0 * 60.0 / widget.bpm * widget.zoomX;
    return Column(
      children: [
        Container(
          height: 40,
          color: panelDark,
          padding: EdgeInsets.symmetric(horizontal: 16),
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
              Spacer(),
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
                  final r = Random();
                  for (var n in widget.clip.notes) {
                    n.start += (r.nextDouble() * 10 - 5);
                    if (n.start < 0) n.start = 0;
                    n.velocity = (n.velocity + (r.nextInt(20) - 10)).clamp(
                      0,
                      127,
                    );
                  }
                  widget.onNotesChanged();
                },
                child: Text('Humanize', style: TextStyle(color: lavenderLight)),
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
        Expanded(
          child: Row(
            children: [
              Container(
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
                              bottom: BorderSide(color: Colors.grey, width: 1),
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
                      return Container(
                        height: _pitchHeight,
                        decoration: BoxDecoration(
                          color: isBlack ? Colors.black : Colors.white,
                          border: Border(
                            bottom: BorderSide(color: Colors.grey, width: 1),
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
                                      color: Colors.red,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              )
                            : null,
                      );
                    }),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    controller: _verticalController2,
                    child: Container(
                      width: max(
                        2000.0,
                        widget.clip.length * widget.zoomX + 100,
                      ),
                      height: _numRows * _pitchHeight,
                      color: panelDark,
                      child: Stack(
                        children: [
                          CustomPaint(
                            painter: GridPainter(
                              pitchHeight: _pitchHeight,
                              beatWidth: beatW,
                              timeSigTop: widget.timeSigTop,
                            ),
                            size: Size(
                              max(
                                2000.0,
                                widget.clip.length * widget.zoomX + 100,
                              ),
                              _numRows * _pitchHeight,
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
                          Positioned(
                            left: widget.clip.length * widget.zoomX,
                            top: 0,
                            bottom: 0,
                            width: 12,
                            child: IgnorePointer(
                              child: Stack(
                                children: [
                                  Container(width: 2, color: lavenderAccent),
                                  Positioned(
                                    left: 0,
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
                                      List<MidiNote> targets =
                                          widget.selectedMidiNotes.contains(
                                            note,
                                          )
                                          ? widget.selectedMidiNotes
                                          : [note];
                                      for (var n in targets) {
                                        _dragInitialPitches[n] = n.pitch;
                                      }
                                    },
                                    onPanUpdate: (d) {
                                      setState(() {
                                        _dragTotalDy += d.delta.dy;
                                        int rowDelta =
                                            (_dragTotalDy / _pitchHeight)
                                                .round();
                                        List<MidiNote> targets =
                                            widget.selectedMidiNotes.contains(
                                              note,
                                            )
                                            ? widget.selectedMidiNotes
                                            : [note];
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
                                              if (newPitch != n.pitch &&
                                                  newPitch != -1) {
                                                n.pitch = newPitch;
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
                                                    if (pad != null) pad.play();
                                                  } else {
                                                    AudioSource src =
                                                        widget
                                                            .track!
                                                            .synthSource ??
                                                        globalSynthSound!;
                                                    if (widget
                                                            .track!
                                                            .synthSource ==
                                                        null) {
                                                      if (widget
                                                              .track!
                                                              .instrumentIndex ==
                                                          1) {
                                                        src = globalSawSound!;
                                                      } else if (widget
                                                              .track!
                                                              .instrumentIndex ==
                                                          2)
                                                        src = globalSineSound!;
                                                      else if (widget
                                                              .track!
                                                              .instrumentIndex ==
                                                          3)
                                                        src = globalPianoSound!;
                                                      else if (widget
                                                              .track!
                                                              .instrumentIndex ==
                                                          4)
                                                        src = globalCelloSound!;
                                                      else if (widget
                                                              .track!
                                                              .instrumentIndex ==
                                                          5)
                                                        src =
                                                            globalViolinSound!;
                                                    }
                                                    double volMultiplier = 1.0;
                                                    if (widget
                                                            .track!
                                                            .instrumentIndex ==
                                                        3) {
                                                      volMultiplier = 3.0;
                                                    } else if (widget
                                                            .track!
                                                            .instrumentIndex ==
                                                        4)
                                                      volMultiplier = 2.0;
                                                    else if (widget
                                                            .track!
                                                            .instrumentIndex ==
                                                        5)
                                                      volMultiplier = 1.5;
                                                    final handle = widget
                                                        .track!
                                                        .bus!
                                                        .play(
                                                          src,
                                                          volume:
                                                              0.5 *
                                                              volMultiplier,
                                                        );
                                                    int basePitch = 69;
                                                    if (widget
                                                            .track!
                                                            .instrumentIndex ==
                                                        3) {
                                                      basePitch = 60;
                                                    } else if (widget
                                                            .track!
                                                            .instrumentIndex ==
                                                        4)
                                                      basePitch = 48;
                                                    else if (widget
                                                            .track!
                                                            .instrumentIndex ==
                                                        5)
                                                      basePitch = 60;
                                                    double speed =
                                                        pow(
                                                              2.0,
                                                              (newPitch -
                                                                      basePitch) /
                                                                  12.0,
                                                            )
                                                            as double;
                                                    SoLoud.instance
                                                        .setRelativePlaySpeed(
                                                          handle,
                                                          speed,
                                                        );
                                                    Timer(
                                                      Duration(
                                                        milliseconds: 100,
                                                      ),
                                                      () {
                                                        if (SoLoud
                                                            .instance
                                                            .isInitialized) {
                                                          SoLoud.instance
                                                              .fadeVolume(
                                                                handle,
                                                                0.0,
                                                                Duration(
                                                                  milliseconds:
                                                                      20,
                                                                ),
                                                              );
                                                          Timer(
                                                            Duration(
                                                              milliseconds: 20,
                                                            ),
                                                            () => SoLoud
                                                                .instance
                                                                .stop(handle),
                                                          );
                                                        }
                                                      },
                                                    );
                                                  }
                                                }
                                              }
                                            }
                                          }
                                        }
                                      });
                                    },
                                    onPanEnd: (d) {
                                      if (widget.snapToGrid) {
                                        setState(() {
                                          List<MidiNote> targets =
                                              widget.selectedMidiNotes.contains(
                                                note,
                                              )
                                              ? widget.selectedMidiNotes
                                              : [note];
                                          for (var n in targets) {
                                            n.start =
                                                (n.start /
                                                        widget.snapResolution)
                                                    .round() *
                                                widget.snapResolution;
                                          }
                                        });
                                      }
                                    },
                                    child: Container(
                                      margin: EdgeInsets.all(1),
                                      decoration: BoxDecoration(
                                        color: isSel
                                            ? textMain
                                            : lavenderAccent,
                                        borderRadius: BorderRadius.circular(2),
                                        border: Border.all(
                                          color: isSel
                                              ? Colors.blueAccent
                                              : Colors.transparent,
                                          width: isSel ? 2 : 0,
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
                        ],
                      ),
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
