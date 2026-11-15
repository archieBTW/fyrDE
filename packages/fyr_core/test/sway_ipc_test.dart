import 'package:flutter_test/flutter_test.dart';
import 'package:fyr_core/fyr_core.dart';

void main() {
  group('SwayIpcProtocol', () {
    test('encodes and decodes i3-ipc binary frames accurately', () {
      const payload = '{"ok":true}';
      final frame = SwayIpcProtocol.encodeFrame(
        SwayIpcProtocol.getWorkspaces,
        payload,
      );

      expect(frame.length, SwayIpcProtocol.headerLength + payload.length);
      expect(SwayIpcProtocol.tryDecodeFrame(frame.sublist(0, 10)), isNull);

      final decoded = SwayIpcProtocol.tryDecodeFrame(frame);
      expect(decoded, isNotNull);
      expect(decoded!.messageType, SwayIpcProtocol.getWorkspaces);
      expect(decoded.payload, payload);
      expect(decoded.totalBytes, frame.length);
    });

    test('maps expected ipc command names to message codes', () {
      expect(
        SwayIpcProtocol.typeCodeForName('run_command'),
        SwayIpcProtocol.runCommand,
      );
      expect(
        SwayIpcProtocol.typeCodeForName('get_workspaces'),
        SwayIpcProtocol.getWorkspaces,
      );
      expect(
        SwayIpcProtocol.typeCodeForName('get_outputs'),
        SwayIpcProtocol.getOutputs,
      );
      expect(SwayIpcProtocol.typeCodeForName('get_tree'), SwayIpcProtocol.getTree);
      expect(SwayIpcProtocol.typeCodeForName('unknown'), isNull);
    });
  });
}
