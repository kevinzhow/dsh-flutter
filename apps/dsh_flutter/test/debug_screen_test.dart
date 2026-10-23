import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_flutter/src/app.dart';
import 'package:dsh_flutter/src/backend.dart';
import 'package:dsh_flutter/src/debug_controller.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted transport: serves one session list, one follow stream, records
/// prompts. Synthetic data only.
class FakeTransport implements SessionTransport {
  final follows = <StreamController<GenerationFrame>>[];
  final events = StreamController<HostEvent>.broadcast(sync: true);
  final prompts = <Map<String, Object?>>[];
  var cancels = 0;

  @override
  Future<Map<String, Object?>> list() async => {
    'items': [
      {
        'sessionId': 's1',
        'updatedAt': 1,
        'agentAvailable': true,
        'running': false,
        'blank': false,
        'projections': {
          'kind': 'sequenced',
          'asOfSeq': 3,
          'values': {'title': 'First session'},
        },
      },
    ],
  };

  @override
  Future<Map<String, Object?>> create(Map<String, Object?> request) async => {
    'sessionId': 's2',
  };
  @override
  Future<void> prompt(Map<String, Object?> request) async =>
      prompts.add(request);
  @override
  Future<void> cancel(String sessionId) async => cancels++;
  @override
  Future<Map<String, Object?>> page(Map<String, Object?> request) async => {
    'records': <Object?>[],
    'hasMore': false,
  };
  @override
  Stream<GenerationFrame> follow(Map<String, Object?> Function() request) {
    final c = StreamController<GenerationFrame>();
    follows.add(c);
    return c.stream;
  }

  @override
  Stream<GenerationFrame> control() => const Stream.empty();
  @override
  Stream<HostEvent> get hostEvents => events.stream;
  @override
  Stream<ConnectionGeneration?> get generations => const Stream.empty();
  @override
  ConnectionGeneration? get generation => null;
}

class FakeBackend implements DebugBackend {
  FakeBackend(this.transport);
  final FakeTransport transport;
  final statusController = StreamController<String>.broadcast();
  final answers = <(String, Object?)>[];
  String? seenUrl;
  String? seenToken;

  @override
  Stream<String> get status => statusController.stream;

  @override
  Future<SessionTransport> connect(String hostUrl, String token) async {
    seenUrl = hostUrl;
    seenToken = token;
    statusController.add('connected (generation 1)');
    return transport;
  }

  @override
  Future<void> answer(WaterfallEvent event, WaterfallOutcome outcome) async =>
      answers.add((event.eventId, (outcome as WaterfallResult).value));

  @override
  Future<void> dispose() async {}
}

Map<String, Object?> rec(
  int seq,
  String type, [
  Map<String, Object?> data = const {},
]) => {
  'type': 'event',
  'event': {'type': type, 'seq': seq, 'time': seq, 'data': data},
};

void main() {
  testWidgets('pair -> list -> open -> prompt -> streamed text -> approval', (
    tester,
  ) async {
    final transport = FakeTransport();
    final backend = FakeBackend(transport);
    final controller = DebugController(backend);
    addTearDown(controller.dispose);
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(DshApp(controller: controller));
    await tester.enterText(
      find.byKey(const ValueKey('url')),
      'http://127.0.0.1:1234',
    );
    await tester.enterText(find.byKey(const ValueKey('token')), 'tok');
    await tester.tap(find.byKey(const ValueKey('connect')));
    await tester.pump();
    await tester.pump();
    expect(backend.seenUrl, 'http://127.0.0.1:1234');
    expect(backend.seenToken, 'tok');
    expect(find.text('1 sessions'), findsOneWidget);
    expect(find.text('First session'), findsOneWidget);
    expect(find.textContaining('connected (generation 1)'), findsOneWidget);

    // open the session: the follow snapshot arrives
    await tester.tap(find.byKey(const ValueKey('session-s1')));
    await tester.pump();
    final follow = transport.follows.single;
    follow.add(const StreamOpened(1));
    follow.add(
      StreamItem(1, {
        'type': 'snapshot',
        'header': {'version': 4},
        'cursor': 1,
        'records': [
          rec(0, 'user/message', {
            'source': {'kind': 'user'},
            'content': [
              {'type': 'text', 'text': 'earlier question'},
            ],
          }),
          rec(1, 'assistant/message', {
            'message': {
              'content': [
                {'type': 'text', 'text': 'earlier answer'},
              ],
            },
          }),
        ],
        'hasMore': false,
        'projections': {'asOfSeq': 1, 'values': <String, Object?>{}},
        'assistantStream': {'revision': 0},
      }),
    );
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('earlier question'), findsOneWidget);
    expect(find.textContaining('earlier answer'), findsOneWidget);

    // send a prompt
    await tester.enterText(find.byKey(const ValueKey('prompt')), 'hello there');
    await tester.tap(find.byKey(const ValueKey('send')));
    await tester.pump();
    expect(transport.prompts.single['sessionId'], 's1');
    expect((transport.prompts.single['content']! as List).single, {
      'type': 'text',
      'text': 'hello there',
    });

    // streamed assistant text from live chunks
    follow.add(
      StreamItem(1, {
        'type': 'assistant-stream',
        'frame': {
          'type': 'start',
          'attemptId': 'a1',
          'revision': 1,
          'turn': 1,
          'step': 1,
          'startedAfterSeq': 1,
        },
      }),
    );
    follow.add(
      StreamItem(1, {
        'type': 'assistant-stream',
        'frame': {
          'type': 'chunk',
          'attemptId': 'a1',
          'revision': 2,
          'index': 0,
          'time': 5,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': 'stream'},
        },
      }),
    );
    follow.add(
      StreamItem(1, {
        'type': 'assistant-stream',
        'frame': {
          'type': 'chunk',
          'attemptId': 'a1',
          'revision': 3,
          'index': 1,
          'time': 6,
          'chunk': {'type': 'text-delta', 'index': 0, 'text': 'ing'},
        },
      }),
    );
    await tester.pump();
    await tester.pump();
    expect(
      find.textContaining('Assistant (streaming): streaming'),
      findsOneWidget,
    );

    // an approval waterfall takes over the composer
    transport.events.add(
      const WaterfallEvent(
        generation: 1,
        event: 'approval/request',
        eventId: 'e1',
        agentId: 's1',
        request: {'toolName': 'bash', 'callId': 'c1'},
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('approval-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('send')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('approval-allow')));
    await tester.pump();
    await tester.pump();
    expect(backend.answers, [('e1', 'allowed-once')]);
    expect(find.byKey(const ValueKey('approval-panel')), findsNothing);
    expect(find.byKey(const ValueKey('send')), findsOneWidget);

    // locale + theme toggles keep working under the contract
    await tester.tap(find.byKey(const ValueKey('locale')));
    await tester.tap(find.byKey(const ValueKey('theme')));
    await tester.pump();
    expect(find.text('中文'), findsOneWidget);
  });
}
