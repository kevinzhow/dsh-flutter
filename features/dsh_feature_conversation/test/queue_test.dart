import 'dart:async';

import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/testing.dart';
import 'package:dsh_theme/testing.dart';
import 'package:flutter/material.dart' show TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const en = DshI18n(DshLocale.en);
InboxItem row(String id, [bool attachment = false]) => InboxItem(
  id,
  [
    {'type': 'text', 'text': 'queued $id'},
    if (attachment)
      {
        'type': 'file',
        'attachment': {
          'attachmentId': 'f',
          'name': 'design.pdf',
          'bytes': 1200,
        },
      },
  ],
  const {'kind': 'user'},
);

void main() {
  testWidgets(
    'multi queue defaults collapsed; edit failure keeps text; admission removes editor',
    (t) async {
      final calls = <(String, Map<String, Object?>)>[];
      var fail = true;
      List<InboxItem> rows = [row('a'), row('b')];
      Future<void> update(String id, Map<String, Object?> action) async {
        calls.add((id, action));
        if (fail) throw StateError('refused');
      }

      Future<void> mount() => t.pumpWidget(
        dshTestApp(
          QueuePanel(rows: rows, running: true, i18n: en, updateQueue: update),
        ),
      );
      await mount();
      expect(find.byKey(const ValueKey('queue-row-a')), findsNothing);
      await t.tap(find.byKey(const ValueKey('queue-header')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('queue-edit-a')));
      await t.pump();
      await t.enterText(find.byType(EditableText), 'edited');
      await t.tap(find.byKey(const ValueKey('queue-save-a')));
      await t.pump();
      expect(find.byKey(const ValueKey('queue-error')), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        'edited',
      );
      fail = false;
      await t.tap(find.byKey(const ValueKey('queue-save-a')));
      await t.pump();
      expect(calls.last.$1, 'a');
      expect(calls.last.$2, {
        'kind': 'edit',
        'content': [
          {'type': 'text', 'text': 'edited'},
        ],
      });
      expect(find.byType(TextField), findsNothing);
      await t.tap(find.byKey(const ValueKey('queue-edit-b')));
      await t.pump();
      rows = [row('a')];
      await mount();
      await t.pump();
      expect(find.byType(TextField), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'one row and attachments; pending cannot mutate; stop disables steer; read-only has no controls',
    (t) async {
      final calls = <String>[];
      Future<void> update(String id, Map<String, Object?> action) async =>
          calls.add('${action['kind']}:$id');
      await t.pumpWidget(
        dshTestApp(
          QueuePanel(
            rows: [row('a', true)],
            running: true,
            i18n: en,
            updateQueue: update,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('queue-header')), findsNothing);
      expect(find.text('design.pdf'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('queue-edit-a')));
      await t.pump();
      expect(find.byType(TextField), findsNothing);
      await t.tap(find.byKey(const ValueKey('queue-steer-a')));
      await t.pump();
      expect(calls, ['steer:a']);
      await t.pumpWidget(
        dshTestApp(
          QueuePanel(
            rows: [row('a')],
            running: false,
            i18n: en,
            updateQueue: update,
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('queue-steer-a')));
      await t.pump();
      expect(calls.length, 1);
      await t.tap(find.byKey(const ValueKey('queue-remove-a')));
      await t.pump();
      expect(calls.last, 'remove:a');
      await t.pumpWidget(
        dshTestApp(
          QueuePanel(
            rows: const [],
            pending: [PendingSubmission('local', 'sending', DateTime(2026))],
            running: true,
            i18n: en,
            updateQueue: update,
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('queue-remove-local')));
      await t.pump();
      expect(calls.length, 2);
      await t.pumpWidget(
        dshTestApp(
          QueuePanel(
            rows: [row('a')],
            mutable: false,
            running: true,
            i18n: en,
            updateQueue: update,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('queue-remove-a')), findsNothing);
    },
  );

  testWidgets(
    'in-flight mutation locks every row and removal cannot resurrect an editor',
    (t) async {
      final gate = Completer<void>();
      Future<void> update(String id, Map<String, Object?> action) =>
          gate.future;
      await t.pumpWidget(
        dshTestApp(
          QueuePanel(
            rows: [row('a'), row('b')],
            running: true,
            i18n: en,
            updateQueue: update,
          ),
        ),
      );
      await t.tap(find.byKey(const ValueKey('queue-header')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('queue-remove-a')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('queue-edit-b')));
      await t.pump();
      expect(find.byType(TextField), findsNothing);
      await t.pumpWidget(
        dshTestApp(
          QueuePanel(
            rows: [row('b')],
            running: true,
            i18n: en,
            updateQueue: update,
          ),
        ),
      );
      gate.complete();
      await t.pump();
      expect(find.byType(TextField), findsNothing);
    },
  );

  testWidgets(
    'composer Enter, Shift Enter, Ctrl Enter, IME and empty queue gesture',
    (t) async {
      final actions = FakeActions();
      final session = Session('s', FakeTransport());
      final owner = testSessionOwner('s', actions: actions, session: session);
      final preferences = ConversationPreferences();
      addTearDown(session.dispose);
      addTearDown(preferences.dispose);
      await t.pumpWidget(
        dshTestApp(
          DefaultComposer(owner: owner, i18n: en, preferences: preferences),
        ),
      );
      await t.enterText(find.byType(EditableText), 'plain');
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(actions.sent, ['plain']);
      expect(actions.sentModes, ['queue']);
      session.handleRunning(true);
      preferences.setBusyEnter('steer');
      await t.pump();
      await t.enterText(find.byType(EditableText), 'steer');
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pump();
      expect(actions.sentModes.last, 'steer');
      await t.enterText(find.byType(EditableText), 'queue');
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      expect(actions.sentModes.last, 'queue');
      await t.enterText(find.byType(EditableText), 'newline');
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.pump();
      expect(actions.sent.length, 3);
      final controller = t
          .widget<EditableText>(find.byType(EditableText))
          .controller;
      controller.value = const TextEditingValue(
        text: 'composition',
        selection: TextSelection.collapsed(offset: 11),
        composing: TextRange(start: 0, end: 11),
      );
      await t.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await t.pump();
      expect(actions.sent.length, 3);
      await t.enterText(find.byType(EditableText), '');
      session.projections.apply('inbox', {
        'next-turn': [
          for (final id in ['a', 'b'])
            {
              'id': id,
              'source': {'kind': 'user'},
              'content': [
                {'type': 'text', 'text': id},
              ],
            },
        ],
      }, 3);
      await t.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await t.pump();
      expect(actions.queueUpdates.map((v) => v.$1), ['a', 'b']);
      expect(actions.queueUpdates.map((v) => v.$2), [
        {'kind': 'steer'},
        {'kind': 'steer'},
      ]);
      expect(actions.sent.length, 3);
    },
  );
  testWidgets('phone attachment queue and pending rows fit without overflow', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => t.binding.setSurfaceSize(null));
    for (final pending in [false, true]) {
      await t.pumpWidget(
        dshTestApp(
          Center(
            child: SizedBox(
              width: 326,
              child: QueuePanel(
                rows: pending ? [] : [row('a', true)],
                pending: pending
                    ? [
                        PendingSubmission('local', 'text', DateTime(2026), [
                          const OutgoingFile(
                            name: 'a-very-long-filename.pdf',
                            size: 12345,
                            receiptId: 'r',
                          ),
                        ]),
                      ]
                    : [],
                running: true,
                i18n: en,
                updateQueue: (_, _) async {},
              ),
            ),
          ),
        ),
      );
      await t.pump();
      expect(t.takeException(), isNull);
    }
  });
}
