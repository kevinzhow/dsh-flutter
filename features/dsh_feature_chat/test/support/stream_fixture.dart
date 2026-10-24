import 'dart:async';

import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_slots/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Six events per turn: start, step, the user's message, the answer, step end
/// and turn end. Turn `t` (0-based) owns seqs `6t+1 .. 6t+6`.
const eventsPerTurn = 6;

String questionOf(int t) => 'Question $t';
String answerOf(int t) => 'Answer $t';

List<Map<String, Object?>> turnRecords(
  int t, {
  String? answer,
  Map<int, String> answers = const {},
  Map<int, String> reasoning = const {},
}) {
  final base = t * eventsPerTurn + 1;
  final text =
      answer ??
      answers[t] ??
      (t % 4 == 0
          ? '${answerOf(t)}\n\n${List.filled(6, 'More words in the answer.').join('\n\n')}'
          : answerOf(t));
  return [
    rec(base, 'turn/start', data: {'turn': t + 1}),
    rec(base + 1, 'step/start', data: {'turn': t + 1, 'step': 1}),
    rec(
      base + 2,
      'user/message',
      data: {
        'content': [
          {'type': 'text', 'text': questionOf(t)},
        ],
        'source': {'kind': 'user', 'rpcId': 'rpc-$t'},
        'role': 'user',
        'id': 'u$t',
      },
      surfaceOp: 'append',
    ),
    rec(
      base + 3,
      'assistant/message',
      data: {
        'turn': t + 1,
        'step': 1,
        'message': {
          'role': 'assistant',
          'content': [
            if (reasoning[t] != null)
              {'type': 'reasoning', 'text': reasoning[t]},
            {'type': 'text', 'text': text},
          ],
          'source': {'kind': 'model', 'provider': 'p', 'model': 'm'},
          'id': 'a$t',
        },
        'stream': <Object?>[],
      },
      surfaceOp: 'append',
    ),
    rec(base + 4, 'step/end', data: {'turn': t + 1, 'step': 1}),
    rec(
      base + 5,
      'turn/end',
      data: {
        'turn': t + 1,
        'reason': {'kind': 'completed'},
      },
    ),
  ];
}

class FixtureActions implements SessionActions {
  FixtureActions(this.session);
  final Session session;
  final sent = <String>[];

  @override
  Future<void> send(
    String text, {
    List<OutgoingAttachment> attachments = const [],
  }) async {
    sent.add(text);
    await session.prompt(text);
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> loadOlder() => session.loadOlder();
}

/// A recorded-style long session: [turns] turns of which the newest [first]
/// are in the opening window, the rest behind older pages that land when the
/// test completes them (`pages`).
class StreamFixture {
  StreamFixture({this.turns = 300, this.first = 60, this.pageTurns = 10});

  final int turns, first, pageTurns;
  final transport = FakeTransport();
  late final Session session = Session('s1', transport);
  late final FixtureActions actions = FixtureActions(session);
  late final SessionOwner owner = testSessionOwner(
    's1',
    session: session,
    actions: actions,
  );
  final pages = <Completer<void>>[];
  Map<int, String> answers = {};
  Map<int, String> reasoning = {};

  List<Map<String, Object?>> records(int from, int to) => [
    for (var t = from; t < to; t++)
      ...turnRecords(t, answers: answers, reasoning: reasoning),
  ];

  /// Opens the session with the newest [first] turns; older turns come page
  /// by page, each held until [landPage].
  Future<void> open() async {
    transport.onPage = (request) async {
      final before = (request['beforeSeq']! as num).toInt();
      final endTurn = (before - 1) ~/ eventsPerTurn;
      final startTurn = (endTurn - pageTurns).clamp(0, endTurn);
      final held = Completer<void>();
      pages.add(held);
      await held.future;
      return {'records': records(startTurn, endTurn), 'hasMore': startTurn > 0};
    };
    unawaited(session.open());
    await Future<void>.delayed(Duration.zero);
    transport.open(
      1,
      snapshot(records(turns - first, turns), hasMore: turns - first > 0),
    );
    await Future<void>.delayed(Duration.zero);
  }

  /// Completes the oldest pending page request.
  Future<void> landPage(WidgetTester t) async {
    final held = pages.firstWhere((p) => !p.isCompleted);
    await t.runAsync(() async {
      held.complete();
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await t.pump();
  }

  SlotRegistry registry({DshI18n? i18n, ToolHostActions? host}) {
    final slots = SlotRegistry();
    for (final s in DshSlots.all) {
      slots.declare(s);
    }
    final text = i18n ?? const DshI18n(DshLocale.en);
    registerChatFeature(slots, i18n: () => text, host: host);
    return slots;
  }

  /// The chat view as the app mounts it.
  Widget view(SlotRegistry slots) => slots.renderList(viewSlot, owner).first;
}

/// Where the text [text] is painted (global), or null when not built.
Rect? paintedText(WidgetTester t, String text) {
  final finder = find.textContaining(text, findRichText: true);
  if (finder.evaluate().isEmpty) return null;
  final box = t.renderObject<RenderBox>(finder.first);
  return box.localToGlobal(Offset.zero) & box.size;
}

Future<void> settleFrames(WidgetTester t, [int n = 20]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 16));
  }
}
