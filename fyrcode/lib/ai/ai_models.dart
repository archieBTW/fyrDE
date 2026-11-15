import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Supported LLM API protocol dialects (currently OpenAI-compatible,
/// which DeepSeek, OpenAI, OpenRouter, Ollama, vLLM, and LiteLLM all implement).
enum AiProviderDialect {
  openAiCompatible,
}

/// Agent operating modes, matching Cursor / Cline / Claude Code conventions.
enum AgentMode {
  act,
  plan,
  ask,
}

extension AgentModeX on AgentMode {
  String get label {
    switch (this) {
      case AgentMode.act:
        return 'Act';
      case AgentMode.plan:
        return 'Plan';
      case AgentMode.ask:
        return 'Ask';
    }
  }

  String get description {
    switch (this) {
      case AgentMode.act:
        return 'Autonomous editing, terminal commands, and tool use';
      case AgentMode.plan:
        return 'Read-only exploration and step-by-step planning';
      case AgentMode.ask:
        return 'Q&A with attached workspace context without modifying files';
    }
  }
}

/// Specification for a model offered by a BYOK provider.
class AiModelSpec {
  final String id;
  final String displayName;
  final int contextWindow;
  final bool supportsTools;
  final bool supportsReasoning;
  final double inputPricePerMillion;
  final double cacheHitPricePerMillion;
  final double outputPricePerMillion;

  const AiModelSpec({
    required this.id,
    required this.displayName,
    this.contextWindow = 64000,
    this.supportsTools = true,
    this.supportsReasoning = false,
    this.inputPricePerMillion = 0.0,
    this.cacheHitPricePerMillion = 0.0,
    this.outputPricePerMillion = 0.0,
  });

  AiModelSpec copyWith({
    String? id,
    String? displayName,
    int? contextWindow,
    bool? supportsTools,
    bool? supportsReasoning,
    double? inputPricePerMillion,
    double? cacheHitPricePerMillion,
    double? outputPricePerMillion,
  }) {
    return AiModelSpec(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      contextWindow: contextWindow ?? this.contextWindow,
      supportsTools: supportsTools ?? this.supportsTools,
      supportsReasoning: supportsReasoning ?? this.supportsReasoning,
      inputPricePerMillion: inputPricePerMillion ?? this.inputPricePerMillion,
      cacheHitPricePerMillion:
          cacheHitPricePerMillion ?? this.cacheHitPricePerMillion,
      outputPricePerMillion:
          outputPricePerMillion ?? this.outputPricePerMillion,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'displayName': displayName,
        'contextWindow': contextWindow,
        'supportsTools': supportsTools,
        'supportsReasoning': supportsReasoning,
        'inputPricePerMillion': inputPricePerMillion,
        'cacheHitPricePerMillion': cacheHitPricePerMillion,
        'outputPricePerMillion': outputPricePerMillion,
      };

  factory AiModelSpec.fromJson(Map<String, dynamic> json) => AiModelSpec(
        id: json['id'] as String,
        displayName: (json['displayName'] as String?) ?? (json['id'] as String),
        contextWindow: (json['contextWindow'] as int?) ?? 64000,
        supportsTools: (json['supportsTools'] as bool?) ?? true,
        supportsReasoning: (json['supportsReasoning'] as bool?) ?? false,
        inputPricePerMillion:
            (json['inputPricePerMillion'] as num?)?.toDouble() ?? 0.0,
        cacheHitPricePerMillion:
            (json['cacheHitPricePerMillion'] as num?)?.toDouble() ?? 0.0,
        outputPricePerMillion:
            (json['outputPricePerMillion'] as num?)?.toDouble() ?? 0.0,
      );
}

/// A configured BYOK provider profile (e.g., DeepSeek, OpenAI, OpenRouter, Ollama).
class AiProviderProfile {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String envVarName;
  final AiProviderDialect dialect;
  final List<AiModelSpec> models;
  final bool isBuiltIn;
  final Map<String, String> customHeaders;

  const AiProviderProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.apiKey = '',
    this.envVarName = '',
    this.dialect = AiProviderDialect.openAiCompatible,
    required this.models,
    this.isBuiltIn = false,
    this.customHeaders = const {},
  });

  /// Returns the user-entered API key, falling back to [envVarName] if set.
  String resolveApiKey([Map<String, String>? env]) {
    if (apiKey.trim().isNotEmpty) return apiKey.trim();
    if (envVarName.isNotEmpty) {
      final source = env ?? Platform.environment;
      final fromEnv = source[envVarName];
      if (fromEnv != null && fromEnv.trim().isNotEmpty) {
        return fromEnv.trim();
      }
    }
    return '';
  }

  bool get requiresApiKey => !baseUrl.contains('localhost') &&
      !baseUrl.contains('127.0.0.1');

  AiProviderProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? apiKey,
    String? envVarName,
    AiProviderDialect? dialect,
    List<AiModelSpec>? models,
    bool? isBuiltIn,
    Map<String, String>? customHeaders,
  }) {
    return AiProviderProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      envVarName: envVarName ?? this.envVarName,
      dialect: dialect ?? this.dialect,
      models: models ?? this.models,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      customHeaders: customHeaders ?? this.customHeaders,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'envVarName': envVarName,
        'dialect': dialect.name,
        'models': models.map((m) => m.toJson()).toList(),
        'isBuiltIn': isBuiltIn,
        'customHeaders': customHeaders,
      };

  factory AiProviderProfile.fromJson(Map<String, dynamic> json) {
    final dialectName = json['dialect'] as String?;
    final dialect = AiProviderDialect.values.firstWhere(
      (d) => d.name == dialectName,
      orElse: () => AiProviderDialect.openAiCompatible,
    );
    return AiProviderProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      apiKey: (json['apiKey'] as String?) ?? '',
      envVarName: (json['envVarName'] as String?) ?? '',
      dialect: dialect,
      models: ((json['models'] as List?) ?? [])
          .map((m) => AiModelSpec.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList(),
      isBuiltIn: (json['isBuiltIn'] as bool?) ?? false,
      customHeaders: Map<String, String>.from(
        (json['customHeaders'] as Map?) ?? const {},
      ),
    );
  }

  /// First-class DeepSeek preset with V4 models (deepseek-v4-pro, deepseek-flash)
  /// alongside legacy V3/R1 aliases (deepseek-chat, deepseek-reasoner).
  static AiProviderProfile deepSeekPreset({String apiKey = ''}) =>
      AiProviderProfile(
        id: 'deepseek',
        name: 'DeepSeek',
        baseUrl: 'https://api.deepseek.com',
        apiKey: apiKey,
        envVarName: 'DEEPSEEK_API_KEY',
        isBuiltIn: true,
        models: const [
          AiModelSpec(
            id: 'deepseek-v4-pro',
            displayName: 'DeepSeek V4 Pro',
            contextWindow: 1000000,
            supportsTools: true,
            supportsReasoning: true,
            inputPricePerMillion: 1.32,
            cacheHitPricePerMillion: 0.044,
            outputPricePerMillion: 3.96,
          ),
          AiModelSpec(
            id: 'deepseek-flash',
            displayName: 'DeepSeek V4.1 Flash',
            contextWindow: 1000000,
            supportsTools: true,
            supportsReasoning: true,
            inputPricePerMillion: 0.30,
            cacheHitPricePerMillion: 0.006,
            outputPricePerMillion: 1.20,
          ),
          AiModelSpec(
            id: 'deepseek-chat',
            displayName: 'DeepSeek Chat',
            contextWindow: 128000,
            supportsTools: true,
            supportsReasoning: false,
            inputPricePerMillion: 0.27,
            cacheHitPricePerMillion: 0.07,
            outputPricePerMillion: 1.10,
          ),
          AiModelSpec(
            id: 'deepseek-reasoner',
            displayName: 'DeepSeek Reasoner',
            contextWindow: 128000,
            supportsTools: true,
            supportsReasoning: true,
            inputPricePerMillion: 0.55,
            cacheHitPricePerMillion: 0.14,
            outputPricePerMillion: 2.19,
          ),
        ],
      );

  static AiProviderProfile openAiPreset({String apiKey = ''}) =>
      AiProviderProfile(
        id: 'openai',
        name: 'OpenAI',
        baseUrl: 'https://api.openai.com/v1',
        apiKey: apiKey,
        envVarName: 'OPENAI_API_KEY',
        models: const [
          AiModelSpec(
            id: 'gpt-4o',
            displayName: 'GPT-4o',
            contextWindow: 128000,
            supportsTools: true,
            inputPricePerMillion: 2.50,
            cacheHitPricePerMillion: 1.25,
            outputPricePerMillion: 10.0,
          ),
          AiModelSpec(
            id: 'o3-mini',
            displayName: 'o3-mini',
            contextWindow: 200000,
            supportsTools: true,
            supportsReasoning: true,
            inputPricePerMillion: 1.10,
            cacheHitPricePerMillion: 0.55,
            outputPricePerMillion: 4.40,
          ),
        ],
      );

  static AiProviderProfile openRouterPreset({String apiKey = ''}) =>
      AiProviderProfile(
        id: 'openrouter',
        name: 'OpenRouter',
        baseUrl: 'https://openrouter.ai/api/v1',
        apiKey: apiKey,
        envVarName: 'OPENROUTER_API_KEY',
        customHeaders: const {
          'HTTP-Referer': 'https://fyrcode.local',
          'X-Title': 'FyrCode',
        },
        models: const [
          AiModelSpec(
            id: 'deepseek/deepseek-chat-v3-0324',
            displayName: 'DeepSeek V3 (OpenRouter)',
            contextWindow: 128000,
            supportsTools: true,
          ),
          AiModelSpec(
            id: 'anthropic/claude-sonnet-4',
            displayName: 'Claude Sonnet 4 (OpenRouter)',
            contextWindow: 200000,
            supportsTools: true,
          ),
        ],
      );

  static AiProviderProfile ollamaPreset() => const AiProviderProfile(
        id: 'ollama',
        name: 'Ollama (Local)',
        baseUrl: 'http://localhost:11434/v1',
        apiKey: 'ollama',
        models: [
          AiModelSpec(
            id: 'qwen2.5-coder:14b',
            displayName: 'Qwen 2.5 Coder 14B',
            contextWindow: 32768,
            supportsTools: true,
          ),
          AiModelSpec(
            id: 'deepseek-r1:14b',
            displayName: 'DeepSeek R1 14B',
            contextWindow: 32768,
            supportsTools: true,
            supportsReasoning: true,
          ),
        ],
      );
}

