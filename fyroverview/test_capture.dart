import 'dart:io';
import 'dart:convert';
void main() async {
  final watch = Stopwatch()..start();
  final wsResult = await Process.run('swaymsg', ['-t', 'get_workspaces']);
  final List<dynamic> wsJson = jsonDecode(wsResult.stdout);
  int activeWs = -1;
  for (var ws in wsJson) {
    if (ws['focused'] == true) {
      activeWs = int.parse(ws['name'].toString());
      break;
    }
  }
  if (activeWs != -1) {
    await Process.run('grim', ['-t', 'jpeg', '-q', '30', '/tmp/fyroverview_ws_$activeWs.jpg']);
  }
  print('Took ${watch.elapsedMilliseconds}ms');
}
