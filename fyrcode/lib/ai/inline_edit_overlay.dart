import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../fyr_theme.dart';
import 'agent_controller.dart';
import 'ai_markdown_view.dart';
import 'deepseek_client.dart';

class InlineEditOverlay extends StatefulWidget {
  final AgentController agentController;
  final String filePath;
  final String fullFileContent;
  final int startLine;
  final int endLine;
  final String targetText;
  final void Function(String replacementText) onAccept;
  final VoidCallback onClose;
  final VoidCallback onOpenSettings;

  const InlineEditOverlay({
    super.key,
    required this.agentController,
    required this.filePath,
    required this.fullFileContent,
    required this.startLine,
    required this.endLine,
    required this.targetText,
    required this.onAccept,
    required this.onClose,
    required this.onOpenSettings,
  });

  @override
  State<InlineEditOverlay> createState() => _InlineEditOverlayState();
}

class _InlineEditOverlayState extends State<InlineEditOverlay> {
  final TextEditingController _promptCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  CancellationToken? _cancelToken;
  bool _isGenerating = false;
  String? _error;
  InlineEditResponse? _proposal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    _promptCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final instruction = _promptCtrl.text.trim();
    if (instruction.isEmpty || _isGenerating) return;

    if (!widget.agentController.hasApiKey) {
      setState(() {
        _error = 'Configure your DeepSeek API key in AI Settings first.';
      });
      return;
    }

    _cancelToken?.cancel();
    final token = CancellationToken();
    _cancelToken = token;

    setState(() {
      _isGenerating = true;
      _error = null;
      _proposal = null;
    });

    try {
      final res = await widget.agentController.generateInlineEdit(
        filePath: widget.filePath,
        fullFileContent: widget.fullFileContent,
        startLine: widget.startLine,
        endLine: widget.endLine,
        selectedOrTargetText: widget.targetText,
        instruction: instruction,
        cancelToken: token,
      );
      if (!mounted || token.isCancelled) return;
      setState(() {
        _isGenerating = false;
        _proposal = res;
      });
    } catch (e) {
      if (!mounted || token.isCancelled) return;
      setState(() {
        _isGenerating = false;
        _error = e.toString();
      });
    }
  }

  void _acceptProposal() {
    final p = _proposal;
    if (p == null) return;
    widget.onAccept(p.replacementText);
  }

  @override
  Widget build(BuildContext context) {
    final lineLabel = widget.startLine == widget.endLine
        ? 'Line ${widget.startLine + 1}'
        : 'Lines ${widget.startLine + 1}-${widget.endLine + 1}';

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () {
          _cancelToken?.cancel();
          widget.onClose();
        },
        if (_proposal != null) ...{
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _acceptProposal,
          const SingleActivator(LogicalKeyboardKey.enter, meta: true):
              _acceptProposal,
        },
      },
      child: Container(
        width: 560,
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          color: FyrTheme.surfaceColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: FyrTheme.dividerColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: FyrTheme.cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(7),
                ),
                border: Border(
                  bottom: BorderSide(color: FyrTheme.dividerColor),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.edit_note,
                    size: 15,
                    color: FyrTheme.accentColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Inline Edit',
                    style: GoogleFonts.jetBrainsMono(
                      color: FyrTheme.textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: FyrTheme.bgColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      lineLabel,
                      style: GoogleFonts.jetBrainsMono(
                        color: FyrTheme.textColorMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    widget.agentController.activeModel.displayName,
                    style: TextStyle(
                      color: FyrTheme.textColorMuted,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () {
                      _cancelToken?.cancel();
                      widget.onClose();
                    },
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: FyrTheme.textColorMuted,
                    ),
                  ),
                ],
              ),
            ),
            // Input Row
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promptCtrl,
                      focusNode: _focusNode,
                      style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                      decoration: InputDecoration(
                        hintText:
                            'Describe your edit (e.g. "Add null safety & docstring")...',
                        hintStyle: TextStyle(
                          color: FyrTheme.textColorMuted,
                          fontSize: 12.5,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        filled: true,
                        fillColor: FyrTheme.bgColor,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: FyrTheme.dividerColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: FyrTheme.dividerColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(6),
                          borderSide: BorderSide(color: FyrTheme.accentColor),
                        ),
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_isGenerating)
                    IconButton(
                      tooltip: 'Stop',
                      onPressed: () {
                        _cancelToken?.cancel();
                        setState(() => _isGenerating = false);
                      },
                      icon: const Icon(
                        Icons.stop_circle,
                        color: Colors.redAccent,
                      ),
                    )
                  else
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: FyrTheme.accentColor,
                        foregroundColor: FyrTheme.getContrastingColor(
                          FyrTheme.accentColor,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      onPressed: _submit,
                      child: const Text('Edit', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
            if (_isGenerating)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (!widget.agentController.hasApiKey)
                      TextButton(
                        onPressed: widget.onOpenSettings,
                        child: Text(
                          'Open Settings',
                          style: TextStyle(
                            color: FyrTheme.accentColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (_proposal != null) ...[
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: DiffPreviewWidget(
                    unifiedDiff: _proposal!.diff.unifiedPreview.isEmpty
                        ? _proposal!.replacementText
                        : _proposal!.diff.unifiedPreview,
                    maxHeight: 210,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: [
                    Text(
                      '+${_proposal!.diff.addedCount} -${_proposal!.diff.removedCount}',
                      style: GoogleFonts.jetBrainsMono(
                        color: FyrTheme.textColorMuted,
                        fontSize: 11.5,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: widget.onClose,
                      child: Text(
                        'Reject (Esc)',
                        style: TextStyle(
                          color: FyrTheme.textColorMuted,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2EA043),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _acceptProposal,
                      icon: const Icon(Icons.check, size: 15),
                      label: const Text(
                        'Accept (Ctrl+Enter)',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