/// Granular auto-approval policy for agent tool calls.
class AutoApprovePolicy {
  final bool readTools;
  final bool editTools;
  final bool runCommands;
  final int maxStepsPerTurn;
  final List<String> allowedCommandPrefixes;

  const AutoApprovePolicy({
    this.readTools = true,
    this.editTools = false,
    this.runCommands = false,
    this.maxStepsPerTurn = 25,
    this.allowedCommandPrefixes = const [],
  });

  bool isCommandAllowlisted(String command) {
    final trimmed = command.trim();
    for (final prefix in allowedCommandPrefixes) {
      if (prefix.isNotEmpty && trimmed.startsWith(prefix)) {
        return true;
      }
    }
    return false;
  }

  AutoApprovePolicy copyWith({
    bool? readTools,
    bool? editTools,
    bool? runCommands,
    int? maxStepsPerTurn,
    List<String>? allowedCommandPrefixes,
  }) {
    return AutoApprovePolicy(
      readTools: readTools ?? this.readTools,
      editTools: editTools ?? this.editTools,
      runCommands: runCommands ?? this.runCommands,
      maxStepsPerTurn: maxStepsPerTurn ?? this.maxStepsPerTurn,
      allowedCommandPrefixes:
          allowedCommandPrefixes ?? this.allowedCommandPrefixes,
    );
  }

