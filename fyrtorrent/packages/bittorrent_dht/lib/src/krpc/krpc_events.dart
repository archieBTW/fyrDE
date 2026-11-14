import 'dart:io';

abstract class KRPCEvent {}

class KRPCResponseEvent implements KRPCEvent {
  final List<int> nodeId;
  final InternetAddress address;
  final int port;
  final dynamic data;
  KRPCResponseEvent({
    required this.nodeId,
    required this.address,
    required this.port,
    required this.data,
  });
}

class PongResponseEvent extends KRPCResponseEvent {
  PongResponseEvent(
      {required List<int> nodeId,
      required InternetAddress address,
      required int port,
      required data})
      : super(nodeId: nodeId, address: address, port: port, data: data);
}

class GetPeersResponseEvent extends KRPCResponseEvent {
  GetPeersResponseEvent(
      {required List<int> nodeId,
      required InternetAddress address,
      required int port,
      required data})
      : super(nodeId: nodeId, address: address, port: port, data: data);
}

class FindNodeResponseEvent extends KRPCResponseEvent {
  FindNodeResponseEvent(
      {required List<int> nodeId,
      required InternetAddress address,
      required int port,
      required data})
      : super(nodeId: nodeId, address: address, port: port, data: data);
}

class AnnouncePeerResponseEvent extends KRPCResponseEvent {
  AnnouncePeerResponseEvent(
      {required List<int> nodeId,
      required InternetAddress address,
      required int port,
      required data})
      : super(nodeId: nodeId, address: address, port: port, data: data);
}

class KRPCErrorEvent implements KRPCEvent {
  InternetAddress address;
  int port;
  int code;
  String msg;
  KRPCErrorEvent({
    required this.address,
    required this.port,
    required this.code,
    required this.msg,
  });
}

class KRPCQueryEvent implements KRPCEvent {
  List<int> nodeId;
  String transactionId;
  InternetAddress address;
  int port;
  dynamic data;
  KRPCQueryEvent({
    required this.nodeId,
    required this.transactionId,
    required this.address,
    required this.port,
    required this.data,
  });
}

class PingQueryEvent extends KRPCQueryEvent {
  PingQueryEvent(
      {required List<int> nodeId,
      required String transactionId,
      required InternetAddress address,
      required int port,
      required data})
      : super(
            nodeId: nodeId,
            transactionId: transactionId,
            address: address,
            port: port,
            data: data);
}

class GetPeersQueryEvent extends KRPCQueryEvent {
  GetPeersQueryEvent(
      {required List<int> nodeId,
      required String transactionId,
      required InternetAddress address,
      required int port,
      required data})
      : super(
            nodeId: nodeId,
            transactionId: transactionId,
            address: address,
            port: port,
            data: data);
}

class FindNodeQueryEvent extends KRPCQueryEvent {
  FindNodeQueryEvent(
      {required List<int> nodeId,
      required String transactionId,
      required InternetAddress address,
      required int port,
      required data})
      : super(
            nodeId: nodeId,
            transactionId: transactionId,
            address: address,
            port: port,
            data: data);
}

class AnnouncePeersQueryEvent extends KRPCQueryEvent {
  AnnouncePeersQueryEvent(
      {required List<int> nodeId,
      required String transactionId,
      required InternetAddress address,
      required int port,
      required data})
      : super(
            nodeId: nodeId,
            transactionId: transactionId,
            address: address,
            port: port,
            data: data);
}
