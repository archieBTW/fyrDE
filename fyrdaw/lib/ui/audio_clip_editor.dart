import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/daw_clip.dart';
import 'package:fyrdaw/models/track.dart';
import 'package:fyrdaw/ui/dial.dart';
import 'package:fyrdaw/ui/painters.dart';

/// Close-up non-destructive & DSP audio clip editor tab for trimming,
/// splitting, fading, gain/pitch/stretch adjustments, and audio transforms.
class AudioClipEditorWidget extends StatefulWidget {
  final AudioClip clip;
  final Track? track;
  final int bpm;
  final double beatWidth;
  final bool snapToGrid;
  final double snapResolution;
  final double playheadPosition;
  final ValueChanged<double> onPlayheadChanged;
  final VoidCallback onChangeStart;
  final VoidCallback onClipChanged;
  final void Function(double splitTimelinePos) onSplitClip;
  final bool isPlaying;
  final VoidCallback? onPlayPause;
  final Future<void> Function()? onNormalize;
  final Future<void> Function()? onReverse;
  final Future<void> Function()? onStripSilence;
  final Future<void> Function()? onAutoMatchBpm;
  final Future<void> Function()? onAudioToMidi;
  final Future<void> Function()? onSliceToSampler;

  const AudioClipEditorWidget({
    super.key,
    required this.clip,
    this.track,
    required this.bpm,
    required this.beatWidth,
    required this.snapToGrid,
    required this.snapResolution,
    required this.playheadPosition,
    required this.onPlayheadChanged,
    required this.onChangeStart,
    required this.onClipChanged,
    required this.onSplitClip,
    this.isPlaying = false,
    this.onPlayPause,
    this.onNormalize,
    this.onReverse,
    this.onStripSilence,
    this.onAutoMatchBpm,
    this.onAudioToMidi,
    this.onSliceToSampler,
  });

  @override
  State<AudioClipEditorWidget> createState() => _AudioClipEditorWidgetState();
}

