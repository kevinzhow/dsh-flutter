// Native component replay over synthetic in-memory decisions and projections.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_feature_plan/dsh_feature_plan.dart';
import 'package:dsh_conversation/dsh_conversation.dart' show SubmittedPlan;
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/material.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';

import 'helpers/plan_fixture.dart';

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
          child: _Fixture(DshI18n(zh ? DshLocale.zh : DshLocale.en)),
        ),
      ),
    ),
  );
}

class _Fixture extends StatefulWidget {
  const _Fixture(this.i18n);
  final DshI18n i18n;
  @override
  State<_Fixture> createState() => _FixtureState();
}

class _Services extends SyntheticPlanServices {
  _Services({required this.exit, super.onOpen});
  final Future<String?> Function() exit;
  @override
  Future<String?> exitPlanMode(String sessionId) => exit();
}

class _FixtureState extends State<_Fixture> {
  final owner = testSessionOwner('native-plan');
  final slots = SlotRegistry();
  late final PlanFeature feature;
  late final _Services services;
  late PendingQuestion pending;
  int tab = 0;
  bool active = true, refuse = false;
  String outcome = '', opened = '';
  int generation = 0;
  @override
  void initState() {
    super.initState();
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
    services = _Services(
      exit: () async {
        if (refuse) return 'Synthetic refusal';
        setState(() {
          active = false;
          outcome = 'Mode off';
        });
        return null;
      },
      onOpen: (address, params) =>
          setState(() => opened = 'Opened synthetic plan'),
    );
    feature = registerPlanFeature(
      slots,
      i18n: () => widget.i18n,
      services: services,
    );
    resetReview();
  }

  void resetReview() {
    pending = PendingQuestion(
      key: 'native-review-${generation++}',
      sessionId: 'native-plan',
      questions: const [],
      callId: 'review-call',
      timed: true,
    );
    pending.setPhase(QuestionPhase.continued);
    pending.attachRpc((answers) async {
      if (refuse) throw StateError('Synthetic refusal');
      setState(() => outcome = 'Approved: ${answers.single.selected.single}');
      return true;
    });
  }

  @override
  void dispose() {
    feature.reset();
    unawaited(pending.dispose());
    unawaited(owner.conversation.dispose());
    unawaited(owner.session.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 48,
        child: Row(
          children: [
            for (final (i, label) in ['Mode', 'Review', 'Preview'].indexed)
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => tab = i),
                  child: Text(label),
                ),
              ),
          ],
        ),
      ),
      Expanded(
        child: tab == 2
            ? PlanDocument(
                plan: SubmittedPlan(
                  callId: 'plan-call',
                  title: 'Synthetic plan',
                  markdown:
                      '$syntheticPlan\n\n${List.generate(40, (i) => '## Synthetic section $i\n\nLong synthetic plan paragraph $i.').join('\n\n')}',
                ),
              )
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 748),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (tab == 0)
                            PlanChip(
                              projection: {'active': active, 'pending': false},
                              i18n: widget.i18n,
                              exitPlanMode: () =>
                                  services.exitPlanMode('native-plan'),
                            )
                          else
                            StreamBuilder(
                              stream: pending.card.changes,
                              builder: (_, _) => pending.snapshot.hidden
                                  ? const Text('Review returned to composer')
                                  : PlanReviewPanel(
                                      key: ValueKey(pending.key),
                                      pending: pending,
                                      review: syntheticReview,
                                      owner: owner,
                                      slots: slots,
                                      i18n: widget.i18n,
                                    ),
                            ),
                          Wrap(
                            children: [
                              TextButton(
                                onPressed: () => setState(() {
                                  active = true;
                                  outcome = '';
                                  feature.reset();
                                  unawaited(pending.dispose());
                                  resetReview();
                                }),
                                child: const Text('Reset'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    setState(() => refuse = !refuse),
                                child: Text(refuse ? 'Allow' : 'Refuse'),
                              ),
                            ],
                          ),
                          Text('Fixture outcome: $outcome'),
                          Text(opened),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    ],
  );
}
