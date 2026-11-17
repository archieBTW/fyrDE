import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';
import '../fyr_theme.dart';
import '../models/director_types.dart';
import '../state/director_controller.dart';

class ProgramMonitor extends StatelessWidget {
  const ProgramMonitor({super.key});

  String _formatTimecode(double sec, double fps) {
    final totalMs = max(0, (sec * 1000).round());
    final hrs = totalMs ~/ 3600000;
    final mins = (totalMs % 3600000) ~/ 60000;
    final secs = (totalMs % 60000) ~/ 1000;
    final frames = ((totalMs % 1000) * fps / 1000).floor();
    return '${hrs.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}:${frames.toString().padLeft(2, '0')}';
  }

  List<double> _buildColorMatrix(ClipEffects e) {
    final b = e.brightness * 255.0;
    final c = e.contrast;
    final s = e.saturation;
    final t = (1.0 - c) * 128.0 + b;

    const rw = 0.2126;
    const gw = 0.7152;
    const bw = 0.0722;
    final sr = (1 - s) * rw;
    final sg = (1 - s) * gw;
    final sb = (1 - s) * bw;

    return [
      (sr + s) * c, sg * c, sb * c, 0, t,
      sr * c, (sg + s) * c, sb * c, 0, t,
      sr * c, sg * c, (sb + s) * c, 0, t,
      0, 0, 0, 1, 0,
    ];
  }

