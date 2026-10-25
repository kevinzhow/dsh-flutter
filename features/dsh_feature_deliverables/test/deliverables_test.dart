import 'dart:ui' show Tristate;

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_deliverables/dsh_feature_deliverables.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const en = DshI18n(DshLocale.en);

class FakeDeliverables implements DeliverablesClient {
  int summaryCalls = 0, diffCalls = 0;
  bool missing = false;
  final opened = <DeliveryFile>[];
  final summaryValue = ChangesSummary(
    turn: 1,
    total: 5,
    added: 5,
    deleted: 1,
    files: [
      for (var i = 0; i < 5; i++)
        ChangedFile(
          path: '/synthetic/file$i.dart',
          display: 'file$i.dart',
          added: 1,
          deleted: i == 0 ? 1 : 0,
        ),
    ],
  );
  @override
  Future<ChangesSummary> summary(
    String id,
    num seq, {
    DeliverablesCancel? cancel,
  }) async {
    summaryCalls++;
    if (missing) throw const DeliverablesHttpFailure(404);
    return summaryValue;
  }

  @override
  Future<ChangesDiff> diff(
    String id,
    num seq,
    int index, {
    DeliverablesCancel? cancel,
  }) async {
    diffCalls++;
    return ChangesDiff(
      kind: 'text',
      path: '/synthetic/file$index.dart',
      display: 'file$index.dart',
      before: true,
      after: true,
      hunks: const [
        ChangesHunk(
          oldStart: 1,
          oldLines: 1,
          newStart: 1,
          newLines: 1,
          lines: ['-old', '+new'],
        ),
      ],
    );
  }

  @override
  Future<PresentedHost> host({DeliverablesCancel? cancel}) async =>
      const PresentedHost(
        name: 'Synthetic remote',
        available: true,
        fileManager: 'finder',
      );
  @override
  Future<void> open(
    DeliveryFile file, {
    NativeFileAction action = NativeFileAction.open,
    String? application,
    DeliverablesCancel? cancel,
  }) async {
    opened.add(file);
  }

  @override
  Future<List<NativeFileApplication>> applications(
    DeliveryFile file, {
    DeliverablesCancel? cancel,
  }) async => const [];
}

