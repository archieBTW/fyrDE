import 'package:flutter/material.dart';
import 'connection_wizard.dart';

/// Modal entry point for creating a new database connection via the 3-step ConnectionWizard.
class ConnectionDialog extends StatelessWidget {
  const ConnectionDialog({super.key});

  static Future<void> show(BuildContext context) {
    return ConnectionWizard.showModal(context);
  }

  @override
  Widget build(BuildContext context) {
    return const ConnectionWizard(isModal: true);
  }
}