  Map<String, dynamic> toJson() => {
        'readTools': readTools,
        'editTools': editTools,
        'runCommands': runCommands,
        'maxStepsPerTurn': maxStepsPerTurn,
        'allowedCommandPrefixes': allowedCommandPrefixes,
      };

  factory AutoApprovePolicy.fromJson(Map<String, dynamic> json) =>
      AutoApprovePolicy(
        readTools: (json['readTools'] as bool?) ?? true,
        editTools: (json['editTools'] as bool?) ?? false,
        runCommands: (json['runCommands'] as bool?) ?? false,
        maxStepsPerTurn: (json['maxStepsPerTurn'] as int?) ?? 25,
        allowedCommandPrefixes: List<String>.from(
          (json['allowedCommandPrefixes'] as List?) ?? const [],
        ),
      );
}

/// Configuration for a stdio Model Context Protocol (MCP) server.
class McpServerConfig {
  final String id;
  final String name;
  final String command;
  final List<String> args;
  final Map<String, String> env;
  final bool enabled;

  const McpServerConfig({
    required this.id,
    required this.name,
    required this.command,
    this.args = const [],
    this.env = const {},
    this.enabled = true,
  });

  McpServerConfig copyWith({
    String? id,
    String? name,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    bool? enabled,
  }) {
    return McpServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      command: command ?? this.command,
      args: args ?? this.args,
      env: env ?? this.env,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'command': command,
        'args': args,
        'env': env,
        'enabled': enabled,
      };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) =>
      McpServerConfig(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? (json['command'] as String? ?? 'MCP'),
        command: (json['command'] as String?) ?? '',
        args: List<String>.from((json['args'] as List?) ?? const []),
        env: Map<String, String>.from((json['env'] as Map?) ?? const {}),
        enabled: (json['enabled'] as bool?) ?? true,
      );
}

