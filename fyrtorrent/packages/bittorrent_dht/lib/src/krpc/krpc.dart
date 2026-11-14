import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:bittorrent_dht/src/krpc/krpc_events.dart';
import 'package:bittorrent_dht/src/krpc/query.dart';
import 'package:bittorrent_dht/src/krpc/transaction.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:events_emitter2/events_emitter2.dart';
import 'package:logging/logging.dart';
import 'krpc_message.dart';
import '../kademlia/id.dart';
import '../kademlia/node.dart';

enum EVENT { PING, GET_PEERS, FIND_NODE, ANNOUNCE_PEER }

const TIME_OUT_TIME = 15;

const Generic_Error = 201;
const Server_Error = 202;
const Protocal_Error = 203;
const UnknownMethod_Error = 204;

var _log = Logger('KRPC');

abstract class KRPC with EventsEmittable<KRPCEvent> {
  /// Start KRPC service.
  ///
  /// Actually it start to UDP listening and init some parameters.
  Future<int?> start([int? port]);

  /// Stop KRPC service.
  ///
  /// Close the UDP sockets and clean all handlers.
  Future stop([dynamic reason]);

  /// Local node id
  ID get nodeId;

  bool get isStopped;

  /// UDP port
  int? get port;

  /// Code	Description
  /// - `201`	Generic Error
  /// - `202`	Server Error
  /// - `203`	Protocol Error, such as a malformed packet, invalid arguments, or bad token
  /// - `204`	Method Unknown
  void sendError(String tid, InternetAddress address, int port,
      [int code = 201, String msg = 'Generic Error']);

  /// send `ping` query to remote
  void ping(InternetAddress address, int port, {Node? queriedNode});

  /// send `ping` response to remote
  void pong(String tid, InternetAddress address, int port, [String? nodeId]);

  /// send `find_node` query to remote
  void findNode(String targetId, InternetAddress address, int port,
      {String? qNodeId, Node? queriedNode});

  /// send `find_node` response to remote
  void responseFindNode(
      String tid, List<Node> nodes, InternetAddress address, int port,
      [String? nodeId]);

  /// send `get_peers` to remote
  void getPeers(String infoHash, InternetAddress address, int port,
      {Node? queriedNode});

  /// send `get_peers` response to remote
  void responseGetPeers(String tid, String infoHash, InternetAddress address,
      int port, String token,
      {Iterable<Node>? nodes, Iterable<CompactAddress>? peers, String? nodeId});

  /// send `announce_peer` to remote
  void announcePeer(String infoHash, int peerPort, String token,
      InternetAddress address, int port,
      {bool impliedPort = true, Node? queriedNode});

  /// send `announce_peer` response to remote
  void responseAnnouncePeer(String tid, InternetAddress address, int port);

  /// Create a new KRPC service.
  factory KRPC.newService(ID nodeId,
      {int timeout = TIME_OUT_TIME, int maxQuery = 24}) {
    var k = _KRPC(nodeId, timeout, maxQuery);
    return k;
  }
}

class _KRPC with EventsEmittable<KRPCEvent> implements KRPC {
  int _globalTransactionId = 0;

  final _globalTransactionIdBuffer = Uint8List(2);

  bool _stopped = false;

  final ID _nodeId;

  final int _maxQuery;

  final Set<String> _pendingQueries = {};

  final int _timeOutTime;

  RawDatagramSocket? _socket;

  final Map<String, QueryTransaction> _transactionsMap = {};

  final Map<String, String?> _transactionsValues = <String, String?>{};

  _KRPC(this._nodeId, this._timeOutTime, this._maxQuery);
  StreamController<KQuery>? _queryController;

  StreamSubscription<KQuery>? _querySub;

  @override
  void sendError(String tid, InternetAddress address, int port,
      [int code = 201, String msg = 'Generic Error']) {
    if (isStopped || _socket == null) return;
    var message = errorMessage(tid, code, msg);
    _socket?.send(message, address, port);
  }

  @override
  void responseAnnouncePeer(String tid, InternetAddress address, int port) {
    if (isStopped || _socket == null) return;
    var message = announcePeerResponse(tid, _nodeId.toString());
    _socket?.send(message, address, port);
  }

