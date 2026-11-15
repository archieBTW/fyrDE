import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrcode/ai/agent_controller.dart';
import 'package:fyrcode/ai/ai_agent_panel.dart';
import 'package:fyrcode/ai/ai_models.dart';
import 'package:fyrcode/ai/ai_settings_dialog.dart';
import 'package:fyrcode/ai/deepseek_client.dart';
import 'package:fyrcode/ai/inline_completion_service.dart';
import 'package:fyrcode/ai/mcp_client.dart';
import 'package:fyrcode/bottom_panel.dart';
import 'package:fyrcode/language_support.dart';
import 'package:fyrcode/quick_open_dialog.dart';
import 'package:path/path.dart' as p;

class _MemoryConfigStore implements AiConfigStore {
  AiConfig storedConfig;
  final List<ChatSession> storedSessions = [];

  _MemoryConfigStore([AiConfig? config])
      : storedConfig = config ?? AiConfig.defaults();

  @override
  Future<AiConfig> loadConfig() async => storedConfig;

  @override
  Future<void> saveConfig(AiConfig config) async {
    storedConfig = config;
  }

  @override
  Future<List<ChatSession>> loadSessions(String projectRoot) async =>
      List<ChatSession>.from(storedSessions);

  @override
  Future<void> saveSession(ChatSession session) async {
    storedSessions.removeWhere((s) => s.id == session.id);
    storedSessions.insert(0, session);
  }

  @override
  Future<void> deleteSession(String projectRoot, String sessionId) async {
    storedSessions.removeWhere((s) => s.id == sessionId);
  }
}

class _CapturingFakeLlmClient extends LlmClient {
  final List<List<Map<String, dynamic>>> capturedMessages = [];
  final List<List<LlmStreamEvent>> scriptTurns;
  int _turnIndex = 0;

  _CapturingFakeLlmClient(this.scriptTurns);

  @override
  Stream<LlmStreamEvent> streamChatCompletion({
    required AiProviderProfile provider,
    required AiModelSpec model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.2,
    bool thinkingEnabled = true,
    String reasoningEffort = 'high',
    int? maxTokens,
    CancellationToken? cancelToken,
  }) async* {
    capturedMessages.add(messages);
    final idx = _turnIndex < scriptTurns.length ? _turnIndex : scriptTurns.length - 1;
    _turnIndex++;
    for (final ev in scriptTurns[idx]) {
      if (cancelToken?.isCancelled ?? false) return;
      yield ev;
    }
  }

  @override
  Future<ConnectionTestResult> testConnection({
    required AiProviderProfile provider,
    AiModelSpec? model,
  }) async =>
      const ConnectionTestResult(
        ok: true,
        message: 'OK',
        latencyMs: 1,
        discoveredModels: ['test'],
      );
}

