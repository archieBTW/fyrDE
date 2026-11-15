import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrcode/ai/agent_controller.dart';
import 'package:fyrcode/ai/ai_agent_panel.dart';
import 'package:fyrcode/ai/ai_models.dart';
import 'package:fyrcode/ai/ai_settings_dialog.dart';
import 'package:fyrcode/ai/deepseek_client.dart';
import 'package:path/path.dart' as p;

typedef FakeTurnHandler = Stream<LlmStreamEvent> Function(
  int callCount,
  List<Map<String, dynamic>> messages,
  List<Map<String, dynamic>>? tools,
);

class FakeLlmClient implements LlmClient {
  final FakeTurnHandler handler;
  int calls = 0;

  FakeLlmClient(this.handler);

  @override
  Stream<LlmStreamEvent> streamChatCompletion({
    required AiProviderProfile provider,
    required AiModelSpec model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.2,
    bool thinkingEnabled = true,
    String reasoningEffort = 'high',
    CancellationToken? cancelToken,
  }) {
    calls++;
    return handler(calls, messages, tools);
  }

  @override
  Future<ConnectionTestResult> testConnection({
    required AiProviderProfile provider,
    AiModelSpec? model,
  }) async {
    return const ConnectionTestResult(
      ok: true,
      message: 'Connected',
      latencyMs: 12,
      discoveredModels: ['deepseek-chat', 'deepseek-reasoner'],
    );
  }
}

void main() {
  group('AgentController agentic loop, approvals, checkpoints & Ctrl+K', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fyrcode_agent_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('executes read -> approval-gated edit -> checkpoint restore', () async {
      final targetFile = File(p.join(tempDir.path, 'hello.dart'));
      await targetFile.writeAsString('String greet() => "hi";\n');
      await File(p.join(tempDir.path, '.fyrcoderules'))
          .writeAsString('Always keep code concise.');

      final mutated = <String>[];
      List<Map<String, dynamic>>? firstMessages;

      final fakeLlm = FakeLlmClient((call, messages, tools) async* {
        if (call == 1) {
          firstMessages = messages;
          yield const LlmStreamEvent(
            reasoningDelta: 'Checking file first.',
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'tc_read',
                name: 'read_file',
                argumentsFragment: '{"path":"hello.dart"}',
              ),
            ],
            finishReason: 'tool_calls',
          );
        } else if (call == 2) {
          yield LlmStreamEvent(
            toolCallDeltas: [
              ToolCallDelta(
                index: 0,
                id: 'tc_edit',
                name: 'replace_in_file',
                argumentsFragment: jsonEncode({
                  'path': 'hello.dart',
                  'old_text': 'String greet() => "hi";',
                  'new_text': 'String greet() => "hello world";',
                }),
              ),
            ],
            finishReason: 'tool_calls',
          );
        } else {
          yield const LlmStreamEvent(
            contentDelta: 'Updated greet() in hello.dart.',
            finishReason: 'stop',
            usage: TokenUsage(promptTokens: 50, completionTokens: 20),
          );
        }
      });

      final store = InMemoryAiConfigStore(
        AiConfig.defaults().copyWith(
          providers: [AiProviderProfile.deepSeekPreset(apiKey: 'sk-test')],
        ),
      );

      final controller = AgentController(
        projectRoot: tempDir.path,
        store: store,
        llmClient: fakeLlm,
        onFileMutated: (path, {bool deleted = false}) async {
          mutated.add(path);
        },
      );
      await controller.initialize();

      // Start the agent turn without awaiting completion yet so we can approve
      // the pending edit gate mid-flight.
      final future = controller.sendMessage('Update @hello.dart greeting');

      // Wait until pendingApproval appears for replace_in_file.
      while (controller.pendingApproval == null) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      final pending = controller.pendingApproval!;
      expect(pending.toolCall.name, 'replace_in_file');
      expect(pending.diffPreview, contains('+String greet() => "hello world";'));
      expect(pending.addedLines, 1);
      expect(pending.removedLines, 1);

      controller.respondToApproval(ToolApprovalAction.approveOnce);
      await future;

      expect(await targetFile.readAsString(), contains('hello world'));
      expect(mutated, contains(targetFile.path));
      expect(
        firstMessages!.first['content'].toString(),
        contains('Always keep code concise.'),
      );
      expect(
        controller.activeSession.messages.last.content,
        'Updated greet() in hello.dart.',
      );

      // Find message with checkpoint and revert it!
      final msgWithCheckpoint = controller.activeSession.messages.firstWhere(
        (m) => m.checkpoints.isNotEmpty,
      );
      final reverted = await controller.revertToCheckpoint(msgWithCheckpoint.id);
      expect(reverted, contains('hello.dart'));
      expect(await targetFile.readAsString(), 'String greet() => "hi";\n');
    });

    test('generateInlineEdit strips fences and returns clean diff', () async {
      final fakeLlm = FakeLlmClient((call, messages, tools) async* {
        yield const LlmStreamEvent(
          contentDelta: '```dart\nint add(int a, int b) => a + b;\n```',
          finishReason: 'stop',
        );
      });

      final store = InMemoryAiConfigStore(
        AiConfig.defaults().copyWith(
          providers: [AiProviderProfile.deepSeekPreset(apiKey: 'sk-test')],
        ),
      );

      final controller = AgentController(
        projectRoot: tempDir.path,
        store: store,
        llmClient: fakeLlm,
      );
      await controller.initialize();

      final res = await controller.generateInlineEdit(
        filePath: p.join(tempDir.path, 'math.dart'),
        fullFileContent: 'int add(int a, int b) {\n  return 0;\n}\n',
        startLine: 0,
        endLine: 2,
        selectedOrTargetText: 'int add(int a, int b) {\n  return 0;\n}',
        instruction: 'Implement addition cleanly',
      );

      expect(res.replacementText, 'int add(int a, int b) => a + b;');
      expect(res.diff.addedCount, 1);
      expect(res.diff.removedCount, 3);
    });
  });

  group('AI Panel & Settings UI widgets', () {
    testWidgets('AiAgentPanel renders DeepSeek models, modes, and opens settings',
        (tester) async {
      final store = InMemoryAiConfigStore();
      final controller = AgentController(
        projectRoot: Directory.current.path,
        store: store,
        llmClient: FakeLlmClient((_, _, _) => const Stream.empty()),
      );
      await controller.initialize();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 420,
              height: 700,
              child: AiAgentPanel(
                controller: controller,
                onClose: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('FyrCode Agent'), findsOneWidget);
      expect(find.text('DeepSeek V4 Pro'), findsOneWidget);
      expect(find.text('Add DeepSeek API Key'), findsOneWidget);
      expect(find.text('Act'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
      expect(find.text('Ask'), findsOneWidget);

      // Switch mode to Plan
      await tester.tap(find.text('Plan'));
      await tester.pump();
      expect(controller.mode, AgentMode.plan);

      // Open BYOK Settings Dialog
      await tester.tap(find.text('Add DeepSeek API Key'));
      await tester.pumpAndSettle();
      expect(find.byType(AiSettingsDialog), findsOneWidget);
      expect(find.text('AI & BYOK Settings'), findsOneWidget);
      expect(find.text('DeepSeek V4.1 Flash'), findsOneWidget);
    });
  });
}
