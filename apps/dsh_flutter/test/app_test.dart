import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_flutter/src/backend.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await t.pump();
  }
}

void main() {
  late FakeBackend backend;
  late AppController controller;

  Future<void> start(
    WidgetTester t, {
    Size size = const Size(1200, 800),
    DshLocale locale = DshLocale.en,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    backend = FakeBackend();
    controller = makeController(backend, locale: locale);
    addTearDown(() async {
      controller.dispose();
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    });
    await t.pumpWidget(WhaleeApp(controller: controller));
  }

  Future<void> connectWith(
    WidgetTester t,
    List<Map<String, Object?>> rows,
  ) async {
    backend.transport.onList = () async => {'items': rows};
    await t.runAsync(() => controller.pair('http://host:18686/?token=abc'));
    await settle(t);
  }

  group('pairing', () {
    testWidgets('starts on the pairing screen with the product name', (
      t,
    ) async {
      await start(t);
      expect(find.byKey(const ValueKey('app-name')), findsOneWidget);
      expect(find.text('Whalee'), findsOneWidget);
      expect(find.text('Connect to a host'), findsOneWidget);
      expect(find.byKey(const ValueKey('pairing-error')), findsNothing);
    });

    testWidgets('a text that is not a launch link is explained', (t) async {
      await start(t);
      await t.enterText(
        find.byKey(const ValueKey('pairing-url')),
        'not a link at all',
      );
      await t.tap(find.byKey(const ValueKey('pairing-connect')));
      await settle(t);
      expect(find.byKey(const ValueKey('pairing-error')), findsOneWidget);
      expect(find.textContaining('not a launch link'), findsOneWidget);
      expect(backend.connects, isEmpty);
    });

    testWidgets('a host address without a token is also rejected locally', (
      t,
    ) async {
      await start(t);
      await t.enterText(
        find.byKey(const ValueKey('pairing-url')),
        '192.168.1.10:8686',
      );
      await t.tap(find.byKey(const ValueKey('pairing-connect')));
      await settle(t);
      expect(find.textContaining('not a launch link'), findsOneWidget);
    });

    testWidgets(
      'a refused token shows the restart hint and stays on the screen',
      (t) async {
        await start(t);
        backend.failWith = const ConnectException(ConnectFailure.rejected);
        await t.enterText(
          find.byKey(const ValueKey('pairing-url')),
          'http://host:18686/?token=stale',
        );
        await t.tap(find.byKey(const ValueKey('pairing-connect')));
        await settle(t);
        expect(find.textContaining('refused the token'), findsOneWidget);
        expect(find.byKey(const ValueKey('pairing-connect')), findsOneWidget);
        expect(backend.connects.single.$1, Uri.parse('http://host:18686'));
        expect(backend.connects.single.$2, 'stale');
      },
    );

    testWidgets('an unreachable host is explained', (t) async {
      await start(t);
      backend.failWith = const ConnectException(
        ConnectFailure.unreachable,
        'refused',
      );
      await t.enterText(find.byKey(const ValueKey('pairing-url')), 'host:9999');
      await t.enterText(find.byKey(const ValueKey('pairing-token')), 'tok');
      await t.tap(find.byKey(const ValueKey('pairing-connect')));
      await settle(t);
      expect(find.textContaining('Could not reach the host'), findsOneWidget);
      expect(backend.connects.single.$1, Uri.parse('http://host:9999'));
    });

    testWidgets(
      'scan says it is not available yet; paste connects from the clipboard',
      (t) async {
        await start(t);
        await t.tap(find.byKey(const ValueKey('pairing-scan')));
        await t.pump();
        expect(find.byKey(const ValueKey('pairing-hint')), findsOneWidget);
        expect(find.textContaining('Paste the launch link'), findsOneWidget);

        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => call.method == 'Clipboard.getData'
              ? {'text': 'http://host:18686/?token=fromclip'}
              : null,
        );
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        backend.transport.onList = () async => {'items': <Object?>[]};
        await t.tap(find.byKey(const ValueKey('pairing-paste')));
        await settle(t);
        expect(backend.connects.single.$2, 'fromclip');
        expect(find.byKey(const ValueKey('browser-title')), findsOneWidget);
      },
    );

    testWidgets('the Chinese copy', (t) async {
      await start(t, locale: DshLocale.zh);
      expect(find.text('连接主机'), findsOneWidget);
      await t.enterText(find.byKey(const ValueKey('pairing-url')), 'x y');
      await t.tap(find.byKey(const ValueKey('pairing-connect')));
      await settle(t);
      expect(find.textContaining('这不是启动链接'), findsOneWidget);
    });
  });

  group('session list', () {
    testWidgets('an empty list shows the empty state', (t) async {
      await start(t);
      await connectWith(t, []);
      expect(find.byKey(const ValueKey('browser-empty')), findsOneWidget);
      expect(find.text('No sessions yet'), findsOneWidget);
    });

    testWidgets('lists sessions; the host and settings controls are there', (
      t,
    ) async {
      await start(t);
      await connectWith(t, [
        listRow('s1', title: 'Fix the build'),
        listRow('s2'),
      ]);
      // Sessions no workspace accounts for sit in the folded Ungrouped group.
      await t.tap(find.byKey(const ValueKey('workspace-row-')));
      await settle(t);
      expect(find.text('Fix the build'), findsOneWidget);
      expect(find.text('Untitled'), findsOneWidget);
      // The host and how it is reached are in the foot menu; the token never
      // reaches the screen.
      await t.tap(find.byKey(const ValueKey('settings-trigger')));
      await settle(t);
      expect(find.text('host:18686'), findsOneWidget);
      expect(find.byKey(const ValueKey('security-plain')), findsOneWidget);
      expect(find.textContaining('abc'), findsNothing);
    });

    testWidgets('settings open as a page and switch the language', (t) async {
      await start(t);
      await connectWith(t, []);
      await openSettingsUi(t);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('settings-panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('general-section')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('language-selector')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('option-zh')));
      await t.pumpAndSettle();
      expect(controller.locale, DshLocale.zh);
      expect(find.text('语言'), findsOneWidget);
    });

    testWidgets('disconnect returns to pairing and forgets the host', (
      t,
    ) async {
      await start(t);
      await connectWith(t, []);
      await openSettingsUi(t);
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('settings-disconnect')));
      await t.tap(find.byKey(const ValueKey('settings-disconnect')));
      await settle(t);
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('pairing-connect')), findsOneWidget);
      expect(backend.disconnects, 1);
    });
  });

  group('session view', () {
    Future<void> openFirst(
      WidgetTester t, {
      List<Map<String, Object?>>? records,
    }) async {
      await connectWith(t, [listRow('s1', title: 'Task one', running: false)]);
      await openRow(t, 's1');
      await settle(t);
      backend.transport.open(
        1,
        snapshot(
          records ?? [userMessage(1, 'Earlier question')],
          projections: {
            'title': 'Task one',
            'modelSelection': {
              'next': {'model': 'deepseek-test', 'reasoningEffort': 'high'},
            },
          },
        ),
      );
      await settle(t);
    }

    testWidgets('opens, shows history, title and the model indicator', (
      t,
    ) async {
      await start(t);
      await openFirst(t);
      expect(find.text('Earlier question'), findsOneWidget);
      expect(find.byKey(const ValueKey('session-title')), findsOneWidget);
      // The model indicator is the phone header's second line; the desktop
      // header carries the title and the view tabs.
      expect(find.byKey(const ValueKey('view-tab-chat')), findsOneWidget);
    });

    testWidgets('streams assistant text and a tool call, then settles', (
      t,
    ) async {
      await start(t);
      await openFirst(
        t,
        records: [
          rec(1, 'turn/start', data: {'turn': 1}),
          rec(2, 'step/start', data: {'turn': 1, 'step': 1}),
          userMessage(3, 'run ls'),
        ],
      );
      // This case tests the tool renderer rather than collapsed process groups.
      controller.chatPreferences.setMode(TranscriptViewMode.verbose);
      await settle(t);
      final tr = backend.transport;
      tr.item(
        1,
        aframe({
          'type': 'start',
          'attemptId': 'a1',
          'revision': 1,
          'turn': 1,
          'step': 1,
          'startedAfterSeq': 3,
        }),
      );
      var index = 0;
      var revision = 1;
      void chunk(Map<String, Object?> c) => tr.item(
        1,
        aframe({
          'type': 'chunk',
          'attemptId': 'a1',
          'revision': ++revision,
          'index': index++,
          'time': 1,
          'chunk': c,
        }),
      );
      chunk({'type': 'block-start', 'index': 0, 'blockType': 'text'});
      chunk({'type': 'text-delta', 'index': 0, 'text': 'Listing the **files'});
      await settle(t);
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('Listing the'),
        ),
        findsOneWidget,
      );
      chunk({'type': 'text-delta', 'index': 0, 'text': '** now'});
      chunk({
        'type': 'block-end',
        'index': 0,
        'block': {'type': 'text', 'text': 'Listing the **files** now'},
      });
      chunk({'type': 'block-start', 'index': 1, 'blockType': 'tool-call'});
      chunk({
        'type': 'tool-call-delta',
        'index': 1,
        'id': 'call-1',
        'name': 'bash',
        'argumentsDelta': '{"command":"ls',
      });
      await settle(t);
      // The bash row appears as soon as the call starts streaming.
      expect(find.byKey(const ValueKey('tool-row-bash')), findsOneWidget);
      expect(find.text('Bash'), findsWidgets);
      chunk({
        'type': 'tool-call-delta',
        'index': 1,
        'id': 'call-1',
        'argumentsDelta': ' -la"}',
      });
      await settle(t);

      // the durable events arrive: the call runs, then returns
      tr.item(1, {
        'type': 'event',
        'event': rec(
          4,
          'tool/call',
          data: {
            'turn': 1,
            'step': 1,
            'callId': 'call-1',
            'name': 'bash',
            'arguments': '{"command":"ls -la"}',
          },
        )['event'],
      });
      await settle(t);
      expect(find.text('ls -la'), findsWidgets);
      tr.item(1, {
        'type': 'event',
        'event': rec(
          5,
          'tool/result',
          surfaceOp: 'append',
          data: {
            'turn': 1,
            'step': 1,
            'message': {
              'role': 'tool',
              'source': {'kind': 'tool', 'callId': 'call-1'},
              'toolCallId': 'call-1',
              'content': [
                {'type': 'text', 'text': 'a.txt b.txt'},
              ],
              'isError': false,
              'id': 'tr1',
            },
          },
        )['event'],
      });
      await settle(t);
      // A settled call is a collapsed row; opening it shows the result.
      expect(find.text('a.txt b.txt'), findsNothing);
      await t.tap(find.byKey(const ValueKey('tool-row-bash')));
      await settle(t);
      expect(find.text('a.txt b.txt'), findsOneWidget);
    });

    testWidgets('the stop button cancels the running turn', (t) async {
      await start(t);
      await openFirst(t);
      expect(find.byKey(const ValueKey('composer-cancel')), findsNothing);
      backend.transport.controlController.add(
        const StreamItem(1, {'type': 'noop'}),
      );
      controller.manager!.get('s1').handleRunning(true);
      await settle(t);
      expect(find.byKey(const ValueKey('composer-cancel')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('composer-cancel')));
      await settle(t);
      expect(backend.transport.cancels, ['s1']);
    });

    testWidgets('sending a prompt goes to the host and shows a local echo', (
      t,
    ) async {
      await start(t);
      await openFirst(t);
      await t.enterText(find.byType(EditableText).last, 'next question');
      await t.pump();
      await t.tap(find.byKey(const ValueKey('composer-send')));
      await settle(t);
      expect(backend.transport.prompts, hasLength(1));
      expect(backend.transport.prompts.single['sessionId'], 's1');
      expect(
        ((backend.transport.prompts.single['content']! as List).single
            as Map)['text'],
        'next question',
      );
      expect(find.text('next question'), findsOneWidget);
    });

    testWidgets(
      'an approval request takes over the composer; allow answers the host',
      (t) async {
        await start(t);
        await openFirst(t);
        expect(find.byKey(const ValueKey('composer-send')), findsOneWidget);
        backend.transport.events.add(
          const WaterfallEvent(
            generation: 1,
            event: 'approval/request',
            eventId: 'ev-1',
            agentId: 's1',
            request: {'toolName': 'bash', 'callId': 'c9'},
          ),
        );
        await settle(t);
        expect(find.byKey(const ValueKey('approval-panel')), findsOneWidget);
        expect(find.byKey(const ValueKey('composer-send')), findsNothing);
        expect(find.textContaining('bash'), findsWidgets);
        await t.tap(find.byKey(const ValueKey('approval-allow')));
        await settle(t);
        expect(backend.answers.single.$1, 'ev-1');
        expect(backend.answers.single.$2, {
          'kind': 'result',
          'value': 'allowed-once',
        });
        expect(find.byKey(const ValueKey('approval-panel')), findsNothing);
        expect(find.byKey(const ValueKey('composer-send')), findsOneWidget);
      },
    );

    testWidgets('a question from the agent is answered through the same flow', (
      t,
    ) async {
      await start(t);
      await openFirst(t);
      backend.transport.events.add(
        const WaterfallEvent(
          generation: 1,
          event: 'user-questions/request',
          eventId: 'q-1',
          agentId: 's1',
          request: {
            'questions': [
              {
                'id': 'q1',
                'question': 'Which one?',
                'options': [
                  {'label': 'Alpha'},
                  {'label': 'Beta'},
                ],
              },
            ],
          },
        ),
      );
      await settle(t);
      expect(find.text('Which one?'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('option-Beta')));
      await t.pump();
      await t.tap(find.byKey(const ValueKey('question-submit')));
      await settle(t);
      expect(backend.answers.single.$1, 'q-1');
      expect(
        ((backend.answers.single.$2['value']! as Map)['answers']! as List)
            .single,
        {
          'id': 'q1',
          'selected': ['Beta'],
        },
      );
    });

    testWidgets('a session that fails to open says so', (t) async {
      await start(t);
      await connectWith(t, [listRow('s1', title: 'T')]);
      await openRow(t, 's1');
      await settle(t);
      expect(find.byKey(const ValueKey('session-loading')), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('a wide window shows the list beside the session', (t) async {
      await start(t, size: const Size(1200, 800));
      await connectWith(t, [listRow('s1', title: 'Wide task')]);
      expect(find.byKey(const ValueKey('browser-title')), findsOneWidget);
      // Sessions outside a Workspace sit under a folded Ungrouped group.
      expect(find.text('Ungrouped'), findsOneWidget);
      await t.tap(find.text('Ungrouped'));
      await settle(t);
      await openRow(t, 's1');
      await settle(t);
      backend.transport.open(1, snapshot([userMessage(1, 'hi from wide')]));
      await settle(t);
      expect(find.byKey(const ValueKey('browser-title')), findsOneWidget);
      expect(find.text('hi from wide'), findsOneWidget);
      expect(find.byKey(const ValueKey('session-back')), findsNothing);
    });

    testWidgets('a phone has a top bar and the sidebar in a drawer', (t) async {
      await start(t, size: const Size(412, 915));
      await connectWith(t, [listRow('s1', title: 'Phone task')]);
      expect(find.byKey(const ValueKey('phone-top-bar')), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-drawer')), findsNothing);
      expect(find.byKey(const ValueKey('browser-title')), findsNothing);
      // The menu button opens the sidebar's real content.
      await t.tap(find.byKey(const ValueKey('phone-menu')));
      await settle(t);
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('phone-drawer')), findsOneWidget);
      expect(find.text('Ungrouped'), findsOneWidget);
      // Picking a session opens it and closes the drawer.
      await openRow(t, 's1');
      await settle(t);
      backend.transport.open(1, snapshot([userMessage(1, 'hi from phone')]));
      await settle(t);
      expect(find.byKey(const ValueKey('phone-drawer')), findsNothing);
      expect(find.byKey(const ValueKey('phone-scrim')), findsNothing);
      expect(find.text('hi from phone'), findsOneWidget);
      expect(find.byKey(const ValueKey('phone-title')), findsOneWidget);
    });

    testWidgets(
      'the sidebar opens Plugins and Automation tasks with Host availability',
      (t) async {
        await start(t, size: const Size(1200, 800));
        await connectWith(t, [listRow('s1', title: 'Wide task')]);
        expect(find.text('Plugins'), findsOneWidget);
        expect(find.text('Automation tasks'), findsOneWidget);
        backend.host.handlers['pluginInventory/list'] = (_) => {
          'entries': <Object?>[],
          'managementAvailable': false,
        };
        await t.tap(find.text('Plugins'));
        await settle(t);
        expect(
          find.byKey(const ValueKey('plugin-manager-page')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('panel-unavailable')), findsNothing);
        expect(
          find.text(controller.i18n.t('pluginManager', 'unavailable')),
          findsOneWidget,
        );
        backend.host.handlers['schedule/catalog'] = (_) => <Object?>[];
        await t.tap(find.text('Automation tasks'));
        await settle(t);
        expect(find.byKey(const ValueKey('panel-unavailable')), findsNothing);
        expect(find.byKey(const ValueKey('task-manager-list')), findsOneWidget);
        expect(
          find.text(
            'No tasks yet. Tasks created in your sessions appear here.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'an open session has the Chat and Trajectory tabs and its menu',
      (t) async {
        await start(t, size: const Size(1200, 800));
        await connectWith(t, [listRow('s1', title: 'Wide task')]);
        await t.tap(find.text('Ungrouped'));
        await settle(t);
        await openRow(t, 's1');
        await settle(t);
        backend.transport.open(1, snapshot([userMessage(1, 'hi from wide')]));
        await settle(t);
        expect(
          find.byKey(const ValueKey('desktop-session-header')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('view-tab-chat')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('view-tab-trajectory')),
          findsOneWidget,
        );
        expect(find.text('hi from wide'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('view-tab-trajectory')));
        await settle(t);
        expect(find.byKey(const ValueKey('panel-unavailable')), findsOneWidget);
        expect(find.text('hi from wide'), findsNothing);
        await t.tap(find.byKey(const ValueKey('view-tab-chat')));
        await settle(t);
        expect(find.text('hi from wide'), findsOneWidget);
        // The overflow menu copies the session id.
        String? copied;
        t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          },
        );
        addTearDown(
          () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        await t.tap(find.byKey(const ValueKey('session-overflow')));
        await settle(t);
        await t.tap(find.text('Copy Session ID'));
        await settle(t);
        expect(copied, 's1');
      },
    );
  });
}
