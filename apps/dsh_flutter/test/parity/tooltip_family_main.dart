// Native input replay of production message actions and the shared tooltip.
import 'dart:io' show Platform;

import 'package:dsh_feature_chat/src/stream/message_actions.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
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
      home: Scaffold(backgroundColor: theme.bgBase, body: const _Scenes()),
    ),
  );
}

class _Scenes extends StatefulWidget {
  const _Scenes();
  @override
  State<_Scenes> createState() => _ScenesState();
}

class _ScenesState extends State<_Scenes> {
  int activations = 0;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Stack(
      children: [
        Positioned(
          left: 40,
          top: 90,
          child: MessageActions(
            text: 'Synthetic message',
            i18n: const DshI18n(DshLocale.en),
            onBranch: () async {},
          ),
        ),
        Positioned(
          left: 40,
          top: 200,
          child: DshTooltip(
            label: 'Read details',
            shortcutKeys: const ['⌘', 'K'],
            side: DshTooltipSide.bottom,
            openOnClick: true,
            child: DshButton(
              onPressed: () => setState(() => activations++),
              child: const Text('Readable action'),
            ),
          ),
        ),
        Positioned(
          left: 40,
          top: 340,
          child: Text('Activations: $activations'),
        ),
      ],
    ),
  );
}
