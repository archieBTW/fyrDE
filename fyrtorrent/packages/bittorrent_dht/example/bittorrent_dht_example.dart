import 'dart:io';

import 'package:bittorrent_dht/src/dht_base.dart';
import 'package:bittorrent_dht/src/dht_events.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:path/path.dart' as path;
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:logging/logging.dart';

var _log = Logger('Dht Example');
var scriptDir = path.dirname(Platform.script.path);
var torrentsPath =
    path.canonicalize(path.join(scriptDir, '..', '..', '..', 'torrents'));
void main() async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print(
        '[${record.loggerName}] ${record.level.name}: ${record.time}: ${record.message}');
  });

  var torrent = await Torrent.parseFromFile(
      path.join(torrentsPath, 'big-buck-bunny.torrent'));
  var infohashStr = String.fromCharCodes(torrent.infoHashBuffer);

  var dht = DHT();
  var test = <CompactAddress>{};
  dht.announce(infohashStr, 22123);
  var dhtListener = dht.createListener();
  dhtListener
    ..on<DHTError>((event) =>
        _log.warning('Error happend:', '[${event.code}]${event.message}'))
    ..on<NewPeerEvent>(
      (event) {
        if (test.add(event.address)) {
          _log.info(
              'Found new peer address : ${event.address}  ， Have ${test.length} peers already');
        }
      },
    );
  await dht.bootstrap(udpTimeout: 5, cleanNodeTime: 5 * 60);
  for (var url in torrent.nodes) {
    await dht.addBootstrapNode(url);
  }

  Future.delayed(Duration(seconds: 10), () {
    dht.stop();
  });
}

String intToRadix2String(int element) {
  var s = element.toRadixString(2);
  if (s.length != 8) {
    var l = s.length;
    for (var i = 0; i < 8 - l; i++) {
      s = '${0}$s';
    }
  }
  return s;
}
