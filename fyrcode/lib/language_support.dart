import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:re_highlight/languages/all.dart';
import 'package:re_highlight/re_highlight.dart';

import 'lsp_client.dart';

/// Command candidate for starting an LSP server for a language.
class LspServerCandidate {
  final String executable;
  final List<String> args;

  const LspServerCandidate(this.executable, [this.args = const []]);
}

/// Metadata and tooling configuration for a programming/markup language.
class LanguageSpec {
  final String id;
  final String displayName;
  final String highlightKey;
  final String lineCommentPrefix;
  final List<LspServerCandidate> lspCandidates;
  final List<String>? cliFormatter;

  const LanguageSpec({
    required this.id,
    required this.displayName,
    required this.highlightKey,
    this.lineCommentPrefix = '//',
    this.lspCandidates = const [],
    this.cliFormatter,
  });

  Mode? get highlightMode => builtinAllLanguages[highlightKey];
  bool get hasLsp => lspCandidates.isNotEmpty;
}

/// Resolves language specs, syntax highlight modes, and `$PATH` LSP binaries.
class LanguageRegistry {
  static const LanguageSpec plainText = LanguageSpec(
    id: 'plaintext',
    displayName: 'Plain Text',
    highlightKey: 'plaintext',
    lineCommentPrefix: '#',
  );

