import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'fyr_theme.dart';

class SearchResult {
  final String filePath;
  final int lineNumber;
  final String snippet;

  SearchResult({
    required this.filePath,
    required this.lineNumber,
    required this.snippet,
  });
}

class GlobalSearchView extends StatefulWidget {
  final String projectRoot;
  final Function(String filePath, int line) onResultSelected;
  final VoidCallback onClose;

  const GlobalSearchView({
    super.key,
    required this.projectRoot,
    required this.onResultSelected,
    required this.onClose,
  });

  @override
  State<GlobalSearchView> createState() => _GlobalSearchViewState();
}

class _GlobalSearchViewState extends State<GlobalSearchView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final FocusNode _listFocusNode = FocusNode();
  List<SearchResult> _results = [];
  int _selectedIndex = 0;
  bool _isSearching = false;
  bool _caseSensitive = false;

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    _listFocusNode.dispose();
    super.dispose();
  }

  Future<void> _performSearch(String query) async {
    if (query.length < 2) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    try {
      // Use grep -rnIE to search recursively, with line numbers, ignoring binary, extended regex
      // Excluding common directories like .git, build, etc.
      final List<String> args = [
        '-rnE', // Recursive, line numbers, extended regex
        if (!_caseSensitive) '-i', // Case-insensitive if toggle is off
        '--exclude-dir=.git',
        '--exclude-dir=build',
        '--exclude-dir=.dart_tool',
        query,
        '.',
      ];

      final result = await Process.run('grep', args, workingDirectory: widget.projectRoot);

      if (!mounted) return;

      final List<SearchResult> newResults = [];
      if (result.stdout != null && result.stdout.toString().isNotEmpty) {
        final lines = result.stdout.toString().split('\n');
        for (var line in lines) {
          if (line.isEmpty) continue;
          
          // Grep output: path/to/file.dart:line_number:content
          final firstColon = line.indexOf(':');
          if (firstColon == -1) continue;
          
          final secondColon = line.indexOf(':', firstColon + 1);
          if (secondColon == -1) continue;
          
          final path = line.substring(0, firstColon);
          final lineNumStr = line.substring(firstColon + 1, secondColon);
          final snippet = line.substring(secondColon + 1).trim();
          
          final lineNum = int.tryParse(lineNumStr);
          if (lineNum != null) {
            newResults.add(SearchResult(
              filePath: '${widget.projectRoot}/$path'.replaceAll('//', '/'),
              lineNumber: lineNum - 1, // 0-indexed for our editor
              snippet: snippet,
            ));
          }
        }
      }

      setState(() {
        _results = newResults;
        _isSearching = false;
        _selectedIndex = 0;
      });
    } catch (e) {
      debugPrint('Search error: $e');
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onClose();
    } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        if (_results.isNotEmpty) {
          _selectedIndex = (_selectedIndex + 1) % _results.length;
        }
      });
    } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        if (_results.isNotEmpty) {
          _selectedIndex = (_selectedIndex - 1 + _results.length) % _results.length;
        }
      });
    } else if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_results.isNotEmpty) {
        final res = _results[_selectedIndex];
        widget.onResultSelected(res.filePath, res.lineNumber);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _listFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Center(
        child: Container(
          width: 600,
          height: 500,
          decoration: BoxDecoration(
            color: FyrTheme.bgColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: FyrTheme.dividerColor, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 30,
                offset: const Offset(0, 15),
              ),
            ],
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _focusNode,
                        onChanged: _performSearch,
                        style: GoogleFonts.jetBrainsMono(color: FyrTheme.textColor),
                        decoration: InputDecoration(
                          hintText: 'Search across files...',
                          hintStyle: TextStyle(color: FyrTheme.textColorMuted),
                          prefixIcon: Icon(Icons.search, color: FyrTheme.dividerColor),
                          suffixIcon: _isSearching 
                              ? Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: CircularProgressIndicator(strokeWidth: 2, color: FyrTheme.dividerColor),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: FyrTheme.cardColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: FyrTheme.cardColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: FyrTheme.dividerColor),
                          ),
                          filled: true,
                          fillColor: FyrTheme.bgColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Match Case',
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _caseSensitive = !_caseSensitive;
                          });
                          _performSearch(_searchController.text);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _caseSensitive ? FyrTheme.dividerColor.withOpacity(0.2) : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _caseSensitive ? FyrTheme.dividerColor : FyrTheme.cardColor,
                            ),
                          ),
                          child: Icon(
                            Icons.text_fields,
                            size: 20,
                            color: _caseSensitive ? FyrTheme.dividerColor : FyrTheme.textColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(Icons.close, color: FyrTheme.textColor),
                      onPressed: widget.onClose,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _results.isEmpty 
                    ? Center(
                        child: Text(
                          _searchController.text.length < 2 
                              ? 'Type at least 2 characters to search' 
                              : 'No results found',
                          style: TextStyle(color: FyrTheme.textColorMuted),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final res = _results[index];
                          final isSelected = index == _selectedIndex;
                          final fileName = res.filePath.split('/').last;
                          
                          return InkWell(
                            onTap: () => widget.onResultSelected(res.filePath, res.lineNumber),
                            child: Container(
                              color: isSelected ? FyrTheme.cardColor : Colors.transparent,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        fileName,
                                        style: GoogleFonts.jetBrainsMono(
                                          color: isSelected ? FyrTheme.dividerColor : FyrTheme.textColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'line ${res.lineNumber + 1}',
                                        style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    res.snippet,
                                    style: GoogleFonts.jetBrainsMono(
                                      color: FyrTheme.textColor.withOpacity(0.7),
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