/// Top-level persisted AI configuration for FyrCode.
class AiConfig {
  final List<AiProviderProfile> providers;
  final String activeProviderId;
  final String activeModelId;
  final AutoApprovePolicy autoApprove;
  final String customInstructions;
  final double temperature;
  final bool thinkingEnabled;
  final String reasoningEffort;
  final bool inlineCompletionsEnabled;
  final List<McpServerConfig> mcpServers;

  const AiConfig({
    required this.providers,
    required this.activeProviderId,
    required this.activeModelId,
    this.autoApprove = const AutoApprovePolicy(),
    this.customInstructions = '',
    this.temperature = 0.2,
    this.thinkingEnabled = true,
    this.reasoningEffort = 'high',
    this.inlineCompletionsEnabled = false,
    this.mcpServers = const [],
  });

  factory AiConfig.defaults() {
    final deepSeek = AiProviderProfile.deepSeekPreset();
    return AiConfig(
      providers: [deepSeek],
      activeProviderId: deepSeek.id,
      activeModelId: deepSeek.models.first.id,
    );
  }

  AiProviderProfile get activeProvider {
    return providers.firstWhere(
      (p) => p.id == activeProviderId,
      orElse: () => providers.isNotEmpty
          ? providers.first
          : AiProviderProfile.deepSeekPreset(),
    );
  }

  AiModelSpec get activeModel {
    final provider = activeProvider;
    return provider.models.firstWhere(
      (m) => m.id == activeModelId,
      orElse: () => provider.models.isNotEmpty
          ? provider.models.first
          : const AiModelSpec(
              id: 'deepseek-v4-pro',
              displayName: 'DeepSeek V4 Pro',
            ),
    );
  }

  AiConfig copyWith({
    List<AiProviderProfile>? providers,
    String? activeProviderId,
    String? activeModelId,
    AutoApprovePolicy? autoApprove,
    String? customInstructions,
    double? temperature,
    bool? thinkingEnabled,
    String? reasoningEffort,
    bool? inlineCompletionsEnabled,
    List<McpServerConfig>? mcpServers,
  }) {
    return AiConfig(
      providers: providers ?? this.providers,
      activeProviderId: activeProviderId ?? this.activeProviderId,
      activeModelId: activeModelId ?? this.activeModelId,
      autoApprove: autoApprove ?? this.autoApprove,
      customInstructions: customInstructions ?? this.customInstructions,
      temperature: temperature ?? this.temperature,
      thinkingEnabled: thinkingEnabled ?? this.thinkingEnabled,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      inlineCompletionsEnabled:
          inlineCompletionsEnabled ?? this.inlineCompletionsEnabled,
      mcpServers: mcpServers ?? this.mcpServers,
    );
  }

  Map<String, dynamic> toJson() => {
        'providers': providers.map((p) => p.toJson()).toList(),
        'activeProviderId': activeProviderId,
        'activeModelId': activeModelId,
        'autoApprove': autoApprove.toJson(),
        'customInstructions': customInstructions,
        'temperature': temperature,
        'thinkingEnabled': thinkingEnabled,
        'reasoningEffort': reasoningEffort,
        'inlineCompletionsEnabled': inlineCompletionsEnabled,
        'mcpServers': mcpServers.map((m) => m.toJson()).toList(),
      };

  factory AiConfig.fromJson(Map<String, dynamic> json) {
    final parsedProviders = ((json['providers'] as List?) ?? [])
        .map(
          (p) =>
              AiProviderProfile.fromJson(Map<String, dynamic>.from(p as Map)),
        )
        .toList();
    if (parsedProviders.isEmpty) {
      parsedProviders.add(AiProviderProfile.deepSeekPreset());
    } else {
      // Ensure built-in DeepSeek profile automatically picks up V4 preset models.
      final dsIdx = parsedProviders.indexWhere((p) => p.id == 'deepseek');
      if (dsIdx != -1) {
        final existing = parsedProviders[dsIdx];
        final existingIds = existing.models.map((m) => m.id).toSet();
        final presetModels = AiProviderProfile.deepSeekPreset().models;
        final missing = presetModels
            .where((m) => !existingIds.contains(m.id))
            .toList();
        if (missing.isNotEmpty) {
          parsedProviders[dsIdx] = existing.copyWith(
            models: [...missing, ...existing.models],
          );
        }
      }
    }
    return AiConfig(
      providers: parsedProviders,
      activeProviderId:
          (json['activeProviderId'] as String?) ?? parsedProviders.first.id,
      activeModelId: (json['activeModelId'] as String?) ??
          (parsedProviders.first.models.isNotEmpty
              ? parsedProviders.first.models.first.id
              : 'deepseek-v4-pro'),
      autoApprove: json['autoApprove'] is Map
          ? AutoApprovePolicy.fromJson(
              Map<String, dynamic>.from(json['autoApprove'] as Map),
            )
          : const AutoApprovePolicy(),
      customInstructions: (json['customInstructions'] as String?) ?? '',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.2,
      thinkingEnabled: (json['thinkingEnabled'] as bool?) ?? true,
      reasoningEffort: (json['reasoningEffort'] as String?) ?? 'high',
      inlineCompletionsEnabled:
          (json['inlineCompletionsEnabled'] as bool?) ?? false,
      mcpServers: ((json['mcpServers'] as List?) ?? [])
          .map(
            (m) => McpServerConfig.fromJson(
              Map<String, dynamic>.from(m as Map),
            ),
          )
          .toList(),
    );
  }
}

