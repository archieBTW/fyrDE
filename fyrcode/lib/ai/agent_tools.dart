import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ai_models.dart';
import 'deepseek_client.dart';
import 'diff_utils.dart';

/// Result returned by executing a single workspace tool.
class ToolExecutionResult {
  final String output;
  final bool isError;
  final String? diffPreview;
  final int addedLines;
  final int removedLines;
  final String? targetPath;
  final FileCheckpoint? checkpoint;
  final List<String> followupOptions;

  const ToolExecutionResult({
    required this.output,
    this.isError = false,
    this.diffPreview,
    this.addedLines = 0,
    this.removedLines = 0,
    this.targetPath,
    this.checkpoint,
    this.followupOptions = const [],
  });
}

/// Callback providing live editor/LSP diagnostics keyed by absolute file path.
typedef DiagnosticsProvider = Map<String, List<dynamic>> Function();

/// Callback invoked whenever a tool mutates or deletes a file on disk.
typedef FileMutatedCallback = Future<void> Function(
  String filePath, {
  bool deleted,
});

/// Defines tool schemas and executes workspace tools safely inside [projectRoot].
class AgentToolExecutor {
  final String projectRoot;
  final DiagnosticsProvider? diagnosticsProvider;
  final FileMutatedCallback? onFileMutated;

  static const Set<String> _ignoredDirs = {
    '.git',
    '.dart_tool',
    'build',
    'node_modules',
    '.idea',
    '.gradle',
    '__pycache__',
    'target',
  };

  static const Set<String> readOnlyTools = {
    'read_file',
    'list_directory',
    'search_files',
    'find_files',
    'get_diagnostics',
    'ask_followup_question',
    'manage_tasks',
  };

  static const Set<String> mutationTools = {
    'write_to_file',
    'replace_in_file',
    'delete_file',
  };

  AgentToolExecutor({
    required this.projectRoot,
    this.diagnosticsProvider,
    this.onFileMutated,
  });

  static bool isReadOnlyTool(String name) => readOnlyTools.contains(name);
  static bool isMutationTool(String name) => mutationTools.contains(name);
  static bool isCommandTool(String name) => name == 'run_command';

  /// Returns OpenAI/DeepSeek `tools` schema list filtered by [AgentMode].
  static List<Map<String, dynamic>> toolDefinitions(AgentMode mode) {
    if (mode == AgentMode.ask) {
      return const [];
    }

    final readDefs = <Map<String, dynamic>>[
      _toolSchema(
        name: 'read_file',
        description:
            'Read the contents of a file in the workspace with 1-based line numbers. Use start_line and end_line for large files.',
        properties: {
          'path': {
            'type': 'string',
            'description': 'Path to the file relative to project root (or absolute within project).',
          },
          'start_line': {
            'type': 'integer',
            'description': 'Optional 1-based inclusive start line.',
          },
          'end_line': {
            'type': 'integer',
            'description': 'Optional 1-based inclusive end line.',
          },
        },
        required: ['path'],
      ),
      _toolSchema(
        name: 'list_directory',
        description:
            'List files and directories inside a directory in the workspace.',
        properties: {
          'path': {
            'type': 'string',
            'description': 'Directory path relative to project root (defaults to ".").',
          },
          'recursive': {
            'type': 'boolean',
            'description': 'Whether to recurse into subdirectories (max depth 3).',
          },
        },
      ),
      _toolSchema(
        name: 'search_files',
        description:
            'Search text or regular expression across workspace files, returning matching file paths, line numbers, and line content.',
        properties: {
          'query': {
            'type': 'string',
            'description': 'Search text or regex pattern.',
          },
          'path': {
            'type': 'string',
            'description': 'Optional subdirectory or file relative to root.',
          },
          'is_regex': {
            'type': 'boolean',
            'description': 'Treat query as a regular expression (default true).',
          },
          'case_sensitive': {
            'type': 'boolean',
            'description': 'Case-sensitive search (default false).',
          },
          'file_extension': {
            'type': 'string',
            'description': 'Optional extension filter without dot, e.g. "dart" or "py".',
          },
        },
        required: ['query'],
      ),
      _toolSchema(
        name: 'find_files',
        description:
            'Find files in the workspace whose relative path or filename matches a query/glob.',
        properties: {
          'pattern': {
            'type': 'string',
            'description': 'Substring or glob pattern (e.g. "*.dart" or "editor").',
          },
          'path': {
            'type': 'string',
            'description': 'Optional subdirectory relative to project root.',
          },
        },
        required: ['pattern'],
      ),
      _toolSchema(
        name: 'get_diagnostics',
        description:
            'Get current compiler/LSP errors and warnings for open files or run project analysis.',
        properties: {
          'path': {
            'type': 'string',
            'description': 'Optional file path to filter diagnostics.',
          },
        },
      ),
      _toolSchema(
        name: 'ask_followup_question',
        description:
            'Ask the user a clarifying question with optional quick-reply choices when requirements are ambiguous.',
        properties: {
          'question': {
            'type': 'string',
            'description': 'Clear question for the user.',
          },
          'options': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Optional 2-4 suggested answers.',
          },
        },
        required: ['question'],
      ),
      _toolSchema(
        name: 'manage_tasks',
        description:
            'Create or update the structured task checklist shown in the IDE chat UI so the user can track multi-step progress.',
        properties: {
          'tasks': {
            'type': 'array',
            'description': 'Ordered list of checklist items.',
            'items': {
              'type': 'object',
              'properties': {
                'id': {
                  'type': 'string',
                  'description': 'Stable identifier for the task item.',
                },
                'title': {
                  'type': 'string',
                  'description': 'Short human-readable task description.',
                },
                'status': {
                  'type': 'string',
                  'enum': ['pending', 'inProgress', 'completed'],
                  'description': 'Current state of the task.',
                },
              },
              'required': ['id', 'title', 'status'],
            },
          },
        },
        required: ['tasks'],
      ),
    ];

