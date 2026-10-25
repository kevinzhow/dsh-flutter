import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

EventEntry event(
  int seq,
  String type,
  Map<String, Object?> data, [
  Object? op,
]) => EventEntry({
  'seq': seq,
  'time': 10000 + seq,
  'type': type,
  'data': data,
  if (op != null)
    'surfaceOp': op is Map
        ? <String, Object?>{
            'op': 'replace',
            for (final e in op.entries) e.key as String: e.value,
          }
        : op,
});
EventEntry system(
  int seq,
  String text, {
  int turn = 1,
  int step = 1,
  Object op = 'append',
}) => event(seq, 'system/message', {
  'turn': turn,
  'step': step,
  'message': {
    'id': 's$seq',
    'role': 'system',
    'source': {'kind': 'system-prompt'},
    'content': [
      {'type': 'text', 'text': text},
    ],
  },
}, op);
EventEntry header(
  int seq, {
  String reason = 'change',
  bool series = false,
  int turn = 1,
  int step = 1,
  List<Object?> tools = const [],
}) => event(seq, 'request/header', {
  'turn': turn,
  'step': step,
  'reason': reason,
  'startsSeries': series,
  'header': {'config': {}, 'tools': tools},
});
final opening = [
  event(0, 'turn/start', {'turn': 1}),
  event(1, 'step/start', {'turn': 1, 'step': 1}),
];
List<ViewNode> prompts(ConversationBinding b) =>
    b.chat.value.nodes.values
        .where((n) => n.kind == 'system-prompt' && n.visible)
        .toList()
      ..sort((a, b) => a.anchorSeq.compareTo(b.anchorSeq));

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

  test(
    'initial append precedes input and same-step header does not repeat it',
    () {
      source.append(system(2, 'first'));
      source.append(header(3, reason: 'initial'));
      final nodes = prompts(binding);
      expect(nodes.length, 1);
      expect(nodes.single.anchorSeq, 0);
      expect((nodes.single.data as SystemPromptData).text, 'first');
      expect(
        binding.chat.value.visibleNodes.where((n) => n.kind == 'system-prompt'),
        isEmpty,
        reason: 'dsh keeps prompt cards outside the ordinary transcript',
      );
    },
  );

  test(
    'appended update stays at its own position and suppresses header duplicate',
    () {
      source.append(system(2, 'first'));
      source.append(header(3, reason: 'initial'));
      source.append(system(4, 'updated'));
      source.append(header(5));
      final nodes = prompts(binding);
      expect(nodes.map((n) => n.anchorSeq), [0, 4]);
      final data = nodes.last.data as SystemPromptData;
      expect(data.text, 'updated');
      expect(data.update, true);
      expect((nodes.first.data as SystemPromptData).text, 'first');
    },
  );

  test('resumed header and explicit series retain unchanged prompt cards', () {
    source.append(system(2, 'first'));
    source.append(header(3, reason: 'initial'));
    source.append(event(4, 'step/start', {'turn': 1, 'step': 2}));
    source.append(header(5, reason: 'series', step: 2));
    source.append(header(6, series: true, step: 2));
    expect(prompts(binding).map((n) => n.anchorSeq), [0, 4, 6]);
    expect(
      prompts(binding).map((n) => (n.data as SystemPromptData).text),
      everyElement('first'),
    );
  });

  test('tools-only change and missing tool catalog do not repeat a prompt', () {
    source.append(system(2, 'first'));
    source.append(header(3, reason: 'initial'));
    source.append(event(4, 'step/start', {'turn': 1, 'step': 2}));
    source.append(
      header(
        5,
        step: 2,
        tools: [
          {'name': 'read'},
        ],
      ),
    );
    source.append(
      event(6, 'request/header', {
        'turn': 1,
        'step': 2,
        'reason': 'change',
        'header': {'config': {}},
      }),
    );
    expect(prompts(binding).length, 1);
  });

  test(
    'positional replacement changes later headers without rewriting history',
    () {
      source.append(system(2, 'first'));
      source.append(header(3, reason: 'initial'));
      source.append(system(4, 'replacement', op: {'startSeq': 2, 'endSeq': 2}));
      source.append(header(5));
      final nodes = prompts(binding);
      expect(nodes.map((n) => n.anchorSeq), [0, 5]);
      expect((nodes.first.data as SystemPromptData).text, 'first');
      expect((nodes.last.data as SystemPromptData).text, 'replacement');
      expect((nodes.last.data as SystemPromptData).update, false);
    },
  );

  test(
    'ordinary replacement removes the prompt and never renders as unknown',
    () {
      source.append(system(2, 'first'));
      source.append(header(3, reason: 'initial'));
      source.append(
        event(
          4,
          'user/message',
          {
            'role': 'user',
            'id': 'checkpoint',
            'source': {'kind': 'compact-checkpoint'},
            'content': [],
          },
          {'startSeq': 2, 'endSeq': 2},
        ),
      );
      source.append(header(5));
      expect(prompts(binding).length, 1);
      expect(binding.chat.value.visibleNodes, isEmpty);
    },
  );

  test('empty appends preserve the effective prompt and create no card', () {
    source.append(system(2, 'first'));
    source.append(header(3, reason: 'initial'));
    source.append(system(4, ''));
    source.append(event(5, 'step/start', {'turn': 1, 'step': 2}));
    source.append(header(6, reason: 'series', step: 2));
    expect(prompts(binding).length, 2);
    expect((prompts(binding).last.data as SystemPromptData).text, 'first');
  });

  test('unknown older endpoint withholds prompt until prepend replay', () {
    final tail = [
      system(10, 'newer'),
      system(11, 'older replacement', op: {'startSeq': 2, 'endSeq': 2}),
      header(12, reason: 'series'),
    ];
    source.replace(tail, true);
    expect(prompts(binding).length, 1);
    source.prepend([...opening, system(2, 'old')], false);
    final nodes = prompts(binding);
    expect(nodes.any((n) => n.id == '12'), true);
    expect((nodes.last.data as SystemPromptData).text, 'newer');
  });

  test(
    'replacement endpoint chains inherit surface order, not chronological seq',
    () {
      SystemPromptState? state;
      void apply(EventEntry e) =>
          state = inspectSystemPrompt(state, ConvEvent(e));
      apply(system(1, 'A'));
      apply(system(3, 'B'));
      apply(system(4, 'A2', op: {'startSeq': 1, 'endSeq': 1}));
      expect(state!.effective!.text, 'B');
      apply(event(5, 'user/message', {}, {'startSeq': 3, 'endSeq': 3}));
      expect(state!.effective!.text, 'A2');
      expect(state!.effective!.seq, 5);
      apply(event(6, 'user/message', {}, {'startSeq': 4, 'endSeq': 4}));
      expect(state!.effective!.text, '');
      expect(state!.replacements[6], 1);
    },
  );
}
