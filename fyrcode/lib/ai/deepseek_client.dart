import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ai_models.dart';

/// Cooperative cancellation token for in-flight LLM requests and tool processes.
class CancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in List<void Function()>.from(_listeners)) {
      try {
        listener();
      } catch (_) {}
    }
    _listeners.clear();
  }

  void onCancel(void Function() callback) {
    if (_isCancelled) {
      callback();
    } else {
      _listeners.add(callback);
    }
  }
}

/// Incremental tool call fragment parsed from SSE `delta.tool_calls`.
class ToolCallDelta {
  final int index;
  final String? id;
  final String? name;
  final String? argumentsFragment;

  const ToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsFragment,
  });
}

/// Event emitted during streaming chat completion.
class LlmStreamEvent {
  final String? contentDelta;
  final String? reasoningDelta;
  final List<ToolCallDelta> toolCallDeltas;
  final String? finishReason;
  final TokenUsage? usage;

  const LlmStreamEvent({
    this.contentDelta,
    this.reasoningDelta,
    this.toolCallDeltas = const [],
    this.finishReason,
    this.usage,
  });
}

class LlmApiException implements Exception {
  final int? statusCode;
  final String message;
  final String? rawBody;

  const LlmApiException(this.message, {this.statusCode, this.rawBody});

  @override
  String toString() =>
      statusCode != null ? 'HTTP $statusCode: $message' : message;
}

class ConnectionTestResult {
  final bool ok;
  final String message;
  final int latencyMs;
  final List<String> discoveredModels;

  const ConnectionTestResult({
    required this.ok,
    required this.message,
    required this.latencyMs,
    this.discoveredModels = const [],
  });
}

/// Abstract LLM client interface so tests can inject deterministic fake streams.
abstract class LlmClient {
  Stream<LlmStreamEvent> streamChatCompletion({
    required AiProviderProfile provider,
    required AiModelSpec model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    double temperature = 0.2,
    bool thinkingEnabled = true,
    String reasoningEffort = 'high',
    CancellationToken? cancelToken,
  });

  Future<ConnectionTestResult> testConnection({
    required AiProviderProfile provider,
    AiModelSpec? model,
  });
}

/// Streaming OpenAI-compatible HTTP client with first-class DeepSeek support.
class OpenAiCompatLlmClient implements LlmClient {
  final HttpClient Function() _httpClientFactory;

