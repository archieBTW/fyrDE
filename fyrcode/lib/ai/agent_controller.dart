import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'agent_tools.dart';
import 'ai_models.dart';
import 'deepseek_client.dart';
import 'diff_utils.dart';
import 'mcp_client.dart';

enum ToolApprovalAction {
  approveOnce,
  approveAllInSession,
  allowCommandPrefix,
  reject,
}

class ToolApprovalDecision {
  final ToolApprovalAction action;
  final String? rejectionReason;

  const ToolApprovalDecision(this.action, {this.rejectionReason});
}

class PendingToolApproval {
  final String messageId;
  final ToolCallRecord toolCall;
  final String? diffPreview;
  final int addedLines;
  final int removedLines;
  final String? resolvedPath;
  final String? commandPreview;
  final Completer<ToolApprovalDecision> completer;

  PendingToolApproval({
    required this.messageId,
    required this.toolCall,
    this.diffPreview,
    this.addedLines = 0,
    this.removedLines = 0,
    this.resolvedPath,
    this.commandPreview,
  }) : completer = Completer<ToolApprovalDecision>();
}

/// Snapshot of active editor context supplied by [EditorScreen] / [CodeEditorPane].
class ActiveEditorContext {
  final String? activeFile;
  final List<String> openFiles;
  final String? selectedText;
  final int? selectionStartLine;
  final int? selectionEndLine;

  const ActiveEditorContext({
    this.activeFile,
    this.openFiles = const [],
    this.selectedText,
    this.selectionStartLine,
    this.selectionEndLine,
  });
}

class InlineEditResponse {
  final String replacementText;
  final DiffResult diff;
  final TokenUsage? usage;

  const InlineEditResponse({
    required this.replacementText,
    required this.diff,
    this.usage,
  });
}

/// Coordinates BYOK LLM streaming, tool execution, approval gates, checkpoints,
/// `@`-context attachments, and session persistence for a FyrCode workspace.
class AgentController extends ChangeNotifier {
  final AiConfigStore store;
  final LlmClient llmClient;
  String _projectRoot;

  final DiagnosticsProvider? diagnosticsProvider;
  final FileMutatedCallback? onFileMutated;
  final ActiveEditorContext Function()? activeEditorContextProvider;

  AiConfig _config = AiConfig.defaults();
  List<ChatSession> _sessions = [];
  late ChatSession _activeSession;
  AgentMode _mode = AgentMode.act;

  bool _initialized = false;
  bool _isRunning = false;
  bool _sessionApproveAllEdits = false;
  bool _sessionApproveAllCommands = false;
  CancellationToken? _activeCancelToken;
  PendingToolApproval? _pendingApproval;
  List<String> _cachedWorkspaceFiles = [];
  DateTime? _lastFileCacheAt;
  final McpManager mcpManager = McpManager();

  int _idCounter = 0;

  AgentController({
    required String projectRoot,
    AiConfigStore? store,
    LlmClient? llmClient,
    this.diagnosticsProvider,
    this.onFileMutated,
    this.activeEditorContextProvider,
  })  : _projectRoot = projectRoot,
        store = store ?? FileAiConfigStore(),
        llmClient = llmClient ?? OpenAiCompatLlmClient() {
    _activeSession = _createEmptySession();
  }

  String get projectRoot => _projectRoot;
  AiConfig get config => _config;
  AiProviderProfile get activeProvider => _config.activeProvider;
  AiModelSpec get activeModel => _config.activeModel;
  List<ChatSession> get sessions => List.unmodifiable(_sessions);
  ChatSession get activeSession => _activeSession;
  AgentMode get mode => _mode;
  bool get isInitialized => _initialized;
  bool get isRunning => _isRunning;
  PendingToolApproval? get pendingApproval => _pendingApproval;
  bool get hasApiKey {
    final p = activeProvider;
    return !p.requiresApiKey || p.resolveApiKey().isNotEmpty;
  }