  static const Map<String, LanguageSpec> _byLanguageId = {
    'dart': LanguageSpec(
      id: 'dart',
      displayName: 'Dart',
      highlightKey: 'dart',
      lineCommentPrefix: '//',
      lspCandidates: [
        LspServerCandidate('dart', ['language-server', '--protocol=lsp']),
      ],
      cliFormatter: ['dart', 'format'],
    ),
    'go': LanguageSpec(
      id: 'go',
      displayName: 'Go',
      highlightKey: 'go',
      lineCommentPrefix: '//',
      lspCandidates: [
        LspServerCandidate('gopls', ['serve']),
      ],
      cliFormatter: ['gofmt', '-w'],
    ),
    'python': LanguageSpec(
      id: 'python',
      displayName: 'Python',
      highlightKey: 'python',
      lineCommentPrefix: '#',
      lspCandidates: [
        LspServerCandidate('pyright-langserver', ['--stdio']),
        LspServerCandidate('basedpyright-langserver', ['--stdio']),
        LspServerCandidate('pylsp'),
        LspServerCandidate('ruff', ['server']),
      ],
      cliFormatter: ['ruff', 'format'],
    ),
    'rust': LanguageSpec(
      id: 'rust',
      displayName: 'Rust',
      highlightKey: 'rust',
      lineCommentPrefix: '//',
      lspCandidates: [LspServerCandidate('rust-analyzer')],
      cliFormatter: ['rustfmt'],
    ),
    'typescript': LanguageSpec(
      id: 'typescript',
      displayName: 'TypeScript',
      highlightKey: 'typescript',
      lineCommentPrefix: '//',
      lspCandidates: [
        LspServerCandidate('typescript-language-server', ['--stdio']),
      ],
    ),
    'javascript': LanguageSpec(
      id: 'javascript',
      displayName: 'JavaScript',
      highlightKey: 'javascript',
      lineCommentPrefix: '//',
      lspCandidates: [
        LspServerCandidate('typescript-language-server', ['--stdio']),
      ],
    ),
    'c': LanguageSpec(
      id: 'c',
      displayName: 'C',
      highlightKey: 'c',
      lineCommentPrefix: '//',
      lspCandidates: [LspServerCandidate('clangd')],
    ),
    'cpp': LanguageSpec(
      id: 'cpp',
      displayName: 'C++',
      highlightKey: 'cpp',
      lineCommentPrefix: '//',
      lspCandidates: [LspServerCandidate('clangd')],
    ),
    'csharp': LanguageSpec(
      id: 'csharp',
      displayName: 'C#',
      highlightKey: 'csharp',
      lineCommentPrefix: '//',
      lspCandidates: [LspServerCandidate('omnisharp', ['-lsp'])],
    ),
    'java': LanguageSpec(
      id: 'java',
      displayName: 'Java',
      highlightKey: 'java',
      lineCommentPrefix: '//',
      lspCandidates: [LspServerCandidate('jdtls')],
    ),
    'kotlin': LanguageSpec(
      id: 'kotlin',
      displayName: 'Kotlin',
      highlightKey: 'kotlin',
      lineCommentPrefix: '//',
      lspCandidates: [LspServerCandidate('kotlin-language-server')],
    ),
    'swift': LanguageSpec(
      id: 'swift',
      displayName: 'Swift',
      highlightKey: 'swift',
      lineCommentPrefix: '//',
      lspCandidates: [LspServerCandidate('sourcekit-lsp')],
    ),
    'ruby': LanguageSpec(
      id: 'ruby',
      displayName: 'Ruby',
      highlightKey: 'ruby',
      lineCommentPrefix: '#',
      lspCandidates: [LspServerCandidate('solargraph', ['stdio'])],
    ),
    'php': LanguageSpec(
      id: 'php',
      displayName: 'PHP',
      highlightKey: 'php',
      lineCommentPrefix: '//',
      lspCandidates: [LspServerCandidate('intelephense', ['--stdio'])],
    ),
    'bash': LanguageSpec(
      id: 'bash',
      displayName: 'Shell',
      highlightKey: 'bash',
      lineCommentPrefix: '#',
      lspCandidates: [
        LspServerCandidate('bash-language-server', ['start']),
      ],
    ),
    'json': LanguageSpec(
      id: 'json',
      displayName: 'JSON',
      highlightKey: 'json',
      lineCommentPrefix: '//',
      lspCandidates: [
        LspServerCandidate('vscode-json-language-server', ['--stdio']),
      ],
    ),
    'yaml': LanguageSpec(
      id: 'yaml',
      displayName: 'YAML',
      highlightKey: 'yaml',
      lineCommentPrefix: '#',
      lspCandidates: [
        LspServerCandidate('yaml-language-server', ['--stdio']),
      ],
    ),
    'toml': LanguageSpec(
      id: 'toml',
      displayName: 'TOML',
      highlightKey: 'ini',
      lineCommentPrefix: '#',
      lspCandidates: [LspServerCandidate('taplo', ['lsp', 'stdio'])],
    ),
    'ini': LanguageSpec(
      id: 'ini',
      displayName: 'INI / Conf',
      highlightKey: 'ini',
      lineCommentPrefix: '#',
    ),
    'markdown': LanguageSpec(
      id: 'markdown',
      displayName: 'Markdown',
      highlightKey: 'markdown',
      lineCommentPrefix: '<!--',
      lspCandidates: [LspServerCandidate('marksman', ['server'])],
    ),
    'html': LanguageSpec(
      id: 'html',
      displayName: 'HTML',
      highlightKey: 'xml',
      lineCommentPrefix: '<!--',
      lspCandidates: [
        LspServerCandidate('vscode-html-language-server', ['--stdio']),
      ],
    ),
    'xml': LanguageSpec(
      id: 'xml',
      displayName: 'XML',
      highlightKey: 'xml',
      lineCommentPrefix: '<!--',
    ),
    'css': LanguageSpec(
      id: 'css',
      displayName: 'CSS',
      highlightKey: 'css',
      lineCommentPrefix: '/*',
      lspCandidates: [
        LspServerCandidate('vscode-css-language-server', ['--stdio']),
      ],
    ),
    'scss': LanguageSpec(
      id: 'scss',
      displayName: 'SCSS',
      highlightKey: 'scss',
      lineCommentPrefix: '//',
      lspCandidates: [
        LspServerCandidate('vscode-css-language-server', ['--stdio']),
      ],
    ),
    'sql': LanguageSpec(
      id: 'sql',
      displayName: 'SQL',
      highlightKey: 'sql',
      lineCommentPrefix: '--',
    ),
    'lua': LanguageSpec(
      id: 'lua',
      displayName: 'Lua',
      highlightKey: 'lua',
      lineCommentPrefix: '--',
      lspCandidates: [LspServerCandidate('lua-language-server')],
    ),
    'dockerfile': LanguageSpec(
      id: 'dockerfile',
      displayName: 'Dockerfile',
      highlightKey: 'dockerfile',
      lineCommentPrefix: '#',
      lspCandidates: [LspServerCandidate('docker-langserver', ['--stdio'])],
    ),
    'makefile': LanguageSpec(
      id: 'makefile',
      displayName: 'Makefile',
      highlightKey: 'makefile',
      lineCommentPrefix: '#',
    ),
    'cmake': LanguageSpec(
      id: 'cmake',
      displayName: 'CMake',
      highlightKey: 'cmake',
      lineCommentPrefix: '#',
    ),
    'nix': LanguageSpec(
      id: 'nix',
      displayName: 'Nix',
      highlightKey: 'nix',
      lineCommentPrefix: '#',
      lspCandidates: [LspServerCandidate('nil')],
    ),
    'haskell': LanguageSpec(
      id: 'haskell',
      displayName: 'Haskell',
      highlightKey: 'haskell',
      lineCommentPrefix: '--',
      lspCandidates: [LspServerCandidate('haskell-language-server-wrapper', ['--lsp'])],
    ),
    'elixir': LanguageSpec(
      id: 'elixir',
      displayName: 'Elixir',
      highlightKey: 'elixir',
      lineCommentPrefix: '#',
    ),
    'vue': LanguageSpec(
      id: 'vue',
      displayName: 'Vue',
      highlightKey: 'xml',
      lineCommentPrefix: '//',
    ),
    'protobuf': LanguageSpec(
      id: 'protobuf',
      displayName: 'Protobuf',
      highlightKey: 'protobuf',
      lineCommentPrefix: '//',
    ),
    'graphql': LanguageSpec(
      id: 'graphql',
      displayName: 'GraphQL',
      highlightKey: 'graphql',
      lineCommentPrefix: '#',
    ),
  };

