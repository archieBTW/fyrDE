import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrcode/ai/agent_tools.dart';
import 'package:fyrcode/ai/ai_models.dart';
import 'package:fyrcode/ai/deepseek_client.dart';
import 'package:path/path.dart' as p;

void main() {
  group('OpenAiCompatLlmClient (DeepSeek SSE)', () {
    test('streams reasoning_content, content, tool_calls, and usage', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      String? capturedAuth;
      Map<String, dynamic>? capturedBody;

      server.listen((req) async {
        capturedAuth = req.headers.value(HttpHeaders.authorizationHeader);
        if (req.uri.path == '/models') {
          req.response.statusCode = 200;
          req.response.write(
            jsonEncode({
              'data': [
                {'id': 'deepseek-chat'},
                {'id': 'deepseek-reasoner'},
              ],
            }),
          );
          await req.response.close();
          return;
        }

        final bodyRaw = await utf8.decoder.bind(req).join();
        capturedBody = jsonDecode(bodyRaw) as Map<String, dynamic>;

        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType('text', 'event-stream');

        final chunks = [
          {
            'choices': [
              {
                'delta': {'reasoning_content': 'Inspecting '},
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {'reasoning_content': 'files.'},
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {'content': 'Let me '},
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {'content': 'check.'},
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'id': 'call_abc',
                      'type': 'function',
                      'function': {'name': 'read_file', 'arguments': '{"path":'},
                    },
                  ],
                },
              },
            ],
          },
          {
            'choices': [
              {
                'delta': {
                  'tool_calls': [
                    {
                      'index': 0,
                      'function': {'arguments': '"lib/main.dart"}'},
                    },
                  ],
                },
                'finish_reason': 'tool_calls',
              },
            ],
            'usage': {
              'prompt_tokens': 120,
              'completion_tokens': 45,
              'prompt_cache_hit_tokens': 80,
              'prompt_cache_miss_tokens': 40,
            },
          },
        ];

        for (final c in chunks) {
          req.response.write('data: ${jsonEncode(c)}\n\n');
        }
        req.response.write('data: [DONE]\n\n');
        await req.response.close();
      });

      final baseUrl = 'http://127.0.0.1:${server.port}';
      final provider = AiProviderProfile.deepSeekPreset(
        apiKey: 'sk-ds-test',
      ).copyWith(baseUrl: baseUrl);
      final v4Pro = provider.models.firstWhere(
        (m) => m.id == 'deepseek-v4-pro',
      );

      final client = OpenAiCompatLlmClient();

      final conn = await client.testConnection(provider: provider);
      expect(conn.ok, isTrue);
      expect(conn.discoveredModels, contains('deepseek-reasoner'));

      final events = await client
          .streamChatCompletion(
            provider: provider,
            model: v4Pro,
            messages: [
              {'role': 'user', 'content': 'Hi'},
            ],
            tools: AgentToolExecutor.toolDefinitions(AgentMode.act),
          )
          .toList();

      expect(capturedAuth, 'Bearer sk-ds-test');
      // Reasoning models omit temperature and include DeepSeek V4 thinking config.
      expect(capturedBody!.containsKey('temperature'), isFalse);
      expect(capturedBody!['thinking'], {'type': 'enabled'});
      expect(capturedBody!['reasoning_effort'], 'high');
      expect(capturedBody!['stream'], isTrue);

      final reasoning = events
          .where((e) => e.reasoningDelta != null)
          .map((e) => e.reasoningDelta!)
          .join();
      final content = events
          .where((e) => e.contentDelta != null)
          .map((e) => e.contentDelta!)
          .join();
      final args = events
          .expand((e) => e.toolCallDeltas)
          .map((d) => d.argumentsFragment ?? '')
          .join();
      final usage = events.lastWhere((e) => e.usage != null).usage!;

      expect(reasoning, 'Inspecting files.');
      expect(content, 'Let me check.');
      expect(args, '{"path":"lib/main.dart"}');
      expect(usage.promptTokens, 120);
      expect(usage.cacheHitTokens, 80);
    });

    test('surfaces friendly error on 401 unauthorized', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((req) async {
        req.response.statusCode = 401;
        req.response.write(
          jsonEncode({
            'error': {'message': 'Invalid API key'},
          }),
        );
        await req.response.close();
      });

      final provider = AiProviderProfile.deepSeekPreset(
        apiKey: 'bad-key',
      ).copyWith(baseUrl: 'http://127.0.0.1:${server.port}');
      final client = OpenAiCompatLlmClient();

      expect(
        () => client
            .streamChatCompletion(
              provider: provider,
              model: provider.models.first,
              messages: [
                {'role': 'user', 'content': 'Hello'},
              ],
            )
            .toList(),
        throwsA(
          isA<LlmApiException>().having(
            (e) => e.message,
            'message',
            contains('Authentication failed (401)'),
          ),
        ),
      );
    });
  });

  group('AgentToolExecutor', () {
    late Directory tempDir;
    late AgentToolExecutor executor;
    final mutatedPaths = <String>[];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fyrcode_tools_');
      mutatedPaths.clear();
      executor = AgentToolExecutor(
        projectRoot: tempDir.path,
        diagnosticsProvider: () => {
          p.join(tempDir.path, 'lib', 'main.dart'): [
            {
              'range': {
                'start': {'line': 2, 'character': 4},
                'end': {'line': 2, 'character': 10},
              },
              'severity': 1,
              'message': 'Undefined name foo',
            },
          ],
        },
        onFileMutated: (path, {bool deleted = false}) async {
          mutatedPaths.add('$path:$deleted');
        },
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('blocks path traversal outside project root', () async {
      final res = await executor.execute('read_file', {
        'path': '../../etc/passwd',
      });
      expect(res.isError, isTrue);
      expect(res.output, contains('outside the project root'));
    });

    test('write, read, replace, search, find, diagnostics, and delete work',
        () async {
      final writeRes = await executor.execute('write_to_file', {
        'path': 'lib/sample.dart',
        'content': 'void main() {\n  print("hello");\n}\n',
      });
      expect(writeRes.isError, isFalse);
      expect(writeRes.checkpoint?.existedBefore, isFalse);
      expect(mutatedPaths.length, 1);

      final readRes = await executor.execute('read_file', {
        'path': 'lib/sample.dart',
        'start_line': 2,
        'end_line': 2,
      });
      expect(readRes.isError, isFalse);
      expect(readRes.output, contains('2:   print("hello");'));

      final replaceRes = await executor.execute('replace_in_file', {
        'path': 'lib/sample.dart',
        'old_text': '  print("hello");',
        'new_text': '  print("world");',
      });
      expect(replaceRes.isError, isFalse);
      expect(replaceRes.addedLines, 1);
      expect(replaceRes.removedLines, 1);
      expect(replaceRes.diffPreview, contains('+  print("world");'));

      final searchRes = await executor.execute('search_files', {
        'query': 'world',
      });
      expect(searchRes.isError, isFalse);
      expect(searchRes.output, contains('lib/sample.dart:2:'));

      final findRes = await executor.execute('find_files', {
        'pattern': '*.dart',
      });
      expect(findRes.output, contains('lib/sample.dart'));

      final diagRes = await executor.execute('get_diagnostics', {});
      expect(diagRes.output, contains('Undefined name foo'));

      final cmdRes = await executor.execute('run_command', {
        'command': 'echo fyrcode_ok',
      });
      expect(cmdRes.isError, isFalse);
      expect(cmdRes.output, contains('fyrcode_ok'));

      final delRes = await executor.execute('delete_file', {
        'path': 'lib/sample.dart',
      });
      expect(delRes.isError, isFalse);
      expect(File(p.join(tempDir.path, 'lib', 'sample.dart')).existsSync(), isFalse);
    });
  });
}
