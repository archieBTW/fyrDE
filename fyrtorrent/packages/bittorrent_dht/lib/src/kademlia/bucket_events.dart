import 'bucket.dart';
import 'node.dart';

abstract class BucketEvent {}

class BucketIsEmpty implements BucketEvent {
  final Bucket bucket;

  BucketIsEmpty(this.bucket);
}

class BucketNodeInserted implements BucketEvent {
  final Node node;

  BucketNodeInserted(this.node);
}

class BucketNodeRemoved implements BucketEvent {
  final Node node;

  BucketNodeRemoved(this.node);
}