  String _nextId(String prefix) {
    _idCounter++;
    return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  ChatSession _createEmptySession() => ChatSession(
        id: _nextId('chat'),
        title: 'New Chat',
        projectRoot: _projectRoot,
        mode: _mode,
      );

  Future<void> initialize() async {
    _config = await store.loadConfig();
    _sessions = await store.loadSessions(_projectRoot);
    if (_sessions.isNotEmpty) {
      _activeSession = _sessions.first;
      _mode = _activeSession.mode;
    } else {
      _activeSession = _createEmptySession();
    }
    _initialized = true;
    notifyListeners();
    if (_config.mcpServers.isNotEmpty) {
      unawaited(
        mcpManager.syncServers(
          _config.mcpServers,
          workingDirectory: _projectRoot,
        ).then((_) => notifyListeners()),
      );
    }
  }

  Future<void> setProjectRoot(String newRoot) async {
    if (newRoot == _projectRoot) return;
    stop();
    _projectRoot = newRoot;
    _cachedWorkspaceFiles = [];
    _lastFileCacheAt = null;
    _sessionApproveAllEdits = false;
    _sessionApproveAllCommands = false;
    _sessions = await store.loadSessions(_projectRoot);
    _activeSession =
        _sessions.isNotEmpty ? _sessions.first : _createEmptySession();
    _mode = _activeSession.mode;
    notifyListeners();
    if (_config.mcpServers.isNotEmpty) {
      unawaited(
        mcpManager.syncServers(
          _config.mcpServers,
          workingDirectory: _projectRoot,
        ).then((_) => notifyListeners()),
      );
    }
  }

  void setMode(AgentMode newMode) {
    if (_mode == newMode) return;
    _mode = newMode;
    _activeSession = _activeSession.copyWith(
      mode: newMode,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
    if (_activeSession.messages.isNotEmpty) {
      store.saveSession(_activeSession);
    }
  }

  Future<void> updateConfig(AiConfig nextConfig) async {
    final prevServers = _config.mcpServers;
    _config = nextConfig;
    await store.saveConfig(nextConfig);
    notifyListeners();
    if (nextConfig.mcpServers.length != prevServers.length ||
        jsonEncode(nextConfig.mcpServers.map((e) => e.toJson()).toList()) !=
            jsonEncode(prevServers.map((e) => e.toJson()).toList())) {
      unawaited(
        mcpManager.syncServers(
          nextConfig.mcpServers,
          workingDirectory: _projectRoot,
        ).then((_) => notifyListeners()),
      );
    }
  }

  @override
  void dispose() {
    unawaited(mcpManager.disposeAll());
    super.dispose();
  }

  Future<void> setActiveModel(String providerId, String modelId) async {
    await updateConfig(
      _config.copyWith(
        activeProviderId: providerId,
        activeModelId: modelId,
      ),
    );
  }

  Future<void> updateAutoApprove(AutoApprovePolicy policy) async {
    await updateConfig(_config.copyWith(autoApprove: policy));
  }

  Future<void> newSession() async {
    stop();
    _sessionApproveAllEdits = false;
    _sessionApproveAllCommands = false;
    _activeSession = _createEmptySession();
    notifyListeners();
  }

  Future<void> switchSession(String sessionId) async {
    stop();
    final found = _sessions.where((s) => s.id == sessionId).firstOrNull;
    if (found == null) return;
    _activeSession = found;
    _mode = found.mode;
    notifyListeners();
  }

  Future<void> deleteSession(String sessionId) async {
    await store.deleteSession(_projectRoot, sessionId);
    _sessions = _sessions.where((s) => s.id != sessionId).toList();
    if (_activeSession.id == sessionId) {
      _activeSession =
          _sessions.isNotEmpty ? _sessions.first : _createEmptySession();
      _mode = _activeSession.mode;
    }
    notifyListeners();
  }

  /// Returns cached relative workspace paths for `@` autocomplete.
  Future<List<String>> getWorkspaceFiles({bool forceRefresh = false}) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedWorkspaceFiles.isNotEmpty &&
        _lastFileCacheAt != null &&
        now.difference(_lastFileCacheAt!).inSeconds < 10) {
      return _cachedWorkspaceFiles;
    }
    final executor = AgentToolExecutor(projectRoot: _projectRoot);
    _cachedWorkspaceFiles = await executor.listWorkspaceFiles();
    _lastFileCacheAt = now;
    return _cachedWorkspaceFiles;
  }

  void respondToApproval(
    ToolApprovalAction action, {
    String? rejectionReason,
  }) {
    final pending = _pendingApproval;
    if (pending == null || pending.completer.isCompleted) return;
    _pendingApproval = null;
    notifyListeners();
    pending.completer.complete(
      ToolApprovalDecision(action, rejectionReason: rejectionReason),
    );
  }