/// Token and cost accounting for a message or session.
class TokenUsage {
  final int promptTokens;
  final int completionTokens;
  final int cacheHitTokens;
  final int cacheMissTokens;
  final double estimatedCostUsd;

  const TokenUsage({
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.cacheHitTokens = 0,
    this.cacheMissTokens = 0,
    this.estimatedCostUsd = 0.0,
  });

  int get totalTokens => promptTokens + completionTokens;

  TokenUsage operator +(TokenUsage other) => TokenUsage(
        promptTokens: promptTokens + other.promptTokens,
        completionTokens: completionTokens + other.completionTokens,
        cacheHitTokens: cacheHitTokens + other.cacheHitTokens,
        cacheMissTokens: cacheMissTokens + other.cacheMissTokens,
        estimatedCostUsd: estimatedCostUsd + other.estimatedCostUsd,
      );

  static double calculateCost(
    AiModelSpec model, {
    required int promptTokens,
    required int completionTokens,
    int cacheHitTokens = 0,
    int cacheMissTokens = 0,
  }) {
    final uncachedInput = cacheHitTokens > 0 || cacheMissTokens > 0
        ? cacheMissTokens
        : (promptTokens - cacheHitTokens).clamp(0, promptTokens);
    final inputCost =
        (uncachedInput / 1000000.0) * model.inputPricePerMillion;
    final cacheCost =
        (cacheHitTokens / 1000000.0) * model.cacheHitPricePerMillion;
    final outputCost =
        (completionTokens / 1000000.0) * model.outputPricePerMillion;
    return inputCost + cacheCost + outputCost;
  }

  Map<String, dynamic> toJson() => {
        'promptTokens': promptTokens,
        'completionTokens': completionTokens,
        'cacheHitTokens': cacheHitTokens,
        'cacheMissTokens': cacheMissTokens,
        'estimatedCostUsd': estimatedCostUsd,
      };

  factory TokenUsage.fromJson(Map<String, dynamic> json) => TokenUsage(
        promptTokens: (json['promptTokens'] as int?) ?? 0,
        completionTokens: (json['completionTokens'] as int?) ?? 0,
        cacheHitTokens: (json['cacheHitTokens'] as int?) ?? 0,
        cacheMissTokens: (json['cacheMissTokens'] as int?) ?? 0,
        estimatedCostUsd:
            (json['estimatedCostUsd'] as num?)?.toDouble() ?? 0.0,
      );
}

enum ContextAttachmentType {
  file,
  folder,
  selection,
  problems,
  gitDiff,
  image,
}

/// Context attached to a user prompt via `@` mentions or UI chips.
class ContextAttachment {
  final ContextAttachmentType type;
  final String label;
  final String? path;
  final String? content;
  final String? mimeType;
  final int? startLine;
  final int? endLine;

  const ContextAttachment({
    required this.type,
    required this.label,
    this.path,
    this.content,
    this.mimeType,
    this.startLine,
    this.endLine,
  });

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'label': label,
        'path': path,
        'content': content,
        'mimeType': mimeType,
        'startLine': startLine,
        'endLine': endLine,
      };

  factory ContextAttachment.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String?;
    final type = ContextAttachmentType.values.firstWhere(
      (t) => t.name == typeName,
      orElse: () => ContextAttachmentType.file,
    );
    return ContextAttachment(
      type: type,
      label: json['label'] as String,
      path: json['path'] as String?,
      content: json['content'] as String?,
      mimeType: json['mimeType'] as String?,
      startLine: json['startLine'] as int?,
      endLine: json['endLine'] as int?,
    );
  }
}

