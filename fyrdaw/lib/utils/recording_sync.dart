import 'dart:math';

/// Timeline placement computed for a newly recorded audio take after
/// compensating for capture startup arrival time and round-trip latency.
class RecordingSyncPlacement {
  final double clipStart;
  final double startOffset;
  final double clipLength;

  const RecordingSyncPlacement({
    required this.clipStart,
    required this.startOffset,
    required this.clipLength,
  });
}

/// Computes exact [RecordingSyncPlacement] for a recorded WAV take.
///
/// - [recordingStartPos]: Timeline position when recording/playback started.
/// - [firstChunkArrivedPlayhead]: Timeline position captured when the first
///   PCM chunk arrived from the mic/interface stream (after writing).
/// - [firstChunkFrames]: Frame count of that first PCM chunk (used to back-date
///   sample 0 of the chunk).
/// - [rawWavDurationSeconds]: Total duration of the written WAV file.
/// - [unitsPerSecond]: Timeline units per second (`100.0` at constant project BPM).
/// - [latencyCompensationMs]: Round-trip output+input latency in milliseconds
///   to pull recorded audio earlier into sync with the metronome grid.
RecordingSyncPlacement computeRecordingSyncPlacement({
  required double recordingStartPos,
  required double? firstChunkArrivedPlayhead,
  required int firstChunkFrames,
  required double rawWavDurationSeconds,
  double unitsPerSecond = 100.0,
  double latencyCompensationMs = 35.0,
  int sampleRate = 44100,
}) {
  final double safeUps = max(1.0, unitsPerSecond);
  final double rawLenUnits = max(10.0, rawWavDurationSeconds * safeUps);
  final double chunkUnits = (sampleRate > 0 && firstChunkFrames > 0)
      ? (firstChunkFrames / sampleRate) * safeUps
      : 0.0;
  final double chunkStartUnits =
      (firstChunkArrivedPlayhead ?? recordingStartPos) - chunkUnits;
  final double compUnits =
      (latencyCompensationMs.clamp(0.0, 500.0) / 1000.0) * safeUps;
  final double compensatedAudioStart = chunkStartUnits - compUnits;

  if (compensatedAudioStart <= recordingStartPos) {
    final double preRoll = (recordingStartPos - compensatedAudioStart).clamp(
      0.0,
      max(0.0, rawLenUnits - 10.0),
    );
    return RecordingSyncPlacement(
      clipStart: recordingStartPos,
      startOffset: preRoll,
      clipLength: max(10.0, rawLenUnits - preRoll),
    );
  }

  return RecordingSyncPlacement(
    clipStart: compensatedAudioStart,
    startOffset: 0.0,
    clipLength: rawLenUnits,
  );
}
