import 'dart:io';
import 'dart:typed_data';

Future<void> reverseWavFile(String inputPath, String outputPath) async {
  final file = File(inputPath);
  final bytes = await file.readAsBytes();

  if (bytes.length < 44) return;

  int fmtOffset = 12;
  while (fmtOffset < bytes.length - 8) {
    String chunkId = String.fromCharCodes(
      bytes.sublist(fmtOffset, fmtOffset + 4),
    );
    if (chunkId == 'fmt ') break;
    int chunkSize =
        bytes[fmtOffset + 4] |
        (bytes[fmtOffset + 5] << 8) |
        (bytes[fmtOffset + 6] << 16) |
        (bytes[fmtOffset + 7] << 24);
    fmtOffset += 8 + chunkSize;
  }

  int numChannels = bytes[fmtOffset + 10] | (bytes[fmtOffset + 11] << 8);
  int bitsPerSample = bytes[fmtOffset + 22] | (bytes[fmtOffset + 23] << 8);
  int bytesPerFrame = numChannels * (bitsPerSample ~/ 8);
  if (bytesPerFrame <= 0) bytesPerFrame = 2;

  int dataOffset = 12;
  int dataSize = 0;
  while (dataOffset < bytes.length - 8) {
    String chunkId = String.fromCharCodes(
      bytes.sublist(dataOffset, dataOffset + 4),
    );
    int chunkSize =
        bytes[dataOffset + 4] |
        (bytes[dataOffset + 5] << 8) |
        (bytes[dataOffset + 6] << 16) |
        (bytes[dataOffset + 7] << 24);
    if (chunkId == 'data') {
      dataSize = chunkSize;
      dataOffset += 8;
      break;
    }
    dataOffset += 8 + chunkSize;
  }

  if (dataOffset >= bytes.length || dataSize == 0) return;
  if (dataOffset + dataSize > bytes.length) {
    dataSize = bytes.length - dataOffset;
  }

  Uint8List newBytes = Uint8List.fromList(bytes);
  int numFrames = dataSize ~/ bytesPerFrame;

  for (int i = 0; i < numFrames ~/ 2; i++) {
    int srcIdx = dataOffset + i * bytesPerFrame;
    int dstIdx = dataOffset + (numFrames - 1 - i) * bytesPerFrame;
    for (int b = 0; b < bytesPerFrame; b++) {
      if (dstIdx + b < newBytes.length && srcIdx + b < newBytes.length) {
        int temp = newBytes[srcIdx + b];
        newBytes[srcIdx + b] = newBytes[dstIdx + b];
        newBytes[dstIdx + b] = temp;
      }
    }
  }

  await File(outputPath).writeAsBytes(newBytes);
}

Future<List<double>?> extractWavWaveform(String path, int chunks) async {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final bytes = await file.readAsBytes();
    if (bytes.length < 44) return null;

    int fmtOffset = 12;
    int bytesPerFrame = 2;
    while (fmtOffset < bytes.length - 8) {
      String chunkId = String.fromCharCodes(
        bytes.sublist(fmtOffset, fmtOffset + 4),
      );
      if (chunkId == 'fmt ') {
        int numChannels = bytes[fmtOffset + 10] | (bytes[fmtOffset + 11] << 8);
        int bitsPerSample =
            bytes[fmtOffset + 22] | (bytes[fmtOffset + 23] << 8);
        bytesPerFrame = numChannels * (bitsPerSample ~/ 8);
        if (bytesPerFrame <= 0) bytesPerFrame = 2;
        break;
      }
      int chunkSize =
          bytes[fmtOffset + 4] |
          (bytes[fmtOffset + 5] << 8) |
          (bytes[fmtOffset + 6] << 16) |
          (bytes[fmtOffset + 7] << 24);
      fmtOffset += 8 + chunkSize;
    }

    int dataOffset = 12;
    int dataSize = 0;
    while (dataOffset < bytes.length - 8) {
      String chunkId = String.fromCharCodes(
        bytes.sublist(dataOffset, dataOffset + 4),
      );
      int chunkSize =
          bytes[dataOffset + 4] |
          (bytes[dataOffset + 5] << 8) |
          (bytes[dataOffset + 6] << 16) |
          (bytes[dataOffset + 7] << 24);
      if (chunkId == 'data') {
        dataSize = chunkSize;
        dataOffset += 8;
        break;
      }
      dataOffset += 8 + chunkSize;
    }

    if (dataSize == 0 || dataOffset >= bytes.length) return null;
    if (dataOffset + dataSize > bytes.length) {
      dataSize = bytes.length - dataOffset;
    }

    int numFrames = dataSize ~/ bytesPerFrame;
    if (numFrames <= 0) return null;
    
    int framesPerChunk = numFrames ~/ chunks;
    if (framesPerChunk <= 0) framesPerChunk = 1;
    int actualChunks = numFrames < chunks ? numFrames : chunks;

    List<double> data = [];
    for (int i = 0; i < actualChunks; i++) {
      double maxAmp = 0;
      for (int j = 0; j < framesPerChunk; j++) {
        int frameIdx = i * framesPerChunk + j;
        int index = dataOffset + frameIdx * bytesPerFrame;
        if (index + 1 < bytes.length) {
          int sample = bytes[index] | (bytes[index + 1] << 8);
          if (sample > 32767) sample -= 65536;
          double amp = sample.abs() / 32768.0;
          if (amp > maxAmp) maxAmp = amp;
        }
      }
      data.add(maxAmp);
    }
    return data;
  } catch (e) {
    return null;
  }
}
