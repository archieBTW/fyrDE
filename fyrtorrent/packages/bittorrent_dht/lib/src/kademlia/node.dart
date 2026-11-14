import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:events_emitter2/events_emitter2.dart';

import 'bucket.dart';
import 'bucket_events.dart';
import 'id.dart';
import 'node_events.dart';

enum ActivityState { questionable, good, bad }

/// Kademlia node
///
class Node with EventsEmittable<NodeEvent> {
  bool _disposed = false;

  final ID id;

  final int k;

  final int _cleanupTime;

  int get cleanupTime => _cleanupTime;

  DateTime get lastActive => [_lastQuerySentTime, _lastResponseSentTime]
      .reduce((min, e) => e.isAfter(min) ? e : min);

  DateTime _lastQuerySentTime = DateTime.now();
  DateTime _lastResponseSentTime = DateTime.now();

  int failedQueries = 0;

  void queryFailed() {
    failedQueries++;
    if (failedQueries > 3) events.emit(NodeTimedOut(this));
  }

  void querySucceeded() {
    failedQueries = 0;
  }

  ActivityState get activityState {
    if (DateTime.now().difference(_lastResponseSentTime) <
        Duration(minutes: 15)) {
      return ActivityState.good;
    }
    if (DateTime.now().difference(_lastQuerySentTime) < Duration(minutes: 15)) {
      return ActivityState.good;
    }
    return ActivityState.questionable;
  }

  bool queried = false;

  Timer? _timer;
  // Timer? _queryReceivedCleanupTimer;
  // Timer? _responseReceivedCleanupTimer;
  // Timer? _querySentCleanupTimer;
  // Timer? _responseSentCleanupTimer;

  final CompactAddress? _compactAddress;

  Map<Bucket, EventsListener<BucketEvent>?>? _buckets;

  InternetAddress? get address => _compactAddress?.address;

  int? get port => _compactAddress?.port;

  List<Bucket> get buckets {
    _buckets ??= _getBuckets();
    return _buckets!.keys.toList();
  }

  final Map<String, String> token = <String, String>{};

  final Map<String, bool> announced = <String, bool>{};

  List<Node> get nodes {
    return buckets.expand((bucket) => bucket.nodes.keys).toList();
  }

  Node(this.id, this._compactAddress,
      [this._cleanupTime = 15 * 60, this.k = 8]) {
    resetCleanupTimers();
  }

  void resetCleanupTimers() {
    _timer?.cancel();
  }

  void querySent() {
    _lastQuerySentTime = DateTime.now();
    resetCleanupTimers();
    events.emit(NodeReset(this));
  }

  void responseSent() {
    _lastResponseSentTime = DateTime.now();
    querySucceeded();
    resetCleanupTimers();
    events.emit(NodeReset(this));
  }

  Map<Bucket, EventsListener<BucketEvent>?> _getBuckets() {
    // TODO:Check
    _buckets ??= {
      for (var element
          in Iterable.generate(id.byteLength * 8, (index) => Bucket(index)))
        element: null
    };
    return _buckets!;
  }

  bool add(Node node) {
    var index = _getBucketIndex(node.id);
    if (index < 0) return false;
    var buckets = _getBuckets();
    Bucket? bucket;
    try {
      bucket = buckets.keys.toList()[index];
    } catch (e) {
      bucket ??= Bucket(index, k);
    }

    buckets.keys.toList()[index] = bucket;
    var bucketListener = bucket.createListener();
    bucketListener
      ..on<BucketIsEmpty>(
          (event) => events.emit(NodeBucketIsEmpty(event.bucket.index)))
      ..on<BucketNodeRemoved>(
          ((event) => events.emit(NodeRemoved(event.node))));
    return bucket.addNode(node) != null;
  }

  Node? findNode(ID id) {
    if (_buckets == null || _buckets!.isEmpty) return null;
    var index = _getBucketIndex(id);
    if (index == -1) return this;
    var buckets = _buckets;
    var bucket = buckets!.keys.toList()[index];
    var tn = bucket.findNode(id);
    return tn?.node;
  }

  Bucket? getIDBelongBucket(ID id) {
    if (_buckets == null || _buckets!.isEmpty) return null;
    var index = _getBucketIndex(id);
    if (index == -1) return null;
    return _buckets!.keys.toList()[index];
  }

  List<Node> findClosestNodes(ID id) {
    if (_buckets == null || _buckets!.isEmpty) return <Node>[];
    var index = _getBucketIndex(id);
    if (index == -1) return <Node>[this];
    var bucket = _buckets!.keys.toList()[index];
    var re = <Node>[];
    while (index < _buckets!.keys.toList().length) {
      if (_fillNodeList(bucket, re, k)) break;
      index++;
      if (index >= _buckets!.keys.toList().length) break;
      bucket = _buckets!.keys.toList()[index];
    }
    return re;
  }

  bool _fillNodeList(Bucket bucket, List<Node> target, int max) {
    for (var i = 0; i < bucket.nodes.keys.length; i++) {
      if (target.length >= max) break;
      target.add(bucket.nodes.keys.toList()[i]);
    }
    return target.length >= max;
  }

  int _getBucketIndex(ID id1) {
    return id.differentLength(id1) - 1;
  }

  void remove(Node node) {
    if (_buckets == null || _buckets!.isEmpty) return;
    var index = _getBucketIndex(node.id);
    var bucket = _buckets?.keys.toList()[index];
    bucket?.removeNode(node);
  }

  void forEach(void Function(Node node) processor) {
    var buckets = this.buckets;
    for (var i = 0; i < buckets.length; i++) {
      var b = buckets[i];
      var l = b.nodes.keys.length;
      for (var i = 0; i < l; i++) {
        var node = b.nodes.keys.toList()[i];
        processor(node);
      }
    }
  }

  String? toContactEncodingString() {
    if (_compactAddress == null) return null;
    return '${id.toString()}${_compactAddress?.toContactEncodingString()}';
  }

  @override
  String toString() {
    return '${_compactAddress?.toString()} ${Uint8List.fromList(id.ids).toHexString()}';
  }

  bool get isDisposed => _disposed;

  void dispose() {
    if (isDisposed) return;
    _disposed = true;
    events.dispose();
    _timer?.cancel();
    _timer = null;

    token.clear();
    announced.clear();

    if (_buckets != null) {
      for (var i = 0; i < _buckets!.length; i++) {
        var b = _buckets!.entries.toList()[i];
        b.value?.dispose();
        b.key.dispose();
      }
    }
    _buckets = null;
  }
}
