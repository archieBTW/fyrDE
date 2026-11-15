import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;

import '../fyr_theme.dart';
import 'agent_controller.dart';
import 'agent_tools.dart';
import 'ai_markdown_view.dart';
import 'ai_models.dart';
import 'ai_settings_dialog.dart';

class AiAgentPanel extends StatefulWidget {
  final AgentController controller;
  final VoidCallback onClose;
  final void Function(String filePath)? onOpenFile;
  final void Function(String code, String? language)? onInsertCode;

  const AiAgentPanel({
    super.key,
    required this.controller,
    required this.onClose,
    this.onOpenFile,
    this.onInsertCode,
  });

  @override
  State<AiAgentPanel> createState() => AiAgentPanelState();
}

class AiAgentPanelState extends State<AiAgentPanel> {
  final TextEditingController _inputCtrl = TextEditingController();
  final TextEditingController _rejectReasonCtrl = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final ScrollController _scrollCtrl = ScrollController();

  final List<ContextAttachment> _pendingAttachments = [];
  bool _showMentionMenu = false;
  String _mentionQuery = '';
  int _mentionStartIndex = -1;
  List<String> _workspaceFiles = [];
  int _mentionSelectedIndex = 0;
  bool _tasksExpanded = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _inputCtrl.addListener(_handleComposerTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _inputCtrl.removeListener(_handleComposerTextChanged);
    _inputCtrl.dispose();
    _rejectReasonCtrl.dispose();
    _inputFocusNode.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void focusInput({ContextAttachment? attachContext}) {
    if (attachContext != null) {
      final exists = _pendingAttachments.any(
        (a) => a.type == attachContext.type && a.label == attachContext.label,
      );
      if (!exists) {
        setState(() => _pendingAttachments.add(attachContext));
      }
    }
    _inputFocusNode.requestFocus();
  }

  void sendQuickPrompt(
    String text, {
    List<ContextAttachment> attachments = const [],
  }) {
    widget.controller.sendMessage(text, explicitAttachments: attachments);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleComposerTextChanged() async {
    final text = _inputCtrl.text;
    final sel = _inputCtrl.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      if (_showMentionMenu) setState(() => _showMentionMenu = false);
      return;
    }

    final cursor = sel.baseOffset;
    if (cursor <= 0) {
      if (_showMentionMenu) setState(() => _showMentionMenu = false);
      return;
    }

    // Look backwards from cursor to find an active `@token`.
    final prefix = text.substring(0, cursor);
    final match = RegExp(r'(?:^|\s)@([^\s]*)$').firstMatch(prefix);
    if (match == null) {
      if (_showMentionMenu) setState(() => _showMentionMenu = false);
      return;
    }

    final query = match.group(1) ?? '';
    final atIdx = prefix.lastIndexOf('@');
    if (_workspaceFiles.isEmpty) {
      final files = await widget.controller.getWorkspaceFiles();
      if (!mounted) return;
      _workspaceFiles = files;
    }

    setState(() {
      _showMentionMenu = true;
      _mentionQuery = query;
      _mentionStartIndex = atIdx;
      _mentionSelectedIndex = 0;
    });
  }

  List<_MentionCandidate> _filteredMentionCandidates() {
    final q = _mentionQuery.toLowerCase();
    final specials = [
      const _MentionCandidate(
        insertToken: '@selection',
        label: '@selection',
        subtitle: 'Active editor selection',
        icon: Icons.select_all,
      ),
      const _MentionCandidate(
        insertToken: '@problems',
        label: '@problems',
        subtitle: 'Current LSP / compiler diagnostics',
        icon: Icons.error_outline,
      ),
      const _MentionCandidate(
        insertToken: '@git_diff',
        label: '@git_diff',
        subtitle: 'Uncommitted git status & diff',
        icon: Icons.difference_outlined,
      ),
    ];

    final fileItems = _workspaceFiles
        .where((f) => q.isEmpty || f.toLowerCase().contains(q))
        .take(20)
        .map(
          (f) => _MentionCandidate(
            insertToken: '@$f',
            label: p.basename(f),
            subtitle: f,
            icon: Icons.insert_drive_file_outlined,
          ),
        );

    return [
      ...specials.where(
        (s) => q.isEmpty || s.label.toLowerCase().contains(q),
      ),
      ...fileItems,
    ];
  }

  void _applyMentionCandidate(_MentionCandidate candidate) {
    final text = _inputCtrl.text;
    final cursor = _inputCtrl.selection.baseOffset;
    if (_mentionStartIndex < 0 || cursor < _mentionStartIndex) return;

    final replacement = '${candidate.insertToken} ';
    final updated = text.replaceRange(_mentionStartIndex, cursor, replacement);
    _inputCtrl.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset: _mentionStartIndex + replacement.length,
      ),
    );
    setState(() => _showMentionMenu = false);
  }

  void _submitPrompt() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty && _pendingAttachments.isEmpty) return;
    if (widget.controller.isRunning) return;

    final attachments = List<ContextAttachment>.from(_pendingAttachments);
    _inputCtrl.clear();
    setState(() {
      _pendingAttachments.clear();
      _showMentionMenu = false;
    });
    widget.controller.sendMessage(text, explicitAttachments: attachments);
  }

  Future<void> _attachSelection() async {
    final ctx = widget.controller.activeEditorContextProvider?.call();
    if (ctx == null ||
        ctx.selectedText == null ||
        ctx.selectedText!.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Select some code in the editor first.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    final rel = ctx.activeFile != null
        ? p.relative(ctx.activeFile!, from: widget.controller.projectRoot)
        : 'editor';
    final label =
        '$rel (L${(ctx.selectionStartLine ?? 0) + 1}-${(ctx.selectionEndLine ?? 0) + 1})';
    setState(() {
      _pendingAttachments.removeWhere(
        (a) => a.type == ContextAttachmentType.selection,
      );
      _pendingAttachments.add(
        ContextAttachment(
          type: ContextAttachmentType.selection,
          label: label,
          path: ctx.activeFile,
          startLine: ctx.selectionStartLine,
          endLine: ctx.selectionEndLine,
          content: ctx.selectedText,
        ),
      );
    });
  }

  Future<void> _attachImage() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );
    final path = result?.files.singleOrNull?.path;
    if (path == null) return;
    try {
      final bytes = await File(path).readAsBytes();
      final ext = p.extension(path).toLowerCase();
      final mime = switch (ext) {
        '.jpg' || '.jpeg' => 'image/jpeg',
        '.webp' => 'image/webp',
        '.gif' => 'image/gif',
        _ => 'image/png',
      };
      final dataUri = 'data:$mime;base64,${base64Encode(bytes)}';
      if (!mounted) return;
      setState(() {
        _pendingAttachments.add(
          ContextAttachment(
            type: ContextAttachmentType.image,
            label: p.basename(path),
            path: path,
            content: dataUri,
            mimeType: mime,
          ),
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not attach image: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final session = ctrl.activeSession;
    final visibleMessages = session.messages
        .where((m) => m.role != ChatRole.tool)
        .toList();

    return Container(
      color: FyrTheme.bgColor,
      child: Column(
        children: [
          _buildHeader(ctrl),
          _buildModeAndModelBar(ctrl),
          if (session.tasks.isNotEmpty) _buildTaskChecklistCard(session.tasks),
          Expanded(
            child: visibleMessages.isEmpty
                ? _buildEmptyState(ctrl)
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemCount: visibleMessages.length,
                    itemBuilder: (context, idx) {
                      final msg = visibleMessages[idx];
                      final isLast = idx == visibleMessages.length - 1;
                      return _buildMessageItem(ctrl, msg, isLast: isLast);
                    },
                  ),
          ),
          if (ctrl.pendingApproval != null)
            _buildApprovalBanner(ctrl, ctrl.pendingApproval!),
          if (_showMentionMenu) _buildMentionPopup(),
          _buildComposer(ctrl),
        ],
      ),
    );
  }

  Widget _buildHeader(AgentController ctrl) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        border: Border(
          bottom: BorderSide(color: FyrTheme.dividerColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 14, color: FyrTheme.accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              ctrl.activeSession.title,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.jetBrainsMono(
                color: FyrTheme.textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Tooltip(
            message: 'New Chat',
            child: IconButton(
              iconSize: 17,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: Icon(Icons.add_comment_outlined, color: FyrTheme.textColor),
              onPressed: ctrl.newSession,
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Chat History',
            color: FyrTheme.surfaceColor,
            icon: Icon(Icons.history, size: 17, color: FyrTheme.textColor),
            onSelected: (value) {
              if (value.startsWith('delete:')) {
                ctrl.deleteSession(value.substring(7));
              } else {
                ctrl.switchSession(value);
              }
            },
            itemBuilder: (_) {
              if (ctrl.sessions.isEmpty) {
                return [
                  PopupMenuItem(
                    enabled: false,
                    child: Text(
                      'No previous chats',
                      style: TextStyle(color: FyrTheme.textColorMuted),
                    ),
                  ),
                ];
              }
              return ctrl.sessions.map((s) {
                final isCurrent = s.id == ctrl.activeSession.id;
                return PopupMenuItem<String>(
                  value: s.id,
                  child: Row(
                    children: [
                      Icon(
                        isCurrent ? Icons.chat_bubble : Icons.chat_bubble_outline,
                        size: 14,
                        color: isCurrent
                            ? FyrTheme.accentColor
                            : FyrTheme.textColorMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: FyrTheme.textColor,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                      IconButton(
                        iconSize: 14,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        icon: Icon(
                          Icons.delete_outline,
                          color: FyrTheme.textColorMuted,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          ctrl.deleteSession(s.id);
                        },
                      ),
                    ],
                  ),
                );
              }).toList();
            },
          ),
          Tooltip(
            message: 'AI & BYOK Provider Settings',
            child: IconButton(
              iconSize: 17,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: Icon(Icons.tune, color: FyrTheme.textColor),
              onPressed: () => AiSettingsDialog.show(context, ctrl),
            ),
          ),
          Tooltip(
            message: 'Close AI Panel (Ctrl+L)',
            child: IconButton(
              iconSize: 17,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              icon: Icon(Icons.close, color: FyrTheme.textColorMuted),
              onPressed: widget.onClose,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeAndModelBar(AgentController ctrl) {
    final usage = ctrl.activeSession.totalUsage;
    final modelEntries = <({String providerId, String providerName, AiModelSpec model})>[];
    for (final provider in ctrl.config.providers) {
      for (final model in provider.models) {
        modelEntries.add((
          providerId: provider.id,
          providerName: provider.name,
          model: model,
        ));
      }
    }

    final currentKey = '${ctrl.activeProvider.id}::${ctrl.activeModel.id}';

    return Container(
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        border: Border(
          bottom: BorderSide(color: FyrTheme.dividerColor, width: 1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 32,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: AgentMode.values.map((m) {
                      final active = ctrl.mode == m;
                      return Tooltip(
                        message: m.description,
                        child: InkWell(
                          onTap: () => ctrl.setMode(m),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: active
                                      ? FyrTheme.accentColor
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                            ),
                            child: Text(
                              m.label,
                              style: GoogleFonts.jetBrainsMono(
                                color: active
                                    ? FyrTheme.textColor
                                    : FyrTheme.textColorMuted,
                                fontSize: 11.5,
                                fontWeight: active
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(width: 8),
                  // Minimal borderless model picker aligned with panel header
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: modelEntries.any(
                          (e) => '${e.providerId}::${e.model.id}' == currentKey,
                        )
                            ? currentKey
                            : null,
                        isExpanded: true,
                        isDense: true,
                        alignment: AlignmentDirectional.centerEnd,
                        dropdownColor: FyrTheme.cardColor,
                        icon: Icon(
                          Icons.expand_more,
                          size: 15,
                          color: FyrTheme.textColorMuted,
                        ),
                        style: GoogleFonts.jetBrainsMono(
                          color: FyrTheme.textColorMuted,
                          fontSize: 11,
                        ),
                        selectedItemBuilder: (context) => modelEntries.map((e) {
                          final label = e.providerId == 'deepseek'
                              ? e.model.displayName
                              : '${e.providerName}: ${e.model.displayName}';
                          return Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              label,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                color: FyrTheme.textColorMuted,
                                fontSize: 11,
                              ),
                            ),
                          );
                        }).toList(),
                        items: modelEntries.map((e) {
                          final key = '${e.providerId}::${e.model.id}';
                          return DropdownMenuItem<String>(
                            value: key,
                            child: Text(
                              e.providerId == 'deepseek'
                                  ? e.model.displayName
                                  : '${e.providerName}: ${e.model.displayName}',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                color: FyrTheme.textColor,
                                fontSize: 11.5,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val == null) return;
                          final parts = val.split('::');
                          if (parts.length == 2) {
                            ctrl.setActiveModel(parts[0], parts[1]);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (usage.totalTokens > 0)
            Container(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 5),
              child: Row(
                children: [
                  Text(
                    '${_formatTokenCount(usage.totalTokens)} tokens',
                    style: GoogleFonts.jetBrainsMono(
                      color: FyrTheme.textColorMuted,
                      fontSize: 10.5,
                    ),
                  ),
                  if (usage.cacheHitTokens > 0)
                    Text(
                      ' (${_formatTokenCount(usage.cacheHitTokens)} cached)',
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.greenAccent.withValues(alpha: 0.8),
                        fontSize: 10.5,
                      ),
                    ),
                  const Spacer(),
                  if (usage.estimatedCostUsd > 0)
                    Text(
                      '\$${usage.estimatedCostUsd.toStringAsFixed(4)}',
                      style: GoogleFonts.jetBrainsMono(
                        color: FyrTheme.textColorMuted,
                        fontSize: 10.5,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTaskChecklistCard(List<AgentTaskItem> tasks) {
    final completed =
        tasks.where((t) => t.status == AgentTaskStatus.completed).length;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _tasksExpanded = !_tasksExpanded),
            child: Row(
              children: [
                Icon(
                  Icons.checklist_rounded,
                  size: 14,
                  color: FyrTheme.accentColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Agent Tasks ($completed/${tasks.length})',
                    style: TextStyle(
                      color: FyrTheme.textColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Icon(
                  _tasksExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 15,
                  color: FyrTheme.textColorMuted,
                ),
              ],
            ),
          ),
          if (_tasksExpanded) ...[
            const SizedBox(height: 4),
            ...tasks.map((t) {
              final IconData icon;
              final Color color;
              switch (t.status) {
                case AgentTaskStatus.completed:
                  icon = Icons.check_circle_outline;
                  color = Colors.greenAccent;
                  break;
                case AgentTaskStatus.inProgress:
                  icon = Icons.timelapse;
                  color = FyrTheme.accentColor;
                  break;
                case AgentTaskStatus.pending:
                  icon = Icons.radio_button_unchecked;
                  color = FyrTheme.textColorMuted;
                  break;
              }
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(icon, size: 13, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        t.title,
                        style: TextStyle(
                          color: t.status == AgentTaskStatus.completed
                              ? FyrTheme.textColorMuted
                              : FyrTheme.textColor,
                          fontSize: 11.5,
                          decoration: t.status == AgentTaskStatus.completed
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(AgentController ctrl) {
    final needsKey = !ctrl.hasApiKey;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.terminal,
              size: 28,
              color: FyrTheme.textColorMuted,
            ),
            const SizedBox(height: 10),
            Text(
              'FyrCode Agent',
              style: GoogleFonts.jetBrainsMono(
                color: FyrTheme.textColor,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${ctrl.activeModel.displayName} • ${ctrl.activeProvider.name}',
              textAlign: TextAlign.center,
              style: GoogleFonts.jetBrainsMono(
                color: FyrTheme.textColorMuted,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 16),
            if (needsKey)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: FyrTheme.cardColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Column(
                  children: [
                    Text(
                      'No ${ctrl.activeProvider.name} API key configured yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: FyrTheme.textColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Add your key in Settings or set \$${ctrl.activeProvider.envVarName}.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.jetBrainsMono(
                        color: FyrTheme.textColorMuted,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: FyrTheme.accentColor,
                        side: BorderSide(color: FyrTheme.dividerColor),
                        backgroundColor: FyrTheme.bgColor,
                      ),
                      onPressed: () => AiSettingsDialog.show(context, ctrl),
                      icon: const Icon(Icons.key, size: 14),
                      label: Text(
                        'Add DeepSeek API Key',
                        style: GoogleFonts.jetBrainsMono(fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              _starterActionButton(
                icon: Icons.account_tree_outlined,
                title: 'Explore & summarize this codebase',
                onTap: () => ctrl.sendMessage(
                  'List the project structure and summarize the architecture of this codebase.',
                ),
              ),
              const SizedBox(height: 8),
              _starterActionButton(
                icon: Icons.bug_report_outlined,
                title: 'Check & fix current diagnostics (@problems)',
                onTap: () => ctrl.sendMessage(
                  'Inspect @problems and fix any compiler or lint issues.',
                ),
              ),
              const SizedBox(height: 8),
              _starterActionButton(
                icon: Icons.difference_outlined,
                title: 'Review uncommitted changes (@git_diff)',
                onTap: () => ctrl.sendMessage(
                  'Review @git_diff for bugs, edge cases, and code quality.',
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Tips: Use @file, @selection, @problems • Ctrl+K for Inline Edit • Ctrl+L to toggle panel',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: FyrTheme.textColorMuted,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _starterActionButton({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: FyrTheme.accentColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.jetBrainsMono(
                  color: FyrTheme.textColor,
                  fontSize: 12,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 15,
              color: FyrTheme.textColorMuted,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageItem(
    AgentController ctrl,
    ChatMessage msg, {
    required bool isLast,
  }) {
    if (msg.role == ChatRole.user) {
      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: FyrTheme.cardColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: FyrTheme.accentColor, width: 2.5),
              ),
            ),
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (msg.attachments.isNotEmpty) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: msg.attachments
                    .map(
                      (a) {
                        Uint8List? imageBytes;
                        if (a.type == ContextAttachmentType.image &&
                            a.content != null &&
                            a.content!.contains(',')) {
                          try {
                            imageBytes = base64Decode(
                              a.content!.split(',').last,
                            );
                          } catch (_) {}
                        }
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: FyrTheme.bgColor,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: FyrTheme.dividerColor),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (imageBytes != null) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: Image.memory(
                                    imageBytes,
                                    width: 18,
                                    height: 18,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 5),
                              ],
                              Text(
                                a.label,
                                style: GoogleFonts.jetBrainsMono(
                                  color: FyrTheme.accentColor,
                                  fontSize: 10.5,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    )
                    .toList(),
              ),
              const SizedBox(height: 6),
            ],
            SelectableText(
              msg.content,
              style: TextStyle(
                color: FyrTheme.textColor,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
          ),
        ),
      );
    }

    // Assistant message
    final isStreamingThis = ctrl.isRunning && isLast;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (msg.reasoningContent != null &&
              msg.reasoningContent!.trim().isNotEmpty)
            _ReasoningBlock(
              text: msg.reasoningContent!,
              isStreaming: isStreamingThis && msg.content.isEmpty,
            ),
          if (msg.toolCalls.isNotEmpty)
            ...msg.toolCalls.map(
              (tc) => _ToolCallCard(
                toolCall: tc,
                projectRoot: ctrl.projectRoot,
                onOpenFile: widget.onOpenFile,
              ),
            ),
          if (msg.content.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: msg.isError
                  ? Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.redAccent.withValues(alpha: 0.4),
                        ),
                      ),
                      child: SelectableText(
                        msg.content,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12.5,
                        ),
                      ),
                    )
                  : AiMarkdownView(
                      data: msg.content,
                      onInsertCode: widget.onInsertCode,
                    ),
            )
          else if (isStreamingThis &&
              msg.toolCalls.isEmpty &&
              (msg.reasoningContent == null || msg.reasoningContent!.isEmpty))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: FyrTheme.accentColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Thinking...',
                    style: TextStyle(
                      color: FyrTheme.textColorMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          if (msg.followupOptions.isNotEmpty && !ctrl.isRunning && isLast)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: msg.followupOptions
                    .map(
                      (opt) => ActionChip(
                        backgroundColor: FyrTheme.cardColor,
                        side: BorderSide(color: FyrTheme.accentColor),
                        label: Text(
                          opt,
                          style: TextStyle(
                            color: FyrTheme.textColor,
                            fontSize: 12,
                          ),
                        ),
                        onPressed: () => ctrl.sendMessage(opt),
                      ),
                    )
                    .toList(),
              ),
            ),
          // Plan mode quick-implement CTA
          if (ctrl.mode == AgentMode.plan &&
              !ctrl.isRunning &&
              isLast &&
              msg.content.isNotEmpty &&
              !msg.isError)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: FyrTheme.accentColor),
                ),
                onPressed: () {
                  ctrl.setMode(AgentMode.act);
                  ctrl.sendMessage('Implement the plan above.');
                },
                icon: Icon(
                  Icons.play_arrow,
                  size: 15,
                  color: FyrTheme.accentColor,
                ),
                label: Text(
                  'Implement Plan (Switch to Act)',
                  style: TextStyle(
                    color: FyrTheme.accentColor,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          // Checkpoint restore bar for turns that mutated files
          if (msg.checkpoints.isNotEmpty && !ctrl.isRunning)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                onTap: () async {
                  final restored = await ctrl.revertToCheckpoint(msg.id);
                  if (mounted && restored.isNotEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Reverted ${restored.length} file(s): ${restored.join(', ')}',
                        ),
                      ),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.restore,
                        size: 13,
                        color: FyrTheme.textColorMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Restore checkpoint (${msg.checkpoints.length} file edit${msg.checkpoints.length == 1 ? '' : 's'})',
                        style: TextStyle(
                          color: FyrTheme.textColorMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildApprovalBanner(
    AgentController ctrl,
    PendingToolApproval pending,
  ) {
    final isCmd = pending.commandPreview != null;
    final targetLabel = isCmd
        ? pending.commandPreview!
        : (pending.resolvedPath != null
            ? p.relative(pending.resolvedPath!, from: ctrl.projectRoot)
            : pending.toolCall.name);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isCmd ? Icons.terminal : Icons.edit_document,
                size: 15,
                color: FyrTheme.accentColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isCmd ? 'Approve Terminal Command?' : 'Approve File Change?',
                  style: TextStyle(
                    color: FyrTheme.textColor,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (!isCmd)
                Text(
                  '+${pending.addedLines} -${pending.removedLines}',
                  style: GoogleFonts.jetBrainsMono(
                    color: FyrTheme.textColorMuted,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: FyrTheme.cardColor,
              borderRadius: BorderRadius.circular(5),
            ),
            child: SelectableText(
              targetLabel,
              style: GoogleFonts.jetBrainsMono(
                color: FyrTheme.textColor,
                fontSize: 11.5,
              ),
            ),
          ),
          if (pending.diffPreview != null &&
              pending.diffPreview!.isNotEmpty) ...[
            const SizedBox(height: 6),
            DiffPreviewWidget(
              unifiedDiff: pending.diffPreview!,
              maxHeight: 160,
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2EA043),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                ),
                onPressed: () {
                  _rejectReasonCtrl.clear();
                  ctrl.respondToApproval(ToolApprovalAction.approveOnce);
                },
                icon: const Icon(Icons.check, size: 14),
                label: const Text('Approve', style: TextStyle(fontSize: 11.5)),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: FyrTheme.dividerColor),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                ),
                onPressed: () {
                  _rejectReasonCtrl.clear();
                  ctrl.respondToApproval(
                    isCmd
                        ? ToolApprovalAction.allowCommandPrefix
                        : ToolApprovalAction.approveAllInSession,
                  );
                },
                child: Text(
                  isCmd ? 'Always Allow Prefix' : 'Auto-Approve Edits',
                  style: TextStyle(color: FyrTheme.textColor, fontSize: 11.5),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                ),
                onPressed: () {
                  final reason = _rejectReasonCtrl.text.trim();
                  _rejectReasonCtrl.clear();
                  ctrl.respondToApproval(
                    ToolApprovalAction.reject,
                    rejectionReason: reason,
                  );
                },
                child: const Text(
                  'Reject',
                  style: TextStyle(color: Colors.redAccent, fontSize: 11.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMentionPopup() {
    final items = _filteredMentionCandidates();
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 0, 10, 4),
      constraints: const BoxConstraints(maxHeight: 190),
      decoration: BoxDecoration(
        color: FyrTheme.bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: FyrTheme.dividerColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
          ),
        ],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: items.length,
        itemBuilder: (context, idx) {
          final item = items[idx];
          final selected = idx == _mentionSelectedIndex;
          return InkWell(
            onTap: () => _applyMentionCandidate(item),
            child: Container(
              color: selected
                  ? FyrTheme.accentColor.withValues(alpha: 0.16)
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: [
                  Icon(item.icon, size: 14, color: FyrTheme.accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        color: FyrTheme.textColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      item.subtitle,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: FyrTheme.textColorMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildComposer(AgentController ctrl) {
    final autoEdits = ctrl.config.autoApprove.editTools;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        border: Border(top: BorderSide(color: FyrTheme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Attached Context Chips
          if (_pendingAttachments.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: _pendingAttachments.map((att) {
                Uint8List? thumbBytes;
                if (att.type == ContextAttachmentType.image &&
                    att.content != null &&
                    att.content!.contains(',')) {
                  try {
                    thumbBytes = base64Decode(att.content!.split(',').last);
                  } catch (_) {}
                }
                return Chip(
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  backgroundColor: FyrTheme.bgColor,
                  side: BorderSide(color: FyrTheme.dividerColor),
                  avatar: thumbBytes != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Image.memory(
                            thumbBytes,
                            width: 18,
                            height: 18,
                            fit: BoxFit.cover,
                          ),
                        )
                      : null,
                  label: Text(
                    att.label,
                    style: GoogleFonts.jetBrainsMono(
                      color: FyrTheme.textColor,
                      fontSize: 10.5,
                    ),
                  ),
                  deleteIcon: Icon(
                    Icons.close,
                    size: 13,
                    color: FyrTheme.textColorMuted,
                  ),
                  onDeleted: () => setState(() {
                    _pendingAttachments.remove(att);
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
          ],
          // Quick Context Bar
          Wrap(
            spacing: 5,
            runSpacing: 5,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _miniChip(
                icon: Icons.alternate_email,
                label: 'File',
                onTap: () {
                  final val = _inputCtrl.text;
                  final next = val.isEmpty || val.endsWith(' ')
                      ? '$val@'
                      : '$val @';
                  _inputCtrl.value = TextEditingValue(
                    text: next,
                    selection: TextSelection.collapsed(offset: next.length),
                  );
                  _inputFocusNode.requestFocus();
                },
              ),
              _miniChip(
                icon: Icons.select_all,
                label: 'Selection',
                onTap: _attachSelection,
              ),
              _miniChip(
                icon: Icons.image_outlined,
                label: 'Image',
                onTap: _attachImage,
              ),
              _miniChip(
                icon: Icons.error_outline,
                label: 'Problems',
                onTap: () {
                  setState(() {
                    if (!_pendingAttachments.any(
                      (a) => a.type == ContextAttachmentType.problems,
                    )) {
                      _pendingAttachments.add(
                        const ContextAttachment(
                          type: ContextAttachmentType.problems,
                          label: '@problems',
                        ),
                      );
                    }
                  });
                  // Also insert @problems if prompt is empty for convenience
                  if (_inputCtrl.text.trim().isEmpty) {
                    _inputCtrl.text = 'Inspect @problems and help fix them.';
                  }
                  _inputFocusNode.requestFocus();
                },
              ),
              if (ctrl.activeModel.supportsReasoning)
                Tooltip(
                  message: 'Toggle DeepSeek Thinking Mode',
                  child: InkWell(
                    onTap: () {
                      ctrl.updateConfig(
                        ctrl.config.copyWith(
                          thinkingEnabled: !ctrl.config.thinkingEnabled,
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(5),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: ctrl.config.thinkingEnabled
                            ? FyrTheme.accentColor.withValues(alpha: 0.18)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: ctrl.config.thinkingEnabled
                              ? FyrTheme.accentColor
                              : FyrTheme.dividerColor,
                        ),
                      ),
                      child: Text(
                        ctrl.config.thinkingEnabled
                            ? 'Think: ON'
                            : 'Think: OFF',
                        style: TextStyle(
                          color: ctrl.config.thinkingEnabled
                              ? FyrTheme.accentColor
                              : FyrTheme.textColorMuted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              Tooltip(
                message: 'Toggle Auto-Approve File Edits',
                child: InkWell(
                  onTap: () {
                    ctrl.updateAutoApprove(
                      ctrl.config.autoApprove.copyWith(editTools: !autoEdits),
                    );
                  },
                  borderRadius: BorderRadius.circular(5),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: autoEdits
                          ? FyrTheme.accentColor.withValues(alpha: 0.18)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: autoEdits
                            ? FyrTheme.accentColor
                            : FyrTheme.dividerColor,
                      ),
                    ),
                    child: Text(
                      autoEdits ? 'Auto-Edit: ON' : 'Auto-Edit: OFF',
                      style: TextStyle(
                        color: autoEdits
                            ? FyrTheme.accentColor
                            : FyrTheme.textColorMuted,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Input + Send / Stop
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;

                    if (_showMentionMenu) {
                      final items = _filteredMentionCandidates();
                      if (event.logicalKey == LogicalKeyboardKey.escape) {
                        setState(() => _showMentionMenu = false);
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowDown &&
                          items.isNotEmpty) {
                        setState(() {
                          _mentionSelectedIndex =
                              (_mentionSelectedIndex + 1) % items.length;
                        });
                        return KeyEventResult.handled;
                      }
                      if (event.logicalKey == LogicalKeyboardKey.arrowUp &&
                          items.isNotEmpty) {
                        setState(() {
                          _mentionSelectedIndex =
                              (_mentionSelectedIndex - 1 + items.length) %
                                  items.length;
                        });
                        return KeyEventResult.handled;
                      }
                      if ((event.logicalKey == LogicalKeyboardKey.enter ||
                              event.logicalKey == LogicalKeyboardKey.tab) &&
                          items.isNotEmpty) {
                        _applyMentionCandidate(items[_mentionSelectedIndex]);
                        return KeyEventResult.handled;
                      }
                    }

                    if (event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _submitPrompt();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(
                    controller: _inputCtrl,
                    focusNode: _inputFocusNode,
                    minLines: 1,
                    maxLines: 6,
                    style: GoogleFonts.jetBrainsMono(
                      color: FyrTheme.textColor,
                      fontSize: 12.5,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Ask ${ctrl.activeModel.displayName} (@ to attach files)...',
                      hintStyle: GoogleFonts.jetBrainsMono(
                        color: FyrTheme.textColorMuted,
                        fontSize: 12,
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
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (ctrl.isRunning)
                Tooltip(
                  message: 'Stop Agent',
                  child: IconButton(
                    onPressed: ctrl.stop,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.redAccent.withValues(alpha: 0.16),
                    ),
                    icon: const Icon(
                      Icons.stop_rounded,
                      color: Colors.redAccent,
                    ),
                  ),
                )
              else
                Tooltip(
                  message: 'Send (Enter)',
                  child: IconButton(
                    onPressed: _submitPrompt,
                    style: IconButton.styleFrom(
                      backgroundColor: FyrTheme.accentColor,
                      foregroundColor: FyrTheme.getContrastingColor(
                        FyrTheme.accentColor,
                      ),
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: FyrTheme.bgColor,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: FyrTheme.dividerColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: FyrTheme.textColorMuted),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                color: FyrTheme.textColorMuted,
                fontSize: 10.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatTokenCount(int count) {
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return count.toString();
  }
}

class _MentionCandidate {
  final String insertToken;
  final String label;
  final String subtitle;
  final IconData icon;

  const _MentionCandidate({
    required this.insertToken,
    required this.label,
    required this.subtitle,
    required this.icon,
  });
}

class _ReasoningBlock extends StatefulWidget {
  final String text;
  final bool isStreaming;

  const _ReasoningBlock({required this.text, required this.isStreaming});

  @override
  State<_ReasoningBlock> createState() => _ReasoningBlockState();
}

class _ReasoningBlockState extends State<_ReasoningBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    Icons.psychology_outlined,
                    size: 15,
                    color: FyrTheme.accentColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.isStreaming ? 'Reasoning...' : 'Thought Process',
                    style: TextStyle(
                      color: FyrTheme.textColorMuted,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: FyrTheme.textColorMuted,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded || widget.isStreaming)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: SingleChildScrollView(
                child: SelectableText(
                  widget.text,
                  style: GoogleFonts.jetBrainsMono(
                    color: FyrTheme.textColorMuted,
                    fontSize: 11.5,
                    height: 1.4,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolCallCard extends StatefulWidget {
  final ToolCallRecord toolCall;
  final String projectRoot;
  final void Function(String filePath)? onOpenFile;

  const _ToolCallCard({
    required this.toolCall,
    required this.projectRoot,
    this.onOpenFile,
  });

  @override
  State<_ToolCallCard> createState() => _ToolCallCardState();
}

class _ToolCallCardState extends State<_ToolCallCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tc = widget.toolCall;
    final args = tc.parsedArguments;
    final target = args['path']?.toString() ??
        args['command']?.toString() ??
        args['query']?.toString() ??
        args['pattern']?.toString() ??
        '';

    final statusWidget = switch (tc.status) {
      ToolCallStatus.running => SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(
            strokeWidth: 1.8,
            color: FyrTheme.accentColor,
          ),
        ),
      ToolCallStatus.pendingApproval => const Icon(
          Icons.hourglass_top,
          size: 14,
          color: Colors.amberAccent,
        ),
      ToolCallStatus.completed => const Icon(
          Icons.check_circle_outline,
          size: 14,
          color: Colors.greenAccent,
        ),
      ToolCallStatus.rejected => const Icon(
          Icons.block,
          size: 14,
          color: Colors.orangeAccent,
        ),
      ToolCallStatus.error => const Icon(
          Icons.error_outline,
          size: 14,
          color: Colors.redAccent,
        ),
    };

    final icon = switch (tc.name) {
      'read_file' => Icons.description_outlined,
      'write_to_file' || 'replace_in_file' => Icons.edit_note,
      'delete_file' => Icons.delete_outline,
      'run_command' => Icons.terminal,
      'search_files' || 'find_files' => Icons.search,
      'list_directory' => Icons.folder_open,
      'get_diagnostics' => Icons.bug_report_outlined,
      _ => Icons.build_outlined,
    };

    final hasDetails = (tc.diffPreview?.isNotEmpty ?? false) ||
        (tc.resultOutput?.isNotEmpty ?? false);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: FyrTheme.cardColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: FyrTheme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: hasDetails
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              child: Row(
                children: [
                  statusWidget,
                  const SizedBox(width: 7),
                  Icon(icon, size: 14, color: FyrTheme.accentColor),
                  const SizedBox(width: 6),
                  Text(
                    tc.name,
                    style: GoogleFonts.jetBrainsMono(
                      color: FyrTheme.textColor,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (target.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Expanded(
                      child: GestureDetector(
                        onTap: tc.targetPath != null &&
                                widget.onOpenFile != null &&
                                tc.name != 'delete_file' &&
                                tc.name != 'list_directory'
                            ? () => widget.onOpenFile!(tc.targetPath!)
                            : null,
                        child: Text(
                          target,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            color: tc.targetPath != null
                                ? FyrTheme.accentColor
                                : FyrTheme.textColorMuted,
                            fontSize: 11,
                            decoration: tc.targetPath != null
                                ? TextDecoration.underline
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  if (AgentToolExecutor.isMutationTool(tc.name) &&
                      (tc.addedLines > 0 || tc.removedLines > 0)) ...[
                    const SizedBox(width: 6),
                    Text(
                      '+${tc.addedLines} -${tc.removedLines}',
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.greenAccent,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                  if (tc.durationMs != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${tc.durationMs}ms',
                      style: GoogleFonts.jetBrainsMono(
                        color: FyrTheme.textColorMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                  if (hasDetails)
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 15,
                      color: FyrTheme.textColorMuted,
                    ),
                ],
              ),
            ),
          ),
          if (_expanded && hasDetails)
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 0, 9, 8),
              child: (tc.diffPreview != null && tc.diffPreview!.isNotEmpty)
                  ? DiffPreviewWidget(
                      unifiedDiff: tc.diffPreview!,
                      maxHeight: 200,
                    )
                  : Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: FyrTheme.cardColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          tc.resultOutput ?? '',
                          style: GoogleFonts.jetBrainsMono(
                            color: tc.status == ToolCallStatus.error
                                ? Colors.redAccent
                                : FyrTheme.textColorMuted,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}
