import 'dart:io';
import 'dart:typed_data';

class WavWriter {
  final RandomAccessFile _file;
  int _audioDataLength = 0;
  final int sampleRate;
  final int channels;

  WavWriter(String path, {this.sampleRate = 44100, this.channels = 1})
    : _file = File(path).openSync(mode: FileMode.write) {
    // Reserve 44 bytes for header
    _file.writeFromSync(Uint8List(44));
  }

  void write(Uint8List pcmData) {
    _file.writeFromSync(pcmData);
    _audioDataLength += pcmData.length;
  }

  void close() {
    _file.setPositionSync(0);
    int byteRate = sampleRate * channels * 2;

    var header = ByteData(44);
    header.setUint8(0, 82);
    header.setUint8(1, 73);
    header.setUint8(2, 70);
    header.setUint8(3, 70);
    header.setUint32(4, 36 + _audioDataLength, Endian.little);
    header.setUint8(8, 87);
    header.setUint8(9, 65);
    header.setUint8(10, 86);
    header.setUint8(11, 69);
    header.setUint8(12, 102);
    header.setUint8(13, 109);
    header.setUint8(14, 116);
    header.setUint8(15, 32);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, channels * 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint8(36, 100);
    header.setUint8(37, 97);
    header.setUint8(38, 116);
    header.setUint8(39, 97);
    header.setUint32(40, _audioDataLength, Endian.little);

    _file.writeFromSync(header.buffer.asUint8List());
    _file.closeSync();
  }
}
