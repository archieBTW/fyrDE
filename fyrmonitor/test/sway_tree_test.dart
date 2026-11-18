import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

/// Mirrors the flattening logic of `SwayWindows` so the tree walking rules can
/// be verified against a captured `swaymsg -t get_tree` payload without
/// spawning a sway session.
class WindowHit {
  WindowHit(this.pid, this.appId, this.title, this.workspace, this.number);

  final int pid;
  final String appId;
  final String title;
  final String workspace;
  final int number;
}

List<WindowHit> flatten(Map<String, dynamic> tree) {
  final out = <WindowHit>[];

  void walk(Map<String, dynamic> node, ({String name, int number})? scope) {
    var current = scope;
    if (node['type'] == 'workspace') {
      current = (
        name: (node['name'] ?? '?').toString(),
        number: node['num'] is int ? node['num'] as int : -1,
      );
    }

    final children = <Map<String, dynamic>>[];
    for (final key in const ['nodes', 'floating_nodes']) {
      final value = node[key];
      if (value is List) {
        for (final child in value) {
          if (child is Map<String, dynamic>) children.add(child);
        }
      }
    }
    if (children.isNotEmpty) {
      for (final child in children) {
        walk(child, current);
      }
      return;
    }

    final type = node['type'];
    if (type != 'con' && type != 'floating_con') return;
    final pid = node['pid'];
    if (pid is! int || pid <= 0) return;
    final appId = (node['app_id'] ?? '').toString();
    final props = node['window_properties'];
    final hasProps = props is Map && props.isNotEmpty;
    if (appId.isEmpty && !hasProps) return;

    out.add(
      WindowHit(
        pid,
        appId.isNotEmpty ? appId : (props!['class'] ?? 'xwayland').toString(),
        (node['name'] ?? '').toString(),
        current?.name ?? '?',
        current?.number ?? -1,
      ),
    );
  }

  walk(tree, null);
  return out;
}

void main() {
  test('flattens nested splits, floating windows and workspaces', () {
    final tree = jsonDecode('''
    {
      "id": 1, "type": "root", "name": "root",
      "nodes": [
        {
          "id": 2, "type": "output", "name": "eDP-1",
          "nodes": [
            {
              "id": 3, "type": "workspace", "name": "2", "num": 2,
              "nodes": [
                {
                  "id": 4, "type": "con", "name": "split",
                  "nodes": [
                    {
                      "id": 5, "type": "con", "name": "fyrterm",
                      "pid": 1111, "app_id": "fyrterm",
                      "nodes": [], "floating_nodes": []
                    },
                    {
                      "id": 6, "type": "con", "name": "editor",
                      "pid": 2222, "app_id": "fyrtext",
                      "nodes": [], "floating_nodes": []
                    }
                  ],
                  "floating_nodes": []
                }
              ],
              "floating_nodes": [
                {
                  "id": 7, "type": "floating_con", "name": "floating thing",
                  "nodes": [
                    {
                      "id": 8, "type": "con", "name": "calc",
                      "pid": 3333, "app_id": "fyrcalculator",
                      "nodes": [], "floating_nodes": []
                    }
                  ],
                  "floating_nodes": []
                }
              ]
            }
          ],
          "floating_nodes": []
        }
      ],
      "floating_nodes": []
    }
    ''') as Map<String, dynamic>;

    final hits = flatten(tree);
    expect(hits.length, 3);
    expect(hits.map((h) => h.appId), ['fyrterm', 'fyrtext', 'fyrcalculator']);
    expect(hits.every((h) => h.number == 2), isTrue);
    expect(hits.first.workspace, '2');
  });

  test('keeps XWayland windows that only have window_properties', () {
    final tree = jsonDecode('''
    {
      "type": "root", "id": 1, "nodes": [
        {
          "type": "workspace", "name": "1", "num": 1, "nodes": [
            {
              "type": "con", "name": "GIMP", "pid": 4444,
              "window_properties": {
                "class": "Gimp", "instance": "gimp-2.10", "title": "GIMP"
              },
              "nodes": [], "floating_nodes": []
            }
          ],
          "floating_nodes": []
        }
      ],
      "floating_nodes": []
    }
    ''') as Map<String, dynamic>;

    final hits = flatten(tree);
    expect(hits.length, 1);
    expect(hits.single.pid, 4444);
    expect(hits.single.appId, 'Gimp');
  });

  test('drops containers without a pid or without identity', () {
    final tree = jsonDecode('''
    {
      "type": "root", "id": 1, "nodes": [
        {
          "type": "workspace", "name": "1", "num": 1, "nodes": [
            {"type": "con", "name": "no pid", "app_id": "x",
             "nodes": [], "floating_nodes": []},
            {"type": "con", "name": "no identity", "pid": 5555,
             "nodes": [], "floating_nodes": []},
            {"type": "con", "name": "pid zero", "pid": 0, "app_id": "y",
             "nodes": [], "floating_nodes": []},
            {"type": "con", "name": "ok", "pid": 6666, "app_id": "fyrfiles",
             "nodes": [], "floating_nodes": []}
          ],
          "floating_nodes": []
        }
      ],
      "floating_nodes": []
    }
    ''') as Map<String, dynamic>;

    final hits = flatten(tree);
    expect(hits.length, 1);
    expect(hits.single.appId, 'fyrfiles');
  });

  test('ignores nodes that are not con/floating_con', () {
    final tree = jsonDecode('''
    {
      "type": "root", "id": 1, "nodes": [
        {
          "type": "workspace", "name": "1", "num": 1, "nodes": [
            {"type": "output", "name": "nope", "pid": 7777, "app_id": "z",
             "nodes": [], "floating_nodes": []}
          ],
          "floating_nodes": []
        }
      ],
      "floating_nodes": []
    }
    ''') as Map<String, dynamic>;
    expect(flatten(tree), isEmpty);
  });
}
