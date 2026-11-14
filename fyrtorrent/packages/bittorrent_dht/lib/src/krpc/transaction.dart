import 'dart:async';

import '../kademlia/node.dart';
import 'krpc.dart';

class QueryTransaction {
  final EVENT event;
  final String transactionId;
  final Node? queriedNode;
  Timer? timer;
  QueryTransaction({
    required this.event,
    required this.transactionId,
    this.queriedNode,
    this.timer,
  });
}
