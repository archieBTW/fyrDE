import 'dart:math';
import 'package:fyrdaw/models/tempo_marker.dart';
import 'package:fyrdaw/utils/timeline_grid.dart';

/// Represents a metronome beat event inside a playback window.
typedef MetronomeBeatEvent = ({double worldPos, bool isDownbeat});

/// Finds metronome beat clicks that should fire across `[fromPos, toPos]`.
///
/// Uses the exact same timeline beat grid as `RulerPainter` and `GridPainter`
/// (`(fromPos, toPos]`, plus `fromPos` within [startTolerance] when
/// [includeStart] is true) so metronome clicks and MIDI/Sampler drum notes
/// share identical beat boundaries.
List<MetronomeBeatEvent> collectMetronomeBeatsInWindow(
  double fromPos,
  double toPos, {
  required int baseBpm,
  required int baseTimeSigTop,
  List<TempoMarker> tempoMarkers = const [],
  bool includeStart = false,
  double startTolerance = 1.0,
}) {
  if (baseBpm <= 0) return const [];
  final double safeFrom = max(0.0, fromPos);
  final double safeTo = max(safeFrom, toPos);
  final double queryStart = max(0.0, safeFrom - max(1.0, startTolerance));
  final double queryEnd = safeTo + max(1.0, startTolerance);

  final lines = buildTimelineGridLines(
    clipStart: queryStart,
    visibleUnits: queryEnd - queryStart,
    zoomX: 1.0,
    baseBpm: baseBpm,
    baseTimeSigTop: baseTimeSigTop,
    tempoMarkers: tempoMarkers,
    subdivisionsPerBeatOverride: 1,
  );

  final events = <MetronomeBeatEvent>[];
  for (final line in lines) {
    final bool atStart =
        includeStart && (line.worldPos - safeFrom).abs() <= startTolerance;
    final bool insideStep =
        line.worldPos > safeFrom + 1e-6 && line.worldPos <= safeTo + 1e-6;
    if (atStart || insideStep) {
      events.add((worldPos: line.worldPos, isDownbeat: line.isMeasure));
    }
  }
  return events;
}

/// Returns whether a clip-local MIDI/Sampler [noteStart] falls inside the
/// playback interval `[windowStart, windowEnd]`, using `(windowStart, windowEnd]`
/// during streaming ticks (matching metronome `(fromPos, toPos]`) and also
/// matching [windowStart] within `1e-4` when [includeStart] is true (play start,
/// seek, or loop wrap).
bool shouldTriggerMidiNoteInWindow({
  required double noteStart,
  required double windowStart,
  required double windowEnd,
  bool includeStart = false,
}) {
  if (includeStart && (noteStart - windowStart).abs() <= 1e-4) {
    return true;
  }
  return noteStart > windowStart && noteStart <= windowEnd;
}
