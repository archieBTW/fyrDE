import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart' as bencoding;
import 'package:crypto/crypto.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/dtorrent_task.dart';
import 'package:test/test.dart';

Uint8List _buildWireMessage(int id, [List<int>? payload]) {
  final payloadLen = payload?.length ?? 0;
  final out = Uint8List(4 + 1 + payloadLen);
  final view = ByteData.view(out.buffer);
  view.setUint32(0, 1 + payloadLen, Endian.big);
  out[4] = id;
  if (payload != null && payload.isNotEmpty) {
    out.setRange(5, 5 + payloadLen, payload);
  }
  return out;
}

Uint8List _buildHandshake(List<int> infoHash, String peerId) {
  final out = Uint8List(68);
  out[0] = 19;
  out.setRange(1, 20, 'BitTorrent protocol'.codeUnits);
  // reserved all zeros (standard BEP-0003)
  out.setRange(28, 48, infoHash);
  out.setRange(48, 68, peerId.codeUnits);
  return out;
}

Future<Torrent> _createValidTorrent(Uint8List data, {int pieceLength = 32768}) async {
  final piecesBytes = <int>[];
  for (var offset = 0; offset < data.length; offset += pieceLength) {
    final end = (offset + pieceLength).clamp(0, data.length);
    piecesBytes.addAll(sha1.convert(data.sublist(offset, end)).bytes);
  }
  final torrentMap = <String, dynamic>{
    'info': <String, dynamic>{
      'name': 'endgame_sample.bin',
      'piece length': pieceLength,
      'pieces': Uint8List.fromList(piecesBytes),
      'length': data.length,
    },
  };
  return await Torrent.parse(Uint8List.fromList(bencoding.encode(torrentMap)));
}

class _MockSeederServer {
  final String bindIp;
  final Torrent torrent;
  final Uint8List data;
  final bool Function(int index, int begin)? shouldDropRequest;
  final bool chokeAfterFirstRequest;

  ServerSocket? _server;
  final List<List<int>> receivedCancels = [];
  final List<List<int>> receivedRequests = [];
  final List<Socket> _sockets = [];

  _MockSeederServer({
    required this.bindIp,
    required this.torrent,
    required this.data,
    this.shouldDropRequest,
    this.chokeAfterFirstRequest = false,
  });

  int get port => _server!.port;

  void _safeAdd(Socket socket, List<int> bytes) {
    try {
      socket.add(bytes);
    } catch (_) {
      // Peer closed connection after download completion
    }
  }

  Future<void> start(String peerId) async {
    _server = await ServerSocket.bind(InternetAddress(bindIp), 0);
    _server!.listen((socket) {
      _sockets.add(socket);
      socket.done.catchError((_) {});
      var handshaked = false;
      final buffer = <int>[];
      var requestCount = 0;

      socket.listen((chunk) {
        buffer.addAll(chunk);
        if (!handshaked && buffer.length >= 68) {
          handshaked = true;
          buffer.removeRange(0, 68);
          _safeAdd(socket, _buildHandshake(torrent.infoHashBuffer, peerId));
          // Send BITFIELD with all pieces set
          final byteLen = (torrent.pieces.length + 7) ~/ 8;
          final bf = Uint8List(byteLen);
          for (var i = 0; i < torrent.pieces.length; i++) {
            bf[i ~/ 8] |= 1 << (7 - (i % 8));
          }
          _safeAdd(socket, _buildWireMessage(5, bf));
          _safeAdd(socket, _buildWireMessage(1)); // UNCHOKE
        }

        while (handshaked && buffer.length >= 4) {
          final msgLen = ByteData.view(Uint8List.fromList(buffer.sublist(0, 4)).buffer)
              .getUint32(0, Endian.big);
          if (buffer.length < 4 + msgLen) break;
          if (msgLen == 0) {
            buffer.removeRange(0, 4);
            continue;
          }
          final id = buffer[4];
          final payload = buffer.sublist(5, 4 + msgLen);
          buffer.removeRange(0, 4 + msgLen);

          if (id == 6 && payload.length == 12) {
            final view = ByteData.view(Uint8List.fromList(payload).buffer);
            final index = view.getUint32(0, Endian.big);
            final begin = view.getUint32(4, Endian.big);
            final length = view.getUint32(8, Endian.big);
            receivedRequests.add([index, begin, length]);
            requestCount++;

            if (chokeAfterFirstRequest && requestCount == 1) {
              _safeAdd(socket, _buildWireMessage(0)); // CHOKE without replying
              continue;
            }

            if (shouldDropRequest != null && shouldDropRequest!(index, begin)) {
              // Simulate a stalled peer dropping this specific final block
              continue;
            }

            final offset = index * torrent.pieceLength + begin;
            final block = data.sublist(offset, offset + length);
            final piecePayload = Uint8List(8 + block.length);
            final pv = ByteData.view(piecePayload.buffer);
            pv.setUint32(0, index, Endian.big);
            pv.setUint32(4, begin, Endian.big);
            piecePayload.setRange(8, 8 + block.length, block);
            _safeAdd(socket, _buildWireMessage(7, piecePayload));
          } else if (id == 8 && payload.length == 12) {
            final view = ByteData.view(Uint8List.fromList(payload).buffer);
            receivedCancels.add([
              view.getUint32(0, Endian.big),
              view.getUint32(4, Endian.big),
              view.getUint32(8, Endian.big),
            ]);
          }
        }
      }, onError: (_) {});
    });
  }