  @override
  void announcePeer(String infoHash, int peerPort, String token,
      InternetAddress address, int port,
      {bool impliedPort = true, Node? queriedNode}) {
    if (isStopped || _socket == null) return;
    var tid = _recordTransaction(EVENT.ANNOUNCE_PEER, queriedNode);
    var message =
        announcePeerMessage(tid, _nodeId.toString(), infoHash, peerPort, token);
    _requestQuery(tid, message, address, port);
  }

  @override
  void pong(String tid, InternetAddress address, int port, [String? nodeId]) {
    if (isStopped || _socket == null) return;
    var message = pongMessage(tid, nodeId ?? _nodeId.toString());
    _socket?.send(message, address, port);
  }

  @override
  void responseFindNode(
      String tid, List<Node> nodes, InternetAddress address, int port,
      [String? nodeId]) {
    if (isStopped || _socket == null) return;
    var message = findNodeResponse(tid, nodeId ?? _nodeId.toString(), nodes);
    _socket?.send(message, address, port);
  }

  @override
  void responseGetPeers(String tid, String infoHash, InternetAddress address,
      int port, String token,
      {Iterable<Node>? nodes,
      Iterable<CompactAddress>? peers,
      String? nodeId}) {
    _log.fine('Sending getPeersResponse to ${address.address} ');
    if (isStopped || _socket == null) return;
    var message = getPeersResponse(tid, nodeId ?? _nodeId.toString(), token,
        nodes: nodes, peers: peers);
    _socket?.send(message, address, port);
  }

  @override
  void ping(InternetAddress address, int port, {Node? queriedNode}) async {
    if (isStopped || _socket == null) return;
    var tid = _recordTransaction(EVENT.PING, queriedNode);
    var message = pingMessage(tid, _nodeId.toString());
    _requestQuery(tid, message, address, port);
  }

  @override
  void findNode(String targetId, InternetAddress address, int port,
      {String? qNodeId, Node? queriedNode}) {
    if (isStopped || _socket == null) return;
    var tid = _recordTransaction(EVENT.FIND_NODE, queriedNode);
    var message = findNodeMessage(tid, qNodeId ?? _nodeId.toString(), targetId);
    _requestQuery(tid, message, address, port);
  }

  @override
  void getPeers(String infoHash, InternetAddress address, int port,
      {Node? queriedNode}) {
    if (isStopped || _socket == null) return;
    var tid = _recordTransaction(EVENT.GET_PEERS, queriedNode);
    _transactionsValues[tid] = infoHash;
    var message = getPeersMessage(tid, _nodeId.toString(), infoHash);
    _requestQuery(tid, message, address, port);
  }

  void _requestQuery(String transacationId, List<int> message,
      InternetAddress address, int port) {
    _queryController ??= StreamController();
    _querySub ??= _queryController?.stream.listen(_processQueryRequest);
    // _totalPending++;
    // print('There are currently $_totalPending pending requests.');
    _queryController?.add(KQuery(
        message: message,
        address: address,
        port: port,
        transacationId: transacationId));
  }

  void _processQueryRequest(KQuery event) {
    if (isStopped) return;

    // print('Sending request $tid, currently pending requests: $_pendingQuery."');
    var transaction = _transactionsMap[event.transacationId];
    if (transaction != null) {
      _increasePendingQuery(transaction);
      transaction.timer = Timer(Duration(seconds: _timeOutTime),
          () => _fireTimeout(event.transacationId));
    }

    _socket?.send(event.message, event.address, event.port);
  }

  String _recordTransaction(EVENT event, Node? queriedNode) {
    var tid = createTransactionId();
    while (_transactionsMap.containsKey(tid)) {
      tid = createTransactionId();
    }
    _transactionsMap[tid] = QueryTransaction(
        event: event, transactionId: tid, queriedNode: queriedNode);
    return tid;
  }

  void _fireTimeout(String id) {
    var transaction = _cleanTransaction(id);
    if (transaction != null) {
      // print('Request timed out for $id, currently pending requests: $_pendingQuery.');
      transaction.queriedNode?.queryFailed();
    }
  }

  QueryTransaction? _cleanTransaction(String id) {
    var queryTransaction = _transactionsMap.remove(id);
    queryTransaction?.timer?.cancel();
    _transactionsValues.remove(id);
    _pendingQueries.remove(id);

    if (_pendingQueries.length < _maxQuery &&
        _querySub != null &&
        _querySub!.isPaused) {
      _querySub?.resume();
    }
    return queryTransaction;
  }

