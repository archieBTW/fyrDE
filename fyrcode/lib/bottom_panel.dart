import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;

import 'fyr_theme.dart';

class ReferenceLocation {
  final String filePath;
  final int line;
  final int col;
  final String preview;

  const ReferenceLocation({
    required this.filePath,
    required this.line,
    required this.col,
    required this.preview,
  });
}

enum BottomPanelTab {
  terminal,
  problems,
  references,
}

/// Collapsible IDE bottom drawer hosting an interactive command terminal,
/// workspace Problems explorer (with Fix-with-AI), and LSP References view.
class BottomPanel extends StatefulWidget {
  final String projectRoot;
  final BottomPanelTab activeTab;
  final ValueChanged<BottomPanelTab> onTabChanged;
  final VoidCallback onClose;
  final Map<String, List<dynamic>> diagnosticsByFile;
  final List<ReferenceLocation> references;
  final void Function(String filePath, int line, int col) onNavigate;
  final void Function(String prompt) onAskAi;

  const BottomPanel({
    super.key,
    required this.projectRoot,
    required this.activeTab,
    required this.onTabChanged,
    required this.onClose,
    required this.diagnosticsByFile,
    required this.references,
    required this.onNavigate,
    required this.onAskAi,
  });

  @override
  State<BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<BottomPanel> {
  final TextEditingController _cmdCtrl = TextEditingController();
  final FocusNode _cmdFocusNode = FocusNode();
  final ScrollController _termScrollCtrl = ScrollController();

  final List<String> _history = [];
  int _historyIdx = -1;
  final StringBuffer _terminalOutput = StringBuffer();
  Process? _runningProc;
  bool _isRunning = false;

  @override
  void dispose() {
    _runningProc?.kill();
    _cmdCtrl.dispose();
    _cmdFocusNode.dispose();
    _termScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _runCommand(String raw) async {
    final cmd = raw.trim();
    if (cmd.isEmpty) return;

    if (cmd == 'clear' || cmd == 'cls') {
      setState(() {
        _terminalOutput.clear();
        _cmdCtrl.clear();
      });
      return;
    }

    if (_runningProc != null) return;

    _history.add(cmd);
    _historyIdx = _history.length;
    _cmdCtrl.clear();

    setState(() {
      _terminalOutput.writeln('\$ $cmd');
      _isRunning = true;
    });
    _scrollToEnd();

    try {
      final proc = Platform.isWindows
          ? await Process.start(
              'cmd',
              ['/c', cmd],
              workingDirectory: widget.projectRoot,
            )
          : await Process.start(
              '/bin/sh',
              ['-c', cmd],
              workingDirectory: widget.projectRoot,
            );
      _runningProc = proc;

      void appendChunk(String text) {
        if (!mounted) return;
        setState(() => _terminalOutput.write(text));
        _scrollToEnd();
      }

      final outSub = proc.stdout
          .transform(utf8.decoder)
          .listen(appendChunk)
          .asFuture<void>();
      final errSub = proc.stderr
          .transform(utf8.decoder)
          .listen(appendChunk)
          .asFuture<void>();

      final code = await proc.exitCode;
      await Future.wait([outSub, errSub]);

      if (!mounted) return;
      setState(() {
        if (_terminalOutput.isNotEmpty &&
            !_terminalOutput.toString().endsWith('\n')) {
          _terminalOutput.writeln();
        }
        if (code != 0) {
          _terminalOutput.writeln('[exit $code]');
        }
        _runningProc = null;
        _isRunning = false;
      });
      _scrollToEnd();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _terminalOutput.writeln('Error: $e');
        _runningProc = null;
        _isRunning = false;
      });
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_termScrollCtrl.hasClients) {
        _termScrollCtrl.jumpTo(_termScrollCtrl.position.maxScrollExtent);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final problemCount = widget.diagnosticsByFile.values.fold<int>(
      0,
      (sum, list) => sum + list.length,
    );

    return Container(
      color: FyrTheme.surfaceColor,
      child: Column(
        children: [
          // Header Tabs
          Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: FyrTheme.cardColor,
              border: Border(
                top: BorderSide(color: FyrTheme.dividerColor),
                bottom: BorderSide(color: FyrTheme.dividerColor),
              ),
            ),
            child: Row(
              children: [
                _tabButton(
                  BottomPanelTab.terminal,
                  Icons.terminal,
                  'Terminal',
                ),
                const SizedBox(width: 6),
                _tabButton(
                  BottomPanelTab.problems,
                  Icons.error_outline,
                  problemCount > 0 ? 'Problems ($problemCount)' : 'Problems',
                ),
                const SizedBox(width: 6),
                _tabButton(
                  BottomPanelTab.references,
                  Icons.link,
                  widget.references.isNotEmpty
                      ? 'References (${widget.references.length})'
                      : 'References',
                ),
                const Spacer(),
                if (widget.activeTab == BottomPanelTab.terminal) ...[
                  if (_terminalOutput.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        final out = _terminalOutput.toString();
                        final tail = out.length > 4000
                            ? out.substring(out.length - 4000)
                            : out;
                        widget.onAskAi(
                          'Analyze this terminal output and help fix any errors:\n```\n$tail\n```',
                        );
                      },
                      icon: Icon(
                        Icons.auto_awesome,
                        size: 13,
                        color: FyrTheme.accentColor,
                      ),
                      label: Text(
                        'Ask AI',
                        style: TextStyle(
                          color: FyrTheme.accentColor,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: 'Clear Terminal',
                    iconSize: 15,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 26,
                      minHeight: 26,
                    ),
                    icon: Icon(
                      Icons.delete_sweep_outlined,
                      color: FyrTheme.textColorMuted,
                    ),
                    onPressed: () => setState(() => _terminalOutput.clear()),
                  ),
                ] else if (widget.activeTab == BottomPanelTab.problems &&
                    problemCount > 0) ...[
                  TextButton.icon(
                    onPressed: () => widget.onAskAi(
                      'Inspect @problems and fix all $problemCount diagnostic issue(s).',
                    ),
                    icon: Icon(
                      Icons.auto_awesome,
                      size: 13,
                      color: FyrTheme.accentColor,
                    ),
                    label: Text(
                      'Fix All with AI',
                      style: TextStyle(
                        color: FyrTheme.accentColor,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                IconButton(
                  tooltip: 'Close Panel (Ctrl+`)',
                  iconSize: 16,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                  icon: Icon(Icons.close, color: FyrTheme.textColorMuted),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          Expanded(
            child: switch (widget.activeTab) {
              BottomPanelTab.terminal => _buildTerminalView(),
              BottomPanelTab.problems => _buildProblemsView(),
              BottomPanelTab.references => _buildReferencesView(),
            },
          ),
        ],
      ),
    );
  }

  Widget _tabButton(BottomPanelTab tab, IconData icon, String label) {
    final active = widget.activeTab == tab;
    return InkWell(
      onTap: () => widget.onTabChanged(tab),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? FyrTheme.accentColor : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: active ? FyrTheme.textColor : FyrTheme.textColorMuted,
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminalView() {
    return Container(
      color: FyrTheme.bgColor,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _termScrollCtrl,
              padding: const EdgeInsets.all(10),
              child: Align(
                alignment: Alignment.topLeft,
                child: SelectableText(
                  _terminalOutput.isEmpty
                      ? 'FyrCode Terminal (${widget.projectRoot}) — type a command below.'
                      : _terminalOutput.toString(),
                  style: GoogleFonts.jetBrainsMono(
                    color: _terminalOutput.isEmpty
                        ? FyrTheme.textColorMuted
                        : FyrTheme.textColor,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: FyrTheme.cardColor,
              border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
            ),
            child: Row(
              children: [
                Text(
                  '\$',
                  style: GoogleFonts.jetBrainsMono(
                    color: FyrTheme.accentColor,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Focus(
                    onKeyEvent: (_, event) {
                      if (event is! KeyDownEvent) return KeyEventResult.ignored;
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                          _history.isNotEmpty) {
                        _historyIdx = (_historyIdx - 1).clamp(
                          0,
                          _history.length - 1,
                        );
                        _cmdCtrl.text = _history[_historyIdx];
                        _cmdCtrl.selection = TextSelection.collapsed(
                          offset: _cmdCtrl.text.length,
                        );
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                          _history.isNotEmpty) {
                        if (_historyIdx < _history.length - 1) {
                          _historyIdx++;
                          _cmdCtrl.text = _history[_historyIdx];
                        } else {
                          _historyIdx = _history.length;
                          _cmdCtrl.clear();
                        }
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TextField(
                      controller: _cmdCtrl,
                      focusNode: _cmdFocusNode,
                      style: GoogleFonts.jetBrainsMono(
                        color: FyrTheme.textColor,
                        fontSize: 12.5,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Run shell command (e.g. flutter test)...',
                        hintStyle: TextStyle(
                          color: FyrTheme.textColorMuted,
                          fontSize: 12,
                        ),
                        isDense: true,
                        border: InputBorder.none,
                      ),
                      onSubmitted: _runCommand,
                    ),
                  ),
                ),
                if (_isRunning)
                  IconButton(
                    tooltip: 'Kill Process',
                    iconSize: 18,
                    onPressed: () => _runningProc?.kill(ProcessSignal.sigterm),
                    icon: const Icon(
                      Icons.stop_circle,
                      color: Colors.redAccent,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProblemsView() {
    final entries = <({
      String filePath,
      int line,
      int col,
      int severity,
      String message,
    })>[];

    for (final entry in widget.diagnosticsByFile.entries) {
      for (final d in entry.value) {
        if (d is! Map) continue;
        final range = d['range'] as Map?;
        final start = range?['start'] as Map?;
        entries.add((
          filePath: entry.key,
          line: (start?['line'] as int?) ?? 0,
          col: (start?['character'] as int?) ?? 0,
          severity: (d['severity'] as int?) ?? 1,
          message: d['message']?.toString() ?? '',
        ));
      }
    }

    if (entries.isEmpty) {
      return Center(
        child: Text(
          'No problems detected in open files.',
          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12.5),
        ),
      );
    }

    return ListView.builder(
      itemCount: entries.length,
      itemBuilder: (ctx, idx) {
        final item = entries[idx];
        final rel = p.relative(item.filePath, from: widget.projectRoot);
        final isError = item.severity == 1;
        return InkWell(
          onTap: () => widget.onNavigate(item.filePath, item.line, item.col),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.warning_amber_rounded,
                  size: 15,
                  color: isError ? Colors.redAccent : Colors.amberAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.message,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: FyrTheme.textColor, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$rel:${item.line + 1}:${item.col + 1}',
                  style: GoogleFonts.jetBrainsMono(
                    color: FyrTheme.textColorMuted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: 'Fix this error with AI',
                  iconSize: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  icon: Icon(
                    Icons.auto_awesome,
                    color: FyrTheme.accentColor,
                  ),
                  onPressed: () => widget.onAskAi(
                    'Fix this error in $rel at line ${item.line + 1}: ${item.message}',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReferencesView() {
    if (widget.references.isEmpty) {
      return Center(
        child: Text(
          'Press Shift+F12 on a symbol to find all references.',
          style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12.5),
        ),
      );
    }

    return ListView.builder(
      itemCount: widget.references.length,
      itemBuilder: (ctx, idx) {
        final ref = widget.references[idx];
        final rel = p.relative(ref.filePath, from: widget.projectRoot);
        return InkWell(
          onTap: () => widget.onNavigate(ref.filePath, ref.line, ref.col),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(Icons.link, size: 14, color: FyrTheme.accentColor),
                const SizedBox(width: 8),
                Text(
                  '$rel:${ref.line + 1}:${ref.col + 1}',
                  style: GoogleFonts.jetBrainsMono(
                    color: FyrTheme.accentColor,
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ref.preview,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      color: FyrTheme.textColorMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
