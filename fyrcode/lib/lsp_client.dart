import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:json_rpc_2/json_rpc_2.dart' as json_rpc;
import 'package:stream_channel/stream_channel.dart';
import 'fyr_theme.dart';

class LspClient {
  Process? _process;
  json_rpc.Peer? _peer;
  bool _isInitialized = false;

  final void Function(String uri, List<dynamic> diagnostics)? onDiagnostics;

  LspClient({this.onDiagnostics});

  Future<void> start(String projectRoot) async {
    _process = await Process.start('dart', [
      'language-server',
      '--protocol=lsp',
    ], workingDirectory: projectRoot);
    print('test');
    _peer = json_rpc.Peer(
      StreamChannel(
        // Read raw bytes instead of Strings to prevent multi-byte characters
        // from splitting incorrectly across chunks or corrupting content-length.
        _process!.stdout.transform(const _LspByteTransformer()),
        StreamController<String>()
          ..stream.listen((data) {
            // Write exact UTF-8 bytes to bypass platform specific \r\n newline translations
            final encodedData = utf8.encode(data);
            final header = utf8.encode(
              'Content-Length: ${encodedData.length}\r\n\r\n',
            );
            _process!.stdin.add(header);
            _process!.stdin.add(encodedData);
          }),
      ),
    );

    _peer!.registerMethod('textDocument/publishDiagnostics', (
      json_rpc.Parameters params,
    ) {
      final uri = params.value['uri'] as String;
      final diagnostics = params.value['diagnostics'] as List<dynamic>;
      if (onDiagnostics != null) {
        onDiagnostics!(uri, diagnostics);
      }
    });

    _peer!.registerMethod('workspace/applyEdit', (json_rpc.Parameters params) {
      // For now we just return true to satisfy the server,
      // but in a real app we should apply the edits to the controller.
      // The actual applying logic will be handled via a callback if needed.
      return {'applied': true};
    });

    _peer!.listen();
    final initResult = await _peer!.sendRequest('initialize', {
      'processId': pid,
      'rootUri': Uri.directory(projectRoot).toString(),
      'capabilities': {
        'workspace': {
          'applyEdit': true,
          'executeCommand': {'dynamicRegistration': true},
          'workspaceEdit': {'documentChanges': true},
        },
        'textDocument': {
          'hover': {'dynamicRegistration': true},
          'codeAction': {
            'dynamicRegistration': true,
            'codeActionLiteralSupport': {
              'codeActionKind': {
                'valueSet': [
                  'quickfix',
                  'refactor',
                  'refactor.extract',
                  'refactor.inline',
                  'refactor.rewrite',
                  'source',
                  'source.organizeImports',
                ],
              },
            },
          },
          'definition': {'dynamicRegistration': true},
          'completion': {
            'dynamicRegistration': true,
            'completionItem': {
              'snippetSupport': true,
              'documentationFormat': ['markdown', 'plaintext'],
              'labelDetailsSupport': true,
              'resolveSupport': {
                'properties': ['documentation', 'detail', 'additionalTextEdits']
              },
            },
            'completionItemKind': {
              'valueSet': [
                1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25
              ]
            },
          },
          'synchronization': {
            'dynamicRegistration': true,
            'willSave': true,
            'willSaveWaitUntil': true,
            'didSave': true,
          },
        },
      },
      'trace': 'off',
    });

    _isInitialized = true;
    _peer!.sendNotification('initialized', {});
  }

  Future<Map<String, dynamic>?> hover(
    String filePath,
    int line,
    int character,
  ) async {
    if (!_isInitialized || _peer == null || _peer!.isClosed) return null;
    try {
      final result = await _peer!.sendRequest('textDocument/hover', {
        'textDocument': {'uri': Uri.file(filePath).toString()},
        'position': {'line': line, 'character': character},
      });
      return result as Map<String, dynamic>?;
    } catch (e) {
      return null;
    }
  }

  Future<List<dynamic>?> getCodeActions(
    String filePath,
    int startLine,
    int startCharacter,
    int endLine,
    int endCharacter, {
    List<dynamic>? diagnostics,
  }) async {
    if (!_isInitialized || _peer == null || _peer!.isClosed) return null;
    try {
      final result = await _peer!.sendRequest('textDocument/codeAction', {
        'textDocument': {'uri': Uri.file(filePath).toString()},
        'range': {
          'start': {'line': startLine, 'character': startCharacter},
          'end': {'line': endLine, 'character': endCharacter},
        },
        'context': {'diagnostics': diagnostics ?? []},
      });
      return result as List<dynamic>?;
    } catch (e) {
      debugPrint('LSP CodeAction Error: $e');
      return null;
    }
  }

