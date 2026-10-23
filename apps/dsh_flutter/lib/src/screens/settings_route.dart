import 'package:dsh_feature_settings/dsh_feature_settings.dart';
import 'package:flutter/widgets.dart';

import '../app_controller.dart';

/// The settings page as a route of the app: it follows the controller (the
/// language, the connection, the registered sections) and leaves by popping.
class SettingsRoute extends StatelessWidget {
  const SettingsRoute({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => SettingsPage(
        slots: controller.slots,
        i18n: controller.i18n,
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }
}