  static const Map<String, String> _extToId = {
    '.dart': 'dart',
    '.go': 'go',
    '.py': 'python',
    '.pyi': 'python',
    '.rs': 'rust',
    '.ts': 'typescript',
    '.tsx': 'typescript',
    '.mts': 'typescript',
    '.cts': 'typescript',
    '.js': 'javascript',
    '.jsx': 'javascript',
    '.mjs': 'javascript',
    '.cjs': 'javascript',
    '.c': 'c',
    '.h': 'c',
    '.cpp': 'cpp',
    '.cc': 'cpp',
    '.cxx': 'cpp',
    '.hpp': 'cpp',
    '.hh': 'cpp',
    '.cs': 'csharp',
    '.java': 'java',
    '.kt': 'kotlin',
    '.kts': 'kotlin',
    '.swift': 'swift',
    '.rb': 'ruby',
    '.php': 'php',
    '.sh': 'bash',
    '.bash': 'bash',
    '.zsh': 'bash',
    '.json': 'json',
    '.jsonc': 'json',
    '.arb': 'json',
    '.yaml': 'yaml',
    '.yml': 'yaml',
    '.toml': 'toml',
    '.ini': 'ini',
    '.conf': 'ini',
    '.cfg': 'ini',
    '.env': 'ini',
    '.md': 'markdown',
    '.markdown': 'markdown',
    '.html': 'html',
    '.htm': 'html',
    '.xml': 'xml',
    '.svg': 'xml',
    '.plist': 'xml',
    '.css': 'css',
    '.scss': 'scss',
    '.sql': 'sql',
    '.lua': 'lua',
    '.dockerfile': 'dockerfile',
    '.cmake': 'cmake',
    '.nix': 'nix',
    '.hs': 'haskell',
    '.ex': 'elixir',
    '.exs': 'elixir',
    '.vue': 'vue',
    '.proto': 'protobuf',
    '.graphql': 'graphql',
    '.gql': 'graphql',
  };

  static const Map<String, String> _filenameToId = {
    'dockerfile': 'dockerfile',
    'makefile': 'makefile',
    'gnumakefile': 'makefile',
    'cmakelists.txt': 'cmake',
    '.bashrc': 'bash',
    '.zshrc': 'bash',
    '.profile': 'bash',
    '.gitignore': 'ini',
    '.fyrcoderules': 'markdown',
  };

  /// Detects language metadata from a file path or filename.
  static LanguageSpec detect(String filePath) {
    final base = p.basename(filePath).toLowerCase();
    final byName = _filenameToId[base];
    if (byName != null) {
      return _byLanguageId[byName] ?? plainText;
    }

    final ext = p.extension(base);
    final byExt = _extToId[ext];
    if (byExt != null) {
      return _byLanguageId[byExt] ?? plainText;
    }

    // Fallback: check re_highlight directly by extension name without leading dot.
    if (ext.length > 1) {
      final raw = ext.substring(1);
      if (builtinAllLanguages.containsKey(raw)) {
        return LanguageSpec(
          id: raw,
          displayName: raw.toUpperCase(),
          highlightKey: raw,
        );
      }
    }

    return plainText;
  }

