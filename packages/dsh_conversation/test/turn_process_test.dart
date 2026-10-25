import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

EventEntry ev(
  int seq,
  String type,
  Map<String, Object?> data, {
  bool surface = false,
}) => EventEntry({
  'seq': seq,
  'time': 10000 + seq * 1000,
  'type': type,
  'data': data,
  if (surface) 'surfaceOp': 'append',
});
EventEntry assistant(int seq, int step, List<Map<String, Object?>> content) =>
    ev(seq, 'assistant/message', {
      'turn': 1,
      'step': step,
      'message': {'id': 'answer-$seq', 'content': content},
    }, surface: true);

void main() {
  late MutableEventSource source;
  late ConversationBinding binding;
  TurnProcessData process() =>
      binding.chat.value.visibleNodes
              .singleWhere((n) => n.kind == 'turn-process')
              .data
          as TurnProcessData;
  setUp(() {
    source = MutableEventSource()..replace([], false);
    binding = ConversationBinding.chat(
      source,
      scheduler: FlushScheduler.immediate(),
    );
  });
  tearDown(() => binding.dispose());

  test(
    'final reply excluded from counts; tools and subagents counted separately',
    () {
      source.append(ev(1, 'turn/start', {'turn': 1}));
      source.append(ev(2, 'step/start', {'turn': 1, 'step': 1}));
      source.append(
        assistant(3, 1, [
          {'type': 'text', 'text': 'Progress.'},
        ]),
      );
      source.append(
        ev(4, 'tool/call', {
          'turn': 1,
          'step': 1,
          'callId': 'read-a',
          'name': 'read',
          'args': '{}',
        }),
      );
      source.append(
        ev(5, 'tool/call', {
          'turn': 1,
          'step': 1,
          'callId': 'agent-a',
          'name': 'subagent_worker',
          'args': '{}',
        }),
      );
      source.append(
        ev(6, 'step/end', {
          'turn': 1,
          'step': 1,
          'reason': {'kind': 'tool-calls'},
        }),
      );
      source.append(ev(7, 'step/start', {'turn': 1, 'step': 2}));
      source.append(
        assistant(8, 2, [
          {'type': 'reasoning', 'text': 'Think.'},
          {'type': 'text', 'text': 'Final.'},
        ]),
      );
      source.append(
        ev(9, 'step/end', {
          'turn': 1,
          'step': 2,
          'reason': {'kind': 'complete'},
        }),
      );
      source.append(
        ev(10, 'turn/end', {
          'turn': 1,
          'reason': {'kind': 'complete'},
        }),
      );
      final data = process();
      expect(data.messageCount, 1);
      expect(data.toolCallCount, 1);
      expect(data.subagentCount, 1);
      expect(data.answerStep, 2);
      expect(data.answerAnchorSeq, 8);
      expect(data.inlineReasoning, isTrue);
      expect(data.processStartSeq, 1);
    },
  );

  test(
    'partial ended window publishes process without inventing start time',
    () {
      source.replace([
        ev(4, 'tool/call', {
          'turn': 1,
          'step': 1,
          'callId': 'r',
          'name': 'read',
          'args': '{}',
        }),
        ev(6, 'turn/end', {
          'turn': 1,
          'reason': {'kind': 'aborted'},
        }),
      ], true);
      final node = binding.chat.value.visibleNodes.singleWhere(
        (n) => n.kind == 'turn-process',
      );
      expect(process().answerAnchorSeq, isNull);
      expect(owningTurn(node.location)?.start, isNull);
      expect(turnProcessAlwaysOpen(node), isTrue);
    },
  );

  test(
    'opening user stays before control; later input stays after process',
    () {
      source.replace([
        ev(1, 'turn/start', {'turn': 1}),
        ev(2, 'step/start', {'turn': 1, 'step': 1}),
        ev(3, 'user/message', {
          'turn': 1,
          'step': 1,
          'id': 'u',
          'source': {'kind': 'user'},
          'content': [
            {'type': 'text', 'text': 'Input'},
          ],
        }, surface: true),
        assistant(4, 1, [
          {'type': 'text', 'text': 'Progress'},
        ]),
        ev(5, 'user/message', {
          'turn': 1,
          'step': 1,
          'id': 'u2',
          'source': {'kind': 'user'},
          'content': [
            {'type': 'text', 'text': 'Interleaved'},
          ],
        }, surface: true),
      ], false);
      expect(binding.chat.value.visibleNodes.map((n) => n.kind), [
        'user',
        'turn-process',
        'assistant-step',
        'user',
      ]);
    },
  );

  test('whitespace and tool-only assistant blocks do not establish answer', () {
    source.replace([
      ev(1, 'turn/start', {'turn': 1}),
      ev(2, 'step/start', {'turn': 1, 'step': 1}),
      assistant(3, 1, [
        {'type': 'text', 'text': '  '},
        {'type': 'tool-call', 'callId': 'r', 'name': 'read', 'args': '{}'},
      ]),
    ], false);
    expect(process().answerAnchorSeq, isNull);
    expect(process().messageCount, 0);
  });
}
