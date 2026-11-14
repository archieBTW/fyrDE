import 'node.dart';

abstract class NodeEvent {}

class NodeTimedOut implements NodeEvent {
  final Node node;

  NodeTimedOut(this.node);
}

class NodeBucketIsEmpty implements NodeEvent {
  final int bucketIndex;
  NodeBucketIsEmpty(this.bucketIndex);
}

class NodeReset implements NodeEvent {
  final Node node;

  NodeReset(this.node);
}

class NodeRemoved implements NodeEvent {
  final Node node;

  NodeRemoved(this.node);
}
