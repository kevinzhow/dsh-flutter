import 'dart:convert';

import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_feature_workflow_run/dsh_feature_workflow_run.dart';
import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_models/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets(
    'assembled nodes render through real feature seats and workflow links require current direct-child facts',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final backend = FakeBackend();
      final AppController controller = makeController(backend);
      addTearDown(() async {
        controller.dispose();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
      });
      backend.transport.onList = () async => {
        'items': [
          listRow('s1', title: 'Synthetic parent'),
          {
            ...listRow('child-fixture', running: true),
            'parentSessionId': 's1',
            'projections': {
              'kind': 'cached',
              'asOfSeq': 0,
              'values': {
                'subagent': {'mode': 'one-shot'},
              },
            },
          },
        ],
      };
      await tester.pumpWidget(WhaleeApp(controller: controller));
      await tester.runAsync(
        () => controller.pair('http://host:18686/?token=abc'),
      );
      await settle(tester);
      await openRow(tester, 's1');
      await settle(tester);
      backend.transport.open(
        1,
        snapshot([
          rec(
            1,
            'command/run',
            data: {
              'commandId': 'goal-fixture',
              'name': 'goal',
              'args': ' Ship fixture',
            },
          ),
          rec(
            2,
            'command/done',
            data: {
              'commandId': 'goal-fixture',
              'kind': 'success',
              'text': 'Goal set',
            },
          ),
          rec(
            3,
            'user/message',
            surfaceOp: 'append',
            data: {
              'id': 'reply',
              'source': {
                'kind': 'user-question-reply',
                'callId': 'ask-fixture',
                'outcome': 'answered',
              },
              'content': [
                {
                  'type': 'text',
                  'text': jsonEncode({
                    'questions': [
                      {'id': 'q', 'question': 'Which option?'},
                    ],
                    'answers': [
                      {
                        'id': 'q',
                        'selected': ['One'],
                      },
                    ],
                  }),
                },
              ],
            },
          ),
          rec(
            4,
            'user/message',
            surfaceOp: 'append',
            data: {
              'id': 'context',
              'source': {'kind': 'fixture'},
              'content': [
                {'type': 'text', 'text': 'Hidden ordinary context'},
              ],
            },
          ),
          rec(
            5,
            'user/message',
            surfaceOp: 'append',
            data: {
              'id': 'tools',
              'source': {'kind': 'fixture'},
              'content': [
                {'type': 'tool-addition', 'toolName': 'read'},
              ],
            },
          ),
          rec(
            6,
            'tool-workflow/run-start',
            data: {'runId': 'run-fixture', 'name': 'Synthetic workflow'},
          ),
          rec(
            7,
            'tool-workflow/agent-start',
            data: {
              'runId': 'run-fixture',
              'seq': 1,
              'label': 'Read synthetic files',
              'childId': 'child-fixture',
            },
          ),
        ]),
      );
      await settle(tester);
      expect(
        find.textContaining('Ship fixture', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('One'), findsOneWidget);
      expect(find.text('Hidden ordinary context'), findsNothing);
      expect(find.byType(ContextInjectionView), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(WorkflowRunPanel),
          matching: find.text('Read synthetic files'),
        ),
      );
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byKey(const ValueKey('subagent-transcript')), findsOneWidget);
      final address = backend.transport.followRequests.last['address'] as Map;
      expect(address['kind'], 'subagent');
      expect(address['parentSessionId'], 's1');
      expect(address['childSessionId'], 'child-fixture');
      expect(address['mode'], 'one-shot');
      await tester.tap(find.byKey(const ValueKey('subagent-close')));
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.byKey(const ValueKey('subagent-transcript')), findsNothing);
      controller.manager!.handleSessionStatus('child-fixture', false);
      await settle(tester);
      final before = backend.transport.followRequests.length;
      await tester.tap(
        find.descendant(
          of: find.byType(WorkflowRunPanel),
          matching: find.text('Read synthetic files'),
        ),
      );
      await settle(tester);
      expect(find.byKey(const ValueKey('subagent-transcript')), findsNothing);
      expect(backend.transport.followRequests.length, before);
      expect(tester.takeException(), isNull);
    },
  );
}
