import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrcode/ai/ai_models.dart';
import 'package:fyrcode/ai/diff_utils.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AiModels & FileAiConfigStore', () {
    test('defaults to DeepSeek with V4 and legacy models', () {
      final config = AiConfig.defaults();
      expect(config.activeProvider.id, 'deepseek');
      expect(config.activeProvider.baseUrl, 'https://api.deepseek.com');
      expect(config.activeModel.id, 'deepseek-v4-pro');
      expect(
        config.activeProvider.models.map((m) => m.id),
        containsAll([
          'deepseek-v4-pro',
          'deepseek-flash',
          'deepseek-chat',
          'deepseek-reasoner',
        ]),
      );
      final v4Pro = config.activeProvider.models.firstWhere(
        (m) => m.id == 'deepseek-v4-pro',
      );
      expect(v4Pro.contextWindow, 1000000);
      expect(v4Pro.supportsReasoning, isTrue);
      expect(v4Pro.supportsTools, isTrue);
    });

    test('resolveApiKey prefers explicit key and falls back to env var', () {
      final preset = AiProviderProfile.deepSeekPreset();
      expect(preset.resolveApiKey({'DEEPSEEK_API_KEY': 'sk-env-123'}), 'sk-env-123');

      final explicit = preset.copyWith(apiKey: 'sk-direct-456');
      expect(
        explicit.resolveApiKey({'DEEPSEEK_API_KEY': 'sk-env-123'}),
        'sk-direct-456',
      );
    });

    test('TokenUsage calculates DeepSeek V4 Pro cache-hit pricing accurately', () {
      final model = AiProviderProfile.deepSeekPreset().models.first;
      final cost = TokenUsage.calculateCost(
        model,
        promptTokens: 1000000,
        completionTokens: 1000000,
        cacheHitTokens: 500000,
        cacheMissTokens: 500000,
      );
      // 0.5M * 1.32 + 0.5M * 0.044 + 1M * 3.96 = 0.66 + 0.022 + 3.96 = 4.642
      expect(cost, closeTo(4.642, 0.0001));
    });

    test('FileAiConfigStore persists config and project sessions', () async {
      final tmpDir = await Directory.systemTemp.createTemp('fyrcode_ai_cfg_');
      addTearDown(() async {
        if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
      });

      final store = FileAiConfigStore(baseConfigDir: tmpDir.path);
      final config = AiConfig.defaults().copyWith(
        providers: [
          AiProviderProfile.deepSeekPreset(apiKey: 'sk-test-secret'),
          AiProviderProfile.ollamaPreset(),
        ],
        activeModelId: 'deepseek-reasoner',
        autoApprove: const AutoApprovePolicy(
          readTools: true,
          editTools: true,
          allowedCommandPrefixes: ['flutter test'],
        ),
      );

      await store.saveConfig(config);
      final loaded = await store.loadConfig();
      expect(loaded.activeModelId, 'deepseek-reasoner');
      expect(loaded.providers.length, 2);
      expect(loaded.activeProvider.apiKey, 'sk-test-secret');
      expect(loaded.autoApprove.editTools, isTrue);
      expect(loaded.autoApprove.isCommandAllowlisted('flutter test test/a.dart'), isTrue);

      final projectRoot = p.join(tmpDir.path, 'repo');
      final session = ChatSession(
        id: 'sess_1',
        title: 'Refactor parser',
        projectRoot: projectRoot,
        mode: AgentMode.plan,
        messages: [
          ChatMessage(
            id: 'm1',
            role: ChatRole.user,
            content: 'Check @lib/main.dart',
          ),
        ],
      );
      await store.saveSession(session);
      final sessions = await store.loadSessions(projectRoot);
      expect(sessions.length, 1);
      expect(sessions.first.title, 'Refactor parser');
      expect(sessions.first.mode, AgentMode.plan);

      await store.deleteSession(projectRoot, 'sess_1');
      expect(await store.loadSessions(projectRoot), isEmpty);
    });
  });

  group('computeLineDiff', () {
    test('computes accurate additions, removals, and unified preview', () {
      const oldText = 'line 1\nline 2\nline 3\nline 4';
      const newText = 'line 1\nline two\nline 3\nline 4\nline 5';

      final diff = computeLineDiff(oldText, newText);
      expect(diff.hasChanges, isTrue);
      expect(diff.removedCount, 1);
      expect(diff.addedCount, 2);
      expect(diff.unifiedPreview, contains('-line 2'));
      expect(diff.unifiedPreview, contains('+line two'));
      expect(diff.unifiedPreview, contains('+line 5'));
    });

    test('returns empty diff when contents match', () {
      final diff = computeLineDiff('abc\ndef', 'abc\ndef');
      expect(diff.hasChanges, isFalse);
      expect(diff.addedCount, 0);
      expect(diff.removedCount, 0);
    });
  });
}
