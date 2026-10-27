// Native replay of the real shell override and agent-preset tag consumers.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_feature_agent_management/dsh_feature_agent_management.dart';
import 'package:dsh_feature_settings/dsh_feature_settings.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

import 'helpers/agents_tasks_fixture.dart';

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
  final fixture = SyntheticAgentsTasks();
  final form = FakeConfigForm(
    const ConfigFormSnapshot(
      status: ConfigFormStatus.ready,
      value: {'timeoutMs': 30000, 'maxOutputBytes': 65536},
      base: {'timeoutMs': 30000, 'maxOutputBytes': 65536},
      user: {'timeoutMs': 30000},
      revision: 1,
      writable: true,
    ),
  );
  static const i18n = DshI18n(DshLocale.en);
  bool presets = false;

  @override
  void dispose() {
    unawaited(fixture.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        Wrap(
          children: [
            DshButton(
              onPressed: () => setState(() => presets = false),
              child: const Text('Shell'),
            ),
            DshButton(
              onPressed: () => setState(() => presets = true),
              child: const Text('Presets'),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: presets
                ? AgentPresetSection(
                    model: fixture.presets,
                    i18n: i18n,
                    startCreator: () {},
                  )
                : NumberSettingsCard(
                    form: form,
                    i18n: i18n,
                    namespace: 'settings.shell',
                    title: 'title',
                    fields: const [
                      (
                        field: 'timeoutMs',
                        labelKey: 'timeoutMs',
                        hintKey: 'timeoutMsHint',
                        minimum: null,
                        invalid: null,
                      ),
                      (
                        field: 'maxOutputBytes',
                        labelKey: 'maxOutputBytes',
                        hintKey: 'maxOutputBytesHint',
                        minimum: null,
                        invalid: null,
                      ),
                    ],
                  ),
          ),
        ),
      ],
    ),
  );
}
