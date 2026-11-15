import 'dart:math';
import 'package:flutter/material.dart';
import 'package:fyrdaw/main.dart';
import 'package:fyrdaw/models/daw_clip.dart';
import 'package:fyrdaw/models/enums.dart';
import 'package:fyrdaw/models/track.dart';

/// Ableton-style Live Session / Clip Launcher Grid view.
/// Lets producers trigger individual clips or full horizontal scenes, quantized
/// to the next bar (or immediately when stopped), alongside live Mute/Solo controls.
class SessionLauncherView extends StatelessWidget {
  final List<Track> tracks;
  final Map<String, List<DawClip>> trackClips;
  final double playheadPosition;
  final bool isPlaying;
  final Set<String> activeSessionClipIds;
  final Set<String> queuedSessionClipIds;
  final void Function(Track track, DawClip clip) onTriggerClip;
  final void Function(int sceneIndex) onTriggerScene;
  final void Function(Track track) onStopTrack;
  final void Function(Track track) onToggleMute;
  final void Function(Track track) onToggleSolo;
  final void Function(Track track, DawClip clip) onOpenClipEditor;

  const SessionLauncherView({
    super.key,
    required this.tracks,
    required this.trackClips,
    required this.playheadPosition,
    required this.isPlaying,
    required this.activeSessionClipIds,
    required this.queuedSessionClipIds,
    required this.onTriggerClip,
    required this.onTriggerScene,
    required this.onStopTrack,
    required this.onToggleMute,
    required this.onToggleSolo,
    required this.onOpenClipEditor,
  });

  @override
  Widget build(BuildContext context) {
    final sessionTracks =
        tracks.where((t) => t.type != TrackType.group).toList();
    int maxScenes = 4;
    for (final t in sessionTracks) {
      final len = (trackClips[t.id] ?? const <DawClip>[]).length;
      if (len > maxScenes) maxScenes = len;
    }

    if (sessionTracks.isEmpty) {
      return Container(
        color: bgDark,
        child: Center(
          child: Text(
            'Add Audio, MIDI, or Sampler tracks to launch clips in Session View.',
            style: TextStyle(color: textMuted),
          ),
        ),
      );
    }

    return Container(
      color: bgDark,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tracks & Clips columns
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: sessionTracks.map((t) {
                  final clips = trackClips[t.id] ?? const <DawClip>[];
                  return Container(
                    width: 156,
                    margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(
                      color: panelDark,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: borderMain),
                    ),
                    child: Column(
                      children: [
                        // Track column header
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: panelLight,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(7),
                            ),
                            border: Border(
                              top: BorderSide(color: t.color, width: 3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  t.name,
                                  style: TextStyle(
                                    color: textMain,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              InkWell(
                                onTap: () => onToggleMute(t),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: t.isMuted
                                        ? Colors.redAccent
                                        : bgDark,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    'M',
                                    style: TextStyle(
                                      color: t.isMuted
                                          ? Colors.white
                                          : textMuted,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              InkWell(
                                onTap: () => onToggleSolo(t),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: t.isSolo
                                        ? Colors.amber
                                        : bgDark,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    'S',
                                    style: TextStyle(
                                      color: t.isSolo
                                          ? Colors.black
                                          : textMuted,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Scene slots
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(6),
                            itemCount: maxScenes,
                            itemBuilder: (ctx, rowIdx) {
                              if (rowIdx >= clips.length) {
                                return Container(
                                  height: 44,
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: bgDark.withValues(alpha: 0.5),
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                      color: borderMain.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Center(
                                    child: Text(
                                      'Empty',
                                      style: TextStyle(
                                        color: textFaint,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final clip = clips[rowIdx];
                              final bool isNowPlaying =
                                  isPlaying &&
                                  ((playheadPosition >= clip.start &&
                                          playheadPosition <
                                              clip.start + clip.length) ||
                                      activeSessionClipIds.contains(clip.id));
                              final bool isQueued =
                                  queuedSessionClipIds.contains(clip.id);
                              final String label = clip.name.isNotEmpty
                                  ? clip.name
                                  : 'Slot ${rowIdx + 1}';

                              return Container(
                                height: 44,
                                margin: const EdgeInsets.only(bottom: 6),
                                decoration: BoxDecoration(
                                  color: isNowPlaying
                                      ? clip.color.withValues(alpha: 0.4)
                                      : (isQueued
                                            ? Colors.amberAccent.withValues(
                                                alpha: 0.25,
                                              )
                                            : bgDark),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: isNowPlaying
                                        ? Colors.greenAccent
                                        : (isQueued
                                              ? Colors.amberAccent
                                              : clip.color.withValues(
                                                  alpha: 0.65,
                                                )),
                                    width: isNowPlaying || isQueued ? 1.8 : 1.0,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () => onTriggerClip(t, clip),
                                  onDoubleTap: () => onOpenClipEditor(t, clip),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isNowPlaying
                                              ? Icons.equalizer
                                              : (isQueued
                                                    ? Icons.schedule
                                                    : Icons.play_arrow),
                                          size: 16,
                                          color: isNowPlaying
                                              ? Colors.greenAccent
                                              : (isQueued
                                                    ? Colors.amberAccent
                                                    : clip.color),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            label,
                                            style: TextStyle(
                                              color: textMain,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            overflow: TextOverflow.ellipsis,
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
                        // Stop Track Clips footer
                        InkWell(
                          onTap: () => onStopTrack(t),
                          child: Container(
                            height: 28,
                            decoration: BoxDecoration(
                              color: panelLight,
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(7),
                              ),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.stop, size: 14, color: textMuted),
                                  const SizedBox(width: 4),
                                  Text(
                                    'STOP',
                                    style: TextStyle(
                                      color: textMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Master Scene Launch Column
          Container(
            width: 132,
            decoration: BoxDecoration(
              color: panelDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: lavenderAccent.withValues(alpha: 0.6)),
            ),
            child: Column(
              children: [
                Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: panelLight,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(7),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      'SCENES',
                      style: TextStyle(
                        color: lavenderLight,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(6),
                    itemCount: maxScenes,
                    itemBuilder: (ctx, rowIdx) {
                      return Container(
                        height: 44,
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: bgDark,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(color: lavenderAccent.withValues(alpha: 0.45)),
                        ),
                        child: InkWell(
                          onTap: () => onTriggerScene(rowIdx),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.play_circle_outline,
                                size: 16,
                                color: lavenderAccent,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Scene ${max(1, rowIdx + 1)}',
                                style: TextStyle(
                                  color: textMain,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

