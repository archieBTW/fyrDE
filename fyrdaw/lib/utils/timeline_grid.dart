import 'package:fyrdaw/models/tempo_marker.dart';

/// Chooses adaptive beat subdivisions (`1, 2, 4, 8, 16`) from the rendered
/// pixel width of a single beat so zooming in reveals progressively finer cells
/// (`1/8`, `1/16`, `1/32`, `1/64`) instead of just stretching existing cells.
int computeGridSubdivisionsPerBeat(double beatWidthPx) {
  if (beatWidthPx >= 360.0) return 16;
  if (beatWidthPx >= 180.0) return 8;
  if (beatWidthPx >= 72.0) return 4;
  if (beatWidthPx >= 32.0) return 2;
  return 1;
}

/// Human-readable denominator label (`1/4` .. `1/64`) for a subdivision count.
String gridSubdivisionLabel(int subdivisionsPerBeat) {
  switch (subdivisionsPerBeat) {
    case 16:
      return '1/64';
    case 8:
      return '1/32';
    case 4:
      return '1/16';
    case 2:
      return '1/8';
    default:
      return '1/4';
  }
}

/// A single vertical grid / ruler division aligned to the project timeline.
class TimelineGridLine {
  final double worldPos;
  final double localPos;
  final int measureNumber;
  final int beatInMeasure;
  final int subIndex;
  final int subdivisionsPerBeat;

  const TimelineGridLine({
    required this.worldPos,
    required this.localPos,
    required this.measureNumber,
    required this.beatInMeasure,
    required this.subIndex,
    required this.subdivisionsPerBeat,
  });

  bool get isMeasure => beatInMeasure == 0 && subIndex == 0;
  bool get isBeat => subIndex == 0;
}

/// Generates timeline-aligned vertical grid lines starting from world `0.0`
/// across `[clipStart, clipStart + visibleUnits]`, honoring [baseBpm],
/// [baseTimeSigTop], [tempoMarkers], and adaptive zoom subdivisions.
List<TimelineGridLine> buildTimelineGridLines({
  required double clipStart,
  required double visibleUnits,
  required double zoomX,
  required int baseBpm,
  required int baseTimeSigTop,
  List<TempoMarker> tempoMarkers = const [],
  int? subdivisionsPerBeatOverride,
}) {
  if (visibleUnits <= 0 || zoomX <= 0 || baseBpm <= 0) return const [];

  final double safeClipStart = clipStart < 0 ? 0.0 : clipStart;
  final double windowEnd = safeClipStart + visibleUnits;
  final int safeBaseTop = baseTimeSigTop < 1 ? 4 : baseTimeSigTop;
  final lines = <TimelineGridLine>[];

  int beatNum = 0;
  int measure = 1;
  int beatInMeasure = 0;
  double worldBeatStart = 0.0;

  while (worldBeatStart <= windowEnd + 1e-6 && beatNum < 8000) {
    final meter = TempoMarker.effectiveMeterAt(
      worldBeatStart,
      tempoMarkers,
      safeBaseTop,
      4,
    );
    final int activeTop = meter.numerator < 1 ? safeBaseTop : meter.numerator;
    final double localBpm = TempoMarker.effectiveBpmAt(
      worldBeatStart,
      tempoMarkers,
      baseBpm.toDouble(),
    );
    final double beatUnits = (100.0 * 60.0 / localBpm).clamp(4.0, 2000.0);
    final double worldBeatEnd = worldBeatStart + beatUnits;

    if (worldBeatEnd >= safeClipStart - 1e-6) {
      final int subdivisions =
          subdivisionsPerBeatOverride ??
          computeGridSubdivisionsPerBeat(beatUnits * zoomX);
      for (int s = 0; s < subdivisions; s++) {
        final double subWorld = worldBeatStart + (beatUnits * s / subdivisions);
        if (subWorld >= safeClipStart - 1e-6 && subWorld <= windowEnd + 1e-6) {
          lines.add(
            TimelineGridLine(
              worldPos: subWorld,
              localPos: (subWorld - safeClipStart).clamp(0.0, visibleUnits),
              measureNumber: measure,
              beatInMeasure: beatInMeasure,
              subIndex: s,
              subdivisionsPerBeat: subdivisions,
            ),
          );
        }
      }
    }

    beatNum++;
    beatInMeasure = (beatInMeasure + 1) % activeTop;
    if (beatInMeasure == 0) {
      measure++;
    }
    worldBeatStart = worldBeatEnd;
  }

  return lines;
}

/// Snaps [worldPos] onto the active adaptive timeline grid step at [worldPos].
double snapWorldPositionToTimelineGrid(
  double worldPos, {
  required int baseBpm,
  required int baseTimeSigTop,
  required double zoomX,
  List<TempoMarker> tempoMarkers = const [],
  bool floorMode = false,
}) {
  final double clampedWorld = worldPos < 0 ? 0.0 : worldPos;
  final int safeBaseTop = baseTimeSigTop < 1 ? 4 : baseTimeSigTop;

  int beatNum = 0;
  int beatInMeasure = 0;
  double worldBeatStart = 0.0;

  while (beatNum < 8000) {
    final meter = TempoMarker.effectiveMeterAt(
      worldBeatStart,
      tempoMarkers,
      safeBaseTop,
      4,
    );
    final int activeTop = meter.numerator < 1 ? safeBaseTop : meter.numerator;
    final double localBpm = TempoMarker.effectiveBpmAt(
      worldBeatStart,
      tempoMarkers,
      baseBpm.toDouble(),
    );
    final double beatUnits = (100.0 * 60.0 / localBpm).clamp(4.0, 2000.0);
    final double worldBeatEnd = worldBeatStart + beatUnits;

    if (clampedWorld < worldBeatEnd || beatNum == 7999) {
      final int subdivisions = computeGridSubdivisionsPerBeat(
        beatUnits * (zoomX > 0 ? zoomX : 1.0),
      );
      final double step = beatUnits / subdivisions;
      final double offsetInBeat = (clampedWorld - worldBeatStart).clamp(0.0, beatUnits);
      final int stepIdx = floorMode
          ? (offsetInBeat / step).floor()
          : (offsetInBeat / step).round();
      return worldBeatStart + stepIdx * step;
    }

    beatNum++;
    beatInMeasure = (beatInMeasure + 1) % activeTop;
    worldBeatStart = worldBeatEnd;
  }
  return clampedWorld;
}

/// Returns the adaptive subdivision step size in timeline units at [worldPos].
double adaptiveGridStepAtWorldPos(
  double worldPos, {
  required int baseBpm,
  required double zoomX,
  List<TempoMarker> tempoMarkers = const [],
}) {
  final double localBpm = TempoMarker.effectiveBpmAt(
    worldPos < 0 ? 0.0 : worldPos,
    tempoMarkers,
    baseBpm.toDouble(),
  );
  final double beatUnits = (100.0 * 60.0 / localBpm).clamp(4.0, 2000.0);
  final int subdivisions = computeGridSubdivisionsPerBeat(
    beatUnits * (zoomX > 0 ? zoomX : 1.0),
  );
  return beatUnits / subdivisions;
}
