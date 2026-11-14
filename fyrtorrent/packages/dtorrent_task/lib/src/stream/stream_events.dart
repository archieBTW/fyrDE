import 'dart:io';

import 'package:dtorrent_task/dtorrent_task.dart';

class StreamingServerStarted extends TaskEvent {
  final int port;
  final InternetAddress internetAddress;
  StreamingServerStarted({required this.port, required this.internetAddress});
}
