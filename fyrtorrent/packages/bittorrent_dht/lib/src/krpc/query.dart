import 'dart:io';

class KQuery {
  final List<int> message;
  final InternetAddress address;
  final int port;
  final String transacationId;

  KQuery(
      {required this.message,
      required this.address,
      required this.port,
      required this.transacationId});
}
