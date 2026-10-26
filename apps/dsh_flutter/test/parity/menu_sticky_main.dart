// Native replay of the production command popup and model sheet with synthetic data.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_client/generated.dart' as session;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_commands/dsh_feature_commands.dart';
import 'package:dsh_feature_model_selection/dsh_feature_model_selection.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
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
      home: Scaffold(
        backgroundColor: theme.bgBase,
        body: const SafeArea(child: _Scenes()),
      ),
    ),
  );
}

class _Scenes extends StatefulWidget {
  const _Scenes();
  @override
  State<_Scenes> createState() => _ScenesState();
}

class _ScenesState extends State<_Scenes> {
  final popup = PopupSelectController(
    consume: (_) => false,
    focusComposer: () {},
  );
  final host = FakeHost();
  late final catalog = ModelCatalogDirectory(host.remotes);
  late final directory = ModelDirectory(
    remotes: host.remotes,
    sessionId: 'fixture',
    catalog: catalog,
    projections: ProjectionStore(),
  );
  bool models = false;

  @override
  void initState() {
    super.initState();
    popup.state.set(
      PopupState(
        open: true,
        command: 'model',
        status: PopupStatus.ready,
        options: [
          for (var g = 0; g < 2; g++)
            for (var i = 0; i < 14; i++)
              SelectOption(
                id: '$g-$i',
                label: 'Option $g-$i',
                group: SelectOptionGroup(
                  name: '$g',
                  label: g == 0 ? 'First provider' : 'Second provider',
                ),
              ),
        ],
      ),
    );
    directory.state.set(
      ModelDirectoryState(
        status: ModelDirectoryStatus.ready,
        groups: [
          for (var g = 0; g < 2; g++)
            session.ModelProviderGroup(
              id: '$g',
              name: g == 0 ? 'First provider' : 'Second provider',
              models: [
                for (var i = 0; i < 14; i++)
                  session.ModelCatalogModel(id: '$g-$i', name: 'Model $g-$i'),
              ],
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    popup.dispose();
    unawaited(() async {
      await directory.dispose();
      await catalog.dispose();
      await host.close();
    }());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            DshButton(
              onPressed: () => setState(() => models = false),
              child: const Text('Command'),
            ),
            const SizedBox(width: 8),
            DshButton(
              onPressed: () => setState(() => models = true),
              child: const Text('Models'),
            ),
          ],
        ),
      ),
      Expanded(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: SizedBox(
              width: 380,
              height: models ? 420 : 320,
              child: models
                  ? ModelSheet(
                      directory: directory,
                      i18n: const DshI18n(DshLocale.en),
                    )
                  : PopupSelectOverlay(
                      sessionId: 'fixture',
                      controller: popup,
                      i18n: const DshI18n(DshLocale.en),
                    ),
            ),
          ),
        ),
      ),
    ],
  );
}
