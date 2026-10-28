// Native input replay of the three real production families reported by Kevin.
// Synthetic services/data are shared with the source-comparison fixtures.
import 'dart:io' show Platform;

import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

import '../../../../features/dsh_feature_model_selection/test/parity/helpers/reported_model_fixture.dart';
import '../../../../features/dsh_feature_sidebar/test/parity/helpers/reported_sidebar_fixture.dart';

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
          child: _Scenes(DshI18n(zh ? DshLocale.zh : DshLocale.en)),
        ),
      ),
    ),
  );
}

class _Scenes extends StatefulWidget {
  const _Scenes(this.i18n);
  final DshI18n i18n;

  @override
  State<_Scenes> createState() => _ScenesState();
}

class _ScenesState extends State<_Scenes> {
  int selected = 0;
  String sidebarAction = 'none';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          children: [
            for (final (index, label) in [
              'Sidebar',
              'Statistics',
              'Model',
            ].indexed)
              DshButton(
                key: ValueKey('scene-$index'),
                onPressed: () => setState(() => selected = index),
                child: Text(label),
              ),
          ],
        ),
      ),
      Text('Sidebar action: $sidebarAction'),
      Expanded(
        child: switch (selected) {
          0 => ReportedSidebarFixture(
            i18n: widget.i18n,
            onAction: (value) => setState(() => sidebarAction = value),
          ),
          1 => _StatisticsScene(i18n: widget.i18n),
          _ => ReportedModelFixture(i18n: widget.i18n),
        },
      ),
    ],
  );
}

class _StatisticsScene extends StatelessWidget {
  const _StatisticsScene({required this.i18n});
  final DshI18n i18n;

  @override
  Widget build(BuildContext context) {
    final activity = activityPill(
      const SessionStats(
        turns: 231,
        steps: 2901,
        llmMs: 37673000,
        toolMs: 9394000,
        ttftMs: 95000,
        ttftSteps: 10,
        decodeMs: 1000,
        decodeTokens: 146,
      ),
      i18n,
    )!;
    final usage = usagePill(
      const TokenUsage(
        uncachedInputTokens: 16000,
        cacheReadTokens: 1600000000,
        outputTokens: 16000000,
      ),
      i18n,
    )!;
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ListView(
              children: [
                for (var index = 0; index < 8; index++) ...[
                  Text(
                    'Synthetic conversation behind the statistics panel $index',
                    style: context.dsh.textStyle('--dsw-font-s-14'),
                  ),
                  const SizedBox(height: 36),
                ],
              ],
            ),
          ),
        ),
        Positioned(left: 16, bottom: 20, child: StatPillView(pill: activity)),
        Positioned(right: 16, bottom: 60, child: StatPillView(pill: usage)),
      ],
    );
  }
}
