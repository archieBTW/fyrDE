import 'dart:io';
import 'dart:convert';

void main() async {
  final treeResult = await Process.run('swaymsg', ['-t', 'get_tree']);
  final Map<String, dynamic> tree = jsonDecode(treeResult.stdout);
  
  String? _findFocusedLayout(Map<String, dynamic> node, [String? parentLayout]) {
    if (node['focused'] == true) return parentLayout;
    if (node['nodes'] != null) {
      for (var child in node['nodes']) {
        final res = _findFocusedLayout(child, node['layout']);
        if (res != null) return res;
      }
    }
    return null;
  }
  
  print('Layout: ${_findFocusedLayout(tree)}');
}
