import 'package:flutter/material.dart';
import 'package:fyrtaskbar/features/quick_settings/quick_settings_controller.dart';
import 'package:fyrtaskbar/features/quick_settings/views/quick_settings_view.dart';

class QuickSettingsPopup extends StatefulWidget {
  final VoidCallback onClose;

  const QuickSettingsPopup({super.key, required this.onClose});

  @override
  State<QuickSettingsPopup> createState() => _QuickSettingsPopupState();
}

class _QuickSettingsPopupState extends State<QuickSettingsPopup>
    with SingleTickerProviderStateMixin {
  late final QuickSettingsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = QuickSettingsController(
      vsync: this,
      onClose: widget.onClose,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) =>
          QuickSettingsView(controller: _controller),
    );
  }
}