  void stop() {
    _activeCancelToken?.cancel();
    _activeCancelToken = null;
    if (_pendingApproval != null && !_pendingApproval!.completer.isCompleted) {
      _pendingApproval!.completer.complete(
        const ToolApprovalDecision(
          ToolApprovalAction.reject,
          rejectionReason: 'Stopped by user.',
        ),
      );
      _pendingApproval = null;
    }
    if (_isRunning) {
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Restores all files modified in [messageId] (and any subsequent messages in
  /// the session) back to their pre-edit snapshots.
  Future<List<String>> revertToCheckpoint(String messageId) async {
    if (_isRunning) stop();
    final idx = _activeSession.messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return const [];

    // Revert checkpoints in reverse chronological order so multiple edits to
    // the same file restore to the earliest snapshot from the reverted range.
    final revertedFiles = <String>{};
    for (var i = _activeSession.messages.length - 1; i >= idx; i--) {
      final msg = _activeSession.messages[i];
      for (final cp in msg.checkpoints.reversed) {
        final file = File(cp.filePath);
        if (cp.existedBefore) {
          await file.parent.create(recursive: true);
          await file.writeAsString(cp.previousContent ?? '');
          await onFileMutated?.call(cp.filePath, deleted: false);
        } else {
          if (await file.exists()) {
            await file.delete();
            await onFileMutated?.call(cp.filePath, deleted: true);
          }
        }
        revertedFiles.add(p.relative(cp.filePath, from: _projectRoot));
      }
    }

    // Truncate messages back to right before the reverted assistant turn, or
    // strip checkpoints on the message if it was the target.
    final updatedMessages = _activeSession.messages.sublist(0, idx);
    _activeSession = _activeSession.copyWith(
      messages: updatedMessages,
      updatedAt: DateTime.now(),
    );
    await _persistActiveSession();
    notifyListeners();
    return revertedFiles.toList();
  }

  /// Sends a user prompt, expands `@` mentions, and executes the agentic loop.
  Future<void> sendMessage(
    String rawText, {
    List<ContextAttachment> explicitAttachments = const [],
  }) async {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty && explicitAttachments.isEmpty) return;
    if (_isRunning) return;

    final resolvedAttachments = await _resolveAllAttachments(
      trimmed,
      explicitAttachments,
    );

    final userMsg = ChatMessage(
      id: _nextId('msg'),
      role: ChatRole.user,
      content: trimmed,
      attachments: resolvedAttachments,
    );

    final nextTitle = _activeSession.messages.isEmpty
        ? _deriveTitle(trimmed)
        : _activeSession.title;

    _activeSession = _activeSession.copyWith(
      title: nextTitle,
      mode: _mode,
      messages: [..._activeSession.messages, userMsg],
      updatedAt: DateTime.now(),
    );
    _isRunning = true;
    final cancelToken = CancellationToken();
    _activeCancelToken = cancelToken;
    notifyListeners();
    await _persistActiveSession();

    final executor = AgentToolExecutor(
      projectRoot: _projectRoot,
      diagnosticsProvider: diagnosticsProvider,
      onFileMutated: onFileMutated,
    );

    try {
      await _runAgentLoop(executor, cancelToken);
    } catch (e) {
      if (!cancelToken.isCancelled) {
        _appendMessage(
          ChatMessage(
            id: _nextId('err'),
            role: ChatRole.assistant,
            content: 'Error: $e',
            isError: true,
          ),
        );
      }
    } finally {
      if (identical(_activeCancelToken, cancelToken)) {
        _activeCancelToken = null;
      }
      _isRunning = false;
      _pendingApproval = null;
      await _persistActiveSession();
      notifyListeners();
    }
  }

  Future<void> _runAgentLoop(
    AgentToolExecutor executor,
    CancellationToken cancelToken,
  ) async {
    final maxSteps = _config.autoApprove.maxStepsPerTurn.clamp(1, 50);
    final mcpSchemas = _mode == AgentMode.ask
        ? const <Map<String, dynamic>>[]
        : mcpManager.allTools.map((t) => t.toOpenAiToolSchema()).toList();
    final tools = [
      ...AgentToolExecutor.toolDefinitions(_mode),
      ...mcpSchemas,
    ];
    final systemPrompt = await _buildSystemPrompt();

    for (var step = 0; step < maxSteps; step++) {
      if (cancelToken.isCancelled) return;

      final assistantMsgId = _nextId('msg');
      var assistantMsg = ChatMessage(
        id: assistantMsgId,
        role: ChatRole.assistant,
        content: '',
      );
      _appendMessage(assistantMsg);

      final apiMessages = _serializeMessagesForApi(systemPrompt);
      final contentBuf = StringBuffer();
      final reasoningBuf = StringBuffer();
      final tcBuilders = <int, _ToolCallBuilder>{};
      TokenUsage? turnUsage;

      await for (final event in llmClient.streamChatCompletion(
        provider: activeProvider,
        model: activeModel,
        messages: apiMessages,
        tools: tools.isEmpty ? null : tools,
        temperature: _config.temperature,
        thinkingEnabled: _config.thinkingEnabled,
        reasoningEffort: _config.reasoningEffort,
        cancelToken: cancelToken,
      )) {
        if (cancelToken.isCancelled) return;

        if (event.reasoningDelta != null) {
          reasoningBuf.write(event.reasoningDelta);
        }
        if (event.contentDelta != null) {
          contentBuf.write(event.contentDelta);
        }
        for (final delta in event.toolCallDeltas) {
          final builder = tcBuilders.putIfAbsent(
            delta.index,
            () => _ToolCallBuilder(id: _nextId('call')),
          );
          if (delta.id != null && delta.id!.isNotEmpty) {
            builder.id = delta.id!;
          }
          if (delta.name != null && delta.name!.isNotEmpty) {
            builder.name.write(delta.name);
          }
          if (delta.argumentsFragment != null) {
            builder.arguments.write(delta.argumentsFragment);
          }
        }
        if (event.usage != null) {
          turnUsage = event.usage;
        }

        final builtCalls = _buildToolCallRecords(tcBuilders);
        assistantMsg = assistantMsg.copyWith(
          content: contentBuf.toString(),
          reasoningContent:
              reasoningBuf.isEmpty ? null : reasoningBuf.toString(),
          toolCalls: builtCalls,
          usage: turnUsage,
        );
        _replaceMessage(assistantMsg);
        notifyListeners();
      }

      if (cancelToken.isCancelled) return;

      if (turnUsage != null) {
        _activeSession = _activeSession.copyWith(
          totalUsage: _activeSession.totalUsage + turnUsage,
        );
      }

      final toolCalls = assistantMsg.toolCalls;
      if (toolCalls.isEmpty) {
        return; // Final answer complete!
      }

      // Execute each requested tool call in order.
      var awaitingUserFollowup = false;
      final turnCheckpoints = <FileCheckpoint>[];

      for (var i = 0; i < toolCalls.length; i++) {
        if (cancelToken.isCancelled) return;
        var tc = toolCalls[i];
        final args = tc.parsedArguments;

        // Handle interactive clarification questions directly in chat UI.
        if (tc.name == 'ask_followup_question') {
          final res = await executor.execute(tc.name, args);
          tc = tc.copyWith(
            status: ToolCallStatus.completed,
            resultOutput: res.output,
          );
          _updateToolCallInMessage(assistantMsgId, i, tc);
          assistantMsg = _findMessage(assistantMsgId)!.copyWith(
            content: assistantMsg.content.isEmpty
                ? res.output
                : '${assistantMsg.content}\n\n${res.output}',
            followupOptions: res.followupOptions,
          );
          _replaceMessage(assistantMsg);
          _appendMessage(
            ChatMessage(
              id: _nextId('tool'),
              role: ChatRole.tool,
              toolCallId: tc.id,
              toolName: tc.name,
              content: 'Waiting for user reply.',
            ),
          );
          awaitingUserFollowup = true;
          notifyListeners();
          continue;
        }

        // Handle structured checklist updates directly in session state.
        if (tc.name == 'manage_tasks') {
          final rawTasks = args['tasks'];
          final updatedTasks = <AgentTaskItem>[];
          if (rawTasks is List) {
            for (final item in rawTasks.whereType<Map>()) {
              final map = Map<String, dynamic>.from(item);
              updatedTasks.add(
                AgentTaskItem(
                  id: map['id']?.toString() ?? _nextId('task'),
                  title: map['title']?.toString() ?? '',
                  status: AgentTaskStatus.values.firstWhere(
                    (s) => s.name == map['status']?.toString(),
                    orElse: () => AgentTaskStatus.pending,
                  ),
                ),
              );
            }
          }
          _activeSession = _activeSession.copyWith(
            tasks: updatedTasks,
            updatedAt: DateTime.now(),
          );
          tc = tc.copyWith(
            status: ToolCallStatus.completed,
            resultOutput: 'Updated ${updatedTasks.length} checklist task(s).',
          );
          _updateToolCallInMessage(assistantMsgId, i, tc);
          _appendMessage(
            ChatMessage(
              id: _nextId('tool'),
              role: ChatRole.tool,
              toolCallId: tc.id,
              toolName: tc.name,
              content: 'Task checklist updated (${updatedTasks.length} items).',
            ),
          );
          notifyListeners();
          continue;
        }

        // Check approval gates before running mutations or shell commands.
        final needsApproval = _needsApproval(tc.name, args);
        String? previewDiff;
        int previewAdded = 0;
        int previewRemoved = 0;
        String? previewPath;

        if (AgentToolExecutor.isMutationTool(tc.name)) {
          final preview = await executor.previewMutation(tc.name, args);
          previewDiff = preview.diffPreview;
          previewAdded = preview.added;
          previewRemoved = preview.removed;
          previewPath = preview.resolvedPath;
        }

        if (needsApproval) {
          tc = tc.copyWith(
            status: ToolCallStatus.pendingApproval,
            diffPreview: previewDiff,
            addedLines: previewAdded,
            removedLines: previewRemoved,
            targetPath: previewPath,
          );
          _updateToolCallInMessage(assistantMsgId, i, tc);

          final pending = PendingToolApproval(
            messageId: assistantMsgId,
            toolCall: tc,
            diffPreview: previewDiff,
            addedLines: previewAdded,
            removedLines: previewRemoved,
            resolvedPath: previewPath,
            commandPreview: tc.name == 'run_command'
                ? args['command']?.toString()
                : null,
          );
          _pendingApproval = pending;
          notifyListeners();

          final decision = await pending.completer.future;
          if (cancelToken.isCancelled) return;

          if (decision.action == ToolApprovalAction.approveAllInSession) {
            if (AgentToolExecutor.isMutationTool(tc.name)) {
              _sessionApproveAllEdits = true;
            } else if (AgentToolExecutor.isCommandTool(tc.name)) {
              _sessionApproveAllCommands = true;
            }
          } else if (decision.action == ToolApprovalAction.allowCommandPrefix &&
              tc.name == 'run_command') {
            final cmd = (args['command']?.toString() ?? '').trim();
            final prefix = cmd.split(RegExp(r'\s+')).firstOrNull ?? '';
            if (prefix.isNotEmpty) {
              final existing = _config.autoApprove.allowedCommandPrefixes;
              if (!existing.contains(prefix)) {
                await updateAutoApprove(
                  _config.autoApprove.copyWith(
                    allowedCommandPrefixes: [...existing, prefix],
                  ),
                );
              }
            }
          } else if (decision.action == ToolApprovalAction.reject) {
            final reason = decision.rejectionReason?.trim().isNotEmpty == true
                ? decision.rejectionReason!.trim()
                : 'User rejected this tool call.';
            tc = tc.copyWith(
              status: ToolCallStatus.rejected,
              resultOutput: reason,
            );
            _updateToolCallInMessage(assistantMsgId, i, tc);
            _appendMessage(
              ChatMessage(
                id: _nextId('tool'),
                role: ChatRole.tool,
                toolCallId: tc.id,
                toolName: tc.name,
                content: 'REJECTED BY USER: $reason',
                isError: true,
              ),
            );
            notifyListeners();
            continue;
          }
        }

        // Execute tool (built-in or MCP).
        tc = tc.copyWith(status: ToolCallStatus.running);
        _updateToolCallInMessage(assistantMsgId, i, tc);
        notifyListeners();

        final sw = Stopwatch()..start();
        late final ToolExecutionResult result;
        if (tc.name.startsWith('mcp__')) {
          final mcpRes = await mcpManager.callQualifiedTool(tc.name, args);
          result = ToolExecutionResult(
            output: mcpRes.output,
            isError: mcpRes.isError,
          );
        } else {
          result = await executor.execute(
            tc.name,
            args,
            cancelToken: cancelToken,
          );
        }
        sw.stop();

        if (result.checkpoint != null) {
          turnCheckpoints.add(result.checkpoint!);
        }

        tc = tc.copyWith(
          status:
              result.isError ? ToolCallStatus.error : ToolCallStatus.completed,
          resultOutput: result.output,
          diffPreview: result.diffPreview ?? tc.diffPreview,
          addedLines: result.addedLines,
          removedLines: result.removedLines,
          targetPath: result.targetPath ?? tc.targetPath,
          durationMs: sw.elapsedMilliseconds,
        );
        _updateToolCallInMessage(assistantMsgId, i, tc);

        _appendMessage(
          ChatMessage(
            id: _nextId('tool'),
            role: ChatRole.tool,
            toolCallId: tc.id,
            toolName: tc.name,
            content: result.output,
            isError: result.isError,
          ),
        );
        notifyListeners();
      }

      if (turnCheckpoints.isNotEmpty) {
        final latest = _findMessage(assistantMsgId);
        if (latest != null) {
          _replaceMessage(
            latest.copyWith(
              checkpoints: [...latest.checkpoints, ...turnCheckpoints],
            ),
          );
        }
      }

      await _persistActiveSession();
      if (awaitingUserFollowup) return;
    }

    // Reached step safety limit.
    _appendMessage(
      ChatMessage(
        id: _nextId('msg'),
        role: ChatRole.assistant,
        content:
            'Reached the maximum of $maxSteps tool steps for this turn. Send another message (e.g., "continue") to keep going.',
      ),
    );
  }

  /// Cursor-style `Ctrl+K` inline edit generator.
  Future<InlineEditResponse> generateInlineEdit({
    required String filePath,
    required String fullFileContent,
    required int startLine,
    required int endLine,
    required String selectedOrTargetText,
    required String instruction,
    CancellationToken? cancelToken,
  }) async {
    final rel = p.relative(filePath, from: _projectRoot);
    final lines = fullFileContent.split('\n');
    final beforeStart = (startLine - 25).clamp(0, lines.length);
    final afterEnd = (endLine + 25).clamp(0, lines.length);
    final contextBefore = lines.sublist(beforeStart, startLine).join('\n');
    final contextAfter = lines.sublist(endLine + 1, afterEnd).join('\n');

    final prompt = '''File: $rel
Lines ${startLine + 1}-${endLine + 1} (0-based $startLine-$endLine).

Surrounding context BEFORE target:
```
$contextBefore
```

TARGET CODE TO REPLACE:
```
$selectedOrTargetText
```

Surrounding context AFTER target:
```
$contextAfter
```

Instruction: $instruction

Return ONLY the exact replacement code for the TARGET CODE section (preserving indentation). Do not include surrounding context lines, explanations, or markdown code fences.''';

    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are an expert code editor inside FyrCode. Output ONLY the replacement code with zero prose and zero markdown fences.',
      },
      {'role': 'user', 'content': prompt},
    ];

    final buf = StringBuffer();
    TokenUsage? usage;
    await for (final ev in llmClient.streamChatCompletion(
      provider: activeProvider,
      model: activeModel,
      messages: messages,
      temperature: 0.1,
      thinkingEnabled: false,
      cancelToken: cancelToken,
    )) {
      if (ev.contentDelta != null) buf.write(ev.contentDelta);
      if (ev.usage != null) usage = ev.usage;
    }

    final cleaned = _stripMarkdownFences(buf.toString());
    final diff = computeLineDiff(selectedOrTargetText, cleaned);
    return InlineEditResponse(
      replacementText: cleaned,
      diff: diff,
      usage: usage,
    );
  }

