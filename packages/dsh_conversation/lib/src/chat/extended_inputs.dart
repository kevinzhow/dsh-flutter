import 'dart:convert';

import '../contract.dart';
import '../event.dart';
import 'definitions.dart';
import 'projection.dart';

/// The goal plugin owns the command echo; generic commands own their results.
class CommandInputData {
  const CommandInputData({
    required this.commandId,
    required this.text,
    required this.time,
  });
  final Object? commandId;
  final String text;
  final num time;
}

class GoalCommandInputDefinition extends ConversationDefinition {
  const GoalCommandInputDefinition();
  @override
  String get kind => 'goal-command-input';
  @override
  String get target => chatTarget;
  @override
  Set<String> get eventTypes => const {'command/run'};
  @override
  MatchResult? match(ConvEvent event) =>
      event.type == 'command/run' && event.data['name'] == 'goal'
      ? MatchResult('${event.data['commandId']}', MatchRole.start)
      : null;
  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) => CommandInputData(
    commandId: match.event.data['commandId'],
    text:
        '/${match.event.data['name']}${(match.event.data['args'] as String? ?? '').trimRight()}',
    time: match.event.time,
  );
  @override
  Object update(NodeContext context, ConversationMatch match) => context.state!;
  @override
  ViewNode? buildViewNode(NodeContext context) => context.state == null
      ? null
      : chatNode(
          context,
          'command-input',
          context.start!.event.seq - .1,
          context.state,
        );
}

class QuestionReplyData {
  const QuestionReplyData({
    required this.callId,
    required this.text,
    required this.time,
    required this.questions,
    required this.answers,
  });
  final String callId, text;
  final num time;
  final List<Map<String, Object?>> questions, answers;

  List<String> answerValues(String id) {
    final answer = answers.where((a) => a['id'] == id).firstOrNull;
    final custom = (answer?['custom'] as String? ?? '').trim();
    return [
      ...?((answer?['selected'] as List?)?.cast<String>()),
      if (custom.isNotEmpty) custom,
    ];
  }
}

/// Validate fields independently, retaining every readable pair from old logs.
({List<Map<String, Object?>> questions, List<Map<String, Object?>> answers})
replyPairsOf(String text) {
  Object? parsed;
  try {
    parsed = jsonDecode(text);
  } on FormatException {
    return (questions: [], answers: []);
  }
  final value = asRecord(parsed);
  if (value?['questions'] is! List) return (questions: [], answers: []);
  final questions = <Map<String, Object?>>[];
  for (final item in value!['questions'] as List) {
    final q = asRecord(item);
    if (q?['id'] is! String || q?['question'] is! String) continue;
    questions.add({
      'id': q!['id'],
      'question': q['question'],
      for (final key in ['detail', 'header'])
        if (q[key] is String) key: q[key],
      if (q['multiSelect'] is bool) 'multiSelect': q['multiSelect'],
      if (q['options'] is List)
        'options': [
          for (final option in q['options'] as List)
            if (asRecord(option)?['label'] is String)
              {
                'label': (option as Map)['label'],
                if (option['description'] is String)
                  'description': option['description'],
              },
        ],
    });
  }
  final answers = <Map<String, Object?>>[
    if (value['answers'] is List)
      for (final item in value['answers'] as List)
        if (asRecord(item)?['id'] is String &&
            asRecord(item)?['selected'] is List)
          {
            'id': (item as Map)['id'],
            'selected': (item['selected'] as List).whereType<String>().toList(),
            if (item['custom'] is String) 'custom': item['custom'],
          },
  ];
  return (questions: questions, answers: answers);
}

class QuestionReplyDefinition extends ConversationDefinition {
  const QuestionReplyDefinition();
  @override
  String get kind => 'user-question-reply';
  @override
  String get target => chatTarget;
  @override
  Set<String> get eventTypes => const {'user/message'};
  @override
  MatchResult? match(ConvEvent event) {
    final source = asRecord(event.data['source']);
    return event.type == 'user/message' &&
            event.isAppendSurface &&
            source?['kind'] == 'user-question-reply' &&
            source?['callId'] is String &&
            source?['outcome'] == 'answered'
        ? MatchResult('${event.data['id']}', MatchRole.start, exclusive: true)
        : null;
  }

  @override
  Object start(
    NodeContext context,
    ConversationMatch match,
    ContextReader reader,
  ) {
    final e = match.event;
    final content = e.data['content'] as List? ?? [];
    final block = content
        .map(asRecord)
        .where((b) => b?['type'] == 'text')
        .firstOrNull;
    final text = block?['text'] as String? ?? '';
    final pairs = replyPairsOf(text);
    return QuestionReplyData(
      callId: (e.data['source'] as Map)['callId'] as String,
      text: text,
      time: e.time,
      questions: pairs.questions,
      answers: pairs.answers,
    );
  }

  @override
  Object update(NodeContext context, ConversationMatch match) => context.state!;
  @override
  ViewNode? buildViewNode(NodeContext context) => context.state == null
      ? null
      : chatNode(
          context,
          'question-reply',
          context.start!.event.seq,
          context.state,
        );
}