/// Snapshot of a file before an AI edit/write/delete for instant checkpoint revert.
class FileCheckpoint {
  final String filePath;
  final bool existedBefore;
  final String? previousContent;
  final DateTime timestamp;

  FileCheckpoint({
    required this.filePath,
    required this.existedBefore,
    this.previousContent,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'filePath': filePath,
        'existedBefore': existedBefore,
        'previousContent': previousContent,
        'timestamp': timestamp.toIso8601String(),
      };

  factory FileCheckpoint.fromJson(Map<String, dynamic> json) => FileCheckpoint(
        filePath: json['filePath'] as String,
        existedBefore: (json['existedBefore'] as bool?) ?? false,
        previousContent: json['previousContent'] as String?,
        timestamp: DateTime.tryParse((json['timestamp'] as String?) ?? '') ??
            DateTime.now(),
      );
}

enum ToolCallStatus {
  pendingApproval,
  running,
  completed,
  rejected,
  error,
}

/// Record of an individual tool invocation inside an assistant turn.
class ToolCallRecord {
  final String id;
  final String name;
  final String argumentsJson;
  final ToolCallStatus status;
  final String? resultOutput;
  final String? diffPreview;
  final int addedLines;
  final int removedLines;
  final String? targetPath;
  final int? durationMs;

  const ToolCallRecord({
    required this.id,
    required this.name,
    required this.argumentsJson,
    this.status = ToolCallStatus.running,
    this.resultOutput,
    this.diffPreview,
    this.addedLines = 0,
    this.removedLines = 0,
    this.targetPath,
    this.durationMs,
  });

  Map<String, dynamic> get parsedArguments {
    try {
      final decoded = jsonDecode(argumentsJson);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return const {};
  }

  ToolCallRecord copyWith({
    String? id,
    String? name,
    String? argumentsJson,
    ToolCallStatus? status,
    String? resultOutput,
    String? diffPreview,
    int? addedLines,
    int? removedLines,
    String? targetPath,
    int? durationMs,
  }) {
    return ToolCallRecord(
      id: id ?? this.id,
      name: name ?? this.name,
      argumentsJson: argumentsJson ?? this.argumentsJson,
      status: status ?? this.status,
      resultOutput: resultOutput ?? this.resultOutput,
      diffPreview: diffPreview ?? this.diffPreview,
      addedLines: addedLines ?? this.addedLines,
      removedLines: removedLines ?? this.removedLines,
      targetPath: targetPath ?? this.targetPath,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'argumentsJson': argumentsJson,
        'status': status.name,
        'resultOutput': resultOutput,
        'diffPreview': diffPreview,
        'addedLines': addedLines,
        'removedLines': removedLines,
        'targetPath': targetPath,
        'durationMs': durationMs,
      };

  factory ToolCallRecord.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String?;
    final status = ToolCallStatus.values.firstWhere(
      (s) => s.name == statusName,
      orElse: () => ToolCallStatus.completed,
    );
    return ToolCallRecord(
      id: json['id'] as String,
      name: json['name'] as String,
      argumentsJson: (json['argumentsJson'] as String?) ?? '{}',
      status: status,
      resultOutput: json['resultOutput'] as String?,
      diffPreview: json['diffPreview'] as String?,
      addedLines: (json['addedLines'] as int?) ?? 0,
      removedLines: (json['removedLines'] as int?) ?? 0,
      targetPath: json['targetPath'] as String?,
      durationMs: json['durationMs'] as int?,
    );
  }
}

enum ChatRole {
  user,
  assistant,
  tool,
  system,
}

class ChatMessage {
  final String id;
  final ChatRole role;
  final String content;
  final String? reasoningContent;
  final List<ToolCallRecord> toolCalls;
  final String? toolCallId;
  final String? toolName;
  final List<ContextAttachment> attachments;
  final List<FileCheckpoint> checkpoints;
  final TokenUsage? usage;
  final DateTime timestamp;
  final bool isError;
  final List<String> followupOptions;

  ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.reasoningContent,
    this.toolCalls = const [],
    this.toolCallId,
    this.toolName,
    this.attachments = const [],
    this.checkpoints = const [],
    this.usage,
    DateTime? timestamp,
    this.isError = false,
    this.followupOptions = const [],
  }) : timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? id,
    ChatRole? role,
    String? content,
    String? reasoningContent,
    List<ToolCallRecord>? toolCalls,
    String? toolCallId,
    String? toolName,
    List<ContextAttachment>? attachments,
    List<FileCheckpoint>? checkpoints,
    TokenUsage? usage,
    DateTime? timestamp,
    bool? isError,
    List<String>? followupOptions,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      reasoningContent: reasoningContent ?? this.reasoningContent,
      toolCalls: toolCalls ?? this.toolCalls,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      attachments: attachments ?? this.attachments,
      checkpoints: checkpoints ?? this.checkpoints,
      usage: usage ?? this.usage,
      timestamp: timestamp ?? this.timestamp,
      isError: isError ?? this.isError,
      followupOptions: followupOptions ?? this.followupOptions,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'reasoningContent': reasoningContent,
        'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
        'toolCallId': toolCallId,
        'toolName': toolName,
        'attachments': attachments.map((a) => a.toJson()).toList(),
        'checkpoints': checkpoints.map((c) => c.toJson()).toList(),
        'usage': usage?.toJson(),
        'timestamp': timestamp.toIso8601String(),
        'isError': isError,
        'followupOptions': followupOptions,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final roleName = json['role'] as String?;
    final role = ChatRole.values.firstWhere(
      (r) => r.name == roleName,
      orElse: () => ChatRole.user,
    );
    return ChatMessage(
      id: json['id'] as String,
      role: role,
      content: (json['content'] as String?) ?? '',
      reasoningContent: json['reasoningContent'] as String?,
      toolCalls: ((json['toolCalls'] as List?) ?? [])
          .map((t) => ToolCallRecord.fromJson(Map<String, dynamic>.from(t as Map)))
          .toList(),
      toolCallId: json['toolCallId'] as String?,
      toolName: json['toolName'] as String?,
      attachments: ((json['attachments'] as List?) ?? [])
          .map(
            (a) => ContextAttachment.fromJson(
              Map<String, dynamic>.from(a as Map),
            ),
          )
          .toList(),
      checkpoints: ((json['checkpoints'] as List?) ?? [])
          .map(
            (c) =>
                FileCheckpoint.fromJson(Map<String, dynamic>.from(c as Map)),
          )
          .toList(),
      usage: json['usage'] is Map
          ? TokenUsage.fromJson(Map<String, dynamic>.from(json['usage'] as Map))
          : null,
      timestamp: DateTime.tryParse((json['timestamp'] as String?) ?? '') ??
          DateTime.now(),
      isError: (json['isError'] as bool?) ?? false,
      followupOptions: List<String>.from(
        (json['followupOptions'] as List?) ?? const [],
      ),
    );
  }
}