  bool _needsApproval(String toolName, Map<String, dynamic> args) {
    if (AgentToolExecutor.isReadOnlyTool(toolName)) {
      return !_config.autoApprove.readTools;
    }
    if (AgentToolExecutor.isMutationTool(toolName)) {
      return !_config.autoApprove.editTools && !_sessionApproveAllEdits;
    }
    if (AgentToolExecutor.isCommandTool(toolName)) {
      if (_config.autoApprove.runCommands || _sessionApproveAllCommands) {
        return false;
      }
      final cmd = args['command']?.toString() ?? '';
      return !_config.autoApprove.isCommandAllowlisted(cmd);
    }
    if (toolName.startsWith('mcp__')) {
      return !_config.autoApprove.runCommands && !_sessionApproveAllCommands;
    }
    return true;
  }

  Future<String> _buildSystemPrompt() async {
    final editorCtx = activeEditorContextProvider?.call();
    final rulesText = await _loadWorkspaceRules();
    final buf = StringBuffer()
      ..writeln(
        'You are FyrCode AI, an expert agentic software engineering assistant built directly into the FyrCode IDE.',
      )
      ..writeln('Workspace root: $_projectRoot')
      ..writeln('OS: ${Platform.operatingSystem}')
      ..writeln('Current mode: ${_mode.label} (${_mode.description})');

    if (_mode == AgentMode.plan) {
      buf.writeln(
        'PLAN MODE RULES: Do NOT modify files or run state-changing commands. Explore the codebase with read-only tools and produce a clear, concrete implementation plan with exact file paths and steps.',
      );
    } else if (_mode == AgentMode.ask) {
      buf.writeln(
        'ASK MODE RULES: Answer clearly and concisely using the attached context. Explain code and propose snippets without modifying files.',
      );
    } else {
      buf.writeln(
        'ACT MODE RULES: Read relevant files before editing. Prefer targeted edits via replace_in_file over overwriting whole files. After making code changes, verify with get_diagnostics or run_command (tests/analyzer) when appropriate.',
      );
    }

    if (editorCtx != null) {
      if (editorCtx.activeFile != null) {
        buf.writeln(
          'Active editor tab: ${p.relative(editorCtx.activeFile!, from: _projectRoot)}',
        );
      }
      if (editorCtx.openFiles.isNotEmpty) {
        final relTabs = editorCtx.openFiles
            .map((f) => p.relative(f, from: _projectRoot))
            .join(', ');
        buf.writeln('Open tabs: $relTabs');
      }
    }

    if (_config.customInstructions.trim().isNotEmpty) {
      buf.writeln('\nUser custom instructions:\n${_config.customInstructions.trim()}');
    }
    if (rulesText.isNotEmpty) {
      buf.writeln('\nWorkspace project rules:\n$rulesText');
    }

    return buf.toString();
  }

