// Native replay of the real plugin-manager bundle switch with a fake host.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_feature_plugins/dsh_feature_plugins.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

import 'helpers/plugins_preview_fixture.dart';

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
  final fixture = SyntheticPluginsPreview();
  final slots = SlotRegistry();

  @override
  void initState() {
    super.initState();
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
  }

  @override
  void dispose() {
    unawaited(fixture.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Locked switch'),
              SizedBox(width: 12),
              DshSwitch(label: 'Locked switch', value: true, onChanged: null),
            ],
          ),
        ),
        Expanded(
          child: PluginManagerPage(
            model: fixture.manager,
            market: fixture.market,
            slots: slots,
            i18n: const DshI18n(DshLocale.en),
          ),
        ),
      ],
    ),
  );
}