class _AudioClipEditorWidgetState extends State<AudioClipEditorWidget> {
  final ScrollController _scrollController = ScrollController();
  double _zoomMultiplier = 1.0;
  double _cursorOffsetInClip = 0.0; // offset from clip.start (timeline units)
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _syncDefaultCursor();
  }

  @override
  void didUpdateWidget(covariant AudioClipEditorWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clip.id != widget.clip.id) {
      _syncDefaultCursor();
    } else {
      _cursorOffsetInClip = _cursorOffsetInClip.clamp(0.0, widget.clip.length);
    }
  }

  void _syncDefaultCursor() {
    final rel = widget.playheadPosition - widget.clip.start;
    if (rel > 1.0 && rel < widget.clip.length - 1.0) {
      _cursorOffsetInClip = rel;
    } else {
      _cursorOffsetInClip = widget.clip.length * 0.5;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double get _sourceSpan {
    final raw = widget.clip.stretchFactor > 0.01
        ? widget.clip.originalLength / widget.clip.stretchFactor
        : widget.clip.originalLength;
    return max(widget.clip.startOffset + widget.clip.length, max(10.0, raw));
  }

  String _formatSeconds(double timelineUnits) {
    final sec = max(0.0, timelineUnits) / 100.0;
    if (sec < 1.0) return '${(sec * 1000).round()}ms';
    return '${sec.toStringAsFixed(2)}s';
  }

  Future<void> _runAsyncAction(Future<void> Function()? fn) async {
    if (fn == null || _isBusy) return;
    setState(() => _isBusy = true);
    try {
      await fn();
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  void _trimStartToCursor() {
    final clip = widget.clip;
    double delta = _cursorOffsetInClip;
    if (delta <= 0.5 || clip.length - delta < 10.0) return;
    widget.onChangeStart();
    setState(() {
      clip.start += delta;
      clip.startOffset += delta;
      clip.length -= delta;
      clip.fadeIn = (clip.fadeIn - delta).clamp(0.0, max(0.0, clip.length - clip.fadeOut));
      clip.fadeOut = clip.fadeOut.clamp(0.0, max(0.0, clip.length - clip.fadeIn));
      _cursorOffsetInClip = 0.0;
    });
    widget.onPlayheadChanged(clip.start);
    widget.onClipChanged();
  }

  void _trimEndToCursor() {
    final clip = widget.clip;
    if (_cursorOffsetInClip < 10.0 || _cursorOffsetInClip >= clip.length - 0.5) return;
    widget.onChangeStart();
    setState(() {
      clip.length = _cursorOffsetInClip;
      clip.fadeIn = clip.fadeIn.clamp(0.0, clip.length);
      clip.fadeOut = clip.fadeOut.clamp(0.0, max(0.0, clip.length - clip.fadeIn));
      _cursorOffsetInClip = clip.length;
    });
    widget.onClipChanged();
  }

  void _resetTrim() {
    final clip = widget.clip;
    final fullLen = clip.stretchFactor > 0.01
        ? clip.originalLength / clip.stretchFactor
        : clip.originalLength;
    widget.onChangeStart();
    setState(() {
      clip.start = max(0.0, clip.start - clip.startOffset);
      clip.startOffset = 0.0;
      clip.length = max(10.0, fullLen);
      clip.fadeIn = clip.fadeIn.clamp(0.0, clip.length * 0.5);
      clip.fadeOut = clip.fadeOut.clamp(0.0, clip.length - clip.fadeIn);
      _cursorOffsetInClip = clip.length * 0.5;
    });
    widget.onClipChanged();
  }

  void _applyFadePreset(double fadeInSec, double fadeOutSec) {
    final clip = widget.clip;
    widget.onChangeStart();
    setState(() {
      final fi = (fadeInSec * 100.0).clamp(0.0, clip.length * 0.49);
      final fo = (fadeOutSec * 100.0).clamp(0.0, clip.length - fi);
      clip.fadeIn = fi;
      clip.fadeOut = fo;
    });
    widget.onClipChanged();
  }

  Widget _buildNormalizedDial({
    required String label,
    required double value,
    required double minVal,
    required double maxVal,
    required double defaultVal,
    required String displayText,
    required ValueChanged<double> onChanged,
    Color? color,
  }) {
    final span = max(1e-6, maxVal - minVal);
    final norm = ((value - minVal) / span * 2.0 - 1.0).clamp(-1.0, 1.0);
    final defNorm = ((defaultVal - minVal) / span * 2.0 - 1.0).clamp(-1.0, 1.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: textMuted, fontSize: 10)),
        const SizedBox(height: 3),
        PanDial(
          pan: norm,
          defaultValue: defNorm,
          size: 32,
          activeColor: color ?? lavenderAccent,
          onChangeStart: widget.onChangeStart,
          formatLabel: (_) => displayText,
          onChanged: (n) {
            final v = minVal + ((n + 1.0) * 0.5) * span;
            onChanged(v.clamp(minVal, maxVal));
          },
        ),
        const SizedBox(height: 2),
        Text(
          displayText,
          style: TextStyle(
            color: textMain,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    String? tooltip,
    Color? accentColor,
  }) {
    final enabled = onPressed != null && !_isBusy;
    final btn = InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: enabled ? panelLight : bgDark,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: enabled ? (accentColor ?? textFaint) : textFaint.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: enabled ? (accentColor ?? lavenderLight) : textFaint,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: enabled ? textMain : textFaint,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
    return tooltip != null ? Tooltip(message: tooltip, child: btn) : btn;
  }

  @override
  Widget build(BuildContext context) {
    final clip = widget.clip;
    final clipLabel = clip.name.isNotEmpty
        ? clip.name
        : p.basenameWithoutExtension(clip.filePath);
    final canSplit =
        _cursorOffsetInClip > 1.0 && _cursorOffsetInClip < clip.length - 1.0;

    return Column(
      children: [
        // Top Toolbar: Clip info + Trim/Split + DSP tools + Zoom
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: panelDark,
            border: Border(bottom: BorderSide(color: textFaint)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 20,
                  decoration: BoxDecoration(
                    color: clip.color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  clipLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${_formatSeconds(clip.length)}  •  Offset ${_formatSeconds(clip.startOffset)}',
                  style: TextStyle(color: textMuted, fontSize: 11),
                ),
                const SizedBox(width: 10),
                if (widget.onPlayPause != null) ...[
                  _actionChip(
                    icon: widget.isPlaying ? Icons.stop : Icons.play_arrow,
                    label: widget.isPlaying ? 'Stop' : 'Audition',
                    accentColor: widget.isPlaying ? Colors.amberAccent : Colors.greenAccent,
                    onPressed: widget.onPlayPause,
                  ),
                  const SizedBox(width: 6),
                ],
                _actionChip(
                  icon: Icons.content_cut,
                  label: 'Split at Cursor',
                  tooltip: 'Split audio segment at amber edit cursor',
                  accentColor: canSplit ? Colors.amberAccent : null,
                  onPressed: canSplit
                      ? () => widget.onSplitClip(clip.start + _cursorOffsetInClip)
                      : null,
                ),
                const SizedBox(width: 6),
                _actionChip(
                  icon: Icons.first_page,
                  label: 'Trim In',
                  tooltip: 'Trim clip start to edit cursor',
                  onPressed: (_cursorOffsetInClip > 0.5 &&
                          clip.length - _cursorOffsetInClip >= 10.0)
                      ? _trimStartToCursor
                      : null,
                ),
                const SizedBox(width: 6),
                _actionChip(
                  icon: Icons.last_page,
                  label: 'Trim Out',
                  tooltip: 'Trim clip end to edit cursor',
                  onPressed: (_cursorOffsetInClip >= 10.0 &&
                          _cursorOffsetInClip < clip.length - 0.5)
                      ? _trimEndToCursor
                      : null,
                ),
                const SizedBox(width: 6),
                _actionChip(
                  icon: Icons.fit_screen,
                  label: 'Reset Trim',
                  tooltip: 'Restore full un-trimmed audio bounds',
                  onPressed: (clip.startOffset > 0.1 ||
                          (clip.length - clip.originalLength / max(0.01, clip.stretchFactor)).abs() > 1.0)
                      ? _resetTrim
                      : null,
                ),
                const SizedBox(width: 10),
                Container(width: 1, height: 22, color: textFaint),
                const SizedBox(width: 10),
                _actionChip(
                  icon: Icons.graphic_eq,
                  label: 'Normalize',
                  onPressed: widget.onNormalize != null
                      ? () => _runAsyncAction(widget.onNormalize)
                      : null,
                ),
                const SizedBox(width: 6),
                _actionChip(
                  icon: Icons.swap_horiz,
                  label: clip.reversed ? 'Un-Reverse' : 'Reverse',
                  accentColor: clip.reversed ? lavenderAccent : null,
                  onPressed: widget.onReverse != null
                      ? () => _runAsyncAction(widget.onReverse)
                      : null,
                ),
                const SizedBox(width: 6),
                _actionChip(
                  icon: Icons.content_cut_outlined,
                  label: 'Strip Silence',
                  onPressed: widget.onStripSilence != null
                      ? () => _runAsyncAction(widget.onStripSilence)
                      : null,
                ),
                const SizedBox(width: 6),
                _actionChip(
                  icon: Icons.speed,
                  label: 'Auto BPM',
                  onPressed: widget.onAutoMatchBpm != null
                      ? () => _runAsyncAction(widget.onAutoMatchBpm)
                      : null,
                ),
                const SizedBox(width: 6),
                _actionChip(
                  icon: Icons.music_note,
                  label: 'Audio->MIDI',
                  onPressed: widget.onAudioToMidi != null
                      ? () => _runAsyncAction(widget.onAudioToMidi)
                      : null,
                ),
                const SizedBox(width: 6),
                _actionChip(
                  icon: Icons.grid_on,
                  label: 'Slice->Pads',
                  onPressed: widget.onSliceToSampler != null
                      ? () => _runAsyncAction(widget.onSliceToSampler)
                      : null,
                ),
                if (clip.takes.length > 1) ...[
                  const SizedBox(width: 10),
                  DropdownButton<int>(
                    value: clip.activeTakeIndex.clamp(0, clip.takes.length - 1),
                    isDense: true,
                    dropdownColor: panelDark,
                    underline: const SizedBox(),
                    style: TextStyle(color: Colors.lightGreenAccent, fontSize: 11),
                    items: List.generate(clip.takes.length, (idx) {
                      return DropdownMenuItem(
                        value: idx,
                        child: Text(clip.takes[idx].name),
                      );
                    }),
                    onChanged: (idx) {
                      if (idx != null) {
                        widget.onChangeStart();
                        setState(() => clip.selectTake(idx));
                        widget.onClipChanged();
                      }
                    },
                  ),
                ],
                const SizedBox(width: 12),
                IconButton(
                  tooltip: 'Zoom Out Waveform',
                  icon: Icon(Icons.zoom_out, size: 16, color: textMuted),
                  onPressed: () => setState(
                    () => _zoomMultiplier = (_zoomMultiplier / 1.4).clamp(0.4, 16.0),
                  ),
                ),
                Text(
                  '${_zoomMultiplier.toStringAsFixed(1)}x',
                  style: TextStyle(color: textMuted, fontSize: 10),
                ),
                IconButton(
                  tooltip: 'Zoom In Waveform',
                  icon: Icon(Icons.zoom_in, size: 16, color: textMuted),
                  onPressed: () => setState(
                    () => _zoomMultiplier = (_zoomMultiplier * 1.4).clamp(0.4, 16.0),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Middle Zoomable Waveform Canvas + Interactive Trim & Fade Handles
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availW = max(200.0, constraints.maxWidth);
              final spanUnits = _sourceSpan;
              final pxPerUnit = (availW / spanUnits) * _zoomMultiplier;
              final canvasW = max(availW, spanUnits * pxPerUnit);
              final activeLeftPx = clip.startOffset * pxPerUnit;
              final activeWidthPx = max(8.0, clip.length * pxPerUnit);
              final activeRightPx = activeLeftPx + activeWidthPx;
              final cursorPx = (clip.startOffset + _cursorOffsetInClip) * pxPerUnit;
              final playheadLocalUnits =
                  widget.playheadPosition - clip.start + clip.startOffset;
              final showGlobalPlayhead =
                  playheadLocalUnits >= 0.0 && playheadLocalUnits <= spanUnits;

              void setCursorFromLocalX(double xPx) {
                double targetOffsetInSource = (xPx / pxPerUnit).clamp(0.0, spanUnits);
                double localInClip = targetOffsetInSource - clip.startOffset;
                if (widget.snapToGrid && widget.snapResolution > 0) {
                  final worldPos = clip.start + localInClip;
                  final snappedWorld =
                      (worldPos / widget.snapResolution).round() * widget.snapResolution;
                  localInClip = snappedWorld - clip.start;
                }
                setState(() {
                  _cursorOffsetInClip = localInClip.clamp(0.0, clip.length);
                });
                widget.onPlayheadChanged(clip.start + _cursorOffsetInClip);
              }

              return Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent) {
                    if (event.scrollDelta.dy != 0) {
                      setState(() {
                        final factor = event.scrollDelta.dy < 0 ? 1.15 : 0.87;
                        _zoomMultiplier = (_zoomMultiplier * factor).clamp(0.4, 16.0);
                      });
                    }
                  }
                },
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: canvasW,
                      height: constraints.maxHeight,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          // Waveform & Ruler interactive surface
                          Positioned.fill(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (d) => setCursorFromLocalX(d.localPosition.dx),
                              onHorizontalDragUpdate: (d) =>
                                  setCursorFromLocalX(d.localPosition.dx),
                              child: CustomPaint(
                                painter: _CloseUpWaveformPainter(
                                  clip: clip,
                                  bpm: widget.bpm,
                                  beatWidth: widget.beatWidth,
                                  sourceSpan: spanUnits,
                                  pxPerUnit: pxPerUnit,
                                  cursorOffsetInSource:
                                      clip.startOffset + _cursorOffsetInClip,
                                  playheadOffsetInSource:
                                      showGlobalPlayhead ? playheadLocalUnits : null,
                                ),
                              ),
                            ),
                          ),

                          // Interactive Left Trim Bracket
                          Positioned(
                            left: max(0.0, activeLeftPx - 6),
                            top: 24,
                            bottom: 0,
                            width: 12,
                            child: Tooltip(
                              message: 'Drag Clip Start / Offset',
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeLeftRight,
                                child: GestureDetector(
                                  onHorizontalDragStart: (_) => widget.onChangeStart(),
                                  onHorizontalDragUpdate: (d) {
                                    double dxUnits = d.delta.dx / pxPerUnit;
                                    double newLen = clip.length - dxUnits;
                                    if (newLen < 10.0) {
                                      dxUnits = clip.length - 10.0;
                                      newLen = 10.0;
                                    }
                                    if (clip.startOffset + dxUnits < 0.0) {
                                      dxUnits = -clip.startOffset;
                                      newLen = clip.length - dxUnits;
                                    }
                                    if (clip.start + dxUnits < 0.0) {
                                      dxUnits = -clip.start;
                                      newLen = clip.length - dxUnits;
                                    }
                                    setState(() {
                                      clip.start += dxUnits;
                                      clip.startOffset += dxUnits;
                                      clip.length = newLen;
                                      clip.fadeIn = clip.fadeIn
                                          .clamp(0.0, max(0.0, clip.length - clip.fadeOut));
                                      clip.fadeOut = clip.fadeOut
                                          .clamp(0.0, max(0.0, clip.length - clip.fadeIn));
                                      _cursorOffsetInClip =
                                          _cursorOffsetInClip.clamp(0.0, clip.length);
                                    });
                                    widget.onClipChanged();
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        left: BorderSide(color: lavenderAccent, width: 3),
                                      ),
                                      color: lavenderAccent.withValues(alpha: 0.12),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Interactive Right Trim Bracket
                          Positioned(
                            left: max(0.0, activeRightPx - 6),
                            top: 24,
                            bottom: 0,
                            width: 12,
                            child: Tooltip(
                              message: 'Drag Clip End / Length',
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeLeftRight,
                                child: GestureDetector(
                                  onHorizontalDragStart: (_) => widget.onChangeStart(),
                                  onHorizontalDragUpdate: (d) {
                                    final dxUnits = d.delta.dx / pxPerUnit;
                                    setState(() {
                                      clip.length = max(10.0, clip.length + dxUnits);
                                      clip.fadeIn = clip.fadeIn.clamp(0.0, clip.length);
                                      clip.fadeOut = clip.fadeOut
                                          .clamp(0.0, max(0.0, clip.length - clip.fadeIn));
                                      _cursorOffsetInClip =
                                          _cursorOffsetInClip.clamp(0.0, clip.length);
                                    });
                                    widget.onClipChanged();
                                  },
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border(
                                        right: BorderSide(color: lavenderAccent, width: 3),
                                      ),
                                      color: lavenderAccent.withValues(alpha: 0.12),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Draggable Fade-In Corner Handle
                          Positioned(
                            left: (activeLeftPx + clip.fadeIn * pxPerUnit - 7)
                                .clamp(activeLeftPx, activeRightPx - 14),
                            top: 24,
                            child: Tooltip(
                              message: 'Fade In: ${_formatSeconds(clip.fadeIn)}',
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeLeftRight,
                                child: GestureDetector(
                                  onHorizontalDragStart: (_) => widget.onChangeStart(),
                                  onHorizontalDragUpdate: (d) {
                                    setState(() {
                                      clip.fadeIn = (clip.fadeIn + d.delta.dx / pxPerUnit)
                                          .clamp(0.0, max(0.0, clip.length - clip.fadeOut));
                                    });
                                    widget.onClipChanged();
                                  },
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(7),
                                      border: Border.all(color: Colors.black, width: 1.5),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Draggable Fade-Out Corner Handle
                          Positioned(
                            left: (activeRightPx - clip.fadeOut * pxPerUnit - 7)
                                .clamp(activeLeftPx, activeRightPx - 14),
                            top: 24,
                            child: Tooltip(
                              message: 'Fade Out: ${_formatSeconds(clip.fadeOut)}',
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeLeftRight,
                                child: GestureDetector(
                                  onHorizontalDragStart: (_) => widget.onChangeStart(),
                                  onHorizontalDragUpdate: (d) {
                                    setState(() {
                                      clip.fadeOut = (clip.fadeOut - d.delta.dx / pxPerUnit)
                                          .clamp(0.0, max(0.0, clip.length - clip.fadeIn));
                                    });
                                    widget.onClipChanged();
                                  },
                                  child: Container(
                                    width: 14,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(7),
                                      border: Border.all(color: Colors.black, width: 1.5),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Edit cursor badge readout
                          Positioned(
                            left: max(4.0, cursorPx + 4),
                            top: 4,
                            child: IgnorePointer(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amberAccent,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  _formatSeconds(_cursorOffsetInClip),
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
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
              );
            },
          ),
        ),

        // Bottom Parameter Strip: Gain, Pitch, Stretch, Fades & Presets
        Container(
          height: 92,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: panelDark,
            border: Border(top: BorderSide(color: textFaint)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildNormalizedDial(
                  label: 'Clip Gain',
                  value: clip.gain,
                  minVal: 0.0,
                  maxVal: 2.0,
                  defaultVal: 1.0,
                  displayText: '${(clip.gain * 100).round()}%',
                  onChanged: (v) {
                    setState(() => clip.gain = v);
                    widget.onClipChanged();
                  },
                ),
                const SizedBox(width: 22),
                _buildNormalizedDial(
                  label: 'Pitch',
                  value: clip.pitchSemitones,
                  minVal: -12.0,
                  maxVal: 12.0,
                  defaultVal: 0.0,
                  color: Colors.cyanAccent,
                  displayText:
                      '${clip.pitchSemitones >= 0 ? '+' : ''}${clip.pitchSemitones.toStringAsFixed(1)} st',
                  onChanged: (v) {
                    setState(() => clip.pitchSemitones = v);
                    widget.onClipChanged();
                  },
                ),
                const SizedBox(width: 22),
                _buildNormalizedDial(
                  label: 'Stretch',
                  value: clip.stretchFactor,
                  minVal: 0.5,
                  maxVal: 2.0,
                  defaultVal: 1.0,
                  color: Colors.cyanAccent,
                  displayText: '${clip.stretchFactor.toStringAsFixed(2)}x',
                  onChanged: (v) {
                    setState(() => clip.stretchFactor = v);
                    widget.onClipChanged();
                  },
                ),
                const SizedBox(width: 22),
                _buildNormalizedDial(
                  label: 'Fade In',
                  value: clip.fadeIn,
                  minVal: 0.0,
                  maxVal: max(10.0, clip.length * 0.5),
                  defaultVal: 0.0,
                  color: Colors.white,
                  displayText: _formatSeconds(clip.fadeIn),
                  onChanged: (v) {
                    setState(() {
                      clip.fadeIn = v.clamp(0.0, max(0.0, clip.length - clip.fadeOut));
                    });
                    widget.onClipChanged();
                  },
                ),
                const SizedBox(width: 22),
                _buildNormalizedDial(
                  label: 'Fade Out',
                  value: clip.fadeOut,
                  minVal: 0.0,
                  maxVal: max(10.0, clip.length * 0.5),
                  defaultVal: 0.0,
                  color: Colors.white,
                  displayText: _formatSeconds(clip.fadeOut),
                  onChanged: (v) {
                    setState(() {
                      clip.fadeOut = v.clamp(0.0, max(0.0, clip.length - clip.fadeIn));
                    });
                    widget.onClipChanged();
                  },
                ),
                const SizedBox(width: 24),
                Container(width: 1, height: 54, color: textFaint),
                const SizedBox(width: 16),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fade Presets',
                      style: TextStyle(color: textMuted, fontSize: 10),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        _actionChip(
                          icon: Icons.clear,
                          label: 'Clear',
                          onPressed: () => _applyFadePreset(0.0, 0.0),
                        ),
                        const SizedBox(width: 6),
                        _actionChip(
                          icon: Icons.linear_scale,
                          label: '15ms De-Click',
                          onPressed: () => _applyFadePreset(0.015, 0.015),
                        ),
                        const SizedBox(width: 6),
                        _actionChip(
                          icon: Icons.trending_up,
                          label: '250ms Swell',
                          onPressed: () => _applyFadePreset(0.25, 0.25),
                        ),
                        const SizedBox(width: 6),
                        _actionChip(
                          icon: Icons.waves,
                          label: 'Long Fade Out',
                          onPressed: () => _applyFadePreset(0.02, 0.75),
                        ),
                        const SizedBox(width: 10),
                        _actionChip(
                          icon: Icons.music_note_outlined,
                          label: clip.preservePitch ? 'Pitch Lock: ON' : 'Pitch Lock: OFF',
                          accentColor: clip.preservePitch ? Colors.cyanAccent : null,
                          onPressed: () {
                            widget.onChangeStart();
                            setState(() => clip.preservePitch = !clip.preservePitch);
                            widget.onClipChanged();
                          },
                        ),
                        const SizedBox(width: 6),
                        _actionChip(
                          icon: Icons.repeat,
                          label: clip.isLooped ? 'Loop: ON' : 'Loop: OFF',
                          accentColor: clip.isLooped ? Colors.amberAccent : null,
                          onPressed: () {
                            widget.onChangeStart();
                            setState(() => clip.isLooped = !clip.isLooped);
                            widget.onClipChanged();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CloseUpWaveformPainter extends CustomPainter {
  final AudioClip clip;
  final int bpm;
  final double beatWidth;
  final double sourceSpan;
  final double pxPerUnit;
  final double cursorOffsetInSource;
  final double? playheadOffsetInSource;

  _CloseUpWaveformPainter({
    required this.clip,
    required this.bpm,
    required this.beatWidth,
    required this.sourceSpan,
    required this.pxPerUnit,
    required this.cursorOffsetInSource,
    required this.playheadOffsetInSource,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double rulerH = 24.0;
    final bodyH = max(10.0, size.height - rulerH);
    final midY = rulerH + bodyH * 0.5;

    // Background & Ruler
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, rulerH),
      Paint()..color = panelLight,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, rulerH, size.width, bodyH),
      Paint()..color = bgDark,
    );

    // Beat / Seconds Grid on Ruler & Canvas
    final secStepUnits = pxPerUnit > 2.5 ? 25.0 : (pxPerUnit > 0.8 ? 50.0 : 100.0);
    final tickPaint = Paint()
      ..color = textFaint.withValues(alpha: 0.45)
      ..strokeWidth = 1.0;
    final subLinePaint = Paint()
      ..color = textFaint.withValues(alpha: 0.16)
      ..strokeWidth = 1.0;

    for (double u = 0; u <= sourceSpan; u += secStepUnits) {
      final x = u * pxPerUnit;
      canvas.drawLine(Offset(x, rulerH), Offset(x, size.height), subLinePaint);
      canvas.drawLine(Offset(x, rulerH - 6), Offset(x, rulerH), tickPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '${(u / 100.0).toStringAsFixed(secStepUnits < 100 ? 2 : 1)}s',
          style: TextStyle(color: textMuted, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (x + tp.width < size.width) {
        tp.paint(canvas, Offset(x + 3, 5));
      }
    }

    // Center & -6 dB guide lines
    final axisPaint = Paint()
      ..color = textFaint.withValues(alpha: 0.5)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), axisPaint);
    canvas.drawLine(
      Offset(0, rulerH + bodyH * 0.25),
      Offset(size.width, rulerH + bodyH * 0.25),
      subLinePaint,
    );
    canvas.drawLine(
      Offset(0, rulerH + bodyH * 0.75),
      Offset(size.width, rulerH + bodyH * 0.75),
      subLinePaint,
    );

    final activeLeftPx = clip.startOffset * pxPerUnit;
    final activeRightPx = (clip.startOffset + clip.length) * pxPerUnit;

    // Active region tint
    canvas.drawRect(
      Rect.fromLTWH(activeLeftPx, rulerH, max(0.0, activeRightPx - activeLeftPx), bodyH),
      Paint()..color = clip.color.withValues(alpha: 0.18),
    );

    // Waveform bars across underlying original audio + loop repeat if extended
    final peaks = clip.waveformData;
    final singleSourceUnits = clip.stretchFactor > 0.01
        ? clip.originalLength / clip.stretchFactor
        : clip.originalLength;
    final barPaintActive = Paint()
      ..color = Color.lerp(clip.color, Colors.white, 0.35)!
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    final barPaintDim = Paint()
      ..color = textMuted.withValues(alpha: 0.35)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final double stepPx = 3.0;
    final gainScale = clip.gain.clamp(0.05, 2.0);
    for (double x = 0; x < size.width; x += stepPx) {
      final u = x / pxPerUnit;
      final wrappedU = singleSourceUnits > 1.0 ? (u % singleSourceUnits) : 0.0;
      double amp;
      if (peaks != null && peaks.isNotEmpty) {
        final normPos = (wrappedU / max(1.0, singleSourceUnits)).clamp(0.0, 0.9999);
        final fIdx = normPos * (peaks.length - 1);
        final i0 = fIdx.floor();
        final i1 = min(peaks.length - 1, i0 + 1);
        final frac = fIdx - i0;
        amp = peaks[i0] * (1.0 - frac) + peaks[i1] * frac;
      } else {
        amp = 0.15 + 0.55 * Random(clip.filePath.hashCode + x.round()).nextDouble();
      }
      final halfH = (amp * gainScale * (bodyH * 0.45)).clamp(1.5, bodyH * 0.48);
      final inActive = x >= activeLeftPx && x <= activeRightPx;
      canvas.drawLine(
        Offset(x, midY - halfH),
        Offset(x, midY + halfH),
        inActive ? barPaintActive : barPaintDim,
      );
    }

    // Dimmed overlay outside trimmed bounds
    final trimShade = Paint()..color = Colors.black.withValues(alpha: 0.48);
    if (activeLeftPx > 0) {
      canvas.drawRect(Rect.fromLTWH(0, rulerH, activeLeftPx, bodyH), trimShade);
    }
    if (activeRightPx < size.width) {
      canvas.drawRect(
        Rect.fromLTWH(activeRightPx, rulerH, size.width - activeRightPx, bodyH),
        trimShade,
      );
    }

    // Fade-in & Fade-out curves inside active window
    canvas.save();
    canvas.translate(activeLeftPx, rulerH);
    final activeW = max(1.0, activeRightPx - activeLeftPx);
    ClipFadePainter(
      fadeInRatio: clip.length > 0 ? (clip.fadeIn / clip.length).clamp(0.0, 0.95) : 0.0,
      fadeOutRatio: clip.length > 0 ? (clip.fadeOut / clip.length).clamp(0.0, 0.95) : 0.0,
      accentColor: Colors.white,
    ).paint(canvas, Size(activeW, bodyH));
    canvas.restore();

    // Edit Cursor
    final curX = cursorOffsetInSource * pxPerUnit;
    canvas.drawLine(
      Offset(curX, 0),
      Offset(curX, size.height),
      Paint()
        ..color = Colors.amberAccent
        ..strokeWidth = 2.0,
    );

    // Global Playhead (if within range)
    if (playheadOffsetInSource != null) {
      final phX = playheadOffsetInSource! * pxPerUnit;
      canvas.drawLine(
        Offset(phX, rulerH),
        Offset(phX, size.height),
        Paint()
          ..color = Colors.white
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CloseUpWaveformPainter oldDelegate) => true;
}