  Future<String> _loadWorkspaceRules() async {
    const candidates = [
      '.fyrcoderules',
      'AGENTS.md',
      'CLAUDE.md',
      '.cursorrules',
    ];
    final buf = StringBuffer();
    for (final name in candidates) {
      final f = File(p.join(_projectRoot, name));
      if (await f.exists()) {
        try {
          var content = await f.readAsString();
          if (content.length > 6000) {
            content = '${content.substring(0, 6000)}\n... (truncated)';
          }
          buf.writeln('--- $name ---\n$content');
        } catch (_) {}
      }
    }
    return buf.toString().trim();
  }

  /// Converts persisted [ChatSession.messages] into OpenAI/DeepSeek chat messages.
  List<Map<String, dynamic>> _serializeMessagesForApi(String systemPrompt) {
    final out = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    final msgs = _activeSession.messages;
    // Find index of the latest user message so we know whether an assistant
    // message belongs to the current active tool-calling turn (DeepSeek
    // Reasoner expects reasoning_content on tool-call steps within the active turn).
    final lastUserIdx = msgs.lastIndexWhere((m) => m.role == ChatRole.user);

    for (var i = 0; i < msgs.length; i++) {
      final m = msgs[i];
      if (m.role == ChatRole.user) {
        final contentBuf = StringBuffer(m.content);
        final imageParts = <Map<String, dynamic>>[];
        for (final att in m.attachments) {
          if (att.type == ContextAttachmentType.image) {
            if (att.content != null && att.content!.isNotEmpty) {
              imageParts.add({
                'type': 'image_url',
                'image_url': {'url': att.content},
              });
            }
          } else if (att.content != null && att.content!.isNotEmpty) {
            contentBuf.writeln(
              '\n<attached_context type="${att.type.name}" label="${att.label}">\n${att.content}\n</attached_context>',
            );
          }
        }
        if (imageParts.isNotEmpty) {
          out.add({
            'role': 'user',
            'content': [
              {'type': 'text', 'text': contentBuf.toString()},
              ...imageParts,
            ],
          });
        } else {
          out.add({
            'role': 'user',
            'content': contentBuf.toString(),
          });
        }
      } else if (m.role == ChatRole.assistant) {
        if (m.isError && m.toolCalls.isEmpty && m.content.startsWith('Error:')) {
          continue;
        }
        // Skip the brand-new empty placeholder message we just appended.
        if (m.content.isEmpty &&
            (m.reasoningContent == null || m.reasoningContent!.isEmpty) &&
            m.toolCalls.isEmpty) {
          continue;
        }
        final entry = <String, dynamic>{
          'role': 'assistant',
          'content': m.content.isEmpty && m.toolCalls.isNotEmpty
              ? null
              : m.content,
        };
        if (i > lastUserIdx &&
            m.toolCalls.isNotEmpty &&
            m.reasoningContent != null &&
            m.reasoningContent!.isNotEmpty) {
          entry['reasoning_content'] = m.reasoningContent;
        }
        if (m.toolCalls.isNotEmpty) {
          entry['tool_calls'] = m.toolCalls
              .map(
                (tc) => {
                  'id': tc.id,
                  'type': 'function',
                  'function': {
                    'name': tc.name,
                    'arguments': tc.argumentsJson,
                  },
                },
              )
              .toList();
        }
        out.add(entry);
      } else if (m.role == ChatRole.tool && m.toolCallId != null) {
        out.add({
          'role': 'tool',
          'tool_call_id': m.toolCallId,
          'content': m.content,
        });
      }
    }

    return out;
  }

