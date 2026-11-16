import 'dart:math';

/// Vertical and horizontal bounds of a single clip inside a track lane.
class TimelineClipLayout {
  final String clipId;
  final double start;
  final double length;
  final double topPadding;
  final double bottomPadding;

  const TimelineClipLayout({
    required this.clipId,
    required this.start,
    required this.length,
    this.topPadding = 10.0,
    this.bottomPadding = 10.0,
  });
}

/// Vertical bounds and clips of a visible track row in timeline content coordinates.
class TimelineTrackRowLayout {
  final String trackId;
  final double top;
  final double bottom;
  final List<TimelineClipLayout> clips;

  const TimelineTrackRowLayout({
    required this.trackId,
    required this.top,
    required this.bottom,
    required this.clips,
  });
}

/// Result of a 2D timeline marquee drag selection.
class MarqueeSelectionResult {
  final Set<String> trackIds;
  final Set<String> clipIds;

  const MarqueeSelectionResult({
    required this.trackIds,
    required this.clipIds,
  });
}

/// Result of clicking a track with optional Shift / Ctrl-or-Cmd modifiers.
class TrackClickSelectionResult {
  final Set<String> selectedTrackIds;
  final int? primaryIndex;
  final int? anchorIndex;

  const TrackClickSelectionResult({
    required this.selectedTrackIds,
    required this.primaryIndex,
    required this.anchorIndex,
  });
}

bool _intervalsOverlap(double aStart, double aEnd, double bStart, double bEnd) {
  if (aStart == aEnd) {
    return aStart >= bStart && aStart < bEnd;
  }
  return aEnd > bStart && aStart < bEnd;
}

/// Computes which tracks and clips intersect the 2D marquee rectangle
/// (`[minX, maxX]` in timeline units, `[minY, maxY]` in vertical content px),
/// matching desktop filesystem box selection: dragging horizontally within one
/// track selects only that track and its intersecting clips; dragging vertically
/// across tracks selects all intersected tracks and clips.
MarqueeSelectionResult computeTimelineMarqueeSelection(
  List<TimelineTrackRowLayout> rows, {
  required double minX,
  required double maxX,
  required double minY,
  required double maxY,
}) {
  final selectedTracks = <String>{};
  final selectedClips = <String>{};

  final double x0 = min(minX, maxX);
  final double x1 = max(minX, maxX);
  final double y0 = min(minY, maxY);
  final double y1 = max(minY, maxY);

  for (final row in rows) {
    if (!_intervalsOverlap(y0, y1, row.top, row.bottom)) continue;
    selectedTracks.add(row.trackId);

    for (final clip in row.clips) {
      final double clipTop = row.top + clip.topPadding;
      final double clipBottom = max(clipTop, row.bottom - clip.bottomPadding);
      if (!_intervalsOverlap(y0, y1, clipTop, clipBottom)) continue;
      if (_intervalsOverlap(x0, x1, clip.start, clip.start + clip.length)) {
        selectedClips.add(clip.clipId);
      }
    }
  }

  return MarqueeSelectionResult(
    trackIds: selectedTracks,
    clipIds: selectedClips,
  );
}

/// Resolves track selection when clicking [clickedIndex] with optional
/// Shift (range select from [anchorIndex]) or Ctrl/Cmd (individual toggle).
TrackClickSelectionResult resolveTrackClickSelection({
  required List<String> trackIds,
  required List<bool> trackVisible,
  required Set<String> currentSelectedIds,
  required int? anchorIndex,
  required int clickedIndex,
  required bool isShiftPressed,
  required bool isCtrlOrMetaPressed,
}) {
  if (clickedIndex < 0 || clickedIndex >= trackIds.length) {
    return const TrackClickSelectionResult(
      selectedTrackIds: <String>{},
      primaryIndex: null,
      anchorIndex: null,
    );
  }

  if (isShiftPressed) {
    final int anchor =
        (anchorIndex != null && anchorIndex >= 0 && anchorIndex < trackIds.length)
            ? anchorIndex
            : clickedIndex;
    final int lo = min(anchor, clickedIndex);
    final int hi = max(anchor, clickedIndex);
    final next = isCtrlOrMetaPressed ? {...currentSelectedIds} : <String>{};
    for (int i = lo; i <= hi; i++) {
      if (i < trackVisible.length && trackVisible[i]) {
        next.add(trackIds[i]);
      }
    }
    if (next.isEmpty) {
      next.add(trackIds[clickedIndex]);
    }
    return TrackClickSelectionResult(
      selectedTrackIds: next,
      primaryIndex: clickedIndex,
      anchorIndex: anchor,
    );
  }

  if (isCtrlOrMetaPressed) {
    final clickedId = trackIds[clickedIndex];
    final next = {...currentSelectedIds};
    if (next.contains(clickedId)) {
      next.remove(clickedId);
      int? nextPrimary;
      for (int i = trackIds.length - 1; i >= 0; i--) {
        if (next.contains(trackIds[i])) {
          nextPrimary = i;
          break;
        }
      }
      return TrackClickSelectionResult(
        selectedTrackIds: next,
        primaryIndex: nextPrimary,
        anchorIndex: nextPrimary,
      );
    } else {
      next.add(clickedId);
      return TrackClickSelectionResult(
        selectedTrackIds: next,
        primaryIndex: clickedIndex,
        anchorIndex: clickedIndex,
      );
    }
  }

  return TrackClickSelectionResult(
    selectedTrackIds: {trackIds[clickedIndex]},
    primaryIndex: clickedIndex,
    anchorIndex: clickedIndex,
  );
}
