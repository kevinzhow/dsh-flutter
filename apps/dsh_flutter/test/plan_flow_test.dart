import 'dart:convert';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_parity/dsh_parity.dart';
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

const document =
    '# Synthetic execution plan\n\nRead the synthetic fixture.\n\n## Verify\n\nKeep the original call identity.';
Map<String, Object?> question(bool temporary) => {
  'id': 'decision',
  'question': 'Approve synthetic plan?',
  'detail': document,
  'intent': {
    'kind': 'plan-review',
    'approve': 'Start building',
    if (!temporary) 'callId': 'plan-call',
  },
  'options': [
    {'label': 'Start building'},
    {'label': 'Wait'},
  ],
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => loadParityFonts(findParityFontsManifest()));
  testWidgets(
    'plan control and review route exact request identities into shared resources',
    (t) async {
      t.view.physicalSize = const Size(1280, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final backend = FakeBackend();
      final AppController app = makeController(backend);
      addTearDown(() async {
        app.dispose();
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      });
      backend.transport.onList = () async => {
        'items': [listRow('s1', title: 'Synthetic plans')],
      };
      backend.host.handlers['commands/execute'] = (_) => {
        'commandId': 'command-plan',
        'result': {'kind': 'success'},
      };
      await t.pumpWidget(WhaleeApp(controller: app));
      await t.runAsync(() => app.pair('http://host:18686/?token=abc'));
      await settle(t);
      await openRow(t, 's1');
      await settle(t);
      backend.transport.open(
        1,
        snapshot(
          [userMessage(1, 'Earlier')],
          projections: {
            'plan': {'active': true, 'pending': false},
          },
        ),
      );
      await settle(t);
      await t.tap(find.byKey(const ValueKey('plan-chip')));
      await settle(t);
      expect(backend.host.callsTo('commands/execute').single.args, {
        'agentId': 's1',
        'line': '/plan off',
        'submittedAttachments': [],
      });
      expect(find.byKey(const ValueKey('plan-chip')), findsOneWidget);
      app.manager!.handleControlFrame({
        'type': 'projection',
        'sessionId': 's1',
        'key': 'plan',
        'seq': 2,
        'value': {'active': true, 'pending': true},
      });
      await settle(t);
      expect(find.byKey(const ValueKey('plan-chip')), findsNothing);
      var seq = 10;
      Future<void> request(String id, {bool temporary = false}) async {
        final q = question(temporary);
        app.manager!.handleControlFrame({
          'type': 'projection',
          'sessionId': 's1',
          'key': 'userQuestions',
          'seq': seq++,
          'value': {
            'active': [
              {
                'callId': id,
                'state': 'open',
                'questions': [q],
              },
            ],
            'settled': [],
          },
        });
        backend.transport.events.add(
          WaterfallEvent(
            generation: 1,
            event: 'user-questions/request',
            eventId: 'event-$id',
            agentId: 's1',
            request: {
              'questions': [q],
              'wait': {'callId': id, 'timed': true},
            },
          ),
        );
        await settle(t);
        backend.claims.last.$2.add(const Duration(minutes: 5));
        await settle(t);
      }

      await request('review-1');
      final sidebar = app.sidebar.stateFor('s1');
      expect(sidebar.expanded, true);
      expect(sidebar.active.contentId, 'dsh-resource://plan/s1/plan-call');
      expect(backend.transport.followRequests, hasLength(2));
      backend.transport.open(
        1,
        snapshot([
          rec(
            4,
            'tool/call',
            data: {
              'name': 'exit_plan_mode',
              'callId': 'plan-call',
              'arguments': jsonEncode({'plan': document}),
            },
          ),
        ], cursor: 8),
      );
      await settle(t);
      expect(find.byKey(const ValueKey('plan-document')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('plan-review-discuss')));
      await settle(t);
      expect(find.byKey(const ValueKey('composer-field')), findsOneWidget);
      expect(backend.answers, isEmpty);
      expect(app.questions.byCallId('s1', 'review-1')!.snapshot.hidden, true);
      sidebar.setExpanded(false);
      await settle(t);
      app.questions.reveal('s1', 'review-1');
      await settle(t);
      expect(sidebar.expanded, false);
      await t.tap(find.text('View full plan'));
      await settle(t);
      expect(sidebar.expanded, true);
      expect(backend.transport.followRequests, hasLength(2));
      await t.tap(find.byKey(const ValueKey('plan-review-approve')));
      await settle(t);
      expect(backend.answers.single.$1, 'event-review-1');
      expect(backend.answers.single.$2, {
        'kind': 'result',
        'value': {
          'answers': [
            {
              'id': 'decision',
              'selected': ['Start building'],
            },
          ],
        },
      });
      expect(find.byKey(const ValueKey('plan-review-approve')), findsOneWidget);
      app.manager!.handleControlFrame({
        'type': 'projection',
        'sessionId': 's1',
        'key': 'userQuestions',
        'seq': seq++,
        'value': {'active': [], 'settled': []},
      });
      await settle(t);
      expect(find.byKey(const ValueKey('plan-review-approve')), findsNothing);
      await request('review-2', temporary: true);
      expect(
        sidebar.active.contentId,
        startsWith('dsh-resource://plan-review/s1/'),
      );
      expect(sidebar.active.params['planReview'], {
        'markdown': document,
        'title': 'Synthetic execution plan',
      });
      expect(backend.transport.followRequests, hasLength(2));
      app.manager!.handleControlFrame({
        'type': 'projection',
        'sessionId': 's1',
        'key': 'userQuestions',
        'seq': seq++,
        'value': {'active': [], 'settled': []},
      });
      backend.transport.events.add(const CancelEvent('event-review-2'));
      await settle(t);
      expect(find.byKey(const ValueKey('plan-review-approve')), findsNothing);
      expect(backend.answers, hasLength(1));
      expect(t.takeException(), isNull);
    },
  );
}
