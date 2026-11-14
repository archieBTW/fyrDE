import 'dart:math';

import 'package:events_emitter2/events_emitter2.dart';

import 'bucket_events.dart';
import 'id.dart';
import 'node.dart';
import 'node_events.dart';
import 'tree_node.dart';

class Bucket extends TreeNode with EventsEmittable<BucketEvent> {
  final int _maxSize;

  final Map<Node, EventsListener<NodeEvent>> _nodes = {};

  int _count = 0;

  final int index;

  Bucket(this.index, [this._maxSize = 8]);

  bool get isEmpty => _count == 0;

  bool get isNotEmpty => !isEmpty;

  bool get isFull => _count >= bucketMaxSize;

  bool get isNotFull => !isFull;

  int get count => _count;

  Map<Node, EventsListener<NodeEvent>> get nodes => _nodes;

  TreeNode? addNode(Node? node) {
    if (node == null) return null;
    if (isFull) {
      return null;
    } else {
      var currentNode = _generateTreeNode(node.id);
      if (currentNode.node == null) {
        _count++;
        currentNode.node = node;
        _nodes[node] = node.createListener();
        _nodes[node]!.on<NodeTimedOut>(_nodeTimedOut);
        events.emit(BucketNodeInserted(node));
        return currentNode;
      } else {
        currentNode.node = node;
        events.emit(BucketNodeInserted(node));
        return currentNode;
      }
    }
  }

  int get bucketMaxSize {
    if (index > 62) {
      return _maxSize;
    }
    return min(_maxSize, pow(2, index).toInt());
  }

  void _nodeTimedOut(NodeTimedOut event) {
    removeNode(event.node);
  }

  TreeNode? removeNode(dynamic a) {
    if (a == null) return null;
    ID? id;
    if (a is TreeNode) {
      var n = a.node;
      if (n == null) return null;
      id = n.id;
    }
    if (a is Node) {
      id = a.id;
    }
    if (a is ID) {
      id = a;
    }
    if (id == null) return null;
    var t = findNode(id);
    if (t != null) {
      var node = t.node;
      _count--;
      var nodeEventsListener = _nodes.remove(node);
      nodeEventsListener!.dispose();
      node!.dispose();
      t.dispose();
      events.emit(BucketNodeRemoved(node));
      if (isEmpty) {
        events.emit(BucketIsEmpty(this));
      }
      return t;
    }
    return null;
  }

  TreeNode _generateTreeNode(ID id) {
    TreeNode currentNode = this;
    for (var byteIndex = id.byteLength - 1; byteIndex >= 0; byteIndex--) {
      var byte = id.getValueAt(byteIndex);
      var base = BASE_NUM;
      for (var bitIndex = 0; bitIndex < 8; bitIndex++) {
        TreeNode? next;
        if (byte & base == 0) {
          next = currentNode.right;
          next ??= TreeNode();
          currentNode.right = next;
        } else {
          next = currentNode.left;
          next ??= TreeNode();
          currentNode.left = next;
        }
        currentNode = next;
        base = base >> 1;
      }
    }
    return currentNode;
  }

  @override
  void dispose() {
    events.dispose();
    for (var element in _nodes.entries) {
      element.value.dispose();
      element.key.dispose();
    }
    _nodes.clear();
    _count = 0;
    super.dispose();
  }

  @override
  String toString() {
    return 'Bucket($_count) : $index';
  }
}