  /// Resolves explicit context chips plus inline `@file`, `@selection`,
  /// `@problems`, `@git_diff`, `@open_files`, and `@folder` mentions.
  Future<List<ContextAttachment>> _resolveAllAttachments(
    String prompt,
    List<ContextAttachment> explicit,
  ) async {
    final result = <ContextAttachment>[...explicit];
    final seenKeys = explicit.map((a) => '${a.type.name}:${a.label}').toSet();

    final mentionRegex = RegExp(r'@([^\s,;()\[\]{}]+)');
    for (final match in mentionRegex.allMatches(prompt)) {
      final token = match.group(1) ?? '';
      if (token.isEmpty) continue;

      if (token == 'selection' && !seenKeys.contains('selection:@selection')) {
        final ctx = activeEditorContextProvider?.call();
        if (ctx != null &&
            ctx.selectedText != null &&
            ctx.selectedText!.isNotEmpty) {
          seenKeys.add('selection:@selection');
          final rel = ctx.activeFile != null
              ? p.relative(ctx.activeFile!, from: _projectRoot)
              : 'editor';
          result.add(
            ContextAttachment(
              type: ContextAttachmentType.selection,
              label: '$rel (L${(ctx.selectionStartLine ?? 0) + 1}-${(ctx.selectionEndLine ?? 0) + 1})',
              path: ctx.activeFile,
              startLine: ctx.selectionStartLine,
              endLine: ctx.selectionEndLine,
              content: ctx.selectedText,
            ),
          );
        }
        continue;
      }

      if (token == 'problems' && !seenKeys.contains('problems:@problems')) {
        seenKeys.add('problems:@problems');
        final exec = AgentToolExecutor(
          projectRoot: _projectRoot,
          diagnosticsProvider: diagnosticsProvider,
        );
        final res = await exec.execute('get_diagnostics', const {});
        result.add(
          ContextAttachment(
            type: ContextAttachmentType.problems,
            label: '@problems',
            content: res.output,
          ),
        );
        continue;
      }

      if (token == 'git_diff' && !seenKeys.contains('gitDiff:@git_diff')) {
        seenKeys.add('gitDiff:@git_diff');
        try {
          final status = await Process.run(
            'git',
            ['status', '--short'],
            workingDirectory: _projectRoot,
          );
          final diff = await Process.run(
            'git',
            ['diff'],
            workingDirectory: _projectRoot,
          );
          final combined =
              'Status:\n${status.stdout}\nDiff:\n${diff.stdout}'.trim();
          result.add(
            ContextAttachment(
              type: ContextAttachmentType.gitDiff,
              label: '@git_diff',
              content: combined.length > 12000
                  ? '${combined.substring(0, 12000)}\n... (truncated)'
                  : combined,
            ),
          );
        } catch (_) {}
        continue;
      }

      final relCandidate = token.startsWith('file:')
          ? token.substring(5)
          : (token.startsWith('folder:') ? token.substring(7) : token);
      final exec = AgentToolExecutor(projectRoot: _projectRoot);
      final safePath = exec.resolveSafePath(relCandidate);
      if (safePath == null) continue;

      if (File(safePath).existsSync() &&
          !seenKeys.contains('file:$relCandidate')) {
        seenKeys.add('file:$relCandidate');
        final res = await exec.execute('read_file', {'path': relCandidate});
        result.add(
          ContextAttachment(
            type: ContextAttachmentType.file,
            label: relCandidate,
            path: safePath,
            content: res.output,
          ),
        );
      } else if (Directory(safePath).existsSync() &&
          !seenKeys.contains('folder:$relCandidate')) {
        seenKeys.add('folder:$relCandidate');
        final res = await exec.execute(
          'list_directory',
          {'path': relCandidate, 'recursive': true},
        );
        result.add(
          ContextAttachment(
            type: ContextAttachmentType.folder,
            label: '$relCandidate/',
            path: safePath,
            content: res.output,
          ),
        );
      }
    }

    return result;
  }

