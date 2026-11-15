import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:fyrdaw/models/midi_note.dart';

class MidiImportResult {
  final double? detectedBpm;
  final int timeSigNum;
  final int timeSigDen;
  final String trackName;
  final List<MidiNote> notes;

  MidiImportResult({
    this.detectedBpm,
    this.timeSigNum = 4,
    this.timeSigDen = 4,
    this.trackName = 'Imported MIDI',
    required this.notes,
  });
}

/// Standard MIDI File (SMF Type 0 & Type 1) decoder and encoder.
class MidiFileCodec {
  static MidiImportResult decodeBytes(
    Uint8List bytes, {
    double beatWidth = 50.0,
  }) {
    if (bytes.length < 14) {
      throw const FormatException('File is too small to be a valid MIDI file.');
    }
    final bd = ByteData.sublistView(bytes);
    if (ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'MThd') {
      throw const FormatException('Missing MThd MIDI header chunk.');
    }
    final int headerLen = bd.getUint32(4, Endian.big);
    final int numTracks = bd.getUint16(10, Endian.big);
    final int division = bd.getUint16(12, Endian.big);
    final int ppqn = (division & 0x8000) == 0 ? max(1, division) : 480;

    int offset = 8 + headerLen;
    double? detectedBpm;
    int timeSigNum = 4;
    int timeSigDen = 4;
    String trackName = 'Imported MIDI';
    final List<MidiNote> notes = [];

    for (int t = 0; t < numTracks && offset + 8 <= bytes.length; t++) {
      final chunkId = ascii.decode(
        bytes.sublist(offset, offset + 4),
        allowInvalid: true,
      );
      final int chunkLen = bd.getUint32(offset + 4, Endian.big);
      offset += 8;
      final int trackEnd = min(bytes.length, offset + chunkLen);

      if (chunkId != 'MTrk') {
        offset = trackEnd;
        continue;
      }

      int pos = offset;
      int absTicks = 0;
      int runningStatus = 0;
      // Active note-on starts keyed by (channel << 8) | pitch
      final Map<int, List<({int tick, int velocity})>> activeNotes = {};

      int readVlq() {
        int val = 0;
        for (int i = 0; i < 4 && pos < trackEnd; i++) {
          final int b = bytes[pos++];
          val = (val << 7) | (b & 0x7F);
          if ((b & 0x80) == 0) break;
        }
        return val;
      }

      while (pos < trackEnd) {
        absTicks += readVlq();
        if (pos >= trackEnd) break;

        int status = bytes[pos];
        if ((status & 0x80) != 0) {
          pos++;
          if (status < 0xF0) {
            runningStatus = status;
          }
        } else {
          status = runningStatus;
        }

        if (status == 0xFF) {
          // Meta event
          if (pos >= trackEnd) break;
          final int metaType = bytes[pos++];
          final int metaLen = readVlq();
          final int dataEnd = min(trackEnd, pos + metaLen);
          if (metaType == 0x51 && metaLen == 3 && pos + 3 <= trackEnd) {
            final int usPerQuarter =
                (bytes[pos] << 16) | (bytes[pos + 1] << 8) | bytes[pos + 2];
            if (usPerQuarter > 0) {
              detectedBpm ??= (60000000.0 / usPerQuarter).clamp(20.0, 300.0);
            }
          } else if (metaType == 0x58 && metaLen >= 2 && pos + 2 <= trackEnd) {
            timeSigNum = max(1, bytes[pos]);
            timeSigDen = 1 << bytes[pos + 1].clamp(0, 5);
          } else if (metaType == 0x03 && metaLen > 0) {
            final name = utf8
                .decode(bytes.sublist(pos, dataEnd), allowMalformed: true)
                .trim();
            if (name.isNotEmpty && trackName == 'Imported MIDI') {
              trackName = name;
            }
          }
          pos = dataEnd;
        } else if (status == 0xF0 || status == 0xF7) {
          final int sysLen = readVlq();
          pos = min(trackEnd, pos + sysLen);
        } else {
          final int cmd = status & 0xF0;
          final int ch = status & 0x0F;
          final int data1 = pos < trackEnd ? bytes[pos++] : 0;
          int data2 = 0;
          if (cmd != 0xC0 && cmd != 0xD0) {
            data2 = pos < trackEnd ? bytes[pos++] : 0;
          }

          if (cmd == 0x90 && data2 > 0) {
            final key = (ch << 8) | data1;
            activeNotes
                .putIfAbsent(key, () => [])
                .add((tick: absTicks, velocity: data2));
          } else if (cmd == 0x80 || (cmd == 0x90 && data2 == 0)) {
            final key = (ch << 8) | data1;
            final q = activeNotes[key];
            if (q != null && q.isNotEmpty) {
              final startEv = q.removeAt(0);
              final double startTimeline = (startEv.tick / ppqn) * beatWidth;
              final double durTimeline = max(
                beatWidth * 0.125,
                ((absTicks - startEv.tick) / ppqn) * beatWidth,
              );
              notes.add(
                MidiNote(
                  pitch: data1.clamp(0, 127),
                  start: startTimeline,
                  length: durTimeline,
                  velocity: startEv.velocity.clamp(1, 127),
                ),
              );
            }
          }
        }
      }

      // Close any hanging notes gracefully
      for (final entry in activeNotes.entries) {
        final int pitch = (entry.key & 0xFF).clamp(0, 127);
        for (final startEv in entry.value) {
          notes.add(
            MidiNote(
              pitch: pitch,
              start: (startEv.tick / ppqn) * beatWidth,
              length: beatWidth * 0.5,
              velocity: startEv.velocity.clamp(1, 127),
            ),
          );
        }
      }

      offset = trackEnd;
    }

    notes.sort((a, b) => a.start.compareTo(b.start));
    return MidiImportResult(
      detectedBpm: detectedBpm,
      timeSigNum: timeSigNum,
      timeSigDen: timeSigDen,
      trackName: trackName,
      notes: notes,
    );
  }