  OpenAiCompatLlmClient({HttpClient Function()? httpClientFactory})
      : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static Uri buildChatCompletionsUri(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/chat/completions')) {
      return Uri.parse(trimmed);
    }
    return Uri.parse('$trimmed/chat/completions');
  }

  static Uri buildModelsUri(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/chat/completions')) {
      final prefix = trimmed.substring(
        0,
        trimmed.length - '/chat/completions'.length,
      );
      return Uri.parse('$prefix/models');
    }
    return Uri.parse('$trimmed/models');
  }

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
    final controller = StreamController<LlmStreamEvent>();

    () async {
      final apiKey = provider.resolveApiKey();
      if (provider.requiresApiKey && apiKey.isEmpty) {
        controller.addError(
          LlmApiException(
            'Missing API key for ${provider.name}. Open AI Settings to enter your key (or set ${provider.envVarName}).',
          ),
        );
        await controller.close();
        return;
      }

      final client = _httpClientFactory();
      client.connectionTimeout = const Duration(seconds: 20);
      var closed = false;

      void abortClient() {
        if (!closed) {
          closed = true;
          try {
            client.close(force: true);
          } catch (_) {}
        }
      }

      cancelToken?.onCancel(() {
        abortClient();
        if (!controller.isClosed) {
          controller.close();
        }
      });

      try {
        final uri = buildChatCompletionsUri(provider.baseUrl);
        final request = await client.postUrl(uri);
        request.headers.set(
          HttpHeaders.contentTypeHeader,
          'application/json; charset=utf-8',
        );
        request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
        if (apiKey.isNotEmpty) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $apiKey',
          );
        }
        for (final entry in provider.customHeaders.entries) {
          request.headers.set(entry.key, entry.value);
        }

        final payload = <String, dynamic>{
          'model': model.id,
          'messages': messages,
          'stream': true,
          'stream_options': {'include_usage': true},
        };

        // Reasoning models (DeepSeek R1 / OpenAI o-series) often ignore or
        // reject explicit sampling temperature. DeepSeek V4 models support
        // dynamic thinking mode toggle + reasoning_effort.
        if (!model.supportsReasoning || !thinkingEnabled) {
          payload['temperature'] = temperature;
        }
        if (model.supportsReasoning &&
            (provider.id == 'deepseek' ||
                provider.baseUrl.contains('deepseek.com'))) {
          payload['thinking'] = {
            'type': thinkingEnabled ? 'enabled' : 'disabled',
          };
          if (thinkingEnabled && model.id != 'deepseek-reasoner') {
            payload['reasoning_effort'] = reasoningEffort;
          }
        }

        if (tools != null && tools.isNotEmpty && model.supportsTools) {
          payload['tools'] = tools;
          payload['tool_choice'] = 'auto';
        }

        request.add(utf8.encode(jsonEncode(payload)));
        final response = await request.close();

        if (cancelToken?.isCancelled ?? false) {
          abortClient();
          return;
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          final body = await response.transform(utf8.decoder).join();
          if (!controller.isClosed) {
            controller.addError(
              LlmApiException(
                _friendlyErrorMessage(response.statusCode, body, provider.name),
                statusCode: response.statusCode,
                rawBody: body,
              ),
            );
          }
          return;
        }

        // Parse SSE stream chunk-by-chunk, respecting UTF-8 boundaries and
        // optional inline <think>...</think> blocks.
        final thinkParser = _InlineThinkTagParser();
        await for (final line
            in response.transform(utf8.decoder).transform(const LineSplitter())) {
          if (cancelToken?.isCancelled ?? false) break;

          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith(':')) continue;
          if (!trimmed.startsWith('data:')) continue;

          final data = trimmed.substring(5).trim();
          if (data == '[DONE]') break;

          Map<String, dynamic> json;
          try {
            json = jsonDecode(data) as Map<String, dynamic>;
          } catch (_) {
            continue;
          }

          if (json['error'] != null) {
            final err = json['error'];
            final msg = err is Map
                ? (err['message']?.toString() ?? err.toString())
                : err.toString();
            if (!controller.isClosed) {
              controller.addError(LlmApiException(msg));
            }
            break;
          }

          TokenUsage? usage;
          if (json['usage'] is Map) {
            usage = _parseUsage(
              Map<String, dynamic>.from(json['usage'] as Map),
              model,
            );
          }

          final choices = json['choices'] as List?;
          if (choices == null || choices.isEmpty) {
            if (usage != null && !controller.isClosed) {
              controller.add(LlmStreamEvent(usage: usage));
            }
            continue;
          }

          final choice = Map<String, dynamic>.from(choices.first as Map);
          final finishReason = choice['finish_reason'] as String?;
          final delta = choice['delta'] is Map
              ? Map<String, dynamic>.from(choice['delta'] as Map)
              : const <String, dynamic>{};

          String? reasoningDelta = delta['reasoning_content'] as String?;
          String? contentDelta = delta['content'] as String?;

          if (contentDelta != null &&
              contentDelta.isNotEmpty &&
              reasoningDelta == null) {
            final split = thinkParser.feed(contentDelta);
            contentDelta = split.content;
            reasoningDelta = split.reasoning;
          }

          final toolCallDeltas = <ToolCallDelta>[];
          if (delta['tool_calls'] is List) {
            for (final rawTc in (delta['tool_calls'] as List)) {
              final tc = Map<String, dynamic>.from(rawTc as Map);
              final fn = tc['function'] is Map
                  ? Map<String, dynamic>.from(tc['function'] as Map)
                  : const <String, dynamic>{};
              toolCallDeltas.add(
                ToolCallDelta(
                  index: (tc['index'] as int?) ?? 0,
                  id: tc['id'] as String?,
                  name: fn['name'] as String?,
                  argumentsFragment: fn['arguments'] as String?,
                ),
              );
            }
          }

          if (!controller.isClosed) {
            controller.add(
              LlmStreamEvent(
                contentDelta:
                    (contentDelta?.isNotEmpty ?? false) ? contentDelta : null,
                reasoningDelta: (reasoningDelta?.isNotEmpty ?? false)
                    ? reasoningDelta
                    : null,
                toolCallDeltas: toolCallDeltas,
                finishReason: finishReason,
                usage: usage,
              ),
            );
          }
        }

        // Flush any buffered <think> state at EOF.
        final trailing = thinkParser.flush();
        if ((trailing.content != null || trailing.reasoning != null) &&
            !controller.isClosed) {
          controller.add(
            LlmStreamEvent(
              contentDelta: trailing.content,
              reasoningDelta: trailing.reasoning,
            ),
          );
        }
      } catch (e) {
        if (!(cancelToken?.isCancelled ?? false) && !controller.isClosed) {
          controller.addError(
            e is LlmApiException ? e : LlmApiException(e.toString()),
          );
        }
      } finally {
        abortClient();
        if (!controller.isClosed) {
          await controller.close();
        }
      }
    }();

    return controller.stream;
  }

  @override
  Future<ConnectionTestResult> testConnection({
    required AiProviderProfile provider,
    AiModelSpec? model,
  }) async {
    final stopwatch = Stopwatch()..start();
    final apiKey = provider.resolveApiKey();
    if (provider.requiresApiKey && apiKey.isEmpty) {
      return ConnectionTestResult(
        ok: false,
        message: 'No API key configured for ${provider.name}.',
        latencyMs: 0,
      );
    }

    final client = _httpClientFactory();
    client.connectionTimeout = const Duration(seconds: 12);
    try {
      final modelsUri = buildModelsUri(provider.baseUrl);
      final req = await client.getUrl(modelsUri);
      if (apiKey.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      }
      for (final entry in provider.customHeaders.entries) {
        req.headers.set(entry.key, entry.value);
      }
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      stopwatch.stop();

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final discovered = <String>[];
        try {
          final parsed = jsonDecode(body);
          if (parsed is Map && parsed['data'] is List) {
            for (final item in (parsed['data'] as List)) {
              if (item is Map && item['id'] is String) {
                discovered.add(item['id'] as String);
              }
            }
          }
        } catch (_) {}

        return ConnectionTestResult(
          ok: true,
          message: discovered.isNotEmpty
              ? 'Connected (${discovered.length} models available)'
              : 'Connected to ${provider.name}',
          latencyMs: stopwatch.elapsedMilliseconds,
          discoveredModels: discovered,
        );
      }

      return ConnectionTestResult(
        ok: false,
        message: _friendlyErrorMessage(resp.statusCode, body, provider.name),
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return ConnectionTestResult(
        ok: false,
        message: 'Connection failed: $e',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } finally {
      client.close(force: true);
    }
  }

  static TokenUsage _parseUsage(
    Map<String, dynamic> raw,
    AiModelSpec model,
  ) {
    final promptTokens = (raw['prompt_tokens'] as int?) ?? 0;
    final completionTokens = (raw['completion_tokens'] as int?) ?? 0;
    final cacheHit = (raw['prompt_cache_hit_tokens'] as int?) ??
        ((raw['prompt_tokens_details'] is Map)
            ? ((raw['prompt_tokens_details']['cached_tokens'] as int?) ?? 0)
            : 0);
    final cacheMiss = (raw['prompt_cache_miss_tokens'] as int?) ??
        (promptTokens - cacheHit).clamp(0, promptTokens);

    return TokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      cacheHitTokens: cacheHit,
      cacheMissTokens: cacheMiss,
      estimatedCostUsd: TokenUsage.calculateCost(
        model,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        cacheHitTokens: cacheHit,
        cacheMissTokens: cacheMiss,
      ),
    );
  }

  static String _friendlyErrorMessage(
    int statusCode,
    String body,
    String providerName,
  ) {
    String? apiMsg;
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        apiMsg = decoded['error']['message']?.toString();
      } else if (decoded is Map && decoded['message'] != null) {
        apiMsg = decoded['message'].toString();
      }
    } catch (_) {}

    switch (statusCode) {
      case 401:
        return 'Authentication failed (401): Check your $providerName API key.${apiMsg != null ? ' ($apiMsg)' : ''}';
      case 402:
        return 'Insufficient balance (402): Please top up your $providerName account.${apiMsg != null ? ' ($apiMsg)' : ''}';
      case 429:
        return 'Rate limited (429): Too many requests to $providerName.${apiMsg != null ? ' ($apiMsg)' : ''}';
      default:
        return apiMsg ?? 'HTTP $statusCode from $providerName: $body';
    }
  }
}

