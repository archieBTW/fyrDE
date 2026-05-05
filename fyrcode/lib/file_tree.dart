import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
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
        InkWell(
          onTap: () {
            if (isDirectory) {
              setState(() {
                if (isExpanded) {
                  _expandedDirs.remove(entity.path);
                } else {
                  _expandedDirs.add(entity.path);
                }
              });
            } else {
              widget.onFileSelected(entity.path);
            }
          },
          child: Padding(
            padding: EdgeInsets.only(
              left: 16.0 + (depth * 12.0),
              top: 4,
              bottom: 4,
            ),
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
            child: ListView.builder(
              itemCount: _entities.length,
              itemBuilder: (context, index) {
                return _buildNode(_entities[index], 0);
              },
            ),
          ),
        ],
      ),
    );
  }
}