class TabActions implements SidebarTabActions {
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

void main() {
  test('review resource encodes the originating session and rejects malformed coordinates', () {
    const address = ChangesReviewAddress('session /?%', 7, 2);
    final parsed = ChangesReviewAddress.parse(address.address)!;
    expect((parsed.sessionId, parsed.seq, parsed.turn), ('session /?%', 7, 2));
    for (final raw in [
      '${ChangesReviewAddress.prefix}s/-1/1',
      '${ChangesReviewAddress.prefix}%GG/7/1',
      '${ChangesReviewAddress.prefix}s/7/0',
    ]) {
      expect(ChangesReviewAddress.parse(raw), isNull);
    }
  });
  testWidgets(
    'delivery fold and changes enablement consume only announced host data',
    (t) async {
      final client = FakeDeliverables();
      final live = DeliverablesModel(client),
          owner = testSessionOwner('s1'),
          slots = SlotRegistry(),
          enabled = Observable(false);
      addTearDown(live.dispose);
      addTearDown(enabled.dispose);
      addTearDown(owner.conversation.dispose);
      for (final slot in DshSlots.all) {
        slots.declare(slot);
      }
      final locations = LocationDataStore();
      locations.setOwned(
        'deliverables',
        'deliverables',
        DeliverablesTurnData(
          changes: const ChangesTurnData(7),
          presented: [
            for (var i = 0; i < 6; i++)
              PresentedPath(
                seq: 8,
                index: i,
                path: '/synthetic/delivered$i.md',
                description: 'Document (Markdown)',
              ),
          ],
        ),
      );
      final snapshot = ChatSnapshot(
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
              data: locations,
            ),
          },
        ),
      );
      final opened = <String>[];
      await t.pumpWidget(
        dshTestApp(
          SizedBox(
            width: 700,
            child: SingleChildScrollView(
              child: DeliverablesTail(
                owner: TurnTailOwner(
                  session: owner,
                  turn: 1,
                  snapshot: snapshot,
                  seq: 10,
                ),
                model: live,
                showCodeDiff: enabled,
                slots: slots,
                i18n: en,
                openFile: opened.add,
                openReview: (_, _, _) {},
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(client.summaryCalls, 0);
      expect(find.byType(PresentedFileCard), findsNWidgets(4));
      expect(find.text('Document'), findsNWidgets(4));
      await t.tap(find.text('All 6 files'));
      await t.pumpAndSettle();
      expect(find.byType(PresentedFileCard), findsNWidgets(6));
      await t.tap(
        find.bySemanticsLabel('Preview /synthetic/delivered0.md in sidebar'),
      );
      await t.pump();
      expect(opened, ['/synthetic/delivered0.md']);
      expect(client.opened, isEmpty);
      enabled.set(true);
      await t.pumpAndSettle();
      expect(client.summaryCalls, 1);
      expect(find.byKey(const ValueKey('changed-files-card')), findsOneWidget);
      expect(find.text('file4.dart'), findsNothing);
      await t.tap(find.text('All 5 files'));
      await t.pumpAndSettle();
      expect(find.text('file4.dart'), findsOneWidget);
      enabled.set(false);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('changed-files-card')), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'review navigation keeps layout choices and never opens native files on render',
    (t) async {
      final semantics = t.ensureSemantics();
      final client = FakeDeliverables();
      final live = DeliverablesModel(client),
          session = testSessionOwner('s1'),
          slots = SlotRegistry();
      addTearDown(live.dispose);
      addTearDown(session.conversation.dispose);
      for (final slot in DshSlots.all) {
        slots.declare(slot);
      }
      registerDeliverablesFeature(
        slots,
        model: live,
        showCodeDiff: Observable(true),
        i18n: () => en,
        openFile: (_, _) {},
        openResource: (_, _, _) {},
      );
      Widget page(int revision, int index) => dshTestApp(
        SizedBox(
          width: 800,
          height: 600,
          child: slots.renderKeyed(
            DshSlots.sidebarRightPaneTab.typed<SidebarTabOwner, Widget>(),
            'changes-review',
            SidebarTabOwner(
              session: session,
              kind: 'changes-review',
              contentId: const ChangesReviewAddress('s1', 7, 1).address,
              id: 'review',
              revision: revision,
              params: {'index': index},
              actions: TabActions(),
            ),
          )!,
        ),
      );
      await t.pumpWidget(page(1, 1));
      await t.pumpAndSettle();
      expect(find.text('file1.dart'), findsOneWidget);
      expect(client.diffCalls, 1);
      expect(client.opened, isEmpty);
      await t.tap(find.bySemanticsLabel('Split view'));
      await t.pumpAndSettle();
      expect(
        t
            .getSemantics(find.bySemanticsLabel('Split view'))
            .flagsCollection
            .isToggled,
        Tristate.isTrue,
      );
      expect(
        find.byKey(const ValueKey('delivery-diff-split-false')),
        findsOneWidget,
      );
      await t.pumpWidget(page(2, 3));
      await t.pumpAndSettle();
      expect(find.text('file3.dart'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('delivery-diff-split-false')),
        findsOneWidget,
      );
      expect(client.opened, isEmpty);
      await t.pumpWidget(const SizedBox());
      semantics.dispose();
    },
  );
  test('numbered and split rows pair edits around context lines', () {
    const h = ChangesHunk(
      oldStart: 4,
      oldLines: 3,
      newStart: 8,
      newLines: 3,
      lines: [' same', '-first', '-second', '+new', ' next'],
    );
    final rows = deliveryHunkRows(h), split = deliverySplitRows(h);
    expect(rows.map((r) => (r.kind, r.old, r.fresh)), [
      ('context', 4, 8),
      ('del', 5, null),
      ('del', 6, null),
      ('add', null, 9),
      ('context', 7, 10),
    ]);
    expect(split.length, 4);
    expect(split[1].$1!.text, 'first');
    expect(split[1].$2!.text, 'new');
    expect(split[2].$2, isNull);
  });
}
