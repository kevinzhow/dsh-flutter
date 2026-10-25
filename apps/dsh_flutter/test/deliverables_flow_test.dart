import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/testing.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump(const Duration(milliseconds: 100));
  }
}

List<Map<String, Object?>> log() => [
  userMessage(1, 'Write a synthetic report.'),
  rec(2, 'turn/start', data: {'turn': 1}),
  rec(3, 'step/start', data: {'turn': 1, 'step': 1}),
  rec(
    4,
    'tool/call',
    data: {
      'turn': 1,
      'step': 1,
      'callId': 'write',
      'name': 'write',
      'arguments': jsonEncode({
        'file_path': 'report.md',
        'content': 'Synthetic report',
      }),
    },
  ),
  rec(
    5,
    'tool/result',
    surfaceOp: 'append',
    data: {
      'turn': 1,
      'step': 1,
      'meta': {'path': '/synthetic/report.md'},
      'message': {
        'role': 'tool',
        'source': {'callId': 'write'},
        'content': <Object?>[],
        'isError': false,
      },
    },
  ),
  rec(
    6,
    'deliverables/presented',
    data: {
      'turn': 1,
      'callId': 'present',
      'files': [
        null,
        {
          'path': '/synthetic/report.md',
          'description': 'Synthetic report (Markdown)',
        },
      ],
    },
  ),
  rec(7, 'workspace/changes', data: {'turn': 1}),
  rec(
    8,
    'assistant/message',
    surfaceOp: 'append',
    data: {
      'turn': 1,
      'step': 1,
      'message': {
        'id': 'answer',
        'role': 'assistant',
        'content': [
          {
            'type': 'text',
            'text': 'Saved `report.md`. Unknown `other.md` stays plain.',
          },
        ],
      },
      'stream': <Object?>[],
    },
  ),
  rec(9, 'step/end', data: {'turn': 1, 'step': 1}),
  rec(
    10,
    'turn/end',
    data: {
      'turn': 1,
      'reason': {'kind': 'completed'},
    },
  ),
];
void main() {
  setUpAll(() => loadParityFonts(findParityFontsManifest()));
  testWidgets(
    'closing files, native actions and Review retain the originating session coordinates',
    (t) async {
      t.view.physicalSize = const Size(1280, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final backend = FakeBackend();
      final controller = makeController(backend);
      var disposed = false;
      addTearDown(() {
        if (!disposed) controller.dispose();
      });
      backend.transport.onList = () async => {
        'items': [
          listRow('s1', title: 'First synthetic session'),
          listRow('s2', title: 'Second synthetic session'),
        ],
      };
      backend.deliverables.summaries['s1:7'] = const ChangesSummary(
        turn: 1,
        total: 1,
        added: 1,
        deleted: 0,
        files: [
          ChangedFile(
            path: '/synthetic/report.md',
            display: 'report.md',
            added: 1,
            deleted: 0,
          ),
        ],
      );
      backend.deliverables.diffs['s1:7:0'] = const ChangesDiff(
        kind: 'text',
        path: '/synthetic/report.md',
        display: 'report.md',
        after: true,
        hunks: [
          ChangesHunk(
            oldStart: 0,
            oldLines: 0,
            newStart: 1,
            newLines: 1,
            lines: ['+Synthetic report'],
          ),
        ],
      );
      await t.pumpWidget(WhaleeApp(controller: controller));
      await t.runAsync(() => controller.pair('http://host:18686/?token=abc'));
      await settle(t);
      await openRow(t, 's1');
      await settle(t);
      backend.transport.open(1, snapshot(log()));
      await settle(t);
      controller.developerTools.enabled.set(true);
      await settle(t);
      expect(find.byKey(const ValueKey('changed-files-card')), findsOneWidget);
      expect(backend.deliverables.opened, isEmpty);
      final inspected = controller.openSession!.owner;
      final answer = inspected.conversation.chat.value.visibleNodes.firstWhere(
        (n) => n.data is AssistantData,
      );
      expect(
        controller.deliverables.mention(
          ChatNodeOwner(
            session: inspected,
            node: answer,
            snapshot: inspected.conversation.chat.value,
          ),
          'report.md',
          controller.i18n,
        ),
        isNotNull,
      );
      final md = t
          .widgetList<DshMarkdown>(find.byType(DshMarkdown))
          .where((m) => m.data.contains('Unknown'))
          .single;
      expect(md.fileMentions, isNotNull);
      expect(md.fileMentions!('report.md'), isNotNull);
      final closingMention = find.byWidgetPredicate(
        (w) =>
            w is Semantics &&
            w.properties.label == 'Open /synthetic/report.md in sidebar',
      );
      expect(closingMention, findsOneWidget);
      expect(find.bySemanticsLabel('Open other.md in sidebar'), findsNothing);
      // The default association fixture has no apps, so the primary gesture
      // reveals on the remote Host using the original, unfiltered file index.
      await t.tap(find.bySemanticsLabel('Show file location').first);
      await settle(t);
      expect(backend.deliverables.opened.single.sessionId, 's1');
      expect(backend.deliverables.opened.single.index, 1);
      expect(backend.deliverables.opened.single.seq, 6);
      await t.tap(find.byKey(const ValueKey('changed-files-card')));
      await settle(t);
      final review = controller.sidebar.stateFor('s1').active;
      expect(review.kind, 'changes-review');
      expect(review.contentId, 'dsh-resource://changes-review/session/s1/7/1');
      final first = controller.openSession!.owner;
      final node = first.conversation.chat.value.visibleNodes.firstWhere(
        (n) => n.data is AssistantData,
      );
      final mention = controller.deliverables.mention(
        ChatNodeOwner(
          session: first,
          node: node,
          snapshot: first.conversation.chat.value,
        ),
        'report.md',
        controller.i18n,
      )!;
      await openRow(t, 's2');
      await settle(t);
      mention.open();
      await settle(t);
      expect(controller.openSessionId, 's2');
      expect(
        controller.sidebar
            .stateFor('s1')
            .tabs
            .any((tab) => tab.contentId.contains('/session/s1/')),
        isTrue,
      );
      expect(
        controller.sidebar
            .stateFor('s2')
            .tabs
            .where((tab) => tab.contentId.contains('/session/s1/')),
        isEmpty,
      );
      // Exercise the inline-code renderer independently of the retained chat's
      // scroll window; only resolved tokens become buttons.
      await t.pumpWidget(
        dshTestApp(
          DshMarkdown(
            '`report.md` and `other.md`',
            fileMentions: (value) => value == 'report.md'
                ? DshMarkdownFileMention(
                    title: mention.title,
                    label: mention.label,
                    open: mention.open,
                  )
                : null,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == mention.label,
        ),
      );
      await t.pumpAndSettle();
      expect(controller.openSessionId, 's2');
      await t.pumpWidget(const SizedBox());
      await t.pump();
      controller.dispose();
      disposed = true;
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );
}
