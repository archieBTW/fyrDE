import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fyrdaw/main.dart';

class SampleBrowserItem {
  final String name;
  final String path; // filesystem path or asset key
  final bool isAsset;
  final bool isMidi;
  final String category; // 'Drums' | 'Instruments' | 'Loops' | 'MIDI'

  const SampleBrowserItem({
    required this.name,
    required this.path,
    required this.isAsset,
    required this.isMidi,
    required this.category,
  });
}

/// Collapsible audio & MIDI sample browser drawer with search, category chips,
/// user folder management, 1-click preview audition, and drag-and-drop.
class SampleBrowserDrawer extends StatefulWidget {
  final List<String> userFolders;
  final String? previewingPath;
  final VoidCallback onAddFolderPressed;
  final ValueChanged<String> onRemoveFolder;
  final ValueChanged<SampleBrowserItem> onTogglePreview;
  final ValueChanged<SampleBrowserItem> onAddToProject;
  final VoidCallback onClose;

  const SampleBrowserDrawer({
    super.key,
    required this.userFolders,
    required this.previewingPath,
    required this.onAddFolderPressed,
    required this.onRemoveFolder,
    required this.onTogglePreview,
    required this.onAddToProject,
    required this.onClose,
  });

  static const List<String> _bundledAssets = [
    'assets/samples/drums/kick_studio.wav',
    'assets/samples/drums/snare_studio.wav',
    'assets/samples/drums/hat_closed_studio.wav',
    'assets/samples/drums/hat_open_studio.wav',
    'assets/samples/drums/clap_studio.wav',
    'assets/samples/drums/tom_low_studio.wav',
    'assets/samples/drums/kick_808.wav',
    'assets/samples/drums/snare_808.wav',
    'assets/samples/drums/hat_closed_808.wav',
    'assets/samples/drums/kick_boombap.wav',
    'assets/samples/drums/snare_boombap.wav',
    'assets/samples/grand_piano_c4.wav',
    'assets/samples/rhodes_ep_c4.wav',
    'assets/samples/nylon_guitar_c4.wav',
    'assets/samples/cello_c3.wav',
    'assets/samples/deep_sine_sub_c2.wav',
    'assets/samples/808_boom_sub_c2.wav',
    'assets/samples/supersaw_lead_c4.wav',
    'assets/samples/choir_ahh_c4.wav',
  ];

  /// Discovers bundled samples plus `.wav/.mp3/.flac/.ogg/.mid` files inside [folders].
  static List<SampleBrowserItem> collectItems(List<String> folders) {
    final items = <SampleBrowserItem>[];
    final seen = <String>{};

    for (final asset in _bundledAssets) {
      seen.add(asset);
      final base = asset.split('/').last;
      final isDrum = asset.contains('/drums/');
      items.add(
        SampleBrowserItem(
          name: base,
          path: asset,
          isAsset: true,
          isMidi: false,
          category: isDrum ? 'Drums' : 'Instruments',
        ),
      );
    }

    const audioExts = {'.wav', '.mp3', '.flac', '.ogg', '.aiff'};
    const midiExts = {'.mid', '.midi'};

    for (final folder in folders) {
      final dir = Directory(folder);
      if (!dir.existsSync()) continue;
      try {
        for (final ent in dir.listSync(recursive: true, followLinks: false)) {
          if (ent is! File) continue;
          if (seen.contains(ent.path)) continue;
          final lower = ent.path.toLowerCase();
          final dot = lower.lastIndexOf('.');
          if (dot < 0) continue;
          final ext = lower.substring(dot);
          final isAudio = audioExts.contains(ext);
          final isMidi = midiExts.contains(ext);
          if (!isAudio && !isMidi) continue;
          seen.add(ent.path);
          final base = ent.path.split(Platform.pathSeparator).last;
          final cat = isMidi
              ? 'MIDI'
              : (lower.contains('drum') ||
                        lower.contains('kick') ||
                        lower.contains('snare') ||
                        lower.contains('hat')
                    ? 'Drums'
                    : 'Loops');
          items.add(
            SampleBrowserItem(
              name: base,
              path: ent.path,
              isAsset: false,
              isMidi: isMidi,
              category: cat,
            ),
          );
        }
      } catch (_) {}
    }

    return items;
  }