  Future<void> stop() async {
    for (final s in _sockets) {
      await s.close().catchError((_) {});
      s.destroy();
    }
    await _server?.close();
  }
}

void main() {
  group('Endgame & Stall Recovery', () {
    test('Piece tracks missing in-flight subpieces and rejects duplicate writes after completion', () {
      final data = Uint8List(32768);
      final hash = sha1.convert(data).toString();
      final piece = Piece(hash, 0, 32768, 0);

      expect(piece.missingInFlightSubPieces, isEmpty);
      expect(piece.popSubPiece(), 0);
      expect(piece.popSubPiece(), 1);
      // Both sub-pieces popped and not received -> both are in-flight
      expect(piece.missingInFlightSubPieces, equals([0, 1]));

      expect(piece.subPieceReceived(0, data.sublist(0, 16384)), isTrue);
      expect(piece.missingInFlightSubPieces, equals([1]));

      // Duplicate delivery returns false
      expect(piece.subPieceReceived(0, data.sublist(0, 16384)), isFalse);

      expect(piece.subPieceReceived(16384, data.sublist(16384, 32768)), isTrue);
      expect(piece.isCompleted, isTrue);
      expect(piece.missingInFlightSubPieces, isEmpty);
    });

    test('Peer.clearPendingRequestsOnChoke returns non-allowFast pending requests immediately', () {
      final peer = Peer.newTCPPeer(
        CompactAddress(InternetAddress('127.0.0.2'), 6881),
        List<int>.filled(20, 1),
        4,
        null,
        PeerSource.manual,
      );
      peer.chokeMe = false;
      expect(peer.addRequest(0, 0, 16384), isTrue);
      expect(peer.addRequest(1, 16384, 16384), isTrue);
      expect(peer.hasPendingRequest(1, 16384), isTrue);

      final reclaimed = peer.clearPendingRequestsOnChoke();
      expect(reclaimed.length, 2);
      expect(peer.isSleeping, isTrue);
      expect(peer.hasPendingRequest(1, 16384), isFalse);
    });

    test('Endgame mode completes final stalled block via healthy seeder without timeout wait', () async {
      final data = Uint8List.fromList(
        List<int>.generate(60000, (i) => (i * 31 + 7) & 0xff),
      );
      final torrent = await _createValidTorrent(data, pieceLength: 32768);
      final tmpDir = await Directory.systemTemp.createTemp('dtorrent_endgame_');

      // Seeder 1 stalls on the very last block (piece 1, begin 16384)
      final stalledSeeder = _MockSeederServer(
        bindIp: '127.0.0.2',
        torrent: torrent,
        data: data,
        shouldDropRequest: (index, begin) => index == 1 && begin == 16384,
      );
      // Seeder 2 serves everything
      final healthySeeder = _MockSeederServer(
        bindIp: '127.0.0.3',
        torrent: torrent,
        data: data,
      );

      await stalledSeeder.start('-STALL00000000000001');
      await healthySeeder.start('-HEALTHY000000000002');

      final task = TorrentTask.newTask(torrent, tmpDir.path);
      final completed = Completer<void>();
      final listener = task.createListener();
      listener.on<TaskCompleted>((_) {
        if (!completed.isCompleted) completed.complete();
      });

      try {
        await task.start();
        task.addPeer(
          CompactAddress(InternetAddress('127.0.0.2'), stalledSeeder.port),
          PeerSource.manual,
        );

        // Wait until stalledSeeder has received the final block request so only that block is in-flight
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!stalledSeeder.receivedRequests
                .any((r) => r[0] == 1 && r[1] == 16384) &&
            DateTime.now().isBefore(deadline)) {
          await Future.delayed(const Duration(milliseconds: 50));
        }
        expect(
          stalledSeeder.receivedRequests.any((r) => r[0] == 1 && r[1] == 16384),
          isTrue,
          reason: 'Stalled seeder should have popped the final block first',
        );

        // Now connect healthy seeder while all remaining blocks are already in-flight on stalledSeeder.
        // Without endgame mode, healthySeeder would sit idle and stall for minutes.
        task.addPeer(
          CompactAddress(InternetAddress('127.0.0.3'), healthySeeder.port),
          PeerSource.manual,
        );

        await completed.future.timeout(const Duration(seconds: 4));

        // Verify downloaded file contents match 100%
        final outFile = File('${tmpDir.path}/endgame_sample.bin');
        expect(outFile.existsSync(), isTrue);
        expect(await outFile.readAsBytes(), equals(data));

        // Verify CANCEL was sent to the stalled peer for the endgame block
        expect(
          stalledSeeder.receivedCancels.any((c) => c[0] == 1 && c[1] == 16384),
          isTrue,
          reason: 'Should cancel duplicate request on stalled seeder after completion',
        );
      } finally {
        listener.dispose();
        await task.stop();
        await stalledSeeder.stop();
        await healthySeeder.stop();
        await tmpDir.delete(recursive: true);
      }
    });

    test('Peer choking immediately frees pending blocks for other seeders', () async {
      final data = Uint8List.fromList(
        List<int>.generate(60000, (i) => (i * 17 + 3) & 0xff),
      );
      final torrent = await _createValidTorrent(data, pieceLength: 32768);
      final tmpDir = await Directory.systemTemp.createTemp('dtorrent_choke_');

      final chokingSeeder = _MockSeederServer(
        bindIp: '127.0.0.4',
        torrent: torrent,
        data: data,
        chokeAfterFirstRequest: true,
      );
      final healthySeeder = _MockSeederServer(
        bindIp: '127.0.0.5',
        torrent: torrent,
        data: data,
      );

      await chokingSeeder.start('-CHOKE00000000000001');
      await healthySeeder.start('-HEALTHY000000000005');

      final task = TorrentTask.newTask(torrent, tmpDir.path);
      final completed = Completer<void>();
      final listener = task.createListener();
      listener.on<TaskCompleted>((_) {
        if (!completed.isCompleted) completed.complete();
      });

      try {
        await task.start();
        task.addPeer(
          CompactAddress(InternetAddress('127.0.0.4'), chokingSeeder.port),
          PeerSource.manual,
        );
        task.addPeer(
          CompactAddress(InternetAddress('127.0.0.5'), healthySeeder.port),
          PeerSource.manual,
        );

        await completed.future.timeout(const Duration(seconds: 4));
        final outFile = File('${tmpDir.path}/endgame_sample.bin');
        expect(await outFile.readAsBytes(), equals(data));
      } finally {
        listener.dispose();
        await task.stop();
        await chokingSeeder.stop();
        await healthySeeder.stop();
        await tmpDir.delete(recursive: true);
      }
    });
  });
}
