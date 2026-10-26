// Native replay of the shared checkbox and the real risk confirmation dialog.
import 'dart:io' show Platform;

import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPinnedFontsFromEnvironment();
  await WindowChrome.init();
  final brightness =
      Platform.environment['WHALEE_PLATFORM_BRIGHTNESS'] == 'dark'
      ? Brightness.dark
      : Brightness.light;
  final theme = resolveTheme(officialPack, ThemeSettings(), brightness);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: brightness, extensions: [theme]),
      home: Scaffold(backgroundColor: theme.bgBase, body: const _Scene()),
    ),
  );
}

class _Scene extends StatefulWidget {
  const _Scene();
  @override
  State<_Scene> createState() => _SceneState();
}

class _SceneState extends State<_Scene> {
  bool image = false;
  String result = 'No decision';

  Future<void> openRisk() async {
    final confirmed = await showDshRiskDialog(
      context,
      title: 'Enable Full access?',
      description: 'Review the synthetic risks before continuing.',
      acknowledgeLabel: 'I understand the risks and want to continue',
      cancelLabel: 'Cancel',
      closeLabel: 'Close',
      confirmLabel: 'Enable Full access',
    );
    if (mounted) setState(() => result = confirmed ? 'Confirmed' : 'Canceled');
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DshCheckbox(
            value: image,
            onChanged: (next) => setState(() => image = next),
            label: 'Images',
          ),
          const SizedBox(height: 20),
          const DshCheckbox(
            value: true,
            onChanged: null,
            label: 'Locked selection',
          ),
          const SizedBox(height: 20),
          DshButton(
            onPressed: openRisk,
            child: const Text('Open risk confirmation'),
          ),
          const SizedBox(height: 20),
          Text('Decision: $result'),
        ],
      ),
    ),
  );
}
