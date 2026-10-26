// Native input replay through the real font settings group and a fake host.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_feature_theme/dsh_feature_theme.dart';
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
  final form = FakeConfigForm(
    ConfigFormSnapshot(
      status: ConfigFormStatus.ready,
      value: ThemeSettings().toJson(),
      base: ThemeSettings().toJson(),
      user: const {},
      revision: 0,
      writable: true,
    ),
  );
  late final service = ThemeSettingsService(host: form);

  @override
  void dispose() {
    unawaited(service.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Column(
      children: [
        DshWatch(
          changes: service.settings.changes,
          builder: (_) => Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Saved font: ${service.current.fontFamilies[FontRole.text]}',
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 564),
              child: DshColumnEnd(
                child: FontSettingsGroup(
                  service: service,
                  i18n: const DshI18n(DshLocale.en),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