  Future<dynamic> executeCommand(
    String command,
    List<dynamic> arguments,
  ) async {
    if (!_isInitialized || _peer == null || _peer!.isClosed) return null;
    try {
      return await _peer!.sendRequest('workspace/executeCommand', {
        'command': command,
        'arguments': arguments,
      });
    } catch (e) {
      return null;
    }
  }

  Future<dynamic> getDefinition(
    String filePath,
    int line,
    int character,
  ) async {
    if (!_isInitialized || _peer == null || _peer!.isClosed) return null;
    try {
      final result = await _peer!.sendRequest('textDocument/definition', {
        'textDocument': {'uri': Uri.file(filePath).toString()},
        'position': {'line': line, 'character': character},
      });
      return result;
    } catch (e) {
      return null;
    }
  }

  // In lib/lsp_client.dart
  Future<dynamic> getCompletions(
    String filePath,
    int line,
    int character, {
    String? triggerCharacter,
  }) async {
    if (!_isInitialized || _peer == null || _peer!.isClosed) return null;

    try {
      final params = <String, dynamic>{
        'textDocument': {'uri': Uri.file(filePath).toString()},
        'position': {'line': line, 'character': character},
      };

      params['context'] = {
        'triggerKind': triggerCharacter != null ? 2 : 1,
        if (triggerCharacter != null) 'triggerCharacter': triggerCharacter,
      };

      // Return raw result to parse Map vs List on the editor side
      return await _peer!.sendRequest('textDocument/completion', params);
    } catch (e) {
      return null;
    }
  }

  Future<dynamic> resolveCompletionItem(dynamic item) async {
    if (!_isInitialized || _peer == null || _peer!.isClosed) return item;
    try {
      return await _peer!.sendRequest('completionItem/resolve', item);
    } catch (e) {
      return item;
    }
  }

  void notifyFileOpened(String filePath, String content) {
    if (!_isInitialized || _peer == null || _peer!.isClosed) return;
    try {
      _peer!.sendNotification('textDocument/didOpen', {
        'textDocument': {
          'uri': Uri.file(filePath).toString(),
          'languageId': 'dart',
          'version': 1,
          'text': content,
        },
      });
    } catch (_) {}
  }

  void notifyDidChange(String filePath, String content, int version) {
    if (!_isInitialized || _peer == null || _peer!.isClosed) return;
    try {
      _peer!.sendNotification('textDocument/didChange', {
        'textDocument': {
          'uri': Uri.file(filePath).toString(),
          'version': version,
        },
        'contentChanges': [
          {'text': content},
        ],
      });
    } catch (_) {}
  }

  void notifyDidSave(String filePath) {
    if (!_isInitialized || _peer == null || _peer!.isClosed) return;
    try {
      _peer!.sendNotification('textDocument/didSave', {
        'textDocument': {'uri': Uri.file(filePath).toString()},
      });
    } catch (_) {}
  }

  void dispose() {
    _peer?.close();
    _process?.kill();
  }
}

// A rock-solid byte-level transformer that correctly handles
// UTF-8 lengths and prevents dropped chunks that crash the parser.
class _LspByteTransformer extends StreamTransformerBase<List<int>, String> {
  const _LspByteTransformer();

  @override
  Stream<String> bind(Stream<List<int>> stream) {
    late StreamController<String> controller;
    controller = StreamController<String>(
      onListen: () {
        List<int> buffer = [];
        stream.listen(
          (data) {
            buffer.addAll(data);
            while (true) {
              int headerEnd = -1;
              for (int i = 0; i < buffer.length - 3; i++) {
                if (buffer[i] == 13 &&
                    buffer[i + 1] == 10 &&
                    buffer[i + 2] == 13 &&
                    buffer[i + 3] == 10) {
                  headerEnd = i;
                  break;
                }
              }
              if (headerEnd == -1) break;

              final headerStr = utf8.decode(buffer.sublist(0, headerEnd));
              final contentLengthMatch = RegExp(
                r'Content-Length:\s*(\d+)',
              ).firstMatch(headerStr);

              if (contentLengthMatch == null) {
                buffer = buffer.sublist(headerEnd + 4);
                continue;
              }

              final contentLength = int.parse(contentLengthMatch.group(1)!);
              final messageStart = headerEnd + 4;

              // Ensure we have exact bytes required
              if (buffer.length < messageStart + contentLength) break;

              final messageBytes = buffer.sublist(
                messageStart,
                messageStart + contentLength,
              );
              final message = utf8.decode(messageBytes);

              buffer = buffer.sublist(messageStart + contentLength);
              controller.add(message);
            }
          },
          onError: (e) => controller.addError(e),
          onDone: () => controller.close(),
        );
      },
    );
    return controller.stream;
  }
}
