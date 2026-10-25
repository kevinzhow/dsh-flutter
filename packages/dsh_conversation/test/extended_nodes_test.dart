import 'dart:convert';

import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:test/test.dart';

EventEntry event(
  int seq,
  String type,
  Map<String, Object?> data, {
  bool surface = false,
}) => EventEntry({
  'seq': seq,
  'time': 1000 + seq * 10,
  'type': type,
  'data': data,
  if (surface) 'surfaceOp': 'append',
});

void main() {
  late MutableEventSource source;
  late ConversationBinding binding;
  setUp(() {
    source = MutableEventSource()..replace([], false);
    binding = ConversationBinding.chat(
      source,
      scheduler: FlushScheduler.immediate(),
    );
  });
  tearDown(() => binding.dispose());
  List<ViewNode> nodes(String kind) =>
      binding.chat.value.visibleNodes.where((n) => n.kind == kind).toList();
  void startRun() => source.append(
    event(1, 'tool-workflow/run-start', {
      'runId': 'run-a',
      'name': 'Synthetic review',
    }),
  );
  void member(int seq, int memberSeq, {String? phase}) => source.append(
    event(seq, 'tool-workflow/agent-start', {
      'runId': 'run-a',
      'seq': memberSeq,
      'label': 'Reader',
      'childId': 'child-$memberSeq',
      if (phase != null) 'phase': phase,
    }),
  );
  WorkflowRunData run() =>
      nodes('workflow-run').single.data! as WorkflowRunData;

  test(
    'goal echo precedes result without adding echoes for other commands',
    () {
      source.append(
        event(1, 'command/run', {
          'commandId': 'a',
          'name': 'goal',
          'args': '  ship /goal docs \n',
        }),
      );
      source.append(
        event(2, 'command/run', {'commandId': 'b', 'name': 'help'}),
      );
      final chat = binding.chat.value.visibleNodes.toList();
      expect(chat.map((n) => n.kind), ['command-input', 'command', 'command']);
      expect(
        (chat.first.data as CommandInputData).text,
        '/goal  ship /goal docs',
      );
      expect(chat.first.anchorSeq, .9);
    },
  );
  test('answered late reply exclusively replaces generic context and filters invalid pairs', () {
    source.append(
      event(1, 'user/message', {
        'id': 'reply',
        'source': {
          'kind': 'user-question-reply',
          'callId': 'ask-a',
          'outcome': 'answered',
        },
        'content': [
          {
            'type': 'text',
            'text': jsonEncode({
              'questions': [
                {
                  'id': 'q',
                  'question': 'Choose',
                  'options': [
                    42,
                    {'label': 'One'},
                  ],
                },
                {'id': 7},
              ],
              'answers': [
                {
                  'id': 'q',
                  'selected': ['One', 4],
                  'custom': '  Other  ',
                },
              ],
            }),
          },
        ],
      }, surface: true),
    );
    expect(
      binding.chat.value.nodes.values.where((n) => n.kind == 'context'),
      isEmpty,
    );
    final data = nodes('question-reply').single.data as QuestionReplyData;
    expect(data.questions, [
      {
        'id': 'q',
        'question': 'Choose',
        'options': [
          {'label': 'One'},
        ],
      },
    ]);
    expect(data.answerValues('q'), ['One', 'Other']);
    expect(data.answerValues('unknown'), isEmpty);
  });
  test(
    'non-answer or replacement reply sources retain generic classification',
    () {
      source.append(
        event(1, 'user/message', {
          'id': 'reply',
          'source': {
            'kind': 'user-question-reply',
            'callId': 'ask-a',
            'outcome': 'continued',
          },
          'content': [
            {'type': 'text', 'text': 'not a settled answer'},
          ],
        }, surface: true),
      );
      expect(nodes('question-reply'), isEmpty);
      expect(replyPairsOf('not JSON').questions, isEmpty);
      expect(
        replyPairsOf('{"questions":[],"answers":[{"id":"a","selected":[]}]}')
            .answers
            .length,
        1,
      );
    },
  );
  test('workflow preserves phase identities and seq-based settlements', () {
    startRun();
    member(2, 1);
    member(3, 2, phase: '');
    member(4, 3, phase: '💡');
    member(5, 4);
    source.append(
      event(6, 'tool-workflow/agent-end', {
        'runId': 'run-a',
        'seq': 1,
        'outcome': 'failed',
      }),
    );
    expect(run().phases.map((p) => p.key), [
      'missing',
      'value:0:',
      'value:2:💡',
    ]);
    expect(run().phases.first.members.map((m) => m.status), [
      WorkflowRunStatus.failed,
      WorkflowRunStatus.running,
    ]);
    source.append(
      event(7, 'tool-workflow/run-end', {
        'runId': 'run-a',
        'stopReason': 'completed',
      }),
    );
    expect(run().status, WorkflowRunStatus.completed);
    // Run completion never fabricates a member outcome.
    expect(run().phases.last.members.single.status, WorkflowRunStatus.running);
  });
  test(
    'updates without loaded start remain absent until the older page arrives',
    () {
      final end = event(4, 'tool-workflow/run-end', {
        'runId': 'run-a',
        'stopReason': 'error',
      });
      source.replace([end], true);
      expect(nodes('workflow-run'), isEmpty);
      source.replace([
        event(1, 'tool-workflow/run-start', {
          'runId': 'run-a',
          'name': 'Recovered',
        }),
        end,
      ], false);
      expect(run().name, 'Recovered');
      expect(run().status, WorkflowRunStatus.failed);
    },
  );
  test('normal turn end does not stop a background run; crash does', () {
    source.append(event(0, 'turn/start', {'turn': 1}));
    startRun();
    member(2, 1);
    source.append(
      event(3, 'turn/end', {
        'turn': 1,
        'reason': {'kind': 'completed'},
      }),
    );
    expect(run().status, WorkflowRunStatus.running);
    source.replace([
      event(0, 'turn/start', {'turn': 1}),
      event(1, 'tool-workflow/run-start', {
        'runId': 'run-a',
        'name': 'Recovered',
      }),
      event(2, 'tool-workflow/agent-start', {
        'runId': 'run-a',
        'seq': 1,
        'label': 'Reader',
        'childId': 'child-1',
      }),
      event(3, 'turn/end', {
        'turn': 1,
        'reason': {'kind': 'interrupted'},
      }),
    ], false);
    expect(run().status, WorkflowRunStatus.interrupted);
    expect(
      run().phases.single.members.single.status,
      WorkflowRunStatus.interrupted,
    );
  });
}
