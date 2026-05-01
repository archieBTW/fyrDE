import 'dart:io';
import 'main.dart';

abstract class SearchProvider {
  Future<List<DesktopApp>> search(String query);
}

class FileSearchProvider extends SearchProvider {
  @override
  Future<List<DesktopApp>> search(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final homeDir = Platform.environment['HOME'] ?? '';
      final result = await Process.run('find', [
        homeDir,
        '-maxdepth',
        '4',
        '-type',
        'f',
        '-iname',
        '*${query.trim()}*',
      ]);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String)
            .split('\n')
            .where((l) => l.isNotEmpty)
            .take(15);
        return lines
            .map(
              (l) => DesktopApp(
                id: l,
                name: l.split('/').last,
                exec: 'xdg-open "$l"',
                icon: null,
              ),
            )
            .toList();
      }
    } catch (e) {}
    return [];
  }
}

class ContactSearchProvider extends SearchProvider {
  @override
  Future<List<DesktopApp>> search(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      return [];
    } catch (e) {
      return [];
    }
  }
}
