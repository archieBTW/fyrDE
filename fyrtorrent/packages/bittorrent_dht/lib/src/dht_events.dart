import 'package:dtorrent_common/dtorrent_common.dart';

import 'kademlia/node.dart';

abstract class DHTEvent {}

class DHTError implements DHTEvent {
  final int code;
  final String message;
  DHTError({
    required this.code,
    required this.message,
  });
}

class NewPeerEvent implements DHTEvent {
  final CompactAddress address;
  final String infoHash;
  NewPeerEvent({
    required this.address,
    required this.infoHash,
  });
}

class NewNodeAdded implements DHTEvent {
  final Node node;
  NewNodeAdded(
    this.node,
  );
}

class DHTNodeRemoved implements DHTEvent {
  final Node node;
  DHTNodeRemoved(
    this.node,
  );
}