  /// Resolves an executable on `$PATH` and standard user developer directories.
  static Future<String?> findExecutable(String executable) async {
    if (executable.contains(Platform.pathSeparator)) {
      return File(executable).existsSync() ? executable : null;
    }

    final home = Platform.environment['HOME'] ?? '';
    final pathEnv = Platform.environment['PATH'] ?? '';
    final searchDirs = <String>[
      ...pathEnv.split(Platform.isWindows ? ';' : ':').where((s) => s.isNotEmpty),
      if (home.isNotEmpty) ...[
        p.join(home, '.local', 'bin'),
        p.join(home, '.cargo', 'bin'),
        p.join(home, 'go', 'bin'),
        p.join(home, '.pub-cache', 'bin'),
        '/usr/local/bin',
        '/usr/bin',
      ],
    ];

    for (final dir in searchDirs) {
      final candidate = p.join(dir, executable);
      if (File(candidate).existsSync()) {
        return candidate;
      }
      if (Platform.isWindows && File('$candidate.exe').existsSync()) {
        return '$candidate.exe';
      }
    }
    return null;
  }
}

/// Manages shared, workspace-scoped LSP client instances across tabs so
/// opening multiple files of the same language reuses a single language server.
class LspSessionManager {
  static final LspSessionManager instance = LspSessionManager._();
  LspSessionManager._();

  final Map<String, LspClient> _clients = {};
  final Map<String, Future<LspClient?>> _pendingStarts = {};
  final Map<String, List<dynamic>> _diagnosticsByUri = {};
  final StreamController<({String filePath, List<dynamic> diagnostics})>
      _diagnosticsController = StreamController.broadcast();

  Stream<({String filePath, List<dynamic> diagnostics})>
      get diagnosticsStream => _diagnosticsController.stream;

  List<dynamic> diagnosticsForFile(String filePath) {
    return _diagnosticsByUri[Uri.file(filePath).toString()] ?? const [];
  }

  Future<LspClient?> getOrStartClient({
    required String projectRoot,
    required LanguageSpec language,
    Map<String, LspServerCandidate>? overrides,
  }) async {
    if (language.lspCandidates.isEmpty &&
        !(overrides?.containsKey(language.id) ?? false)) {
      return null;
    }

    final key = '$projectRoot::${language.id}';
    final existing = _clients[key];
    if (existing != null && !existing.isDisposed) {
      return existing;
    }

    if (_pendingStarts.containsKey(key)) {
      return _pendingStarts[key];
    }

    final starter = _startClient(key, projectRoot, language, overrides);
    _pendingStarts[key] = starter;
    try {
      return await starter;
    } finally {
      _pendingStarts.remove(key);
    }
  }

  Future<LspClient?> _startClient(
    String key,
    String projectRoot,
    LanguageSpec language,
    Map<String, LspServerCandidate>? overrides,
  ) async {
    final candidates = <LspServerCandidate>[
      if (overrides != null && overrides.containsKey(language.id))
        overrides[language.id]!,
      ...language.lspCandidates,
    ];

    for (final candidate in candidates) {
      final binPath = await LanguageRegistry.findExecutable(
        candidate.executable,
      );
      if (binPath == null) continue;

      final client = LspClient(
        onDiagnostics: (uri, diagnostics) {
          _diagnosticsByUri[uri] = diagnostics;
          try {
            final filePath = Uri.parse(uri).toFilePath();
            _diagnosticsController.add((
              filePath: filePath,
              diagnostics: diagnostics,
            ));
          } catch (_) {}
        },
      );

      try {
        await client.start(
          projectRoot,
          command: binPath,
          args: candidate.args,
        );
        _clients[key] = client;
        return client;
      } catch (_) {
        client.dispose();
      }
    }

    return null;
  }

  void disposeWorkspace(String projectRoot) {
    final prefix = '$projectRoot::';
    final keys = _clients.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      _clients.remove(k)?.dispose();
    }
  }

  void disposeAll() {
    for (final client in _clients.values) {
      client.dispose();
    }
    _clients.clear();
  }
}
