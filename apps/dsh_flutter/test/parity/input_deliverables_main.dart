// Synthetic native replay; file operations remain in-memory fixture responses.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_feature_deliverables/dsh_feature_deliverables.dart';
import 'package:dsh_feature_input_trigger/dsh_feature_input_trigger.dart';
import 'package:dsh_feature_open_in_app/src/file_route_action.dart';
import 'package:dsh_feature_reference/dsh_feature_reference.dart';
import 'package:dsh_feature_secret_mask/dsh_feature_secret_mask.dart';
import 'package:dsh_flutter/src/platform/pinned_fonts.dart';
import 'package:dsh_flutter/src/platform/window_chrome.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/material.dart';

import 'helpers/deliverables_fixture.dart';

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
  final brightness = dark ? Brightness.dark : Brightness.light,
      theme = resolveTheme(
        officialPack,
        ThemeSettings(),
        dark ? Brightness.dark : Brightness.light,
      );
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
  final slots = SlotRegistry(),
      userText = UserTextRegistry(),
      client = SyntheticDeliverables(),
      enabled = Observable(true),
      draft = TextDraft(sessionId: 'fixture'),
      triggers = InputTriggerRegistry();
  late final model = DeliverablesModel(client),
      base = testSessionOwner('fixture');
  late final SessionOwner owner;
  late final ChatSnapshot snapshot;
  int tab = 0, revision = 0, index = 0;
  String status = 'Ready';
  @override
  void initState() {
    super.initState();
    owner = SessionOwner(
      session: base.session,
      conversation: base.conversation,
      actions: base.actions,
      textDraft: draft,
      cwdReader: () => '/synthetic',
    );
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
    triggers.registerSource(_Commands());
    draft.input.bind(triggers);
    registerInputTriggerFeature(slots, i18n: () => widget.i18n);
    userText.register(sessionReferenceRule);
    registerUserTextFactory(slots, userText);
    registerSentReferenceFeature(
      slots,
      userText: userText,
      i18n: () => widget.i18n,
      openFile: (_, path) => setState(() => status = 'Preview $path'),
    );
    registerSecretMaskFeature(
      slots,
      userText: userText,
      i18n: () => widget.i18n,
    );
    for (final seat in [
      DshSlots.deliverablesFileActions,
      DshSlots.deliverablesReviewFileActions,
    ]) {
      slots.register<DeliverablesFileActionsOwner, Widget>(
        seat.typed<DeliverablesFileActionsOwner, Widget>(),
        (owner) => FileRouteAction(owner: owner, i18n: widget.i18n),
        id: 'native-actions',
      );
    }
    registerDeliverablesFeature(
      slots,
      model: model,
      showCodeDiff: enabled,
      i18n: () => widget.i18n,
      openFile: (_, path) => setState(() => status = 'Preview $path'),
      openResource: (_, address, at) => setState(() {
        tab = 2;
        index = at;
        revision++;
      }),
    );
    final data = LocationDataStore()
      ..setOwned(
        'deliverables',
        'deliverables',
        DeliverablesTurnData(
          changes: const ChangesTurnData(7),
          presented: [
            for (var i = 0; i < 6; i++)
              PresentedPath(
                seq: 8,
                index: i,
                path: '/synthetic/report$i.md',
                description: 'Synthetic report (Markdown)',
              ),
          ],
        ),
      );
    snapshot = ChatSnapshot(
      order: const [],
      nodes: const {},
      timeline: ConversationTimeline(
        const [1],
        {
          1: TurnLocation(
            turn: 1,
            start: null,
            end: null,
            status: BoundaryStatus.closed,
            steps: const [],
            data: data,
          ),
        },
      ),
    );
  }

  @override
  void dispose() {
    draft.input.dispose();
    unawaited(model.dispose());
    unawaited(base.conversation.dispose());
    unawaited(userText.dispose());
    unawaited(enabled.dispose());
    super.dispose();
  }

  Widget sent(String text) => DefaultTextStyle(
    style: context.dsh
        .textStyle('--dsw-font-s-14')
        .sized(14, line: 22)
        .copyWith(color: context.dsh.labelPrimary),
    child: slots.renderSingle(
      DshSlots.conversationUserText.typed<UserTextOwner, Widget>(),
      UserTextOwner(
        text: text,
        session: owner,
        interactive: true,
        facts: const {
          'sessionLabels': ['Synthetic session'],
        },
      ),
    )!,
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(
        height: 48,
        child: Row(
          children: [
            for (final (at, label) in ['Text', 'Files', 'Review'].indexed)
              Expanded(
                child: TextButton(
                  onPressed: () => setState(() => tab = at),
                  child: Text(label),
                ),
              ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(status, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      Expanded(
        child: tab == 0
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sent(
                      'Read @src/report.dart and @docs/ with @Synthetic session.',
                    ),
                    const SizedBox(height: 16),
                    sent('Use sk-${List.filled(16, 'Q7').join()} safely.'),
                    const SizedBox(height: 16),
                    sent(
                      'Read @"src/a very long synthetic report name with spaces.dart" and keep the rest.',
                    ),
                    const Spacer(),
                    DefaultComposer(
                      owner: owner,
                      i18n: widget.i18n,
                      slots: slots,
                    ),
                  ],
                ),
              )
            : tab == 1
            ? SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        children: [
                          TextButton(
                            onPressed: () {
                              enabled.set(!enabled.value);
                              setState(
                                () => status = enabled.value
                                    ? 'Changes shown'
                                    : 'Changes hidden',
                              );
                            },
                            child: const Text('Toggle changes'),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              client.refuse = true;
                              status = 'Next native request fails';
                            }),
                            child: const Text('Fail once'),
                          ),
                        ],
                      ),
                      DeliverablesTail(
                        owner: TurnTailOwner(
                          session: owner,
                          turn: 1,
                          seq: 10,
                          snapshot: snapshot,
                        ),
                        model: model,
                        showCodeDiff: enabled,
                        slots: slots,
                        i18n: widget.i18n,
                        openFile: (path) =>
                            setState(() => status = 'Preview $path'),
                        openReview: (seq, turn, at) => setState(() {
                          tab = 2;
                          index = at;
                          revision++;
                        }),
                      ),
                    ],
                  ),
                ),
              )
            : slots.renderKeyed(
                DshSlots.sidebarRightPaneTab.typed<SidebarTabOwner, Widget>(),
                'changes-review',
                SidebarTabOwner(
                  session: owner,
                  kind: 'changes-review',
                  contentId: const ChangesReviewAddress(
                    'fixture',
                    7,
                    1,
                  ).address,
                  id: 'fixture-review',
                  revision: revision,
                  params: {'index': index},
                  actions: _TabActions(),
                ),
              )!,
      ),
    ],
  );
}

class _Commands extends InputTriggerSource {
  @override
  TriggerChar get trigger => TriggerChar.slash;
  @override
  String get name => 'command';
  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest req,
  ) async => const [
    InputTriggerCandidate(
      name: 'goal',
      label: 'Synthetic goal',
      description: 'Insert a synthetic goal command',
      icon: 'goal',
    ),
  ];
  @override
  PickOutcome? onPick(InputTriggerPick pick) => const PickInsertText('/goal ');
}

class _TabActions implements SidebarTabActions {
  @override
  void openResource(
    String address, {
    int? line,
    Map<String, Object?> params = const {},
  }) {}
  @override
  void openTab(
    String kind, {
    String? replaceTabId,
    Map<String, Object?> params = const {},
  }) {}
}
