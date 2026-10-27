// Native replay of the actual plugin and preset-guide tab consumers.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_feature_agent_management/dsh_feature_agent_management.dart';
import 'package:dsh_feature_plugins/dsh_feature_plugins.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

import 'helpers/agents_tasks_fixture.dart';
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
  final plugins = SyntheticPluginsPreview();
  final agents = SyntheticAgentsTasks();
  final slots = SlotRegistry();
  bool presets = false;
  static const i18n = DshI18n(DshLocale.en);

  @override
  void initState() {
    super.initState();
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
  }

  @override
  void dispose() {
    unawaited(plugins.dispose());
    unawaited(agents.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: DefaultTextStyle(
      style: context.dsh
          .textStyle('--dsw-font-s-14')
          .copyWith(color: context.dsh.labelPrimary),
      child: Column(
        children: [
          Row(
            children: [
              DshButton(
                onPressed: () => setState(() => presets = false),
                child: const Text('Plugins'),
              ),
              DshButton(
                onPressed: () => setState(() => presets = true),
                child: const Text('Presets'),
              ),
            ],
          ),
          Expanded(
            child: presets
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: AgentPresetSection(
                      model: agents.presets,
                      i18n: i18n,
                      startCreator: () {},
                    ),
                  )
                : PluginManagerPage(
                    model: plugins.manager,
                    market: plugins.market,
                    slots: slots,
                    i18n: i18n,
                  ),
          ),
        ],
      ),
    ),
  );
}
