import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api_provider.dart';

class SaveDialog extends StatefulWidget {
  const SaveDialog({super.key});

  @override
  State<SaveDialog> createState() => _SaveDialogState();
}

class _SaveDialogState extends State<SaveDialog> {
  final _nameController = TextEditingController();
  String? _selectedCollectionId;

  @override
  void initState() {
    super.initState();
    final api = context.read<ApiProvider>();
    if (api.collections.isNotEmpty) {
      _selectedCollectionId = api.collections.first.id;
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<ApiProvider>();

    return AlertDialog(
      title: const Text('Save Request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(hintText: 'Request Name (e.g. Login User)'),
          ),
          const SizedBox(height: 16),
          if (api.collections.isEmpty)
            const Text('No collections found. Create one in the sidebar first.')
          else
            DropdownButton<String>(
              isExpanded: true,
              value: _selectedCollectionId,
              items: api.collections.map((c) => DropdownMenuItem(
                value: c.id,
                child: Text(c.name),
              )).toList(),
              onChanged: (val) => setState(() => _selectedCollectionId = val),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: (_selectedCollectionId == null || _nameController.text.isEmpty)
              ? null
              : () {
                  api.saveRequestToCollection(_selectedCollectionId!, _nameController.text);
                  Navigator.pop(context);
                },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
