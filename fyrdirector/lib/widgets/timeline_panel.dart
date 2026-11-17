import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/director_types.dart';
import '../state/director_controller.dart';

class TimelinePanel extends StatefulWidget {
  const TimelinePanel({super.key});

  @override
  State<TimelinePanel> createState() => _TimelinePanelState();
}

class _TimelinePanelState extends State<TimelinePanel> {
  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

  static const double _headerWidth = 172.0;
  static const double _rulerHeight = 26.0;
  static const double _trackHeight = 58.0;

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DirectorController>();
    final totalSec = ctrl.totalDurationSec;
    final timelineWidth = max(900.0, totalSec * ctrl.timelineZoom);

    return Container(
      height: 310,
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        children: [
          // Timeline Toolbar
          Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: FyrTheme.surfaceColor,
              border: Border(bottom: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              children: [
                _toolChip(
                  icon: Icons.near_me_rounded,
                  label: 'Select (V)',
                  active: ctrl.activeTool == DirectorTool.select,
                  onTap: () {
                    ctrl.activeTool = DirectorTool.select;
                    ctrl.refresh();
                  },
                ),
                const SizedBox(width: 6),
                _toolChip(
                  icon: Icons.content_cut_rounded,
                  label: 'Razor (C)',
                  active: ctrl.activeTool == DirectorTool.razor,
                  onTap: () {
                    ctrl.activeTool = DirectorTool.razor;
                    ctrl.refresh();
                  },
                ),
                const SizedBox(width: 12),
                _iconAction(Icons.vertical_split_rounded,
                    'Split at Playhead (S)', ctrl.splitAtPlayhead),
                _iconAction(Icons.copy_rounded, 'Duplicate Clip (Ctrl+D)',
                    ctrl.duplicateSelectedClip),
                _iconAction(Icons.delete_outline_rounded, 'Delete Clip (Del)',
                    ctrl.deleteSelectedClip),
                const SizedBox(width: 8),
                _toolChip(
                  icon: Icons.align_horizontal_left_rounded,
                  label: 'Snap (N)',
                  active: ctrl.snapEnabled,
                  onTap: () {
                    ctrl.snapEnabled = !ctrl.snapEnabled;
                    ctrl.refresh();
                  },
                ),
                const Spacer(),
                _iconAction(Icons.video_call_outlined, 'Add Video Track',
                    () => ctrl.addTrack(isAudio: false)),
                _iconAction(Icons.library_music_outlined, 'Add Audio Track',
                    () => ctrl.addTrack(isAudio: true)),
                const SizedBox(width: 8),
                Icon(Icons.zoom_out_rounded,
                    size: 15, color: FyrTheme.textColorMuted),
                SizedBox(
                  width: 100,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 2.5,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 9),
                      activeTrackColor: FyrTheme.accentColor,
                      thumbColor: FyrTheme.accentColor,
                    ),
                    child: Slider(
                      value: ctrl.timelineZoom.clamp(15.0, 220.0),
                      min: 15.0,
                      max: 220.0,
                      onChanged: (v) {
                        ctrl.timelineZoom = v;
                        ctrl.refresh();
                      },
                    ),
                  ),
                ),
                Icon(Icons.zoom_in_rounded,
                    size: 15, color: FyrTheme.textColorMuted),
              ],
            ),
          ),
          // Tracks & Ruler Area
          Expanded(
            child: Row(
              children: [
                // Fixed Left Track Headers Column
                SizedBox(
                  width: _headerWidth,
                  child: Column(
                    children: [
                      Container(
                        height: _rulerHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        alignment: Alignment.centerLeft,
                        decoration: BoxDecoration(
                          color: FyrTheme.contentColor,
                          border: Border(
                            right: BorderSide(color: FyrTheme.dividerColor),
                            bottom: BorderSide(color: FyrTheme.dividerColor),
                          ),
                        ),
                        child: Text(
                          'TRACKS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.9,
                            color: FyrTheme.textColorMuted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _vScroll,
                          itemCount: ctrl.tracks.length,
                          itemBuilder: (_, idx) =>
                              _TrackHeader(track: ctrl.tracks[idx], ctrl: ctrl),
                        ),
                      ),
                    ],
                  ),
                ),
                // Scrollable Time Ruler + Lanes
                Expanded(
                  child: Scrollbar(
                    controller: _hScroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _hScroll,
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: timelineWidth,
                        child: Column(
                          children: [
                            // Timecode Ruler
                            GestureDetector(
                              onTapDown: (d) => ctrl.seekTo(
                                  d.localPosition.dx / ctrl.timelineZoom),
                              onHorizontalDragUpdate: (d) => ctrl.seekTo(
                                  d.localPosition.dx / ctrl.timelineZoom),
                              child: SizedBox(
                                height: _rulerHeight,
                                width: timelineWidth,
                                child: CustomPaint(
                                  painter: _RulerPainter(
                                    zoom: ctrl.timelineZoom,
                                    playheadSec: ctrl.playheadSec,
                                    accent: FyrTheme.accentColor,
                                    bg: FyrTheme.contentColor,
                                    text: FyrTheme.textColorMuted,
                                    border: FyrTheme.dividerColor,
                                  ),
                                ),
                              ),
                            ),
                            // Track Lanes + Playhead Line
                            Expanded(
                              child: Stack(
                                children: [
                                  ListView.builder(
                                    itemCount: ctrl.tracks.length,
                                    itemBuilder: (_, tIdx) {
                                      return _TrackLane(
                                        trackIndex: tIdx,
                                        track: ctrl.tracks[tIdx],
                                        width: timelineWidth,
                                        height: _trackHeight,
                                        ctrl: ctrl,
                                      );
                                    },
                                  ),
                                  // Playhead vertical line
                                  Positioned(
                                    left: ctrl.playheadSec * ctrl.timelineZoom,
                                    top: 0,
                                    bottom: 0,
                                    child: IgnorePointer(
                                      child: Container(
                                        width: 1.8,
                                        color: FyrTheme.accentColor,
                                      ),
                                    ),
                                  ),
                                ],
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
      ),
    );
  }

  Widget _toolChip({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? FyrTheme.accentColor.withValues(alpha: 0.2)
              : FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? FyrTheme.accentColor : FyrTheme.dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 13,
                color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active ? FyrTheme.textColor : FyrTheme.textColorMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconAction(IconData icon, String tip, VoidCallback onTap) {
    return Tooltip(
      message: tip,
      child: IconButton(
        icon: Icon(icon, size: 17, color: FyrTheme.textColorMuted),
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        onPressed: onTap,
      ),
    );
  }
}

class _TrackHeader extends StatelessWidget {
  final TimelineTrack track;
  final DirectorController ctrl;

  const _TrackHeader({required this.track, required this.ctrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _TimelinePanelState._trackHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: FyrTheme.sidebarColor,
        border: Border(
          right: BorderSide(color: FyrTheme.dividerColor),
          bottom: BorderSide(color: FyrTheme.dividerColor),
        ),
      ),
      child: Row(
        children: [
          Icon(
            track.isAudio ? Icons.audiotrack_rounded : Icons.videocam_rounded,
            size: 14,
            color: track.isAudio
                ? const Color(0xFF26A69A)
                : FyrTheme.accentColor,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              track.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: FyrTheme.textColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _miniToggle('M', track.muted, Colors.redAccent, () {
            track.muted = !track.muted;
            ctrl.refresh();
          }),
          const SizedBox(width: 3),
          _miniToggle('S', track.solo, Colors.amberAccent, () {
            track.solo = !track.solo;
            ctrl.refresh();
          }),
          const SizedBox(width: 3),
          if (!track.isAudio)
            InkWell(
              onTap: () {
                track.visible = !track.visible;
                ctrl.refresh();
              },
              child: Icon(
                track.visible
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                size: 14,
                color: track.visible
                    ? FyrTheme.textColorMuted
                    : FyrTheme.textColorMuted.withValues(alpha: 0.35),
              ),
            ),
          const SizedBox(width: 3),
          InkWell(
            onTap: () {
              track.locked = !track.locked;
              ctrl.refresh();
            },
            child: Icon(
              track.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: 13,
              color: track.locked
                  ? FyrTheme.accentColor
                  : FyrTheme.textColorMuted.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniToggle(
      String label, bool active, Color activeColor, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.25)
              : FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? activeColor : FyrTheme.dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            color: active ? activeColor : FyrTheme.textColorMuted,
          ),
        ),
      ),
    );
  }
}

class _TrackLane extends StatelessWidget {
  final int trackIndex;
  final TimelineTrack track;
  final double width;
  final double height;
  final DirectorController ctrl;

  const _TrackLane({
    required this.trackIndex,
    required this.track,
    required this.width,
    required this.height,
    required this.ctrl,
  });

  @override
  Widget build(BuildContext context) {
    final trackClips =
        ctrl.clips.where((c) => c.trackIndex == trackIndex).toList();

    return DragTarget<MediaAsset>(
      onAcceptWithDetails: (details) {
        final box = context.findRenderObject() as RenderBox?;
        double atSec = ctrl.playheadSec;
        if (box != null) {
          final local = box.globalToLocal(details.offset);
          atSec = max(0.0, local.dx / ctrl.timelineZoom);
        }
        ctrl.addAssetToTimeline(
          details.data,
          trackIndex: trackIndex,
          atSec: ctrl.snapTime(atSec),
        );
      },
      builder: (context, candidateData, _) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapDown: (d) {
            ctrl.selectClip(null);
            ctrl.seekTo(d.localPosition.dx / ctrl.timelineZoom);
          },
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: candidateData.isNotEmpty
                  ? FyrTheme.accentColor.withValues(alpha: 0.1)
                  : (trackIndex.isEven
                      ? FyrTheme.contentColor
                      : FyrTheme.bgColor),
              border: Border(
                bottom: BorderSide(color: FyrTheme.dividerColor),
              ),
            ),
            child: Stack(
              children: trackClips.map((clip) {
                return _ClipBlock(
                  clip: clip,
                  trackIndex: trackIndex,
                  trackHeight: height,
                  ctrl: ctrl,
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}

class _ClipBlock extends StatefulWidget {
  final TimelineClip clip;
  final int trackIndex;
  final double trackHeight;
  final DirectorController ctrl;

  const _ClipBlock({
    required this.clip,
    required this.trackIndex,
    required this.trackHeight,
    required this.ctrl,
  });

  @override
  State<_ClipBlock> createState() => _ClipBlockState();
}

class _ClipBlockState extends State<_ClipBlock> {
  double _dragStartSec = 0;
  double _dragAccumDx = 0;
  double _dragAccumDy = 0;

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.ctrl;
    final clip = widget.clip;
    final leftPx = clip.timelineStartSec * ctrl.timelineZoom;
    final widthPx = max(16.0, clip.durationSec * ctrl.timelineZoom);
    final selected = ctrl.selectedClipId == clip.id;
    final asset = ctrl.assetById(clip.assetId);

    return Positioned(
      left: leftPx,
      top: 4,
      width: widthPx,
      height: widget.trackHeight - 8,
      child: GestureDetector(
        onTapDown: (d) {
          if (ctrl.activeTool == DirectorTool.razor) {
            final clickSec =
                clip.timelineStartSec + d.localPosition.dx / ctrl.timelineZoom;
            ctrl.splitClipAt(clip.id, clickSec);
          } else {
            ctrl.selectClip(clip.id);
          }
        },
        onPanStart: (_) {
          if (ctrl.activeTool == DirectorTool.razor) return;
          ctrl.selectClip(clip.id);
          _dragStartSec = clip.timelineStartSec;
          _dragAccumDx = 0;
          _dragAccumDy = 0;
        },
        onPanUpdate: (d) {
          if (ctrl.activeTool == DirectorTool.razor) return;
          _dragAccumDx += d.delta.dx;
          _dragAccumDy += d.delta.dy;
          final targetTrack =
              widget.trackIndex + (_dragAccumDy / widget.trackHeight).round();
          ctrl.moveClip(
            clip.id,
            max(0.0, _dragStartSec + _dragAccumDx / ctrl.timelineZoom),
            targetTrack,
          );
        },
        onPanEnd: (_) {
          if (ctrl.activeTool == DirectorTool.razor) return;
          ctrl.moveClip(clip.id, clip.timelineStartSec, clip.trackIndex,
              commit: true);
        },
        child: Container(
          decoration: BoxDecoration(
            color: clip.clipColor.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected ? Colors.white : clip.clipColor,
              width: selected ? 1.8 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Thumbnails for video/image
              if (asset != null && asset.thumbnailPaths.isNotEmpty)
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.45,
                    child: Row(
                      children: asset.thumbnailPaths
                          .where((p) => File(p).existsSync())
                          .map((p) => Expanded(
                                child: Image.file(File(p),
                                    fit: BoxFit.cover, height: double.infinity),
                              ))
                          .toList(),
                    ),
                  ),
                ),
              // Audio Waveform
              if (asset?.waveformPeaks != null)
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WaveformPainter(
                      peaks: asset!.waveformPeaks!,
                      color: clip.clipColor.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              // Clip label
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        clip.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                    if ((clip.effects.speed - 1.0).abs() > 0.05)
                      Text(
                        '${clip.effects.speed.toStringAsFixed(1)}x',
                        style: const TextStyle(
                            fontSize: 9.5, color: Colors.amberAccent),
                      ),
                  ],
                ),
              ),
              // Left Trim Handle
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 8,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) =>
                        ctrl.trimClipLeft(clip.id, d.delta.dx / ctrl.timelineZoom),
                    onHorizontalDragEnd: (_) =>
                        ctrl.trimClipLeft(clip.id, 0, commit: true),
                    child: Container(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.35)
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
              // Right Trim Handle
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                width: 8,
                child: MouseRegion(
                  cursor: SystemMouseCursors.resizeLeftRight,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onHorizontalDragUpdate: (d) => ctrl.trimClipRight(
                        clip.id, d.delta.dx / ctrl.timelineZoom),
                    onHorizontalDragEnd: (_) =>
                        ctrl.trimClipRight(clip.id, 0, commit: true),
                    child: Container(
                      color: selected
                          ? Colors.white.withValues(alpha: 0.35)
                          : Colors.transparent,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final Float32List peaks;
  final Color color;

  _WaveformPainter({required this.peaks, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final midY = size.height / 2;
    final step = size.width / peaks.length;
    for (int i = 0; i < peaks.length; i++) {
      final x = i * step;
      final h = peaks[i] * (size.height * 0.8);
      canvas.drawLine(
          Offset(x, midY - h / 2), Offset(x, midY + h / 2), p);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) => old.peaks != peaks;
}

class _RulerPainter extends CustomPainter {
  final double zoom;
  final double playheadSec;
  final Color accent;
  final Color bg;
  final Color text;
  final Color border;

  _RulerPainter({
    required this.zoom,
    required this.playheadSec,
    required this.accent,
    required this.bg,
    required this.text,
    required this.border,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = bg);
    final stepSec = zoom >= 120 ? 1 : (zoom >= 50 ? 2 : 5);
    final tickPaint = Paint()
      ..color = text.withValues(alpha: 0.45)
      ..strokeWidth = 1;

    final maxSec = (size.width / zoom).ceil();
    for (int s = 0; s <= maxSec; s += stepSec) {
      final x = s * zoom;
      canvas.drawLine(
          Offset(x, size.height - 8), Offset(x, size.height), tickPaint);
      final m = (s ~/ 60).toString().padLeft(2, '0');
      final sec = (s % 60).toString().padLeft(2, '0');
      final tp = TextPainter(
        text: TextSpan(
          text: '$m:$sec',
          style: TextStyle(fontSize: 9.5, color: text),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x + 3, 4));
    }

    // Playhead cap
    final px = playheadSec * zoom;
    final path = Path()
      ..moveTo(px - 6, 0)
      ..lineTo(px + 6, 0)
      ..lineTo(px + 6, 10)
      ..lineTo(px, 17)
      ..lineTo(px - 6, 10)
      ..close();
    canvas.drawPath(path, Paint()..color = accent);

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()..color = border,
    );
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) => true;
}