enum AgentTaskStatus {
  pending,
  inProgress,
  completed,
}

class AgentTaskItem {
  final String id;
  final String title;
  final AgentTaskStatus status;

  const AgentTaskItem({
    required this.id,
    required this.title,
    this.status = AgentTaskStatus.pending,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'status': status.name,
      };

  factory AgentTaskItem.fromJson(Map<String, dynamic> json) {
    final statusStr = json['status'] as String?;
    final status = switch (statusStr) {
      'in_progress' || 'inProgress' => AgentTaskStatus.inProgress,
      'completed' => AgentTaskStatus.completed,
      _ => AgentTaskStatus.pending,
    };
    return AgentTaskItem(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      status: status,
    );
  }
}

/// A persisted conversation session scoped to a workspace directory.
class ChatSession {
  final String id;
  final String title;
  final String projectRoot;
  final AgentMode mode;
  final List<ChatMessage> messages;
  final List<AgentTaskItem> tasks;
  final TokenUsage totalUsage;
  final DateTime createdAt;
  final DateTime updatedAt;

  ChatSession({
    required this.id,
    required this.title,
    required this.projectRoot,
    this.mode = AgentMode.act,
    this.messages = const [],
    this.tasks = const [],
    this.totalUsage = const TokenUsage(),
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  ChatSession copyWith({
    String? id,
    String? title,
    String? projectRoot,
    AgentMode? mode,
    List<ChatMessage>? messages,
    List<AgentTaskItem>? tasks,
    TokenUsage? totalUsage,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ChatSession(
      id: id ?? this.id,
      title: title ?? this.title,
      projectRoot: projectRoot ?? this.projectRoot,
      mode: mode ?? this.mode,
      messages: messages ?? this.messages,
      tasks: tasks ?? this.tasks,
      totalUsage: totalUsage ?? this.totalUsage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'projectRoot': projectRoot,
        'mode': mode.name,
        'messages': messages.map((m) => m.toJson()).toList(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
        'totalUsage': totalUsage.toJson(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ChatSession.fromJson(Map<String, dynamic> json) {
    final modeName = json['mode'] as String?;
    final mode = AgentMode.values.firstWhere(
      (m) => m.name == modeName,
      orElse: () => AgentMode.act,
    );
    return ChatSession(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'New Chat',
      projectRoot: (json['projectRoot'] as String?) ?? '',
      mode: mode,
      messages: ((json['messages'] as List?) ?? [])
          .map((m) => ChatMessage.fromJson(Map<String, dynamic>.from(m as Map)))
          .toList(),
      tasks: ((json['tasks'] as List?) ?? [])
          .map(
            (t) => AgentTaskItem.fromJson(Map<String, dynamic>.from(t as Map)),
          )
          .toList(),
      totalUsage: json['totalUsage'] is Map
          ? TokenUsage.fromJson(
              Map<String, dynamic>.from(json['totalUsage'] as Map),
            )
          : const TokenUsage(),
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }
}

/// Persistence interface for BYOK config and per-workspace chat sessions.
abstract class AiConfigStore {
  Future<AiConfig> loadConfig();
  Future<void> saveConfig(AiConfig config);
  Future<List<ChatSession>> loadSessions(String projectRoot);
  Future<void> saveSession(ChatSession session);
  Future<void> deleteSession(String projectRoot, String sessionId);
}

/// File-backed store under `~/.config/fyr/` with `0600` key-file protection.
class FileAiConfigStore implements AiConfigStore {
  final String baseConfigDir;

  FileAiConfigStore({String? baseConfigDir})
      : baseConfigDir = baseConfigDir ?? _defaultConfigDir();

  static String _defaultConfigDir() {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    return p.join(home, '.config', 'fyr');
  }

  File get _configFile => File(p.join(baseConfigDir, 'fyrcode_ai.json'));

  Directory _sessionsDir(String projectRoot) {
    final normalized = p.normalize(projectRoot);
    final hash = normalized.codeUnits.fold<int>(
      5381,
      (prev, elem) => ((prev << 5) + prev + elem) & 0x7fffffff,
    );
    return Directory(p.join(baseConfigDir, 'fyrcode_sessions', '$hash'));
  }

  @override
  Future<AiConfig> loadConfig() async {
    try {
      if (await _configFile.exists()) {
        final raw = await _configFile.readAsString();
        if (raw.trim().isNotEmpty) {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          return AiConfig.fromJson(json);
        }
      }
    } catch (_) {}
    return AiConfig.defaults();
  }

  @override
  Future<void> saveConfig(AiConfig config) async {
    final dir = _configFile.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final tmpFile = File('${_configFile.path}.tmp');
    await tmpFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(config.toJson()),
    );
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', tmpFile.path]);
      } catch (_) {}
    }
    await tmpFile.rename(_configFile.path);
  }

  @override
  Future<List<ChatSession>> loadSessions(String projectRoot) async {
    final dir = _sessionsDir(projectRoot);
    if (!await dir.exists()) return [];
    final sessions = <ChatSession>[];
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        try {
          final raw = await entity.readAsString();
          final json = jsonDecode(raw) as Map<String, dynamic>;
          sessions.add(ChatSession.fromJson(json));
        } catch (_) {}
      }
    }
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }

  @override
  Future<void> saveSession(ChatSession session) async {
    final dir = _sessionsDir(session.projectRoot);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dir.path, '${session.id}.json'));
    final tmpFile = File('${file.path}.tmp');
    await tmpFile.writeAsString(jsonEncode(session.toJson()));
    await tmpFile.rename(file.path);
  }

  @override
  Future<void> deleteSession(String projectRoot, String sessionId) async {
    final file = File(p.join(_sessionsDir(projectRoot).path, '$sessionId.json'));
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// In-memory store used in unit and widget tests.
class InMemoryAiConfigStore implements AiConfigStore {
  AiConfig _config;
  final Map<String, Map<String, ChatSession>> _sessionsByRoot = {};

  InMemoryAiConfigStore([AiConfig? initial])
      : _config = initial ?? AiConfig.defaults();

  @override
  Future<AiConfig> loadConfig() async => _config;

  @override
  Future<void> saveConfig(AiConfig config) async {
    _config = config;
  }

  @override
  Future<List<ChatSession>> loadSessions(String projectRoot) async {
    final list = (_sessionsByRoot[projectRoot]?.values.toList() ?? [])
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<void> saveSession(ChatSession session) async {
    _sessionsByRoot.putIfAbsent(session.projectRoot, () => {});
    _sessionsByRoot[session.projectRoot]![session.id] = session;
  }

  @override
  Future<void> deleteSession(String projectRoot, String sessionId) async {
    _sessionsByRoot[projectRoot]?.remove(sessionId);
  }
}
