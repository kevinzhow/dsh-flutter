import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

EventEntry event(
  int seq,
  String type,
  Map<String, Object?> data, {
  Object? surface,
}) => EventEntry({
  'seq': seq,
  'time': 10000 + seq,
  'type': type,
  'data': data,
  if (surface != null) 'surfaceOp': surface,
});
EventEntry start(int seq, {String? command}) => event(seq, 'compaction/start', {
  'compactionId': 'compact-a',
  'turn': null,
  if (command != null) 'sourceCommandId': command,
});
EventEntry summary(
  int seq, {
  String? command,
  Object? seqs = const [0, 1],
  Object? tokens = 125,
}) => event(seq, 'compaction/summary', {
  'compactionId': 'compact-a',
  if (command != null) 'sourceCommandId': command,
  'summary': [
    {'type': 'text', 'text': '## Summary\n'},
    {'type': 'image'},
    {'type': 'text', 'text': 'Remember this.'},
  ],
  'shadowedSeqs': seqs,
  'shadowedTokenCount': tokens,
});
EventEntry checkpoint(int seq, {String? command}) => event(
  seq,
  'user/message',
  {
    'id': 'checkpoint',
    'source': {
      'kind': 'compact-checkpoint',
      'compactionId': 'compact-a',
      if (command != null) 'sourceCommandId': command,
    },
    'content': [
      {
        'type': 'text',
        'text': 'MODEL ENVELOPE: never show this as the summary',
      },
    ],
  },
  surface: {'op': 'replace', 'startSeq': 0, 'endSeq': 1},
);
EventEntry run(int seq, {String name = 'compact'}) => event(
  seq,
  'command/run',
  {'commandId': 'command-a', 'name': name, 'args': '  keep this whitespace'},
);
EventEntry done(int seq, {String kind = 'success', Object? source = 1}) =>
    event(seq, 'command/done', {
      'commandId': 'command-a',
      'kind': kind,
      'text': 'First line\nSecond line',
      'sourceEventSeq': source,
    });