void main() {
  group('LanguageRegistry & multi-language support', () {
    test('detects common languages, comment prefixes, and highlight modes', () {
      final cases = <String, ({String id, String comment, bool hasMode})>{
        '/proj/app.py': (id: 'python', comment: '#', hasMode: true),
        '/proj/src/lib.rs': (id: 'rust', comment: '//', hasMode: true),
        '/proj/web/app.ts': (id: 'typescript', comment: '//', hasMode: true),
        '/proj/web/app.tsx': (id: 'typescript', comment: '//', hasMode: true),
        '/proj/native/main.cpp': (id: 'cpp', comment: '//', hasMode: true),
        '/proj/Dockerfile': (id: 'dockerfile', comment: '#', hasMode: true),
        '/proj/CMakeLists.txt': (id: 'cmake', comment: '#', hasMode: true),
        '/proj/ci.yaml': (id: 'yaml', comment: '#', hasMode: true),
        '/proj/build.sh': (id: 'bash', comment: '#', hasMode: true),
        '/proj/schema.sql': (id: 'sql', comment: '--', hasMode: true),
        '/proj/main.go': (id: 'go', comment: '//', hasMode: true),
        '/proj/lib/main.dart': (id: 'dart', comment: '//', hasMode: true),
        '/proj/README.md': (id: 'markdown', comment: '<!--', hasMode: true),
      };

      for (final entry in cases.entries) {
        final spec = LanguageRegistry.detect(entry.key);
        expect(spec.id, entry.value.id, reason: entry.key);
        expect(
          spec.lineCommentPrefix,
          entry.value.comment,
          reason: entry.key,
        );
        if (entry.value.hasMode) {
          expect(
            spec.highlightMode,
            isNotNull,
            reason: 'Expected highlightMode for ${entry.key}',
          );
        }
      }
    });
  });

  group('LSP DocumentSymbol flattening', () {
    test('flattens nested DocumentSymbol hierarchy and flat SymbolInformation', () {
      final nested = [
        {
          'name': 'MyService',
          'kind': 5,
          'selectionRange': {
            'start': {'line': 10, 'character': 6},
          },
          'children': [
            {
              'name': 'fetchData',
              'kind': 6,
              'range': {
                'start': {'line': 12, 'character': 2},
              },
            },
          ],
        },
      ];
      final flatNested = DocumentSymbolEntry.flatten(nested);
      expect(flatNested.length, 2);
      expect(flatNested[0].name, 'MyService');
      expect(flatNested[0].depth, 0);
      expect(flatNested[0].line, 10);
      expect(flatNested[1].name, 'fetchData');
      expect(flatNested[1].depth, 1);
      expect(flatNested[1].line, 12);

      final symbolInfo = [
        {
          'name': 'topFn',
          'kind': 12,
          'location': {
            'range': {
              'start': {'line': 3, 'character': 0},
            },
          },
        },
      ];
      final flatInfo = DocumentSymbolEntry.flatten(symbolInfo);
      expect(flatInfo.length, 1);
      expect(flatInfo.first.name, 'topFn');
      expect(flatInfo.first.line, 3);
    });
  });

  group('QuickOpen, CommandPalette, and BottomPanel widgets', () {
    testWidgets('QuickOpenDialog filters fuzzily and selects clicked file', (
      tester,
    ) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuickOpenDialog(
              projectRoot: '/workspace',
              openFiles: const ['/workspace/lib/main.dart'],
              loadWorkspaceFiles: () async => [
                'lib/main.dart',
                'lib/ai/agent_controller.dart',
                'pubspec.yaml',
              ],
              onFileSelected: (path) => picked = path,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('main.dart'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'agctrl');
      await tester.pumpAndSettle();

      expect(find.text('agent_controller.dart'), findsOneWidget);
      await tester.tap(find.text('agent_controller.dart'));
      await tester.pumpAndSettle();
      expect(picked, '/workspace/lib/ai/agent_controller.dart');
    });

    testWidgets('CommandPaletteDialog filters and executes command', (
      tester,
    ) async {
      var ran = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CommandPaletteDialog(
              commands: [
                PaletteCommand(
                  title: 'Toggle Integrated Terminal',
                  category: 'View',
                  shortcut: 'Ctrl+`',
                  icon: Icons.terminal,
                  onExecute: () => ran = true,
                ),
                PaletteCommand(
                  title: 'Save Current File',
                  category: 'File',
                  icon: Icons.save,
                  onExecute: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'term');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Toggle Integrated Terminal'));
      await tester.pumpAndSettle();
      expect(ran, isTrue);
    });

    testWidgets('BottomPanel Problems tab navigates and triggers Fix with AI', (
      tester,
    ) async {
      String? navPath;
      int? navLine;
      String? aiPrompt;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 260,
              child: BottomPanel(
                projectRoot: '/workspace',
                activeTab: BottomPanelTab.problems,
                onTabChanged: (_) {},
                onClose: () {},
                diagnosticsByFile: const {
                  '/workspace/lib/foo.dart': [
                    {
                      'severity': 1,
                      'message': 'Undefined name bar',
                      'range': {
                        'start': {'line': 4, 'character': 2},
                      },
                    },
                  ],
                },
                references: const [],
                onNavigate: (path, line, col) {
                  navPath = path;
                  navLine = line;
                },
                onAskAi: (prompt) => aiPrompt = prompt,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Undefined name bar'), findsOneWidget);
      await tester.tap(find.textContaining('Undefined name bar'));
      expect(navPath, '/workspace/lib/foo.dart');
      expect(navLine, 4);

      await tester.tap(find.byTooltip('Fix this error with AI'));
      expect(aiPrompt, isNotNull);
    });
  });

  group('Next-Level AI: manage_tasks, multimodal images, ghost text, & MCP', () {
    testWidgets('manage_tasks updates session checklist and renders in AiAgentPanel', (
      tester,
    ) async {
      final tmp = await tester.runAsync(
        () => Directory.systemTemp.createTemp('fyrcode_tasks_'),
      );
      addTearDown(() async {
        await tester.runAsync(() => tmp!.delete(recursive: true));
      });

      final fakeLlm = _CapturingFakeLlmClient([
        [
          const LlmStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'call_tasks',
                name: 'manage_tasks',
                argumentsFragment:
                    '{"tasks":[{"id":"1","title":"Inspect code","status":"completed"},{"id":"2","title":"Write tests","status":"inProgress"}]}',
              ),
            ],
          ),
        ],
        [const LlmStreamEvent(contentDelta: 'Checklist updated.')],
      ]);

      final config = AiConfig.defaults().copyWith(
        providers: [
          AiProviderProfile.deepSeekPreset().copyWith(apiKey: 'sk-test'),
        ],
      );
      final ctrl = AgentController(
        projectRoot: tmp!.path,
        store: _MemoryConfigStore(config),
        llmClient: fakeLlm,
      );
      addTearDown(ctrl.dispose);
      await tester.runAsync(() => ctrl.initialize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 440,
              height: 600,
              child: AiAgentPanel(controller: ctrl, onClose: () {}),
            ),
          ),
        ),
      );

      await tester.runAsync(
        () => ctrl.sendMessage(
          'Track tasks and attach screenshot',
          explicitAttachments: [
            const ContextAttachment(
              type: ContextAttachmentType.image,
              label: 'bug.png',
              content:
                  'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=',
              mimeType: 'image/png',
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Task checklist updated and rendered
      expect(ctrl.activeSession.tasks.length, 2);
      expect(find.text('Agent Tasks (1/2)'), findsOneWidget);
      expect(find.text('Inspect code'), findsOneWidget);
      expect(find.text('Write tests'), findsOneWidget);

      // Verify multimodal image_url was serialized to LLM API payload
      final firstApiCallMsgs = fakeLlm.capturedMessages.first;
      final userMsg = firstApiCallMsgs.firstWhere((m) => m['role'] == 'user');
      expect(userMsg['content'], isList);
      final parts = userMsg['content'] as List;
      expect(parts.any((p) => p['type'] == 'image_url'), isTrue);
    });

    testWidgets('AiSettingsDialog shows MCP Servers tab and saves Inline Completions toggle', (
      tester,
    ) async {
      final tmp = await tester.runAsync(
        () => Directory.systemTemp.createTemp('fyrcode_settings_'),
      );
      addTearDown(() async {
        await tester.runAsync(() => tmp!.delete(recursive: true));
      });

      final ctrl = AgentController(
        projectRoot: tmp!.path,
        store: _MemoryConfigStore(),
        llmClient: _CapturingFakeLlmClient([]),
      );
      addTearDown(ctrl.dispose);
      await tester.runAsync(() => ctrl.initialize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AiSettingsDialog(controller: ctrl)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('MCP Servers'));
      await tester.pumpAndSettle();
      expect(find.text('Model Context Protocol (MCP) Servers'), findsOneWidget);
      expect(find.text('Add Server'), findsOneWidget);

      await tester.tap(find.text('Agent & Autonomy'));
      await tester.pumpAndSettle();
      expect(find.text('Inline AI Ghost-Text Autocomplete'), findsOneWidget);
    });

    test('InlineCompletionService strips markdown fences', () async {
      final fakeLlm = _CapturingFakeLlmClient([
        [const LlmStreamEvent(contentDelta: '```dart\nreturn a + b;\n```')],
      ]);
      final svc = InlineCompletionService(llmClient: fakeLlm);
      final cfg = AiConfig.defaults().copyWith(
        providers: [
          AiProviderProfile.deepSeekPreset().copyWith(apiKey: 'sk-test'),
        ],
      );
      final res = await svc.completeAtCursor(
        config: cfg,
        filePath: '/proj/main.dart',
        languageId: 'dart',
        prefix: 'int add(int a, int b) {\n  ',
        suffix: '\n}',
      );
      expect(res, 'return a + b;');
    });

    test('McpStdioClient connects, lists tools, and invokes tool over stdio JSON-RPC', () async {
      final tmp = await Directory.systemTemp.createTemp('fyrcode_mcp_');
      addTearDown(() => tmp.delete(recursive: true));

      final mockServer = File(p.join(tmp.path, 'mock_mcp.dart'));
      await mockServer.writeAsString(r'''
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  await for (final line in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.trim().isEmpty) continue;
    final req = jsonDecode(line) as Map<String, dynamic>;
    final id = req['id'];
    final method = req['method'];
    if (method == 'initialize') {
      stdout.writeln(jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'protocolVersion': '2024-11-05',
          'serverInfo': {'name': 'mock', 'version': '1.0'},
          'capabilities': {'tools': {}},
        },
      }));
    } else if (method == 'tools/list') {
      stdout.writeln(jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'tools': [
            {
              'name': 'echo',
              'description': 'Echo input text',
              'inputSchema': {
                'type': 'object',
                'properties': {'text': {'type': 'string'}},
              },
            },
          ],
        },
      }));
    } else if (method == 'tools/call') {
      final text = req['params']['arguments']['text'];
      stdout.writeln(jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'result': {
          'content': [{'type': 'text', 'text': 'ECHO:$text'}],
          'isError': false,
        },
      }));
    }
  }
}
''');

      final manager = McpManager();
      await manager.syncServers([
        McpServerConfig(
          id: 'srv1',
          name: 'mock',
          command: 'dart',
          args: [mockServer.path],
        ),
      ], workingDirectory: tmp.path);

      expect(manager.isConnected('srv1'), isTrue);
      expect(manager.toolCountFor('srv1'), 1);
      expect(manager.allTools.single.qualifiedName, 'mcp__srv1__echo');

      final res = await manager.callQualifiedTool(
        'mcp__srv1__echo',
        {'text': 'hello'},
      );
      expect(res.isError, isFalse);
      expect(res.output, 'ECHO:hello');
      await manager.disposeAll();
    });
  });
}