  String createTransactionId() {
    ++_globalTransactionId;
    if (_globalTransactionId == 65535) {
      _globalTransactionId = 0;
    }
    ByteData.view(_globalTransactionIdBuffer.buffer)
        .setUint16(0, _globalTransactionId);
    return String.fromCharCodes(_globalTransactionIdBuffer);
  }

  @override
  Future<int?> start([int? port]) async {
    _socket ??=
        await RawDatagramSocket.bind(InternetAddress.anyIPv4, port ?? 0);
    _socket?.listen((event) {
      if (event == RawSocketEvent.read) {
        var datagram = _socket?.receive();
        Timer.run(() {
          try {
            if (datagram != null) {
              _processReceiveData(
                  datagram.address, datagram.port, datagram.data);
            }
          } catch (e) {
            _log.warning('Process Receive Message Error', e);
          }
        });
      }
    },
        onDone: () => stop('Remote/Local close the socket'),
        onError: (e) => stop(e));
    return _socket?.port;
  }

  void _increasePendingQuery(QueryTransaction transaction) {
    _log.fine('Current pending queries ${_pendingQueries.length}');
    _pendingQueries.add(transaction.transactionId);
    if (_pendingQueries.length >= _maxQuery &&
        _querySub != null &&
        !_querySub!.isPaused) {
      _log.fine('max query count $_maxQuery reached, pausing ');
      _querySub?.pause();
    }
  }

  void _processReceiveData(
      InternetAddress address, int port, Uint8List bufferData) {
    // _totalPending--;
    // print('There are currently $_totalPending requests.');
    dynamic data;
    try {
      data = decode(bufferData);
    } catch (e) {
      _fireError(Protocal_Error, null, 'Can\'t Decode Message', address, port);
      return;
    }
    if (data[TRANSACTION_KEY] == null || data[METHOD_KEY] == null) {
      _fireError(
          Protocal_Error, null, 'Data Don\'t Contains y or t', address, port);
      return;
    }
    String? tid;
    try {
      tid = String.fromCharCodes(data[TRANSACTION_KEY], 0);
    } catch (e) {
      _log.warning('"Error parsing Tid', e);
    } //Error parsing Tid.
    // print('Request response for $tid, currently pending requests: $_pendingQuery.');
    if (tid == null) {
      _fireError(
          Protocal_Error, null, 'Incorret Transaction ID', address, port);
      return;
    }
    var additionalValues = _transactionsValues[tid];

    String? method;
    try {
      method = String.fromCharCodes(data[METHOD_KEY], 0, 1);
    } catch (e) {
      _log.warning('Error parsing Method', e);
    }
    if (method == RESPONSE_KEY && data[RESPONSE_KEY] != null) {
      var idBytes = data[RESPONSE_KEY][ID_KEY];
      if (idBytes == null) {
        _fireError(Protocal_Error, tid, 'Incorrect Node ID', address, port);
        return;
      }
      var queryTransaction = _cleanTransaction(tid);

      if (queryTransaction == null) {
        return;
      }
      var r = data[RESPONSE_KEY];
      if (additionalValues != null && r != null) {
        r['__additional'] = additionalValues;
      }
      // Processing the response sent by the remote

      _fireResponse(queryTransaction.event, idBytes, address, port, r);
      return;
    }
    if (method == QUERY_KEY &&
        data[QUERY_KEY] != null &&
        data[QUERY_KEY].isNotEmpty) {
      var queryKey = String.fromCharCodes(data[QUERY_KEY]);
      if (!QUERY_KEYS.contains(queryKey)) {
        _fireError(
            Server_Error, tid, 'Unknown Query: $queryKey', address, port);
        return;
      }
      var idBytes = data[ARGUMENTS_KEY][ID_KEY];
      if (idBytes == null || idBytes.length != 20) {
        _fireError(Protocal_Error, tid, 'Incorrect Node ID', address, port);
        return;
      }
      EVENT? event;
      if (queryKey == PING) {
        event = EVENT.PING;
      }
      if (queryKey == FIND_NODE) {
        event = EVENT.FIND_NODE;
      }
      if (queryKey == GET_PEERS) {
        event = EVENT.GET_PEERS;
      }
      if (queryKey == ANNOUNCE_PEER) {
        event = EVENT.ANNOUNCE_PEER;
      }
      _log.fine('Received a Query request: $event, from $address : $port');
      var arguments = data[ARGUMENTS_KEY];
      if (event != null) {
        _fireQuery(event, idBytes, tid, address, port, arguments);
      }
      return;
    }
    if (method == ERROR_KEY) {
      var error = data[ERROR_KEY];
      var code = 201;
      var msg = 'unknown';
      if (error != null && error.length >= 2) {
        if (error[1] is List) {
          code = error[0];
          msg = String.fromCharCodes(error[1]);
        } else {
          msg = String.fromCharCodes(error);
        }
        _getError(tid, address, port, code, msg);
      }
      return;
    }
    _fireError(
        UnknownMethod_Error, tid, 'Unknown Method: $method', address, port);
  }

