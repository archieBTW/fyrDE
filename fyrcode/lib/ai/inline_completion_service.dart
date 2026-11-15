import 'dart:async';

import 'ai_models.dart';
import 'deepseek_client.dart';

/// Generates lightweight, debounced inline ghost-text code completions
/// around the cursor using the active BYOK provider (preferring `deepseek-flash`
/// when available for low latency).
class InlineCompletionService {
  final LlmClient llmClient;
  CancellationToken? _activeCancel;

  InlineCompletionService({required this.llmClient});

  void cancel() {
    _activeCancel?.cancel();
    _activeCancel = null;
  }

  Future<String?> completeAtCursor({
    required AiConfig config,
    required String filePath,
    required String languageId,
    required String prefix,
    required String suffix,
  }) async {
    final provider = config.activeProvider;
    if (provider.requiresApiKey && provider.resolveApiKey().isEmpty) {
      return null;
    }

    // Prefer low-latency `deepseek-flash` if configured on the DeepSeek provider.
    final preferredModel = provider.models.firstWhere(
      (m) => m.id == 'deepseek-flash',
      orElse: () => config.activeModel,
    );

    cancel();
    final token = CancellationToken();
    _activeCancel = token;

    // Trim prefix/suffix to keep completion prompts fast and focused.
    final clippedPrefix =
        prefix.length > 3000 ? prefix.substring(prefix.length - 3000) : prefix;
    final clippedSuffix =
        suffix.length > 1000 ? suffix.substring(0, 1000) : suffix;

    final messages = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are a fast inline code completion engine. Return ONLY the exact code snippet to insert at <CURSOR> (usually 1-4 lines). Do NOT repeat code before <CURSOR>, do NOT include markdown fences, and do NOT explain anything.',
      },
      {
        'role': 'user',
        'content':
            'Language: $languageId\nFile: $filePath\n\n$clippedPrefix<CURSOR>$clippedSuffix',
      },
    ];

    try {
      final buf = StringBuffer();
      await for (final ev in llmClient.streamChatCompletion(
        provider: provider,
        model: preferredModel,
        messages: messages,
        temperature: 0.0,
        thinkingEnabled: false,
        cancelToken: token,
      )) {
        if (token.isCancelled) return null;
        if (ev.contentDelta != null) {
          buf.write(ev.contentDelta);
          if (buf.length > 400) break;
        }
      }

      if (token.isCancelled) return null;
      var result = buf.toString();
      final fenceMatch = RegExp(
        r'^```[a-zA-Z0-9_-]*\r?\n([\s\S]*?)\r?\n```$',
      ).firstMatch(result.trim());
      if (fenceMatch != null) {
        result = fenceMatch.group(1) ?? result;
      }
      if (result.trim().isEmpty) return null;
      return result;
    } catch (_) {
      return null;
    }
  }
}