  /// Encodes [notes] as a Type 0 Standard MIDI File (.mid) with tempo & time sig.
  static Uint8List encodeNotes(
    List<MidiNote> notes, {
    double bpm = 120.0,
    int timeSigNum = 4,
    int timeSigDen = 4,
    double beatWidth = 50.0,
    String trackName = 'Sound Booth Export',
  }) {
    const int ppqn = 480;
    final List<({int tick, List<int> data})> events = [];

    // Tempo meta event
    final int usPerQuarter = (60000000.0 / bpm.clamp(20.0, 300.0)).round();
    events.add((
      tick: 0,
      data: [
        0xFF,
        0x51,
        0x03,
        (usPerQuarter >> 16) & 0xFF,
        (usPerQuarter >> 8) & 0xFF,
        usPerQuarter & 0xFF,
      ],
    ));

    // Time signature meta event
    final int denPow = (log(max(1, timeSigDen)) / ln2).round().clamp(0, 5);
    events.add((
      tick: 0,
      data: [0xFF, 0x58, 0x04, timeSigNum.clamp(1, 16), denPow, 24, 8],
    ));

    // Track name
    final nameBytes = utf8.encode(trackName);
    events.add((
      tick: 0,
      data: [0xFF, 0x03, nameBytes.length.clamp(0, 127), ...nameBytes.take(127)],
    ));

    for (final n in notes) {
      final int startTick = max(0, ((n.start / beatWidth) * ppqn).round());
      final int endTick = max(
        startTick + 1,
        (((n.start + n.length) / beatWidth) * ppqn).round(),
      );
      final int p = n.pitch.clamp(0, 127);
      final int v = n.velocity.clamp(1, 127);
      events.add((tick: startTick, data: [0x90, p, v]));
      events.add((tick: endTick, data: [0x80, p, 0]));
    }

    events.sort((a, b) => a.tick.compareTo(b.tick));

    final trackBuf = BytesBuilder();
    void writeVlq(int val) {
      final List<int> stack = [val & 0x7F];
      int v = val >> 7;
      while (v > 0) {
        stack.add((v & 0x7F) | 0x80);
        v >>= 7;
      }
      for (int i = stack.length - 1; i >= 0; i--) {
        trackBuf.addByte(stack[i]);
      }
    }

    int lastTick = 0;
    for (final ev in events) {
      writeVlq(max(0, ev.tick - lastTick));
      trackBuf.add(ev.data);
      lastTick = ev.tick;
    }
    // End of track
    writeVlq(0);
    trackBuf.add([0xFF, 0x2F, 0x00]);

    final trackBytes = trackBuf.toBytes();
    final header = ByteData(14);
    header.setUint32(0, 0x4D546864, Endian.big); // MThd
    header.setUint32(4, 6, Endian.big);
    header.setUint16(8, 0, Endian.big); // Format 0
    header.setUint16(10, 1, Endian.big); // 1 track
    header.setUint16(12, ppqn, Endian.big);

    final trackHdr = ByteData(8);
    trackHdr.setUint32(0, 0x4D54726B, Endian.big); // MTrk
    trackHdr.setUint32(4, trackBytes.length, Endian.big);

    return Uint8List.fromList([
      ...header.buffer.asUint8List(),
      ...trackHdr.buffer.asUint8List(),
      ...trackBytes,
    ]);
  }
}
