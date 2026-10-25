import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

EventEntry event(int seq, String type, Map<String, Object?> data) =>
    EventEntry({'seq': seq, 'time': 9000000 + seq, 'type': type, 'data': data});

EventEntry retry(int seq, String id, int attempt, {bool always = false}) =>
    event(seq, 'llm/retry', {
      'turn': 1,
      'step': 1,
      'retryId': id,
      'retry': attempt,
      'mode': always ? 'always' : 'normal',
      'maxRetries': 3,
      'delayMs': 2500,
      'provider': 'fixture',
      'policyKey': 'fixture',
      'failure': {'code': 'RATE_LIMIT', 'message': 'Try later'},
    });

final opening = [
  event(1, 'turn/start', {'turn': 1}),
  event(2, 'step/start', {'turn': 1, 'step': 1}),
];

List<ModelRetryData> retries(ConversationBinding binding) => [
  for (final node in binding.chat.value.visibleNodes)
    if (node.kind == 'model-retry') node.data as ModelRetryData,
];

void main() {
  late MutableEventSource source;
  late ConversationBinding binding;
  setUp(() {
    source = MutableEventSource()..replace(opening, false);
    binding = ConversationBinding.chat(
      source,
      scheduler: FlushScheduler.immediate(),
    );
  });
  tearDown(() => binding.dispose());

  test('correlates by producer ID and keeps one row at its first seq', () {
    source.append(retry(3, 'a', 1));
    source.append(
      event(4, 'llm/retry-started', {
        'turn': 1,
        'step': 1,
        'retryId': 'a',
        'retry': 1,
      }),
    );
    source.append(retry(5, 'b', 1));
    source.append(retry(6, 'a', 2));
    final nodes = binding.chat.value.visibleNodes
        .where((n) => n.kind == 'model-retry')
        .toList();
    expect(nodes.length, 2);
    expect(nodes.first.anchorSeq, 3);
    final a = nodes.first.data as ModelRetryData;
    expect(a.attempts.map((a) => a.state), [
      ModelRetryState.started,
      ModelRetryState.scheduled,
    ]);
    expect(a.current.retry, 2);
    expect(a.current.maxRetries, 3);
    expect(a.current.failureMessage, 'Try later');
    expect((nodes.last.data as ModelRetryData).current.retryId, 'b');
  });

  test('a start event changes only the matching attempt', () {
    source.append(retry(3, 'a', 1));
    source.append(retry(4, 'a', 2));
    source.append(
      event(5, 'llm/retry-started', {
        'turn': 1,
        'step': 1,
        'retryId': 'a',
        'retry': 1,
      }),
    );
    expect(
      retries(binding).single.attempts.first.state,
      ModelRetryState.started,
    );
    expect(retries(binding).single.current.state, ModelRetryState.scheduled);
  });

  for (final boundary in ['step/end', 'turn/end']) {
    test('$boundary cancels only the latest scheduled attempt', () {
      source.append(retry(3, 'a', 1));
      source.append(retry(4, 'a', 2));
      source.append(
        event(5, boundary, {
          'turn': 1,
          'step': 1,
          'reason': {'kind': 'completed'},
        }),
      );
      expect(retries(binding).single.current.state, ModelRetryState.cancelled);
      expect(
        retries(binding).single.attempts.first.state,
        ModelRetryState.scheduled,
      );
    });
  }

  test('closing the turn does not cancel an attempt already started', () {
    source.append(retry(3, 'a', 1, always: true));
    source.append(
      event(4, 'llm/retry-started', {
        'turn': 1,
        'step': 1,
        'retryId': 'a',
        'retry': 1,
      }),
    );
    source.append(
      event(5, 'turn/end', {
        'turn': 1,
        'reason': {'kind': 'completed'},
      }),
    );
    expect(retries(binding).single.current.state, ModelRetryState.started);
    expect(retries(binding).single.current.maxRetries, isNull);
  });

  test('an update-only window waits for its first retry on prepend', () {
    final first = retry(3, 'a', 1);
    final second = retry(4, 'a', 2);
    source.replace([second], true);
    expect(retries(binding), isEmpty);
    source.prepend([...opening, first], false);
    expect(retries(binding).single.attempts.length, 2);
    expect(
      binding.chat.value.visibleNodes
          .singleWhere((n) => n.kind == 'model-retry')
          .anchorSeq,
      3,
    );
  });

  test('incremental and full replay agree after closing a retry chain', () {
    final events = [
      ...opening,
      retry(3, 'a', 1),
      retry(4, 'a', 2),
      event(5, 'step/end', {'turn': 1, 'step': 1}),
    ];
    for (final e in events.skip(2)) {
      source.append(e);
    }
    final full = MutableEventSource()..replace(events, false);
    final other = ConversationBinding.chat(
      full,
      scheduler: FlushScheduler.immediate(),
    );
    addTearDown(other.dispose);
    final a = retries(binding).single, b = retries(other).single;
    expect(
      a.attempts.map((a) => (a.seq, a.state)),
      b.attempts.map((a) => (a.seq, a.state)),
    );
  });

  test('missing or empty producer IDs do not create a retry row', () {
    source.append(event(3, 'llm/retry', {'retry': 1}));
    source.append(event(4, 'llm/retry-started', {'retryId': '', 'retry': 1}));
    expect(retries(binding), isEmpty);
  });
}