  double _effectiveClipOpacity(TimelineClip clip, double t) {
    final e = clip.effects;
    double alpha = e.opacity;
    final localT = t - clip.timelineStartSec;
    final remT = clip.timelineEndSec - t;

    final fadeIn = e.fadeInSec > 0.02
        ? e.fadeInSec
        : ((e.transitionIn == TransitionKind.fade ||
                e.transitionIn == TransitionKind.dissolve)
            ? e.transitionDurationSec
            : 0.0);
    if (fadeIn > 0.02 && localT < fadeIn) {
      alpha *= (localT / fadeIn).clamp(0.0, 1.0);
    }
    if (e.fadeOutSec > 0.02 && remT < e.fadeOutSec) {
      alpha *= (remT / e.fadeOutSec).clamp(0.0, 1.0);
    }
    return alpha.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<DirectorController>();
    final activeVisuals = ctrl.activeVisualClipsAt(ctrl.playheadSec);
    final seqAspect = ctrl.sequence.width / max(1, ctrl.sequence.height);

    return Expanded(
      child: Container(
        color: FyrTheme.contentColor,
        child: Column(
          children: [
            // Viewport Canvas
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Center(
                  child: AspectRatio(
                    aspectRatio: seqAspect,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: FyrTheme.dividerColor),
                        boxShadow: const [
                          BoxShadow(color: Colors.black54, blurRadius: 18),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: LayoutBuilder(
                        builder: (context, box) {
                          return Stack(
                            fit: StackFit.expand,
                            children: [
                              if (activeVisuals.isEmpty)
                                Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.movie_outlined,
                                          size: 36,
                                          color: Colors.white
                                              .withValues(alpha: 0.2)),
                                      const SizedBox(height: 6),
                                      Text(
                                        '${ctrl.sequence.width} × ${ctrl.sequence.height}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.white
                                              .withValues(alpha: 0.3),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                ...activeVisuals.map((clip) => _buildLayer(
                                      ctrl,
                                      clip,
                                      box.biggest,
                                    )),
                              if (ctrl.showSafeGuides)
                                IgnorePointer(
                                  child: CustomPaint(
                                    painter: _SafeGuidesPainter(),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Transport Controls Bar
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: FyrTheme.surfaceColor,
                border: Border(
                  top: BorderSide(color: FyrTheme.dividerColor),
                  bottom: BorderSide(color: FyrTheme.dividerColor),
                ),
              ),
              child: Row(
                children: [
                  Text(
                    _formatTimecode(ctrl.playheadSec, ctrl.sequence.fps),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: FyrTheme.accentColor,
                    ),
                  ),
                  Text(
                    ' / ${_formatTimecode(ctrl.contentEndSec, ctrl.sequence.fps)}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: FyrTheme.textColorMuted,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, size: 19),
                    tooltip: 'Go to Start (Home)',
                    onPressed: () => ctrl.seekTo(0.0),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, size: 20),
                    tooltip: 'Previous Frame (←)',
                    onPressed: () => ctrl.stepFrame(-1),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: FyrTheme.accentColor,
                      foregroundColor:
                          FyrTheme.getContrastingColor(FyrTheme.accentColor),
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(34, 34),
                    ),
                    onPressed: ctrl.togglePlay,
                    child: Icon(
                      ctrl.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 19,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, size: 20),
                    tooltip: 'Next Frame (→)',
                    onPressed: () => ctrl.stepFrame(1),
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, size: 19),
                    tooltip: 'Go to End (End)',
                    onPressed: () => ctrl.seekTo(ctrl.contentEndSec),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(
                      Icons.crop_free_rounded,
                      size: 16,
                      color: ctrl.showSafeGuides
                          ? FyrTheme.accentColor
                          : FyrTheme.textColorMuted,
                    ),
                    tooltip: 'Toggle Safe Margins',
                    onPressed: () {
                      ctrl.showSafeGuides = !ctrl.showSafeGuides;
                      ctrl.refresh();
                    },
                  ),
                  IconButton(
                    icon: Icon(
                      ctrl.masterMuted
                          ? Icons.volume_off_rounded
                          : Icons.volume_up_rounded,
                      size: 17,
                      color: FyrTheme.textColorMuted,
                    ),
                    onPressed: () {
                      ctrl.masterMuted = !ctrl.masterMuted;
                      ctrl.refresh();
                    },
                  ),
                  SizedBox(
                    width: 72,
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2.5,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5),
                        overlayShape:
                            const RoundSliderOverlayShape(overlayRadius: 9),
                        activeTrackColor: FyrTheme.accentColor,
                        thumbColor: FyrTheme.accentColor,
                      ),
                      child: Slider(
                        value: ctrl.masterVolume,
                        onChanged: (v) {
                          ctrl.masterVolume = v;
                          ctrl.refresh();
                        },
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

  Widget _buildLayer(
      DirectorController ctrl, TimelineClip clip, Size monitorSize) {
    final e = clip.effects;
    final alpha = _effectiveClipOpacity(clip, ctrl.playheadSec);
    if (alpha <= 0.01) return const SizedBox.shrink();

    final localT = ctrl.playheadSec - clip.timelineStartSec;
    double extraSlideX = 0.0;
    double extraScale = 1.0;
    if (e.transitionIn == TransitionKind.slideLeft &&
        localT < e.transitionDurationSec) {
      final p = (localT / max(0.05, e.transitionDurationSec)).clamp(0.0, 1.0);
      extraSlideX = (1.0 - p) * monitorSize.width;
    } else if (e.transitionIn == TransitionKind.zoomIn &&
        localT < e.transitionDurationSec) {
      final p = (localT / max(0.05, e.transitionDurationSec)).clamp(0.0, 1.0);
      extraScale = 0.6 + 0.4 * p;
    }

    Widget content;
    if (clip.type == MediaType.title) {
      final st = clip.titleStyle ?? TitleClipStyle();
      final scaleFactor = monitorSize.height / max(1, ctrl.sequence.height);
      content = Align(
        alignment: Alignment(0, st.posYRatio * 2.0 - 1.0),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16 * scaleFactor,
            vertical: 8 * scaleFactor,
          ),
          decoration: BoxDecoration(
            color: st.bgOpacity > 0.01
                ? st.bgColor.withValues(alpha: st.bgOpacity)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10 * scaleFactor),
          ),
          child: Text(
            st.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: st.fontFamily,
              fontSize: st.fontSize * scaleFactor,
              fontWeight: st.bold ? FontWeight.bold : FontWeight.normal,
              color: st.textColor,
              shadows: const [
                Shadow(
                    color: Colors.black87,
                    blurRadius: 6,
                    offset: Offset(1, 1)),
              ],
            ),
          ),
        ),
      );
    } else if (clip.type == MediaType.image) {
      final asset = ctrl.assetById(clip.assetId);
      content = asset != null && File(asset.path).existsSync()
          ? Image.file(File(asset.path), fit: BoxFit.contain)
          : const SizedBox.shrink();
    } else {
      content = ctrl.videoController != null
          ? Video(
              controller: ctrl.videoController!,
              controls: NoVideoControls,
              fit: BoxFit.contain,
            )
          : Container(color: Colors.black54);
    }

    if (e.blur > 0.3) {
      content = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: e.blur, sigmaY: e.blur),
        child: content,
      );
    }

    content = ColorFiltered(
      colorFilter: ColorFilter.matrix(_buildColorMatrix(e)),
      child: content,
    );

    content = Transform.translate(
      offset: Offset(
        e.offsetX * monitorSize.width + extraSlideX,
        e.offsetY * monitorSize.height,
      ),
      child: Transform.rotate(
        angle: e.rotationDeg * pi / 180.0,
        child: Transform.scale(
          scale: e.scale * extraScale,
          child: Opacity(opacity: alpha, child: content),
        ),
      ),
    );

    return content;
  }
}

class _SafeGuidesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    // Title-safe 80% & Action-safe 90%
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: size.width * 0.9,
        height: size.height * 0.9,
      ),
      p,
    );
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: size.width * 0.8,
        height: size.height * 0.8,
      ),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _SafeGuidesPainter oldDelegate) => false;
}