void main() {
  late MutableEventSource source;
  late ConversationBinding binding;
  List<ViewNode> nodes() => binding.chat.value.visibleNodes;
  setUp(() {
    source = MutableEventSource()..replace([], false);
    binding = ConversationBinding.chat(
      source,
      scheduler: FlushScheduler.immediate(),
    );
  });
  tearDown(() => binding.dispose());

  test(
    'automatic marker waits for landing and leaves old transcript visible',
    () {
      source.append(
        event(0, 'user/message', {
          'id': 'old',
          'source': {'kind': 'user'},
          'content': [
            {'type': 'text', 'text': 'Keep old transcript'},
          ],
        }, surface: 'append'),
      );
      source.append(start(1));
      source.append(summary(2));
      expect(nodes().map((n) => n.kind), ['user']);
      source.append(checkpoint(3));
      expect(nodes().map((n) => n.kind), ['user', 'compaction']);
      final marker = nodes().last.data as CompactionData;
      expect(marker.summary, '## Summary\nRemember this.');
      expect(marker.seq, 3);
      expect(marker.time, 10003);
      expect(marker.summaryEventSeq, 2);
      expect(marker.shadowedItemCount, 2);
      expect(marker.shadowedTokenCount, 125);
      expect(nodes().last.anchorSeq, 3);
    },
  );

  test(
    'checkpoint-only window backfills summary and retains marker identity',
    () {
      source.replace([checkpoint(3)], true);
      final key = nodes().single.key;
      expect((nodes().single.data as CompactionData).summary, isNull);
      source.prepend([start(1), summary(2)], false);
      expect(nodes().single.key, key);
      expect(nodes().single.anchorSeq, 3);
      expect(
        (nodes().single.data as CompactionData).summary,
        contains('Remember'),
      );
      source.replace([checkpoint(3)], true);
      expect((nodes().single.data as CompactionData).summary, isNull);
      expect((nodes().single.data as CompactionData).shadowedItemCount, isNull);
    },
  );

  test('manual compaction is one command row that moves to the checkpoint', () {
    source.append(run(0));
    expect(nodes().single.kind, 'manual-compaction');
    expect(nodes().single.anchorSeq, 0);
    source.append(start(1, command: 'command-a'));
    source.append(summary(2, command: 'command-a'));
    source.append(checkpoint(3, command: 'command-a'));
    source.append(done(4));
    expect(nodes().length, 1);
    expect(nodes().single.kind, 'manual-compaction');
    expect(nodes().single.anchorSeq, 3);
    final data = nodes().single.data as ManualCompactionData;
    expect(data.command.seq, 0);
    expect(data.command.args, '  keep this whitespace');
    expect(data.command.outcome!.text, 'First line\nSecond line');
    expect(data.compaction!.summaryEventSeq, 2);
  });

  test('manual checkpoint fallback resolves without an in-window run', () {
    source.replace([
      summary(2, command: 'command-a'),
      checkpoint(3, command: 'command-a'),
      done(4),
    ], true);
    expect(nodes().length, 1);
    final data = nodes().single.data as ManualCompactionData;
    expect(data.command.name, 'compact');
    expect(data.command.seq, 4);
    expect(nodes().single.anchorSeq, 3);
    expect(data.compaction!.summary, contains('Remember'));
    source.replace([checkpoint(3, command: 'command-a')], true);
    final orphan = nodes().single.data as ManualCompactionData;
    expect(orphan.command.seq, 3);
    expect(orphan.command.outcome, isNull);
    expect(orphan.compaction!.summary, isNull);
  });

  test('orphan settlement soft-falls and older run restores name and args', () {
    source.replace([done(4)], true);
    expect(nodes().single.kind, 'command');
    expect((nodes().single.data as CommandData).name, isNull);
    source.prepend([run(0, name: 'status')], false);
    final data = nodes().single.data as CommandData;
    expect(data.name, 'status');
    expect(data.args, '  keep this whitespace');
    expect(data.seq, 0);
    expect(data.outcome!.sourceEventSeq, 1);
  });

  test('failed or no-checkpoint compact command keeps complete settlement', () {
    source.append(run(0));
    source.append(start(1, command: 'command-a'));
    source.append(done(2, kind: 'error'));
    final data = nodes().single.data as ManualCompactionData;
    expect(data.compaction, isNull);
    expect(data.command.outcome!.kind, 'error');
    expect(data.command.outcome!.text, 'First line\nSecond line');
    expect(data.command.outcome!.sourceEventSeq, isNull);
  });

  for (final invalid in [
    -1,
    1.5,
    9007199254740992,
    double.infinity,
    double.nan,
    true,
  ]) {
    test('invalid structured counts are unavailable: $invalid', () {
      source.replace([
        start(1),
        summary(2, seqs: [invalid], tokens: invalid),
        checkpoint(3),
      ], false);
      final data = nodes().single.data as CompactionData;
      expect(data.shadowedItemCount, isNull);
      expect(data.shadowedTokenCount, isNull);
      expect(data.summary, isNotNull);
    });
  }

  test('empty summary cannot expand but valid zero counts are retained', () {
    final blank = event(2, 'compaction/summary', {
      'compactionId': 'compact-a',
      'summary': [
        {'type': 'text', 'text': ' \n '},
      ],
      'shadowedSeqs': [],
      'shadowedTokenCount': 0,
    });
    source.replace([start(1), blank, checkpoint(3)], false);
    final data = nodes().single.data as CompactionData;
    expect(data.summary, isNull);
    expect(data.summaryEventSeq, 2);
    expect(data.shadowedItemCount, 0);
    expect(data.shadowedTokenCount, 0);
  });

  test(
    'unlanded automatic lifecycle and malformed identity create no marker',
    () {
      source.replace([
        start(1),
        summary(2),
        event(3, 'compaction/end', {'compactionId': 'compact-a'}),
        event(4, 'compaction/start', {'compactionId': ''}),
      ], false);
      expect(nodes(), isEmpty);
    },
  );
}