  void _getError(
      String tid, InternetAddress address, int port, int code, String msg) {
    _log.fine('Received an error message from ${address.address}:$port :',
        '[$code]$msg');
    events.emit(
        KRPCErrorEvent(address: address, port: port, code: code, msg: msg));
  }

  /// Code	Description
  /// - `201`	Generic Error
  /// - `202`	Server Error
  /// - `203`	Protocol Error, such as a malformed packet, invalid arguments, or bad token
  /// - `204`	Method Unknown
  void _fireError(
      int code, String? tid, String msg, InternetAddress address, int port) {
    if (tid != null) {
      var tr = _transactionsMap.remove(tid);
      tr?.timer?.cancel();
      sendError(tid, address, port, code, msg);
    } else {
      _log.warning('UnSend Error:', '[$code]$msg');
    }
  }

  void _fireResponse(EVENT event, List<int> nodeIdBytes,
      InternetAddress address, int port, dynamic response) {
    switch (event) {
      case EVENT.ANNOUNCE_PEER:
        events.emit(AnnouncePeerResponseEvent(
            nodeId: nodeIdBytes, address: address, port: port, data: response));
        break;
      case EVENT.FIND_NODE:
        events.emit(FindNodeResponseEvent(
            nodeId: nodeIdBytes, address: address, port: port, data: response));
        break;
      case EVENT.GET_PEERS:
        events.emit(GetPeersResponseEvent(
            nodeId: nodeIdBytes, address: address, port: port, data: response));
        break;
      case EVENT.PING:
        events.emit(PongResponseEvent(
            nodeId: nodeIdBytes, address: address, port: port, data: response));
        break;
    }
  }

  void _fireQuery(EVENT event, List<int> nodeIdBytes, String transactionId,
      InternetAddress address, int port, dynamic arguments) {
    switch (event) {
      case EVENT.ANNOUNCE_PEER:
        events.emit(AnnouncePeersQueryEvent(
            nodeId: nodeIdBytes,
            transactionId: transactionId,
            address: address,
            port: port,
            data: arguments));
        break;
      case EVENT.FIND_NODE:
        events.emit(FindNodeQueryEvent(
            nodeId: nodeIdBytes,
            transactionId: transactionId,
            address: address,
            port: port,
            data: arguments));
        break;
      case EVENT.GET_PEERS:
        events.emit(GetPeersQueryEvent(
            nodeId: nodeIdBytes,
            transactionId: transactionId,
            address: address,
            port: port,
            data: arguments));
        break;
      case EVENT.PING:
        events.emit(PingQueryEvent(
            nodeId: nodeIdBytes,
            transactionId: transactionId,
            address: address,
            port: port,
            data: arguments));
        break;
    }
  }

  @override
  Future stop([dynamic reason]) async {
    if (_stopped) return;
    _stopped = true;
    _log.warning('KRPC stopped , reason:', reason);
    events.dispose();
    _socket?.close();
    _socket = null;
    _globalTransactionId = 0;
    _globalTransactionIdBuffer[0] = 0;
    _globalTransactionIdBuffer[1] = 0;
    for (var transaction in _transactionsMap.entries) {
      transaction.value.timer?.cancel();
    }
    _transactionsMap.clear();
    _transactionsValues.clear();

    try {
      await _querySub?.cancel();
    } finally {
      _querySub = null;
    }
    try {
      await _queryController?.close();
    } finally {
      _queryController = null;
    }
  }

  @override
  bool get isStopped => _stopped;

  @override
  ID get nodeId => _nodeId;

  @override
  int? get port => _socket?.port;
}