    if (mode == AgentMode.plan) {
      return readDefs;
    }

    // Act mode adds file mutation and terminal execution tools.
    return [
      ...readDefs,
      _toolSchema(
        name: 'replace_in_file',
        description:
            'Make a targeted edit to an existing file by replacing an exact text block (old_text) with new_text. Prefer this over write_to_file for modifying existing files.',
        properties: {
          'path': {
            'type': 'string',
            'description': 'Path to the file relative to project root.',
          },
          'old_text': {
            'type': 'string',
            'description': 'Exact existing code block to find and replace (include enough surrounding lines to be unique).',
          },
          'new_text': {
            'type': 'string',
            'description': 'Replacement code block.',
          },
          'replace_all': {
            'type': 'boolean',
            'description': 'Replace every occurrence instead of requiring a single unique match (default false).',
          },
        },
        required: ['path', 'old_text', 'new_text'],
      ),
      _toolSchema(
        name: 'write_to_file',
        description:
            'Create a new file or completely overwrite an existing file with the provided content. Creates parent directories automatically.',
        properties: {
          'path': {
            'type': 'string',
            'description': 'Path to the file relative to project root.',
          },
          'content': {
            'type': 'string',
            'description': 'Full file content to write.',
          },
        },
        required: ['path', 'content'],
      ),
      _toolSchema(
        name: 'delete_file',
        description: 'Delete a file from the workspace.',
        properties: {
          'path': {
            'type': 'string',
            'description': 'Path to the file relative to project root.',
          },
        },
        required: ['path'],
      ),
      _toolSchema(
        name: 'run_command',
        description:
            'Execute a shell command in the project root directory (e.g., tests, build, git status, linters).',
        properties: {
          'command': {
            'type': 'string',
            'description': 'Shell command to execute.',
          },
          'working_directory': {
            'type': 'string',
            'description': 'Optional subdirectory relative to project root.',
          },
          'timeout_seconds': {
            'type': 'integer',
            'description': 'Command timeout in seconds (default 60, max 300).',
          },
        },
        required: ['command'],
      ),
    ];
  }

  static Map<String, dynamic> _toolSchema({
    required String name,
    required String description,
    required Map<String, dynamic> properties,
    List<String> required = const [],
  }) {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': properties,
          if (required.isNotEmpty) 'required': required,
        },
      },
    };
  }

  /// Preview diff for a pending file mutation BEFORE applying it, so the user
  /// sees exact `+`/`-` changes in the Approval Card.
  Future<({String? diffPreview, int added, int removed, String? resolvedPath, String? error})>
      previewMutation(String toolName, Map<String, dynamic> args) async {
    final rawPath = args['path']?.toString() ?? '';
    final resolved = resolveSafePath(rawPath);
    if (resolved == null) {
      return (
        diffPreview: null,
        added: 0,
        removed: 0,
        resolvedPath: null,
        error: 'Path "$rawPath" is outside the project root.',
      );
    }

    final file = File(resolved);
    final existed = await file.exists();
    final oldContent = existed ? await file.readAsString() : '';

    if (toolName == 'write_to_file') {
      final newContent = args['content']?.toString() ?? '';
      final diff = computeLineDiff(oldContent, newContent);
      return (
        diffPreview: diff.unifiedPreview,
        added: diff.addedCount,
        removed: diff.removedCount,
        resolvedPath: resolved,
        error: null,
      );
    }

    if (toolName == 'replace_in_file') {
      if (!existed) {
        return (
          diffPreview: null,
          added: 0,
          removed: 0,
          resolvedPath: resolved,
          error: 'File not found: $rawPath',
        );
      }
      final oldText = args['old_text']?.toString() ?? '';
      final newText = args['new_text']?.toString() ?? '';
      final replaceAll = args['replace_all'] == true;
      final normalizedOld = oldContent.replaceAll('\r\n', '\n');
      final normalizedTarget = oldText.replaceAll('\r\n', '\n');

      if (normalizedTarget.isEmpty) {
        return (
          diffPreview: null,
          added: 0,
          removed: 0,
          resolvedPath: resolved,
          error: 'old_text cannot be empty.',
        );
      }

      final matches = _countOccurrences(normalizedOld, normalizedTarget);
      if (matches == 0) {
        return (
          diffPreview: null,
          added: 0,
          removed: 0,
          resolvedPath: resolved,
          error: 'old_text not found in $rawPath.',
        );
      }
      if (!replaceAll && matches > 1) {
        return (
          diffPreview: null,
          added: 0,
          removed: 0,
          resolvedPath: resolved,
          error:
              'old_text matched $matches locations in $rawPath. Include more surrounding lines or set replace_all: true.',
        );
      }

      final newContent = replaceAll
          ? normalizedOld.replaceAll(normalizedTarget, newText)
          : normalizedOld.replaceFirst(normalizedTarget, newText);
      final diff = computeLineDiff(normalizedOld, newContent);
      return (
        diffPreview: diff.unifiedPreview,
        added: diff.addedCount,
        removed: diff.removedCount,
        resolvedPath: resolved,
        error: null,
      );
    }

    if (toolName == 'delete_file') {
      if (!existed) {
        return (
          diffPreview: null,
          added: 0,
          removed: 0,
          resolvedPath: resolved,
          error: 'File not found: $rawPath',
        );
      }
      final diff = computeLineDiff(oldContent, '');
      return (
        diffPreview: diff.unifiedPreview,
        added: diff.addedCount,
        removed: diff.removedCount,
        resolvedPath: resolved,
        error: null,
      );
    }

    return (
      diffPreview: null,
      added: 0,
      removed: 0,
      resolvedPath: resolved,
      error: null,
    );
  }

  /// Resolves [inputPath] against [projectRoot] and returns null if it escapes
  /// outside the workspace root.
  String? resolveSafePath(String inputPath) {
    final trimmed = inputPath.trim();
    final rootNorm = p.canonicalize(projectRoot);
    final candidate = trimmed.isEmpty || trimmed == '.'
        ? rootNorm
        : p.isAbsolute(trimmed)
            ? p.normalize(trimmed)
            : p.normalize(p.join(rootNorm, trimmed));

    // Resolve existing parent symlinks if possible, while checking prefix.
    String canonicalCandidate;
    try {
      if (FileSystemEntity.typeSync(candidate) != FileSystemEntityType.notFound) {
        canonicalCandidate = p.canonicalize(candidate);
      } else {
        canonicalCandidate = candidate;
      }
    } catch (_) {
      canonicalCandidate = candidate;
    }

    if (canonicalCandidate == rootNorm ||
        p.isWithin(rootNorm, canonicalCandidate)) {
      return canonicalCandidate;
    }
    return null;
  }

  Future<ToolExecutionResult> execute(
    String name,
    Map<String, dynamic> args, {
    CancellationToken? cancelToken,
  }) async {
    switch (name) {
      case 'read_file':
        return _readFile(args);
      case 'write_to_file':
        return _writeToFile(args);
      case 'replace_in_file':
        return _replaceInFile(args);
      case 'delete_file':
        return _deleteFile(args);
      case 'list_directory':
        return _listDirectory(args);
      case 'search_files':
        return _searchFiles(args);
      case 'find_files':
        return _findFiles(args);
      case 'run_command':
        return _runCommand(args, cancelToken: cancelToken);
      case 'get_diagnostics':
        return _getDiagnostics(args);
      case 'ask_followup_question':
        final question = args['question']?.toString() ?? '';
        final options = ((args['options'] as List?) ?? [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
        return ToolExecutionResult(
          output: question,
          followupOptions: options,
        );
      default:
        return ToolExecutionResult(
          output: 'Unknown tool: $name',
          isError: true,
        );
    }
  }

  Future<ToolExecutionResult> _readFile(Map<String, dynamic> args) async {
    final rawPath = args['path']?.toString() ?? '';
    final resolved = resolveSafePath(rawPath);
    if (resolved == null) {
      return ToolExecutionResult(
        output: 'Access denied: "$rawPath" is outside the project root.',
        isError: true,
      );
    }

    final file = File(resolved);
    if (!await file.exists()) {
      return ToolExecutionResult(
        output: 'File not found: $rawPath',
        isError: true,
        targetPath: resolved,
      );
    }

    try {
      final bytes = await file.readAsBytes();
      if (_looksBinary(bytes)) {
        return ToolExecutionResult(
          output: 'Cannot read binary file ($rawPath, ${bytes.length} bytes).',
          isError: true,
          targetPath: resolved,
        );
      }
      final content = utf8.decode(bytes, allowMalformed: true);
      final lines = content.split('\n');
      final startLine = ((args['start_line'] as num?)?.toInt() ?? 1).clamp(
        1,
        lines.isEmpty ? 1 : lines.length,
      );
      final requestedEnd = (args['end_line'] as num?)?.toInt();
      final maxLineLimit = startLine + 499;
      final endLine = (requestedEnd ?? maxLineLimit).clamp(
        startLine,
        lines.isEmpty ? 1 : lines.length,
      );

      final buf = StringBuffer();
      buf.writeln(
        'File: ${p.relative(resolved, from: projectRoot)} (${lines.length} lines total, showing $startLine-$endLine)',
      );
      for (var i = startLine - 1; i < endLine && i < lines.length; i++) {
        buf.writeln('${i + 1}: ${lines[i]}');
      }
      if (endLine < lines.length && requestedEnd == null) {
        buf.writeln(
          '... (${lines.length - endLine} more lines; pass start_line=${endLine + 1} to continue reading)',
        );
      }
      return ToolExecutionResult(
        output: buf.toString().trimRight(),
        targetPath: resolved,
      );
    } catch (e) {
      return ToolExecutionResult(
        output: 'Error reading $rawPath: $e',
        isError: true,
        targetPath: resolved,
      );
    }
  }

  Future<ToolExecutionResult> _writeToFile(Map<String, dynamic> args) async {
    final rawPath = args['path']?.toString() ?? '';
    final content = args['content']?.toString() ?? '';
    final resolved = resolveSafePath(rawPath);
    if (resolved == null) {
      return ToolExecutionResult(
        output: 'Access denied: "$rawPath" is outside the project root.',
        isError: true,
      );
    }

    try {
      final file = File(resolved);
      final existed = await file.exists();
      final oldContent = existed ? await file.readAsString() : '';
      final checkpoint = FileCheckpoint(
        filePath: resolved,
        existedBefore: existed,
        previousContent: existed ? oldContent : null,
      );

      await file.parent.create(recursive: true);
      await file.writeAsString(content);
      await onFileMutated?.call(resolved, deleted: false);

      final diff = computeLineDiff(oldContent, content);
      final rel = p.relative(resolved, from: projectRoot);
      return ToolExecutionResult(
        output:
            '${existed ? 'Updated' : 'Created'} $rel (+${diff.addedCount} -${diff.removedCount} lines).',
        diffPreview: diff.unifiedPreview,
        addedLines: diff.addedCount,
        removedLines: diff.removedCount,
        targetPath: resolved,
        checkpoint: checkpoint,
      );
    } catch (e) {
      return ToolExecutionResult(
        output: 'Failed to write $rawPath: $e',
        isError: true,
        targetPath: resolved,
      );
    }
  }

  Future<ToolExecutionResult> _replaceInFile(Map<String, dynamic> args) async {
    final rawPath = args['path']?.toString() ?? '';
    final oldText = args['old_text']?.toString() ?? '';
    final newText = args['new_text']?.toString() ?? '';
    final replaceAll = args['replace_all'] == true;
    final resolved = resolveSafePath(rawPath);

    if (resolved == null) {
      return ToolExecutionResult(
        output: 'Access denied: "$rawPath" is outside the project root.',
        isError: true,
      );
    }
    if (oldText.isEmpty) {
      return ToolExecutionResult(
        output: 'old_text must not be empty.',
        isError: true,
        targetPath: resolved,
      );
    }

    final file = File(resolved);
    if (!await file.exists()) {
      return ToolExecutionResult(
        output: 'File not found: $rawPath',
        isError: true,
        targetPath: resolved,
      );
    }

    try {
      final rawContent = await file.readAsString();
      final normalizedContent = rawContent.replaceAll('\r\n', '\n');
      final normalizedOld = oldText.replaceAll('\r\n', '\n');
      final matches = _countOccurrences(normalizedContent, normalizedOld);

      if (matches == 0) {
        return ToolExecutionResult(
          output:
              'Could not find exact old_text in $rawPath. Read the file again to verify exact whitespace and indentation.',
          isError: true,
          targetPath: resolved,
        );
      }
      if (!replaceAll && matches > 1) {
        return ToolExecutionResult(
          output:
              'old_text matched $matches occurrences in $rawPath. Provide more surrounding context lines to match uniquely, or set replace_all: true.',
          isError: true,
          targetPath: resolved,
        );
      }

      final checkpoint = FileCheckpoint(
        filePath: resolved,
        existedBefore: true,
        previousContent: rawContent,
      );

      final updated = replaceAll
          ? normalizedContent.replaceAll(normalizedOld, newText)
          : normalizedContent.replaceFirst(normalizedOld, newText);
      await file.writeAsString(updated);
      await onFileMutated?.call(resolved, deleted: false);

      final diff = computeLineDiff(normalizedContent, updated);
      final rel = p.relative(resolved, from: projectRoot);
      return ToolExecutionResult(
        output:
            'Applied edit to $rel (+${diff.addedCount} -${diff.removedCount} lines).',
        diffPreview: diff.unifiedPreview,
        addedLines: diff.addedCount,
        removedLines: diff.removedCount,
        targetPath: resolved,
        checkpoint: checkpoint,
      );
    } catch (e) {
      return ToolExecutionResult(
        output: 'Failed to edit $rawPath: $e',
        isError: true,
        targetPath: resolved,
      );
    }
  }

  Future<ToolExecutionResult> _deleteFile(Map<String, dynamic> args) async {
    final rawPath = args['path']?.toString() ?? '';
    final resolved = resolveSafePath(rawPath);
    if (resolved == null) {
      return ToolExecutionResult(
        output: 'Access denied: "$rawPath" is outside the project root.',
        isError: true,
      );
    }

    final file = File(resolved);
    if (!await file.exists()) {
      return ToolExecutionResult(
        output: 'File not found: $rawPath',
        isError: true,
        targetPath: resolved,
      );
    }

    try {
      final oldContent = await file.readAsString();
      final checkpoint = FileCheckpoint(
        filePath: resolved,
        existedBefore: true,
        previousContent: oldContent,
      );
      await file.delete();
      await onFileMutated?.call(resolved, deleted: true);

      final diff = computeLineDiff(oldContent, '');
      final rel = p.relative(resolved, from: projectRoot);
      return ToolExecutionResult(
        output: 'Deleted $rel (-${diff.removedCount} lines).',
        diffPreview: diff.unifiedPreview,
        addedLines: 0,
        removedLines: diff.removedCount,
        targetPath: resolved,
        checkpoint: checkpoint,
      );
    } catch (e) {
      return ToolExecutionResult(
        output: 'Failed to delete $rawPath: $e',
        isError: true,
        targetPath: resolved,
      );
    }
  }

  Future<ToolExecutionResult> _listDirectory(Map<String, dynamic> args) async {
    final rawPath = args['path']?.toString() ?? '.';
    final recursive = args['recursive'] == true;
    final resolved = resolveSafePath(rawPath);
    if (resolved == null) {
      return ToolExecutionResult(
        output: 'Access denied: "$rawPath" is outside the project root.',
        isError: true,
      );
    }

    final dir = Directory(resolved);
    if (!await dir.exists()) {
      return ToolExecutionResult(
        output: 'Directory not found: $rawPath',
        isError: true,
      );
    }

    final entries = <String>[];
    const maxEntries = 200;

    Future<void> walk(Directory current, int depth) async {
      if (entries.length >= maxEntries) return;
      final children = current.listSync()
        ..sort((a, b) {
          if (a is Directory && b is File) return -1;
          if (a is File && b is Directory) return 1;
          return a.path.toLowerCase().compareTo(b.path.toLowerCase());
        });

      for (final entity in children) {
        if (entries.length >= maxEntries) break;
        final name = p.basename(entity.path);
        if (_ignoredDirs.contains(name)) continue;

        final rel = p.relative(entity.path, from: projectRoot);
        if (entity is Directory) {
          entries.add('$rel/');
          if (recursive && depth < 3) {
            await walk(entity, depth + 1);
          }
        } else {
          entries.add(rel);
        }
      }
    }

    await walk(dir, 1);
    final header = entries.length >= maxEntries
        ? '${entries.join('\n')}\n... (truncated at $maxEntries entries)'
        : (entries.isEmpty ? '(empty directory)' : entries.join('\n'));
    return ToolExecutionResult(output: header, targetPath: resolved);
  }

  Future<ToolExecutionResult> _searchFiles(Map<String, dynamic> args) async {
    final query = args['query']?.toString() ?? '';
    if (query.isEmpty) {
      return const ToolExecutionResult(
        output: 'Search query cannot be empty.',
        isError: true,
      );
    }

    final rawPath = args['path']?.toString() ?? '.';
    final resolved = resolveSafePath(rawPath);
    if (resolved == null) {
      return ToolExecutionResult(
        output: 'Access denied: "$rawPath" is outside the project root.',
        isError: true,
      );
    }

    final isRegex = args['is_regex'] != false;
    final caseSensitive = args['case_sensitive'] == true;
    final extFilter = args['file_extension']?.toString().trim();

    RegExp? pattern;
    if (isRegex) {
      try {
        pattern = RegExp(query, caseSensitive: caseSensitive);
      } catch (e) {
        return ToolExecutionResult(
          output: 'Invalid regex "$query": $e',
          isError: true,
        );
      }
    }

    final matches = <String>[];
    const maxMatches = 100;
    final needle = caseSensitive ? query : query.toLowerCase();

    final targetEntityType = FileSystemEntity.typeSync(resolved);
    final files = <File>[];
    if (targetEntityType == FileSystemEntityType.file) {
      files.add(File(resolved));
    } else if (targetEntityType == FileSystemEntityType.directory) {
      await _collectWorkspaceFiles(Directory(resolved), files, maxFiles: 2000);
    } else {
      return ToolExecutionResult(
        output: 'Path not found: $rawPath',
        isError: true,
      );
    }

    for (final file in files) {
      if (matches.length >= maxMatches) break;
      if (extFilter != null && extFilter.isNotEmpty) {
        final normalizedExt = extFilter.startsWith('.') ? extFilter : '.$extFilter';
        if (!file.path.endsWith(normalizedExt)) continue;
      }

      try {
        final bytes = await file.readAsBytes();
        if (_looksBinary(bytes)) continue;
        final lines = utf8.decode(bytes, allowMalformed: true).split('\n');
        final rel = p.relative(file.path, from: projectRoot);

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          final hit = pattern != null
              ? pattern.hasMatch(line)
              : (caseSensitive
                  ? line.contains(needle)
                  : line.toLowerCase().contains(needle));
          if (hit) {
            final clipped =
                line.length > 240 ? '${line.substring(0, 240)}...' : line;
            matches.add('$rel:${i + 1}: $clipped');
            if (matches.length >= maxMatches) break;
          }
        }
      } catch (_) {}
    }

    if (matches.isEmpty) {
      return ToolExecutionResult(output: 'No matches found for "$query".');
    }
    final suffix = matches.length >= maxMatches
        ? '\n... (showing first $maxMatches matches)'
        : '';
    return ToolExecutionResult(output: '${matches.join('\n')}$suffix');
  }

  Future<ToolExecutionResult> _findFiles(Map<String, dynamic> args) async {
    final rawPattern = args['pattern']?.toString().trim() ?? '';
    final rawPath = args['path']?.toString() ?? '.';
    final resolved = resolveSafePath(rawPath);
    if (resolved == null) {
      return ToolExecutionResult(
        output: 'Access denied: "$rawPath" is outside the project root.',
        isError: true,
      );
    }

    final dir = Directory(resolved);
    if (!await dir.exists()) {
      return ToolExecutionResult(
        output: 'Directory not found: $rawPath',
        isError: true,
      );
    }

    final files = <File>[];
    await _collectWorkspaceFiles(dir, files, maxFiles: 3000);

    final globRegex = _globToRegex(rawPattern);
    final lowerPattern = rawPattern.toLowerCase();
    final matched = <String>[];

    for (final file in files) {
      final rel = p.relative(file.path, from: projectRoot);
      final isMatch = globRegex != null
          ? (globRegex.hasMatch(rel) || globRegex.hasMatch(p.basename(rel)))
          : rel.toLowerCase().contains(lowerPattern);
      if (isMatch) {
        matched.add(rel);
        if (matched.length >= 150) break;
      }
    }

    if (matched.isEmpty) {
      return ToolExecutionResult(
        output: 'No files matching "$rawPattern".',
      );
    }
    return ToolExecutionResult(output: matched.join('\n'));
  }

  Future<ToolExecutionResult> _runCommand(
    Map<String, dynamic> args, {
    CancellationToken? cancelToken,
  }) async {
    final command = args['command']?.toString().trim() ?? '';
    if (command.isEmpty) {
      return const ToolExecutionResult(
        output: 'Command cannot be empty.',
        isError: true,
      );
    }

    final rawDir = args['working_directory']?.toString() ?? '.';
    final cwd = resolveSafePath(rawDir);
    if (cwd == null) {
      return ToolExecutionResult(
        output: 'Access denied: working_directory "$rawDir" is outside project root.',
        isError: true,
      );
    }

    final timeoutSec =
        ((args['timeout_seconds'] as num?)?.toInt() ?? 60).clamp(5, 300);

    Process? proc;
    try {
      proc = Platform.isWindows
          ? await Process.start('cmd', ['/c', command], workingDirectory: cwd)
          : await Process.start('/bin/sh', ['-c', command], workingDirectory: cwd);

      var killed = false;
      cancelToken?.onCancel(() {
        killed = true;
        try {
          proc?.kill(ProcessSignal.sigterm);
        } catch (_) {}
      });

      final stdoutBuf = StringBuffer();
      final stderrBuf = StringBuffer();
      final stdoutDone = proc.stdout
          .transform(utf8.decoder)
          .listen(stdoutBuf.write)
          .asFuture<void>();
      final stderrDone = proc.stderr
          .transform(utf8.decoder)
          .listen(stderrBuf.write)
          .asFuture<void>();

      final exitCode = await proc.exitCode.timeout(
        Duration(seconds: timeoutSec),
        onTimeout: () {
          proc?.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      await Future.wait([stdoutDone, stderrDone]);

      if (killed) {
        return const ToolExecutionResult(
          output: 'Command cancelled by user.',
          isError: true,
        );
      }

      var combined = '';
      if (stdoutBuf.isNotEmpty) {
        combined += stdoutBuf.toString().trimRight();
      }
      if (stderrBuf.isNotEmpty) {
        if (combined.isNotEmpty) combined += '\n';
        combined += '[stderr]\n${stderrBuf.toString().trimRight()}';
      }
      if (combined.length > 16000) {
        combined =
            '${combined.substring(0, 8000)}\n... (output truncated) ...\n${combined.substring(combined.length - 6000)}';
      }

      final header = 'Exit code: $exitCode';
      return ToolExecutionResult(
        output: combined.isEmpty ? header : '$header\n$combined',
        isError: exitCode != 0,
      );
    } catch (e) {
      proc?.kill();
      return ToolExecutionResult(
        output: 'Failed to execute command: $e',
        isError: true,
      );
    }
  }

  Future<ToolExecutionResult> _getDiagnostics(Map<String, dynamic> args) async {
    final filterPath = args['path']?.toString().trim();
    String? resolvedFilter;
    if (filterPath != null && filterPath.isNotEmpty) {
      resolvedFilter = resolveSafePath(filterPath);
      if (resolvedFilter == null) {
        return ToolExecutionResult(
          output: 'Access denied: "$filterPath" is outside project root.',
          isError: true,
        );
      }
    }

    final diagMap = diagnosticsProvider?.call() ?? const {};
    final lines = <String>[];

    for (final entry in diagMap.entries) {
      if (resolvedFilter != null && entry.key != resolvedFilter) continue;
      final rel = p.relative(entry.key, from: projectRoot);
      for (final d in entry.value) {
        if (d is Map) {
          final range = d['range'] as Map?;
          final start = range?['start'] as Map?;
          final lineNum = ((start?['line'] as int?) ?? 0) + 1;
          final colNum = ((start?['character'] as int?) ?? 0) + 1;
          final sevCode = (d['severity'] as int?) ?? 1;
          final sev = switch (sevCode) {
            1 => 'ERROR',
            2 => 'WARNING',
            3 => 'INFO',
            _ => 'HINT',
          };
          final msg = d['message']?.toString() ?? '';
          lines.add('$rel:$lineNum:$colNum [$sev] $msg');
        }
      }
    }

    if (lines.isNotEmpty) {
      return ToolExecutionResult(output: lines.join('\n'));
    }

    // Fallback to `dart analyze` if this is a Dart/Flutter workspace and no live
    // diagnostics are populated in open tabs.
    if (File(p.join(projectRoot, 'pubspec.yaml')).existsSync()) {
      final target = resolvedFilter ?? '.';
      final res = await Process.run(
        'dart',
        ['analyze', target],
        workingDirectory: projectRoot,
      );
      final out = '${res.stdout}\n${res.stderr}'.trim();
      return ToolExecutionResult(
        output: out.isEmpty ? 'No diagnostics found.' : out,
      );
    }

    return const ToolExecutionResult(
      output: 'No active LSP diagnostics found.',
    );
  }

  /// Collects relative file paths in the workspace for `@` mention autocomplete.
  Future<List<String>> listWorkspaceFiles({int maxFiles = 1500}) async {
    final files = <File>[];
    final root = Directory(projectRoot);
    if (!await root.exists()) return const [];
    await _collectWorkspaceFiles(root, files, maxFiles: maxFiles);
    return files
        .map((f) => p.relative(f.path, from: projectRoot))
        .toList()
      ..sort();
  }

  Future<void> _collectWorkspaceFiles(
    Directory dir,
    List<File> out, {
    int maxFiles = 2000,
  }) async {
    if (out.length >= maxFiles) return;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (out.length >= maxFiles) break;
        final name = p.basename(entity.path);
        if (name.startsWith('.') && name != '.env.example') {
          if (entity is Directory || _ignoredDirs.contains(name)) continue;
        }
        if (entity is Directory) {
          if (_ignoredDirs.contains(name)) continue;
          await _collectWorkspaceFiles(entity, out, maxFiles: maxFiles);
        } else if (entity is File) {
          out.add(entity);
        }
      }
    } catch (_) {}
  }

  static bool _looksBinary(List<int> bytes) {
    final checkLen = bytes.length < 512 ? bytes.length : 512;
    for (var i = 0; i < checkLen; i++) {
      if (bytes[i] == 0) return true;
    }
    return false;
  }

  static int _countOccurrences(String text, String pattern) {
    var count = 0;
    var index = 0;
    while (true) {
      index = text.indexOf(pattern, index);
      if (index == -1) break;
      count++;
      index += pattern.length;
    }
    return count;
  }

  static RegExp? _globToRegex(String pattern) {
    if (!pattern.contains('*') && !pattern.contains('?')) return null;
    final escaped = RegExp.escape(pattern)
        .replaceAll(r'\*\*', '.*')
        .replaceAll(r'\*', '[^/]*')
        .replaceAll(r'\?', '.');
    return RegExp('^$escaped\$', caseSensitive: false);
  }
}