  List<ToolCallRecord> _buildToolCallRecords(Map<int, _ToolCallBuilder> map) {
    final keys = map.keys.toList()..sort();
    return keys.map((k) {
      final b = map[k]!;
      return ToolCallRecord(
        id: b.id,
        name: b.name.toString(),
        argumentsJson: b.arguments.isEmpty ? '{}' : b.arguments.toString(),
        status: ToolCallStatus.running,
      );
    }).toList();
  }

  void _appendMessage(ChatMessage msg) {
    _activeSession = _activeSession.copyWith(
      messages: [..._activeSession.messages, msg],
      updatedAt: DateTime.now(),
    );
  }

  ChatMessage? _findMessage(String id) {
    return _activeSession.messages.where((m) => m.id == id).firstOrNull;
  }

  void _replaceMessage(ChatMessage updated) {
    final list = List<ChatMessage>.from(_activeSession.messages);
    final idx = list.indexWhere((m) => m.id == updated.id);
    if (idx != -1) {
      list[idx] = updated;
      _activeSession = _activeSession.copyWith(
        messages: list,
        updatedAt: DateTime.now(),
      );
    }
  }

  void _updateToolCallInMessage(
    String messageId,
    int toolIndex,
    ToolCallRecord updatedCall,
  ) {
    final msg = _findMessage(messageId);
    if (msg == null) return;
    final calls = List<ToolCallRecord>.from(msg.toolCalls);
    if (toolIndex < 0 || toolIndex >= calls.length) return;
    calls[toolIndex] = updatedCall;
    _replaceMessage(msg.copyWith(toolCalls: calls));
  }

  Future<void> _persistActiveSession() async {
    if (_activeSession.messages.isEmpty) return;
    await store.saveSession(_activeSession);
    final idx = _sessions.indexWhere((s) => s.id == _activeSession.id);
    if (idx == -1) {
      _sessions = [_activeSession, ..._sessions];
    } else {
      final copy = List<ChatSession>.from(_sessions);
      copy[idx] = _activeSession;
      copy.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      _sessions = copy;
    }
  }

  static String _deriveTitle(String prompt) {
    final singleLine = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= 44) return singleLine;
    return '${singleLine.substring(0, 41)}...';
  }

  static String _stripMarkdownFences(String raw) {
    final trimmed = raw.trim();
    final fenceMatch = RegExp(
      r'^```[a-zA-Z0-9_-]*\r?\n([\s\S]*?)\r?\n```$',
    ).firstMatch(trimmed);
    if (fenceMatch != null) {
      return fenceMatch.group(1) ?? trimmed;
    }
    return raw;
  }
}

class _ToolCallBuilder {
  String id;
  final StringBuffer name = StringBuffer();
  final StringBuffer arguments = StringBuffer();

  _ToolCallBuilder({required this.id});
}
