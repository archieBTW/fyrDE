import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import '../api_provider.dart';
import '../fyr_theme.dart';
import 'package:intl/intl.dart';
import 'traffic_lights.dart';

class Sidebar extends StatelessWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1);

    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        border: Border(right: BorderSide(color: borderColor)),
      ),
      child: Column(
        children: [
          // Header with Traffic Lights
          DragToMoveArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: const Row(
                children: [
                  TrafficLights(),
                ],
              ),
            ),
          ),
          _buildHeader(context, isDark),
          Expanded(
            child: DefaultTabController(
              length: 3,
              child: Column(
                children: [
                  TabBar(
                    labelColor: FyrTheme.accentColor,
                    unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
                    indicatorColor: FyrTheme.accentColor,
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    tabs: const [
                      Tab(text: 'History'),
                      Tab(text: 'Collections'),
                      Tab(text: 'Env'),
                    ],
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildHistoryList(api, isDark),
                        _buildCollectionsList(api, context, isDark),
                        _buildEnvironmentEditor(api, isDark),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.folder_outlined, color: FyrTheme.accentColor, size: 20),
          const SizedBox(width: 12),
          Text(
            'Workspace',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.add, size: 20),
            onPressed: () => _showCreateCollectionDialog(context),
            tooltip: 'New Collection',
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryList(ApiProvider api, bool isDark) {
    if (api.history.isEmpty) return const Center(child: Text('No history yet', style: TextStyle(fontSize: 12)));
    return ListView.builder(
      itemCount: api.history.length,
      itemBuilder: (context, index) {
        final req = api.history[index];
        return ListTile(
          dense: true,
          leading: Text(req.method, style: TextStyle(color: _getMethodColor(req.method), fontWeight: FontWeight.bold, fontSize: 10)),
          title: Text(req.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
          subtitle: Text(DateFormat('HH:mm').format(req.timestamp), style: const TextStyle(fontSize: 10)),
          onTap: () => api.loadRequest(req),
        );
      },
    );
  }

  Widget _buildCollectionsList(ApiProvider api, BuildContext context, bool isDark) {
    if (api.collections.isEmpty) return const Center(child: Text('No collections', style: TextStyle(fontSize: 12)));
    return ListView.builder(
      itemCount: api.collections.length,
      itemBuilder: (context, index) {
        final col = api.collections[index];
        return ExpansionTile(
          dense: true,
          title: Text(col.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          children: col.requests.map((req) => ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 32, right: 16),
            leading: Text(req.method, style: TextStyle(color: _getMethodColor(req.method), fontWeight: FontWeight.bold, fontSize: 10)),
            title: Text(req.name, style: const TextStyle(fontSize: 12)),
            onTap: () => api.loadRequest(req),
          )).toList(),
        );
      },
    );
  }

  Widget _buildEnvironmentEditor(ApiProvider api, bool isDark) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: DropdownButton<int>(
            isExpanded: true,
            value: api.environments.indexOf(api.activeEnvironment),
            items: api.environments.asMap().entries.map((e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value.name, style: const TextStyle(fontSize: 12)),
            )).toList(),
            onChanged: (val) => api.setActiveEnvironment(val!),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: api.activeEnvironment.variables.length + 1,
            itemBuilder: (context, index) {
              if (index == api.activeEnvironment.variables.length) {
                return TextButton.icon(
                  onPressed: () => api.addEnvVar(api.environments.indexOf(api.activeEnvironment)),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Variable', style: TextStyle(fontSize: 12)),
                );
              }
              final v = api.activeEnvironment.variables[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: TextField(
                      decoration: const InputDecoration(hintText: 'Key', isDense: true),
                      style: const TextStyle(fontSize: 11),
                      onChanged: (val) { v.key = val; api.saveData(); },
                      controller: TextEditingController(text: v.key)..selection = TextSelection.collapsed(offset: v.key.length),
                    )),
                    const SizedBox(width: 4),
                    Expanded(child: TextField(
                      decoration: const InputDecoration(hintText: 'Value', isDense: true),
                      style: const TextStyle(fontSize: 11),
                      onChanged: (val) { v.value = val; api.saveData(); },
                      controller: TextEditingController(text: v.value)..selection = TextSelection.collapsed(offset: v.value.length),
                    )),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showCreateCollectionDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New Collection'),
        content: TextField(controller: controller, decoration: const InputDecoration(hintText: 'Collection Name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () {
            context.read<ApiProvider>().createCollection(controller.text);
            Navigator.pop(context);
          }, child: const Text('Create')),
        ],
      ),
    );
  }

  Color _getMethodColor(String method) {
    switch (method) {
      case 'GET': return Colors.greenAccent;
      case 'POST': return Colors.blueAccent;
      case 'PUT': return Colors.orangeAccent;
      case 'PATCH': return Colors.purpleAccent;
      case 'DELETE': return Colors.redAccent;
      default: return Colors.grey;
    }
  }
}
