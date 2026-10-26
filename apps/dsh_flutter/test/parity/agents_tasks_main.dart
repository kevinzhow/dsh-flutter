import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_agent_management/dsh_feature_agent_management.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

import 'helpers/agents_tasks_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadPinnedFontsFromEnvironment();
  await WindowChrome.init();
  final dark =
      const bool.fromEnvironment('PARITY_DARK') ||
      Platform.environment['WHALEE_PLATFORM_BRIGHTNESS'] == 'dark';
  final theme = resolveTheme(
    officialPack,
    ThemeSettings(),
    dark ? Brightness.dark : Brightness.light,
  );
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: theme.brightness, extensions: [theme]),
      home: Scaffold(
        backgroundColor: theme.bgBase,
        body: SafeArea(child: Fixture()),
      ),
    ),
  );
}

class Fixture extends StatefulWidget {
  const Fixture({super.key});
  @override
  State<Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<Fixture> {
  final fixture = SyntheticAgentsTasks();
  final i18n = const DshI18n(DshLocale.en);
  StreamSubscription<int>? sub, presetSub;
  String page = 'Live';
  @override
  void initState() {
    super.initState();
    sub = fixture.changed.changes.listen((_) {
      if (mounted) setState(() {});
    });
    presetSub = fixture.presets.changed.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(sub?.cancel());
    unawaited(presetSub?.cancel());
    unawaited(fixture.dispose());
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
              children: [
                for (final name in ['Live', 'Presets', 'Tasks'])
                  DshButton(
                    onPressed: () => setState(() => page = name),
                    child: Text(name),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              'Preset: ${fixture.selected} · Stops: ${fixture.stops} · Updates: ${fixture.updates} · Deletes: ${fixture.deletions}',
            ),
          ),
          Expanded(
            child: switch (page) {
              'Presets' => SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: AgentPresetSection(
                  model: fixture.presets,
                  i18n: i18n,
                  startCreator: () => fixture.presets.select('cordis'),
                ),
              ),
              'Tasks' => TaskManagerPage(
                service: fixture.schedules,
                i18n: i18n,
                deviceZone: 'Asia/Tokyo',
                onNew: () => setState(() => page = 'Live'),
                onOpenSession: (_) => setState(() => page = 'Live'),
              ),
              _ => SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 24),
                    GoalBar(model: fixture.goalModel, i18n: i18n),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: JobListAction(
                          service: fixture.jobs,
                          sessionId: 'synthetic-session',
                          i18n: i18n,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: SkillRow(
                        call: ToolResult(
                          callId: 'synthetic-skill',
                          name: 'skill',
                          args: PartialArguments.fromText('{"name":"review"}'),
                          subCalls: const [],
                          seq: 10,
                          time: 1000,
                          content: const [
                            {
                              'type': 'text',
                              'text': 'Synthetic review instructions\nCheck the diff and report findings.',
                            },
                          ],
                          isError: false,
                          callArgsRaw: '{"name":"review"}',
                        ),
                        i18n: i18n,
                      ),
                    ),
                  ],
                ),
              ),
            },
          ),
        ],
      ),
      TaskDeleteNotice(service: fixture.schedules, i18n: i18n),
    ],
  );
}
