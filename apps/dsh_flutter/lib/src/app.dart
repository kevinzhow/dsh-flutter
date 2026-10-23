import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/material.dart';

import 'debug_controller.dart';
import 'debug_screen.dart';

/// Composition root widget: resolves the official theme pack under the user's
/// settings and hands the contract to every component through a ThemeExtension.
class DshApp extends StatelessWidget {
  const DshApp({super.key, required this.controller});

  final DebugController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final platform =
            MediaQuery.maybePlatformBrightnessOf(context) ??
            WidgetsBinding.instance.platformDispatcher.platformBrightness;
        final dsh = resolveTheme(
          officialPack,
          controller.themeSettings,
          platform,
        );
        return MaterialApp(
          title: 'DSH (unofficial client)',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(brightness: dsh.brightness, extensions: [dsh]),
          home: DebugScreen(controller: controller),
        );
      },
    );
  }
}
