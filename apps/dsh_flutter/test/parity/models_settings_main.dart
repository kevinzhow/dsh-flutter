// Synthetic native replay through generated Remote calls and shared ConfigForms.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_feature_model_settings/dsh_feature_model_settings.dart';
import 'package:dsh_feature_settings/dsh_feature_settings.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

import 'helpers/models_settings_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPinnedFontsFromEnvironment();
  await WindowChrome.init();
  final dark =
      const bool.fromEnvironment('PARITY_DARK') ||
      Platform.environment['WHALEE_PLATFORM_BRIGHTNESS'] == 'dark';
  final zh =
      const String.fromEnvironment('PARITY_LOCALE') == 'zh' ||
      (Platform.environment['LC_ALL'] ?? '').startsWith('zh');
  final brightness = dark ? Brightness.dark : Brightness.light;
  final theme = resolveTheme(officialPack, ThemeSettings(), brightness);
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: brightness, extensions: [theme]),
      home: Scaffold(
        backgroundColor: theme.bgBase,
        body: SafeArea(
          child: Fixture(DshI18n(zh ? DshLocale.zh : DshLocale.en)),
        ),
      ),
    ),
  );
}

class Fixture extends StatefulWidget {
  const Fixture(this.i18n, {super.key});
  final DshI18n i18n;
  @override
  State<Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<Fixture> {
  final host = FakeHost();
  final slots = SlotRegistry();
  late final ConfigForms forms;
  late final SyntheticModelSettings fixture;
  late final ModelSettingsFeature models;
  late final void Function() offCommon, offSettings;
  bool settings = true;
  String? section;
  int revision = 0;
  @override
  void initState() {
    super.initState();
    fixture = SyntheticModelSettings(host);
    forms = ConfigForms(host.remotes);
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
    offSettings = registerSettingsFeature(
      slots,
      i18n: () => widget.i18n,
      hostVersion: () => null,
    );
    offCommon = registerCommonSettings(
      slots,
      forms: forms,
      remotes: host.remotes,
      i18n: () => widget.i18n,
    );
    models = registerModelSettingsFeature(
      slots,
      remotes: host.remotes,
      forms: forms,
      i18n: () => widget.i18n,
    );
  }

  @override
  void dispose() {
    offSettings();
    offCommon();
    unawaited(models.dispose());
    unawaited(forms.dispose().then((_) => host.close()));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Synthetic settings'),
                DshButton(
                  key: const ValueKey('fixture-open-settings'),
                  variant: DshButtonVariant.outline,
                  onPressed: () => setState(() => settings = true),
                  child: const Text('Open settings'),
                ),
                DshButton(
                  variant: DshButtonVariant.outline,
                  onPressed: () => setState(() {
                    section = 'models';
                    settings = true;
                    revision++;
                  }),
                  child: const Text('Models'),
                ),
                DshButton(
                  variant: DshButtonVariant.outline,
                  onPressed: () => setState(() {
                    section = 'general';
                    settings = true;
                    revision++;
                  }),
                  child: const Text('General'),
                ),
                DshButton(
                  variant: DshButtonVariant.outline,
                  onPressed: () => setState(() {
                    section = 'plugins';
                    settings = true;
                    revision++;
                  }),
                  child: const Text('Plugins'),
                ),
              ],
            ),
          ),
          Expanded(
            child: settings
                ? SettingsPage(
                    key: ValueKey('settings-$revision'),
                    slots: slots,
                    i18n: widget.i18n,
                    initialSection: section,
                    onClose: () => setState(() => settings = false),
                  )
                : const Center(child: Text('Settings closed')),
          ),
        ],
      ),
      ...slots.renderList(
        DshShellSlots.shellOverlay.typed<Object?, Widget>(),
        null,
      ),
      SettingsOnboarding(
        slots: slots,
        openSection: (value) => setState(() {
          section = value;
          settings = true;
          revision++;
        }),
      ),
    ],
  );
}
