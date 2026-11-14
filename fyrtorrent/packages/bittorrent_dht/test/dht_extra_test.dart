import 'package:test/test.dart';
import 'package:bittorrent_dht/src/kademlia/distance.dart';
import 'package:bittorrent_dht/src/kademlia/id.dart';
import 'package:bittorrent_dht/src/kademlia/bucket.dart';
import 'package:bittorrent_dht/src/kademlia/node.dart';
import 'package:bittorrent_dht/src/kademlia/bucket_events.dart';
import 'package:bittorrent_dht/src/kademlia/node_events.dart';

void main() {
  group('Distance', () {
    test('equality and comparison', () {
      final d1 = Distance([1, 2, 3]);
      final d2 = Distance([1, 2, 3]);
      final d3 = Distance([2, 2, 3]);
      expect(d1, equals(d2));
      expect(d1 == d3, isFalse);
      expect(d3 > d1, isTrue);
      expect(d1 < d3, isTrue);
      expect(d1 >= d2, isTrue);
      expect(d1 <= d2, isTrue);
      expect(() => d1 > Distance([1, 2]), throwsA(isA<String>()));
    });
    test('toString', () {
      final d = Distance([65, 66]);
      expect(d.toString(), String.fromCharCodes([65, 66]));
    });
  });

  group('BucketEvents and NodeEvents', () {
    test('Bucket emits events on insert/remove/empty', () async {
      final bucket = Bucket(0, 2);
      final events = <String>[];
      bucket.createListener()
        ..on<BucketNodeInserted>((e) => events.add('inserted'))
        ..on<BucketNodeRemoved>((e) => events.add('removed'))
        ..on<BucketIsEmpty>((e) => events.add('empty'));
      final node1 = Node(ID.randomID(2), null);
      final node2 = Node(ID.randomID(2), null);
      bucket.addNode(node1);
      bucket.addNode(node2);
      bucket.removeNode(node1);
      bucket.removeNode(node2);
      await Future.delayed(Duration(microseconds: 1));
      expect(events, containsAll(['inserted', 'removed', 'empty']));
    });
    test('Node emits NodeTimedOut and NodeRemoved', () async {
      final node = Node(ID.randomID(2), null);
      final events = <String>[];
      node.createListener()
        ..on<NodeTimedOut>((e) => events.add('timedout'))
        ..on<NodeRemoved>((e) => events.add('removed'));
      node.queryFailed();
      node.queryFailed();
      node.queryFailed();
      node.queryFailed(); // Should emit NodeTimedOut
      await Future.delayed(Duration(microseconds: 1));
      expect(events, contains('timedout'));
    });
  });

  group('Bucket/Node disposal', () {
    test('Bucket and Node dispose without error', () {
      final bucket = Bucket(0, 2);
      final node = Node(ID.randomID(2), null);
      bucket.addNode(node);
      expect(() => bucket.dispose(), returnsNormally);
      expect(() => node.dispose(), returnsNormally);
    });
  });
}
