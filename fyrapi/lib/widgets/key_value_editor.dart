import 'package:flutter/material.dart';
import '../api_provider.dart';
import '../fyr_theme.dart';

class KeyValueEditor extends StatelessWidget {
  final List<KeyValue> items;
  final VoidCallback onAdd;
  final Function(int) onRemove;
  final String keyLabel;
  final String valueLabel;

  const KeyValueEditor({
    super.key,
    required this.items,
    required this.onAdd,
    required this.onRemove,
    this.keyLabel = 'Key',
    this.valueLabel = 'Value',
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: items.length + 1,
      itemBuilder: (context, index) {
        if (index == items.length) {
          return Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Add Row'),
              style: TextButton.styleFrom(
                foregroundColor: FyrTheme.accentColor,
              ),
            ),
          );
        }

        final item = items[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            children: [
              Checkbox(
                value: item.enabled,
                onChanged: (val) {
                  item.enabled = val ?? true;
                  (context as Element).markNeedsBuild();
                },
                activeColor: FyrTheme.accentColor,
              ),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: keyLabel,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (val) => item.key = val,
                  controller: TextEditingController(text: item.key)
                    ..selection = TextSelection.collapsed(offset: item.key.length),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: valueLabel,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (val) => item.value = val,
                  controller: TextEditingController(text: item.value)
                    ..selection = TextSelection.collapsed(offset: item.value.length),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => onRemove(index),
                color: Colors.redAccent.withOpacity(0.7),
              ),
            ],
          ),
        );
      },
    );
  }
}