  @override
  State<SampleBrowserDrawer> createState() => _SampleBrowserDrawerState();
}

class _SampleBrowserDrawerState extends State<SampleBrowserDrawer> {
  String _query = '';
  String _category = 'All';

  @override
  Widget build(BuildContext context) {
    final allItems = SampleBrowserDrawer.collectItems(widget.userFolders);
    final filtered = allItems.where((item) {
      if (_category != 'All' && item.category != _category) return false;
      if (_query.isNotEmpty &&
          !item.name.toLowerCase().contains(_query.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return Container(
      key: const Key('sample_browser_drawer'),
      width: 245,
      decoration: BoxDecoration(
        color: panelDark,
        border: Border(right: BorderSide(color: borderMain)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: panelLight,
              border: Border(bottom: BorderSide(color: borderMain)),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_open, color: lavenderAccent, size: 15),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Sample & MIDI Browser',
                    style: TextStyle(
                      color: textMain,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Add Folder',
                  icon: Icon(Icons.create_new_folder, color: lavenderLight, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: widget.onAddFolderPressed,
                ),
                IconButton(
                  tooltip: 'Close Browser',
                  icon: Icon(Icons.close, color: textMuted, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              style: TextStyle(color: textMain, fontSize: 11),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search sounds & .mid...',
                hintStyle: TextStyle(color: textMuted, fontSize: 11),
                prefixIcon: Icon(Icons.search, size: 14, color: textMuted),
                filled: true,
                fillColor: bgDark,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: borderMain),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 6,
                ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 28,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: ['All', 'Drums', 'Instruments', 'Loops', 'MIDI'].map((
                cat,
              ) {
                final sel = _category == cat;
                return Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: ChoiceChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 10,
                        color: sel ? Colors.black : textMuted,
                        fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    selected: sel,
                    selectedColor: lavenderAccent,
                    backgroundColor: bgDark,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _category = cat),
                  ),
                );
              }).toList(),
            ),
          ),
          if (widget.userFolders.isNotEmpty)
            Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: widget.userFolders.map((f) {
                  final short = f.split(Platform.pathSeparator).last;
                  return Padding(
                    padding: const EdgeInsets.only(right: 4, top: 2),
                    child: Chip(
                      label: Text(
                        short,
                        style: TextStyle(color: textMain, fontSize: 9),
                      ),
                      deleteIcon: Icon(Icons.close, size: 11, color: textMuted),
                      onDeleted: () => widget.onRemoveFolder(f),
                      backgroundColor: bgDark,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 4),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      'No matching files.\nClick + folder to add loops.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textMuted, fontSize: 11),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (ctx, idx) {
                      final item = filtered[idx];
                      final isPreviewing = widget.previewingPath == item.path;
                      final rowWidget = Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: isPreviewing
                              ? lavenderAccent.withValues(alpha: 0.14)
                              : Colors.transparent,
                          border: Border(
                            bottom: BorderSide(
                              color: borderMain.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: item.isMidi
                                  ? null
                                  : () => widget.onTogglePreview(item),
                              child: Icon(
                                item.isMidi
                                    ? Icons.piano
                                    : (isPreviewing
                                          ? Icons.stop_circle
                                          : Icons.play_circle_fill),
                                size: 16,
                                color: item.isMidi
                                    ? Colors.amberAccent
                                    : (isPreviewing
                                          ? Colors.greenAccent
                                          : lavenderLight),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                item.name,
                                style: TextStyle(color: textMain, fontSize: 11),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            InkWell(
                              onTap: () => widget.onAddToProject(item),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: panelLight,
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(color: borderMain),
                                ),
                                child: Text(
                                  '+Add',
                                  style: TextStyle(
                                    color: lavenderLight,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );

                      return Draggable<SampleBrowserItem>(
                        data: item,
                        feedback: Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: panelDark.withValues(alpha: 0.92),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: lavenderAccent),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  item.isMidi ? Icons.piano : Icons.audiotrack,
                                  color: lavenderAccent,
                                  size: 14,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  item.name,
                                  style: TextStyle(
                                    color: textMain,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        child: rowWidget,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
