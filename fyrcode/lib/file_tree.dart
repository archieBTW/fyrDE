import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'fyr_theme.dart';

class FileTree extends StatefulWidget {
  final String rootDirectory;
  final void Function(String path) onFileSelected;
  final void Function(String oldPath, String newPath)? onFileRenamed;
  final void Function(String path)? onFileDeleted;
  final VoidCallback? onCollapse;
  final Map<String, int> fileErrorCounts;

  const FileTree({
    super.key,
    required this.rootDirectory,
    required this.onFileSelected,
    this.onFileRenamed,
    this.onFileDeleted,
    this.onCollapse,
    this.fileErrorCounts = const {},
  });

  @override
  State<FileTree> createState() => _FileTreeState();
}

class _FileTreeState extends State<FileTree> {
  List<FileSystemEntity> _entities = [];
  final Set<String> _expandedDirs = {};
  StreamSubscription? _dirWatchSub;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _loadDirectory();
    _startWatching();
  }

  @override
  void didUpdateWidget(covariant FileTree oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rootDirectory != widget.rootDirectory) {
      _expandedDirs.clear();
      _loadDirectory();
      _startWatching();
    }
  }

  void _startWatching() {
    _dirWatchSub?.cancel();
    final dir = Directory(widget.rootDirectory);
    if (!dir.existsSync()) return;
    try {
      _dirWatchSub = dir.watch(recursive: true).listen((event) {
        _debounceTimer?.cancel();
        _debounceTimer = Timer(const Duration(milliseconds: 300), () {
          if (mounted) _loadDirectory();
        });
      });
    } catch (_) {}
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

  @override
  void dispose() {
    _dirWatchSub?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Widget _buildNode(FileSystemEntity entity, int depth) {
    final isDirectory = entity is Directory;
    final isExpanded = _expandedDirs.contains(entity.path);
    final name = entity.path.split(Platform.pathSeparator).last;

    if (name.startsWith('.'))
      return const SizedBox.shrink(); // hide hidden files

    final errorCount = isDirectory ? 0 : (widget.fileErrorCounts[entity.path] ?? 0);
    final hasErrors = errorCount > 0;
    const errorRed = Color(0xFFED8796);

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
                        : (hasErrors ? errorRed : FyrTheme.textColor),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      name,
                      style: GoogleFonts.jetBrainsMono(
                        color: hasErrors ? errorRed : FyrTheme.textColor,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasErrors)
                    Container(
                      margin: const EdgeInsets.only(left: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: errorRed,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        errorCount.toString(),
                        style: GoogleFonts.jetBrainsMono(
                          color: FyrTheme.bgColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
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
      items: <PopupMenuEntry<dynamic>>[
        PopupMenuItem<dynamic>(
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
        if (path != widget.rootDirectory) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            onTap: () => Future.delayed(
              Duration.zero,
              () => _renameItem(context, path, isDirectory),
            ),
            child: Row(
              children: [
                Icon(Icons.edit_outlined, color: FyrTheme.textColor, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Rename',
                  style: GoogleFonts.jetBrainsMono(
                    color: FyrTheme.textColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuItem(
            onTap: () => Clipboard.setData(
              ClipboardData(text: p.relative(path, from: widget.rootDirectory)),
            ),
            child: Row(
              children: [
                Icon(Icons.copy, color: FyrTheme.textColor, size: 16),
                const SizedBox(width: 8),
                Text(
                  'Copy Relative Path',
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
              () => _deleteItem(context, path, isDirectory),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.delete_outline,
                  color: Colors.redAccent,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'Delete',
                  style: GoogleFonts.jetBrainsMono(
                    color: Colors.redAccent,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _renameItem(
    BuildContext context,
    String path,
    bool isDirectory,
  ) async {
    final controller = TextEditingController(text: p.basename(path));
    final nextName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FyrTheme.cardColor,
        title: Text(
          'Rename',
          style: GoogleFonts.jetBrainsMono(
            color: FyrTheme.textColor,
            fontSize: 15,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.jetBrainsMono(color: FyrTheme.textColor),
          onSubmitted: (val) => Navigator.pop(ctx, val),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'CANCEL',
              style: GoogleFonts.jetBrainsMono(color: FyrTheme.textColorMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(
              'RENAME',
              style: GoogleFonts.jetBrainsMono(color: FyrTheme.accentColor),
            ),
          ),
        ],
      ),
    );

    if (nextName == null || nextName.trim().isEmpty) return;
    final newPath = p.join(p.dirname(path), nextName.trim());
    if (newPath == path) return;
    try {
      if (isDirectory) {
        await Directory(path).rename(newPath);
      } else {
        await File(path).rename(newPath);
      }
      _loadDirectory();
      widget.onFileRenamed?.call(path, newPath);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Rename failed: $e')),
        );
      }
    }
  }

  Future<void> _deleteItem(
    BuildContext context,
    String path,
    bool isDirectory,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FyrTheme.cardColor,
        title: Text(
          'Delete ${p.basename(path)}?',
          style: GoogleFonts.jetBrainsMono(
            color: FyrTheme.textColor,
            fontSize: 15,
          ),
        ),
        content: Text(
          isDirectory
              ? 'This will recursively delete the folder and its contents.'
              : 'This file will be permanently deleted from disk.',
          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'CANCEL',
              style: GoogleFonts.jetBrainsMono(color: FyrTheme.textColorMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'DELETE',
              style: GoogleFonts.jetBrainsMono(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      if (isDirectory) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
      _loadDirectory();
      widget.onFileDeleted?.call(path);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
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
            padding: const EdgeInsets.fromLTRB(16.0, 6.0, 8.0, 6.0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'EXPLORER',
                    style: GoogleFonts.jetBrainsMono(
                      color: FyrTheme.textColorMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (widget.onCollapse != null)
                  Tooltip(
                    message: 'Collapse Explorer (Ctrl+B)',
                    child: InkWell(
                      onTap: widget.onCollapse,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          Icons.chevron_left,
                          size: 16,
                          color: FyrTheme.textColorMuted,
                        ),
                      ),
                    ),
                  ),
              ],
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
