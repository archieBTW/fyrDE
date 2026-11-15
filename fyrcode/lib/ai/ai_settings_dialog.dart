import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../fyr_theme.dart';
import 'agent_controller.dart';
import 'ai_models.dart';
import 'deepseek_client.dart';

class AiSettingsDialog extends StatefulWidget {
  final AgentController controller;

  const AiSettingsDialog({super.key, required this.controller});

  static Future<void> show(BuildContext context, AgentController controller) {
    return showDialog(
      context: context,
      builder: (_) => AiSettingsDialog(controller: controller),
    );
  }

  @override
  State<AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<AiSettingsDialog> {
  late AiConfig _draftConfig;
  late String _selectedProviderId;
  int _tabIndex = 0;

  bool _obscureKey = true;
  bool _testingConnection = false;
  ConnectionTestResult? _testResult;

  late TextEditingController _nameCtrl;
  late TextEditingController _baseUrlCtrl;
  late TextEditingController _apiKeyCtrl;
  late TextEditingController _customInstructionsCtrl;
  late TextEditingController _allowedPrefixesCtrl;

  @override
  void initState() {
    super.initState();
    _draftConfig = widget.controller.config;
    _selectedProviderId = _draftConfig.activeProvider.id;
    _nameCtrl = TextEditingController();
    _baseUrlCtrl = TextEditingController();
    _apiKeyCtrl = TextEditingController();
    _customInstructionsCtrl = TextEditingController(
      text: _draftConfig.customInstructions,
    );
    _allowedPrefixesCtrl = TextEditingController(
      text: _draftConfig.autoApprove.allowedCommandPrefixes.join(', '),
    );
    _syncProviderFields();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _baseUrlCtrl.dispose();
    _apiKeyCtrl.dispose();
    _customInstructionsCtrl.dispose();
    _allowedPrefixesCtrl.dispose();
    super.dispose();
  }

  AiProviderProfile get _selectedProvider {
    return _draftConfig.providers.firstWhere(
      (p) => p.id == _selectedProviderId,
      orElse: () => _draftConfig.providers.first,
    );
  }

  void _syncProviderFields() {
    final p = _selectedProvider;
    _nameCtrl.text = p.name;
    _baseUrlCtrl.text = p.baseUrl;
    _apiKeyCtrl.text = p.apiKey;
    _testResult = null;
  }

  void _commitCurrentProviderFields() {
    final updated = _selectedProvider.copyWith(
      name: _nameCtrl.text.trim().isEmpty
          ? _selectedProvider.name
          : _nameCtrl.text.trim(),
      baseUrl: _baseUrlCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
    );
    final providers = _draftConfig.providers
        .map((p) => p.id == updated.id ? updated : p)
        .toList();
    _draftConfig = _draftConfig.copyWith(providers: providers);
  }

  Future<void> _testConnection() async {
    _commitCurrentProviderFields();
    setState(() {
      _testingConnection = true;
      _testResult = null;
    });
    final res = await widget.controller.llmClient.testConnection(
      provider: _selectedProvider,
    );
    if (!mounted) return;
    setState(() {
      _testingConnection = false;
      _testResult = res;
    });
  }

  void _addPresetOrCustomProvider(String kind) {
    _commitCurrentProviderFields();
    final ts = DateTime.now().millisecondsSinceEpoch;
    late AiProviderProfile next;
    switch (kind) {
      case 'openai':
        next = AiProviderProfile.openAiPreset();
        break;
      case 'openrouter':
        next = AiProviderProfile.openRouterPreset();
        break;
      case 'ollama':
        next = AiProviderProfile.ollamaPreset();
        break;
      default:
        next = AiProviderProfile(
          id: 'custom_$ts',
          name: 'Custom Provider',
          baseUrl: 'https://api.example.com/v1',
          models: const [
            AiModelSpec(
              id: 'custom-model',
              displayName: 'Custom Model',
            ),
          ],
        );
    }

    if (_draftConfig.providers.any((p) => p.id == next.id)) {
      next = next.copyWith(id: '${next.id}_$ts');
    }

    setState(() {
      _draftConfig = _draftConfig.copyWith(
        providers: [..._draftConfig.providers, next],
      );
      _selectedProviderId = next.id;
      _syncProviderFields();
    });
  }

  Future<void> _showAddModelDialog() async {
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    var supportsTools = true;
    var supportsReasoning = false;

    final created = await showDialog<AiModelSpec>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: FyrTheme.surfaceColor,
          title: Text(
            'Add Model to ${_selectedProvider.name}',
            style: TextStyle(color: FyrTheme.textColor, fontSize: 15),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtrl,
                autofocus: true,
                style: GoogleFonts.jetBrainsMono(
                  color: FyrTheme.textColor,
                  fontSize: 13,
                ),
                decoration: _inputDecoration(
                  'Model ID (e.g. deepseek-chat)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                decoration: _inputDecoration(
                  'Display Name (optional)',
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: supportsTools,
                activeColor: FyrTheme.accentColor,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Supports Tool Calling',
                  style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                ),
                onChanged: (v) =>
                    setModalState(() => supportsTools = v ?? true),
              ),
              CheckboxListTile(
                value: supportsReasoning,
                activeColor: FyrTheme.accentColor,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Reasoning / Thinking Model',
                  style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                ),
                onChanged: (v) =>
                    setModalState(() => supportsReasoning = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Cancel',
                style: TextStyle(color: FyrTheme.textColorMuted),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: FyrTheme.accentColor,
                foregroundColor: FyrTheme.getContrastingColor(
                  FyrTheme.accentColor,
                ),
              ),
              onPressed: () {
                final id = idCtrl.text.trim();
                if (id.isEmpty) return;
                Navigator.pop(
                  ctx,
                  AiModelSpec(
                    id: id,
                    displayName: nameCtrl.text.trim().isEmpty
                        ? id
                        : nameCtrl.text.trim(),
                    supportsTools: supportsTools,
                    supportsReasoning: supportsReasoning,
                  ),
                );
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (created != null) {
      _commitCurrentProviderFields();
      final updatedModels = [..._selectedProvider.models, created];
      final updatedProvider = _selectedProvider.copyWith(models: updatedModels);
      setState(() {
        _draftConfig = _draftConfig.copyWith(
          providers: _draftConfig.providers
              .map((p) => p.id == updatedProvider.id ? updatedProvider : p)
              .toList(),
        );
      });
    }
  }

  Future<void> _saveAndClose() async {
    _commitCurrentProviderFields();
    final prefixes = _allowedPrefixesCtrl.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final finalConfig = _draftConfig.copyWith(
      customInstructions: _customInstructionsCtrl.text,
      autoApprove: _draftConfig.autoApprove.copyWith(
        allowedCommandPrefixes: prefixes,
      ),
    );
    await widget.controller.updateConfig(finalConfig);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: FyrTheme.bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FyrTheme.dividerColor),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 580),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: FyrTheme.cardColor,
                border: Border(
                  bottom: BorderSide(color: FyrTheme.dividerColor),
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune,
                    color: FyrTheme.accentColor,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI & BYOK Settings',
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.jetBrainsMono(
                        color: FyrTheme.textColor,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildTabChip('Providers & Keys', 0),
                  const SizedBox(width: 6),
                  _buildTabChip('Agent & Autonomy', 1),
                  const SizedBox(width: 6),
                  _buildTabChip('MCP Servers', 2),
                ],
              ),
            ),
            // Body
            Expanded(
              child: _tabIndex == 0
                  ? _buildProvidersTab()
                  : _tabIndex == 1
                      ? _buildAutonomyTab()
                      : _buildMcpTab(),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: FyrTheme.dividerColor),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Keys stored locally in ~/.config/fyr/fyrcode_ai.json',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: FyrTheme.textColorMuted,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: FyrTheme.textColorMuted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: FyrTheme.accentColor,
                      foregroundColor: FyrTheme.getContrastingColor(
                        FyrTheme.accentColor,
                      ),
                    ),
                    onPressed: _saveAndClose,
                    child: const Text('Save Settings'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabChip(String label, int idx) {
    final active = _tabIndex == idx;
    return InkWell(
      onTap: () => setState(() => _tabIndex = idx),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? FyrTheme.accentColor.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? FyrTheme.accentColor : FyrTheme.dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? FyrTheme.accentColor : FyrTheme.textColorMuted,
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildProvidersTab() {
    final provider = _selectedProvider;
    final hasEnvKey = provider.envVarName.isNotEmpty &&
        (Platform.environment[provider.envVarName]?.trim().isNotEmpty ?? false);

    return Row(
      children: [
        // Left Provider List
        Container(
          width: 210,
          decoration: BoxDecoration(
            border: Border(right: BorderSide(color: FyrTheme.dividerColor)),
          ),
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(8),
                  children: _draftConfig.providers.map((p) {
                    final selected = p.id == provider.id;
                    final isActive = p.id == _draftConfig.activeProviderId;
                    final configured =
                        !p.requiresApiKey || p.resolveApiKey().isNotEmpty;
                    return InkWell(
                      onTap: () {
                        _commitCurrentProviderFields();
                        setState(() {
                          _selectedProviderId = p.id;
                          _syncProviderFields();
                        });
                      },
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? FyrTheme.accentColor.withValues(alpha: 0.14)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: selected
                                ? FyrTheme.accentColor.withValues(alpha: 0.6)
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: configured
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                p.name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: FyrTheme.textColor,
                                  fontSize: 13,
                                  fontWeight: isActive
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            if (isActive)
                              Text(
                                'ACTIVE',
                                style: GoogleFonts.jetBrainsMono(
                                  color: FyrTheme.accentColor,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: PopupMenuButton<String>(
                  color: FyrTheme.surfaceColor,
                  onSelected: _addPresetOrCustomProvider,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'openai',
                      child: Text('Add OpenAI'),
                    ),
                    PopupMenuItem(
                      value: 'openrouter',
                      child: Text('Add OpenRouter'),
                    ),
                    PopupMenuItem(
                      value: 'ollama',
                      child: Text('Add Ollama (Local)'),
                    ),
                    PopupMenuItem(
                      value: 'custom',
                      child: Text('Add Custom OpenAI-Compatible'),
                    ),
                  ],
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: FyrTheme.dividerColor),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.add,
                          size: 16,
                          color: FyrTheme.accentColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Add Provider',
                          style: TextStyle(
                            color: FyrTheme.textColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Right Provider Details
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      provider.name,
                      style: TextStyle(
                        color: FyrTheme.textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (!provider.isBuiltIn && _draftConfig.providers.length > 1)
                      TextButton.icon(
                        onPressed: () {
                          final remaining = _draftConfig.providers
                              .where((p) => p.id != provider.id)
                              .toList();
                          setState(() {
                            _draftConfig = _draftConfig.copyWith(
                              providers: remaining,
                              activeProviderId:
                                  _draftConfig.activeProviderId == provider.id
                                      ? remaining.first.id
                                      : _draftConfig.activeProviderId,
                            );
                            _selectedProviderId = remaining.first.id;
                            _syncProviderFields();
                          });
                        },
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: Colors.redAccent,
                        ),
                        label: const Text(
                          'Remove',
                          style: TextStyle(color: Colors.redAccent, fontSize: 12),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _fieldLabel('Provider Name'),
                TextField(
                  controller: _nameCtrl,
                  style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
                  decoration: _inputDecoration('e.g. DeepSeek'),
                ),
                const SizedBox(height: 12),
                _fieldLabel('API Base URL (OpenAI-Compatible)'),
                TextField(
                  controller: _baseUrlCtrl,
                  style: GoogleFonts.jetBrainsMono(
                    color: FyrTheme.textColor,
                    fontSize: 12.5,
                  ),
                  decoration: _inputDecoration('https://api.deepseek.com'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _fieldLabel('API Key'),
                    if (hasEnvKey) ...[
                      const SizedBox(width: 8),
                      Text(
                        '(${provider.envVarName} detected in env)',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                TextField(
                  controller: _apiKeyCtrl,
                  obscureText: _obscureKey,
                  style: GoogleFonts.jetBrainsMono(
                    color: FyrTheme.textColor,
                    fontSize: 12.5,
                  ),
                  decoration: _inputDecoration(
                    provider.envVarName.isNotEmpty
                        ? 'Enter key or use \$${provider.envVarName}'
                        : 'sk-...',
                  ).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureKey ? Icons.visibility : Icons.visibility_off,
                        size: 18,
                        color: FyrTheme.textColorMuted,
                      ),
                      onPressed: () =>
                          setState(() => _obscureKey = !_obscureKey),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _testingConnection ? null : _testConnection,
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: FyrTheme.dividerColor),
                      ),
                      icon: _testingConnection
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              Icons.bolt,
                              size: 16,
                              color: FyrTheme.accentColor,
                            ),
                      label: Text(
                        _testingConnection ? 'Testing...' : 'Test Connection',
                        style: TextStyle(color: FyrTheme.textColor, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (_testResult != null)
                      Expanded(
                        child: Text(
                          '${_testResult!.ok ? "✓" : "✗"} ${_testResult!.message} (${_testResult!.latencyMs}ms)',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _testResult!.ok
                                ? Colors.greenAccent
                                : Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Text(
                      'Models',
                      style: TextStyle(
                        color: FyrTheme.textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (_testResult != null &&
                        _testResult!.discoveredModels.isNotEmpty)
                      TextButton.icon(
                        onPressed: () {
                          final existingIds =
                              provider.models.map((m) => m.id).toSet();
                          final discovered = _testResult!.discoveredModels
                              .where((id) => !existingIds.contains(id))
                              .map(
                                (id) => AiModelSpec(
                                  id: id,
                                  displayName: id,
                                  supportsTools: true,
                                  supportsReasoning: id.contains('reasoner') ||
                                      id.contains('r1') ||
                                      id.contains('v4') ||
                                      id.contains('flash'),
                                ),
                              )
                              .toList();
                          if (discovered.isEmpty) return;
                          final updatedP = provider.copyWith(
                            models: [...provider.models, ...discovered],
                          );
                          setState(() {
                            _draftConfig = _draftConfig.copyWith(
                              providers: _draftConfig.providers
                                  .map((p) => p.id == updatedP.id ? updatedP : p)
                                  .toList(),
                            );
                          });
                        },
                        icon: Icon(
                          Icons.sync,
                          size: 15,
                          color: FyrTheme.accentColor,
                        ),
                        label: Text(
                          'Sync Models',
                          style: TextStyle(
                            color: FyrTheme.accentColor,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    TextButton.icon(
                      onPressed: _showAddModelDialog,
                      icon: Icon(
                        Icons.add,
                        size: 16,
                        color: FyrTheme.accentColor,
                      ),
                      label: Text(
                        'Add Model',
                        style: TextStyle(
                          color: FyrTheme.accentColor,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ...provider.models.map((m) {
                  final isActive =
                      _draftConfig.activeProviderId == provider.id &&
                          _draftConfig.activeModelId == m.id;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isActive
                          ? FyrTheme.accentColor.withValues(alpha: 0.12)
                          : FyrTheme.cardColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isActive
                            ? FyrTheme.accentColor
                            : FyrTheme.dividerColor,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _draftConfig = _draftConfig.copyWith(
                                  activeProviderId: provider.id,
                                  activeModelId: m.id,
                                );
                              });
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      m.displayName,
                                      style: TextStyle(
                                        color: FyrTheme.textColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    if (m.supportsReasoning)
                                      _badge('REASONING'),
                                    if (m.supportsTools) _badge('TOOLS'),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  m.id,
                                  style: GoogleFonts.jetBrainsMono(
                                    color: FyrTheme.textColorMuted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (isActive)
                          Icon(
                            Icons.check_circle,
                            color: FyrTheme.accentColor,
                            size: 18,
                          )
                        else
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _draftConfig = _draftConfig.copyWith(
                                  activeProviderId: provider.id,
                                  activeModelId: m.id,
                                );
                              });
                            },
                            child: Text(
                              'Use',
                              style: TextStyle(
                                color: FyrTheme.accentColor,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        if (provider.models.length > 1)
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              size: 15,
                              color: FyrTheme.textColorMuted,
                            ),
                            onPressed: () {
                              final filtered = provider.models
                                  .where((item) => item.id != m.id)
                                  .toList();
                              final nextP = provider.copyWith(models: filtered);
                              setState(() {
                                _draftConfig = _draftConfig.copyWith(
                                  providers: _draftConfig.providers
                                      .map((p) => p.id == nextP.id ? nextP : p)
                                      .toList(),
                                  activeModelId:
                                      _draftConfig.activeModelId == m.id
                                          ? filtered.first.id
                                          : _draftConfig.activeModelId,
                                );
                              });
                            },
                          ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAutonomyTab() {
    final policy = _draftConfig.autoApprove;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tool Auto-Approval',
            style: TextStyle(
              color: FyrTheme.textColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: FyrTheme.accentColor,
            title: Text(
              'Auto-approve read-only tools',
              style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
            ),
            subtitle: Text(
              'read_file, list_directory, search_files, find_files, get_diagnostics',
              style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11.5),
            ),
            value: policy.readTools,
            onChanged: (val) => setState(() {
              _draftConfig = _draftConfig.copyWith(
                autoApprove: policy.copyWith(readTools: val),
              );
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: FyrTheme.accentColor,
            title: Text(
              'Auto-approve file edits & creation',
              style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
            ),
            subtitle: Text(
              'Apply replace_in_file, write_to_file, and delete_file without confirmation (checkpoints still saved)',
              style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11.5),
            ),
            value: policy.editTools,
            onChanged: (val) => setState(() {
              _draftConfig = _draftConfig.copyWith(
                autoApprove: policy.copyWith(editTools: val),
              );
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: FyrTheme.accentColor,
            title: Text(
              'Auto-approve all terminal commands',
              style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
            ),
            subtitle: Text(
              'Run shell commands without prompting (use with caution)',
              style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11.5),
            ),
            value: policy.runCommands,
            onChanged: (val) => setState(() {
              _draftConfig = _draftConfig.copyWith(
                autoApprove: policy.copyWith(runCommands: val),
              );
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: FyrTheme.accentColor,
            title: Text(
              'Inline AI Ghost-Text Autocomplete',
              style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
            ),
            subtitle: Text(
              'Show dimmed inline code completions while typing (Tab to accept, Esc to dismiss)',
              style: TextStyle(color: FyrTheme.textColorMuted, fontSize: 11.5),
            ),
            value: _draftConfig.inlineCompletionsEnabled,
            onChanged: (val) => setState(() {
              _draftConfig = _draftConfig.copyWith(
                inlineCompletionsEnabled: val,
              );
            }),
          ),
          const SizedBox(height: 10),
          _fieldLabel(
            'Always-Allowed Command Prefixes (comma-separated, e.g. flutter test, dart analyze, git status)',
          ),
          TextField(
            controller: _allowedPrefixesCtrl,
            style: GoogleFonts.jetBrainsMono(
              color: FyrTheme.textColor,
              fontSize: 12.5,
            ),
            decoration: _inputDecoration('flutter test, dart analyze, ls'),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Max Agent Steps Per Turn: ${policy.maxStepsPerTurn}',
                style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
              ),
              Expanded(
                child: Slider(
                  value: policy.maxStepsPerTurn.toDouble(),
                  min: 5,
                  max: 50,
                  divisions: 9,
                  activeColor: FyrTheme.accentColor,
                  onChanged: (val) => setState(() {
                    _draftConfig = _draftConfig.copyWith(
                      autoApprove: policy.copyWith(
                        maxStepsPerTurn: val.round(),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                'Temperature: ${_draftConfig.temperature.toStringAsFixed(1)}',
                style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
              ),
              Expanded(
                child: Slider(
                  value: _draftConfig.temperature,
                  min: 0.0,
                  max: 1.0,
                  divisions: 10,
                  activeColor: FyrTheme.accentColor,
                  onChanged: (val) => setState(() {
                    _draftConfig = _draftConfig.copyWith(temperature: val);
                  }),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _fieldLabel(
            'Custom System Instructions (also reads .fyrcoderules / AGENTS.md in workspace)',
          ),
          TextField(
            controller: _customInstructionsCtrl,
            maxLines: 4,
            style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
            decoration: _inputDecoration(
              'e.g. Always write unit tests for new logic and keep functions concise.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMcpTab() {
    final mcpManager = widget.controller.mcpManager;
    final servers = _draftConfig.mcpServers;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Model Context Protocol (MCP) Servers',
                      style: TextStyle(
                        color: FyrTheme.textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Connect local stdio MCP tools (e.g. npx, uvx, python) and expose their tools directly to the AI agent.',
                      style: TextStyle(
                        color: FyrTheme.textColorMuted,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: FyrTheme.accentColor,
                  foregroundColor: FyrTheme.getContrastingColor(
                    FyrTheme.accentColor,
                  ),
                ),
                onPressed: _showAddMcpServerDialog,
                icon: const Icon(Icons.add, size: 15),
                label: const Text('Add Server', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (servers.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: FyrTheme.bgColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: FyrTheme.dividerColor),
              ),
              child: Text(
                'No MCP servers configured yet. Click "Add Server" to connect a stdio MCP server.',
                style: TextStyle(
                  color: FyrTheme.textColorMuted,
                  fontSize: 12.5,
                ),
              ),
            )
          else
            ...servers.map((srv) {
              final connected = mcpManager.isConnected(srv.id);
              final toolCount = mcpManager.toolCountFor(srv.id);
              final err = mcpManager.connectionErrors[srv.id];
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: FyrTheme.bgColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: FyrTheme.dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 9,
                          color: connected
                              ? Colors.greenAccent
                              : srv.enabled
                                  ? Colors.orangeAccent
                                  : FyrTheme.textColorMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            srv.name,
                            style: TextStyle(
                              color: FyrTheme.textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (connected)
                          _badge('$toolCount tools'),
                        const SizedBox(width: 8),
                        Switch(
                          value: srv.enabled,
                          activeThumbColor: FyrTheme.accentColor,
                          onChanged: (val) => setState(() {
                            _draftConfig = _draftConfig.copyWith(
                              mcpServers: servers
                                  .map(
                                    (s) => s.id == srv.id
                                        ? s.copyWith(enabled: val)
                                        : s,
                                  )
                                  .toList(),
                            );
                          }),
                        ),
                        IconButton(
                          tooltip: 'Delete Server',
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 16,
                            color: Colors.redAccent,
                          ),
                          onPressed: () => setState(() {
                            _draftConfig = _draftConfig.copyWith(
                              mcpServers: servers
                                  .where((s) => s.id != srv.id)
                                  .toList(),
                            );
                          }),
                        ),
                      ],
                    ),
                    Text(
                      '${srv.command} ${srv.args.join(' ')}'.trim(),
                      style: GoogleFonts.jetBrainsMono(
                        color: FyrTheme.textColorMuted,
                        fontSize: 11.5,
                      ),
                    ),
                    if (err != null && err.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        err,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _showAddMcpServerDialog() async {
    final nameCtrl = TextEditingController();
    final cmdCtrl = TextEditingController();
    final argsCtrl = TextEditingController();

    final created = await showDialog<McpServerConfig>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: FyrTheme.surfaceColor,
        title: Text(
          'Add Stdio MCP Server',
          style: TextStyle(color: FyrTheme.textColor, fontSize: 15),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              style: TextStyle(color: FyrTheme.textColor, fontSize: 13),
              decoration: _inputDecoration('Server name (e.g. filesystem)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: cmdCtrl,
              style: GoogleFonts.jetBrainsMono(
                color: FyrTheme.textColor,
                fontSize: 12.5,
              ),
              decoration: _inputDecoration('Command (e.g. npx or python3)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: argsCtrl,
              style: GoogleFonts.jetBrainsMono(
                color: FyrTheme.textColor,
                fontSize: 12.5,
              ),
              decoration: _inputDecoration(
                'Arguments (space-separated, e.g. -y @modelcontextprotocol/server-filesystem .)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: FyrTheme.textColorMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: FyrTheme.accentColor,
              foregroundColor: FyrTheme.getContrastingColor(
                FyrTheme.accentColor,
              ),
            ),
            onPressed: () {
              final cmd = cmdCtrl.text.trim();
              if (cmd.isEmpty) return;
              final name = nameCtrl.text.trim().isEmpty
                  ? cmd
                  : nameCtrl.text.trim();
              final args = argsCtrl.text
                  .trim()
                  .split(RegExp(r'\s+'))
                  .where((s) => s.isNotEmpty)
                  .toList();
              Navigator.pop(
                ctx,
                McpServerConfig(
                  id: 'mcp_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  command: cmd,
                  args: args,
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    nameCtrl.dispose();
    cmdCtrl.dispose();
    argsCtrl.dispose();

    if (created != null) {
      setState(() {
        _draftConfig = _draftConfig.copyWith(
          mcpServers: [..._draftConfig.mcpServers, created],
        );
      });
    }
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: FyrTheme.accentColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: GoogleFonts.jetBrainsMono(
          color: FyrTheme.accentColor,
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Text(
        label,
        style: TextStyle(
          color: FyrTheme.textColorMuted,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: FyrTheme.textColorMuted, fontSize: 12.5),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      filled: true,
      fillColor: FyrTheme.bgColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: FyrTheme.dividerColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: FyrTheme.dividerColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: FyrTheme.accentColor),
      ),
    );
  }
}