/// Splits inline `<think>...</think>` tags out of streamed content chunks
/// for models that emit reasoning tags inline instead of `reasoning_content`.
class _InlineThinkTagParser {
  bool _insideThink = false;
  String _carry = '';

  ({String? content, String? reasoning}) feed(String chunk) {
    var input = _carry + chunk;
    _carry = '';

    final contentBuf = StringBuffer();
    final reasoningBuf = StringBuffer();

    while (input.isNotEmpty) {
      if (_insideThink) {
        final closeIdx = input.indexOf('</think>');
        if (closeIdx == -1) {
          final partial = _trailingPartialPrefix(input, '</think>');
          reasoningBuf.write(input.substring(0, input.length - partial.length));
          _carry = partial;
          break;
        }
        reasoningBuf.write(input.substring(0, closeIdx));
        input = input.substring(closeIdx + '</think>'.length);
        _insideThink = false;
      } else {
        final openIdx = input.indexOf('<think>');
        if (openIdx == -1) {
          final partial = _trailingPartialPrefix(input, '<think>');
          contentBuf.write(input.substring(0, input.length - partial.length));
          _carry = partial;
          break;
        }
        contentBuf.write(input.substring(0, openIdx));
        input = input.substring(openIdx + '<think>'.length);
        _insideThink = true;
      }
    }

    return (
      content: contentBuf.isEmpty ? null : contentBuf.toString(),
      reasoning: reasoningBuf.isEmpty ? null : reasoningBuf.toString(),
    );
  }

  ({String? content, String? reasoning}) flush() {
    if (_carry.isEmpty) return (content: null, reasoning: null);
    final rem = _carry;
    _carry = '';
    return _insideThink
        ? (content: null, reasoning: rem)
        : (content: rem, reasoning: null);
  }

  static String _trailingPartialPrefix(String input, String tag) {
    final maxCheck = input.length < tag.length - 1 ? input.length : tag.length - 1;
    for (var len = maxCheck; len >= 1; len--) {
      final suffix = input.substring(input.length - len);
      if (tag.startsWith(suffix)) {
        return suffix;
      }
    }
    return '';
  }
}
