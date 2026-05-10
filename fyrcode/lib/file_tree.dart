import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'fyr_theme.dart';

class FileTree extends StatefulWidget {
  final String rootDirectory;
  final void Function(String path) onFileSelected;

  const FileTree({
    super.key,
    required this.rootDirectory,
    required this.onFileSelected,
  });

  @override
  State<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<FileTree> {
  List<FileSystemEntity> _entities = [];
  final Set<String> _expandedDirs = {};

  @override
  void initState() {
    super.initState();
    _loadDirectory();
  }

  @override
  void didUpdateWidget(covariant FileTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootDirectory != widget.rootDirectory) {
      _expandedDirs.clear();
      _loadDirectory();
    }
  }

  void _loadDirectory() {
    final dir = Directory(widget.rootDirectory);
    if (dir.existsSync()) {
      setState(() {
        _entities = dir.listSync().toList()
          ..sort((a, b) {
            if (a is Directory && b is File) return -1;
            if (a is File && b is Directory) return 1;
            return a.path.toLowerCase().compareTo(b.path.toLowerCase());
          });
      });
    }
  }

  Widget _buildNode(FileSystemEntity entity, int depth) {
    final isDirectory = entity is Directory;
    final isExpanded = _expandedDirs.contains(entity.path);
    final name = entity.path.split(Platform.pathSeparator).last;

    if (name.startsWith('.'))
      return const SizedBox.shrink(); // hide hidden files

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            if (isDirectory) {
              setState(() {
                if (isExpanded) {
                  _expandedDirs.remove(entity.path);
                } else {
                  _expandedDirs.add(entity.path);
                }
              });
            }
          },
          onDoubleTap: () {
            if (!isDirectory) {
              widget.onFileSelected(entity.path);
            }
          },
          onSecondaryTapDown: (details) {
            _showContextMenu(
              context,
              details.globalPosition,
              entity.path,
              isDirectory,
            );
          },
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Container(
              padding: EdgeInsets.only(
                left: 16.0 + (depth * 12.0),
                top: 4,
                bottom: 4,
              ),
              color: Colors.transparent, // Ensure it's hit-testable
              child: Row(
                children: [
                  Icon(
                    isDirectory
                        ? (isExpanded ? Icons.folder_open : Icons.folder)
                        : Icons.insert_drive_file,
                    size: 14,
                    color: isDirectory
                        ? FyrTheme.accentColor
                        : FyrTheme.textColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.jetBrainsMono(
                        color: FyrTheme.textColor,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (isDirectory && isExpanded)
          // Fix: Wrap the directory evaluation and sort inside parentheses
          ...(Directory(entity.path)
                  .listSync()
                  .where(
                    (e) => !e.path
                        .split(Platform.pathSeparator)
                        .last
                        .startsWith('.'),
                  )
                  .toList()
                ..sort((a, b) {
                  if (a is Directory && b is File) return -1;
                  if (a is File && b is Directory) return 1;
                  return a.path.toLowerCase().compareTo(b.path.toLowerCase());
                }))
              // The cascade is resolved, now map the resulting List<FileSystemEntity> to Widgets
              .map((e) => _buildNode(e, depth + 1)),
      ],
    );
  }

  void _showContextMenu(
    BuildContext context,
    Offset position,
    String path,
    bool isDirectory,
  ) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final parentDir = isDirectory ? path : Directory(path).parent.path;

    showMenu(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      color: FyrTheme.cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          onTap: () => Future.delayed(
            Duration.zero,
            () => _createNewItem(context, parentDir, false),
          ),
          child: Row(
            children: [
              Icon(
                Icons.insert_drive_file,
                color: FyrTheme.textColor,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                'New File',
                style: GoogleFonts.jetBrainsMono(
                  color: FyrTheme.textColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          onTap: () => Future.delayed(
            Duration.zero,
            () => _createNewItem(context, parentDir, true),
          ),
          child: Row(
            children: [
              Icon(Icons.folder, color: FyrTheme.textColor, size: 16),
              const SizedBox(width: 8),
              Text(
                'New Folder',
                style: GoogleFonts.jetBrainsMono(
                  color: FyrTheme.textColor,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _createNewItem(
    BuildContext context,
    String parentPath,
    bool isDirectory,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: FyrTheme.cardColor,
        title: Text(
          isDirectory ? 'New Folder' : 'New File',
          style: GoogleFonts.jetBrainsMono(
            color: FyrTheme.textColor,
            fontSize: 16,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.jetBrainsMono(color: FyrTheme.textColor),
          decoration: InputDecoration(
            hintText: 'Enter name',
            hintStyle: GoogleFonts.jetBrainsMono(
              color: FyrTheme.textColorMuted,
            ),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: FyrTheme.accentColor),
            ),
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: FyrTheme.accentColor, width: 2),
            ),
          ),
          onSubmitted: (val) => Navigator.pop(context, val),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'CANCEL',
              style: GoogleFonts.jetBrainsMono(
                color: FyrTheme.textColorMuted,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(
              'CREATE',
              style: GoogleFonts.jetBrainsMono(
                color: FyrTheme.accentColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      final newPath = p.join(parentPath, name.trim());
      try {
        if (isDirectory) {
          await Directory(newPath).create();
        } else {
          await File(newPath).create();
        }
        _loadDirectory();
        setState(() {
          _expandedDirs.add(parentPath);
        });
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red.shade900,
              content: Text(
                'Error creating item: $e',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: FyrTheme.bgColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Text(
              'EXPLORER',
              style: GoogleFonts.jetBrainsMono(
                color: FyrTheme.textColorMuted,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onSecondaryTapDown: (details) {
                _showContextMenu(
                  context,
                  details.globalPosition,
                  widget.rootDirectory,
                  true,
                );
              },
              child: ListView.builder(
                itemCount: _entities.length,
                itemBuilder: (context, index) {
                  return _buildNode(_entities[index], 0);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
