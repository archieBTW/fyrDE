import 'package:flutter_test/flutter_test.dart';
import 'package:fyrsettings/panes/display_pane.dart';

void main() {
  final sampleOutput = <String, dynamic>{
    'name': 'DP-1',
    'rect': {'x': 1920, 'y': 0, 'width': 1707, 'height': 960},
    'scale': 1.5,
    'transform': '90',
    'adaptive_sync_status': 'enabled',
    'current_mode': {'width': 2560, 'height': 1440, 'refresh': 143998},
    'modes': [
      {'width': 1920, 'height': 1080, 'refresh': 60000},
      {'width': 2560, 'height': 1440, 'refresh': 60000},
      {'width': 2560, 'height': 1440, 'refresh': 143998},
      {'width': 2560, 'height': 1440, 'refresh': 120000},
    ],
  };

  test('parseOutputModes sorts by resolution area then refresh rate', () {
    final modes = parseOutputModes(sampleOutput);
    expect(modes.length, 4);
    expect(modes.first.resolutionKey, '2560x1440');
    expect(modes.first.refreshMHz, 143998);
    expect(modes.first.formattedRefresh, '144 Hz');
    expect(modes.last.resolutionKey, '1920x1080');
  });

  test('uniqueResolutionsForModes and refreshModesForResolution group cleanly', () {
    final modes = parseOutputModes(sampleOutput);
    final current = currentModeForOutput(sampleOutput);
    final resolutions = uniqueResolutionsForModes(modes, current);
    expect(resolutions, ['2560x1440', '1920x1080']);

    final rates = refreshModesForResolution(modes, '2560x1440', current);
    expect(rates.map((r) => r.refreshMHz).toList(), [143998, 120000, 60000]);
  });

  test('buildSwayOutputConfigLine preserves physical mode, scale, transform, and VRR', () {
    final line = buildSwayOutputConfigLine(sampleOutput);
    expect(
      line,
      'output DP-1 mode 2560x1440@143.998Hz position 1920 0 scale 1.5 transform 90 adaptive_sync on',
    );
  });
}
