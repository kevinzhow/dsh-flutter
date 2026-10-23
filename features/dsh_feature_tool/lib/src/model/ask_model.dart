import 'dart:convert';

import 'package:dsh_conversation/dsh_conversation.dart';

import 'details_model.dart' show Tr;
import 'raw_call.dart';
import 'row_model.dart';

/// Validated, localized data of the ask-user transcript card (dsh
/// `AskQuestionCardModel`).
sealed class AskCard {
  const AskCard();
}

class AnsweredAsk extends AskCard {
  const AnsweredAsk(this.questions, this.skippedLabel);
  final List<({String id, String question, List<String> answers})> questions;
  final String skippedLabel;
}

class UnansweredAsk extends AskCard {
  const UnansweredAsk(this.questions, this.verdict);
  final List<({String id, String question})> questions;
  final String verdict;
}

/// One recorded answer.
class AskAnswer {
  const AskAnswer(this.id, this.selected, this.custom);
  final String id;
  final List<String> selected;
  final String? custom;
}

/// One question of the call.
class AskQuestion {
  const AskQuestion(this.id, this.question);
  final String id;
  final String question;
}

Object? _parse(String text) {
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// Answer records from the result JSON; null when malformed.
List<AskAnswer>? answerEntries(String text) {
  final parsed = _parse(text);
  if (parsed is! Map<String, Object?>) return null;
  final answers = parsed['answers'];
  if (answers is! List || !answers.every(isRecord)) return null;
  final out = <AskAnswer>[];
  for (final a in answers.cast<Map<String, Object?>>()) {
    if (a['id'] is! String ||
        a['selected'] is! List ||
        !(a['selected'] as List).every((s) => s is String) ||
        (a.containsKey('custom') && a['custom'] is! String)) {
      return null;
    }
    out.add(
      AskAnswer(a['id']! as String, [
        for (final s in a['selected'] as List) s as String,
      ], a['custom'] as String?),
    );
  }
  return out;
}

/// Questions from call JSON; null when pairing with answers would be ambiguous.
List<AskQuestion>? questionEntries(String argsRaw) {
  final parsed = _parse(argsRaw);
  if (parsed is! Map<String, Object?>) return null;
  final questions = parsed['questions'];
  if (questions is! List || questions.isEmpty) return null;
  final out = <AskQuestion>[];
  final ids = <String>{};
  for (final q in questions) {
    if (q is! Map<String, Object?> ||
        q['id'] is! String ||
        q['question'] is! String ||
        !ids.add(q['id']! as String)) {
      return null;
    }
    out.add(AskQuestion(q['id']! as String, q['question']! as String));
  }
  return out;
}

List<({String id, String question, List<String> answers})>? pairAnswers(
  List<AskQuestion> questions,
  List<AskAnswer> answers,
) {
  if (questions.length != answers.length) return null;
  final byId = <String, AskAnswer>{};
  for (final a in answers) {
    if (byId.containsKey(a.id)) return null;
    byId[a.id] = a;
  }
  final paired = <({String id, String question, List<String> answers})>[];
  for (final q in questions) {
    final a = byId[q.id];
    if (a == null) return null;
    paired.add((
      id: q.id,
      question: q.question,
      answers: [
        ...a.selected,
        if (a.custom != null && a.custom!.isNotEmpty) a.custom!,
      ],
    ));
  }
  return paired;
}

/// What an answered row shows: summary and the transcript card.
({String summary, AskCard? transcript}) answeredPresentation(
  List<AskQuestion>? questions,
  List<AskAnswer> answers,
  Tr t,
) {
  final answered = answers
      .where((a) => a.selected.isNotEmpty || (a.custom ?? '').isNotEmpty)
      .length;
  final paired = questions == null ? null : pairAnswers(questions, answers);
  return (
    summary: t('ask.answered', {'answered': answered, 'total': answers.length}),
    transcript: paired == null ? null : AnsweredAsk(paired, t('ask.skipped')),
  );
}

/// Best-effort answered-count summary when strict pairing fails.
String? answeredSummary(String text, Tr t) {
  final parsed = _parse(text);
  if (parsed is! Map<String, Object?>) return null;
  final answers = parsed['answers'];
  if (answers is! List || !answers.every(isRecord)) return null;
  final answered = answers.cast<Map<String, Object?>>().where((a) {
    final selected = a['selected'];
    final custom = a['custom'];
    return (selected is List && selected.isNotEmpty) ||
        (custom is String && custom.isNotEmpty);
  }).length;
  return t('ask.answered', {'answered': answered, 'total': answers.length});
}

bool isPendingResult(String text) {
  final parsed = _parse(text);
  return parsed is Map<String, Object?> &&
      parsed['pending'] == true &&
      parsed['callId'] is String;
}

/// The summary, row state and transcript of an `ask_user_question` call.
class AskPresentation {
  const AskPresentation(this.summary, this.state, this.transcript);
  final String summary;
  final ToolRowState state;
  final AskCard? transcript;
}

/// Present a pending, answered, cancelled or interrupted question set (the
/// part of dsh's `AskQuestionRow` that reads the call and its result;
/// [answerable] and [settledAnswers] come from the `userQuestions` projection).
AskPresentation presentAsk(
  ToolCall call,
  ToolRowModel model,
  Tr t, {
  required bool answerable,
  required List<AskAnswer>? settledAnswers,
}) {
  final Object? code = call is ToolResult ? (call.error?['code']) : null;
  final argsRaw = model.bodyRaw ?? '';
  var summary = model.summary;
  var state = model.state;
  AskCard? transcript;
  UnansweredAsk? unanswered(List<AskQuestion>? q, String verdict) => q == null
      ? null
      : UnansweredAsk([
          for (final x in q) (id: x.id, question: x.question),
        ], verdict);

  if (code == 'ASK_CANCELLED') {
    summary = t('ask.cancelled');
    state = ToolRowState.ok;
    transcript = unanswered(questionEntries(argsRaw), t('ask.cancelledDetail'));
  } else if (code == 'ASK_ABORTED') {
    summary = t('ask.interrupted');
    state = ToolRowState.stopped;
    transcript = unanswered(
      questionEntries(argsRaw),
      t('ask.interruptedDetail'),
    );
  } else if (model.state == ToolRowState.running) {
    summary = t('ask.waiting');
  } else if (code == 'TOOL_OUTCOME_UNKNOWN' &&
      (answerable || settledAnswers != null)) {
    state = ToolRowState.ok;
    final questions = questionEntries(argsRaw);
    if (answerable) {
      summary = t('ask.pending');
      transcript = unanswered(questions, t('ask.pendingDetail'));
    } else if (settledAnswers!.isEmpty) {
      summary = t('ask.closed');
      transcript = unanswered(questions, t('ask.closedDetail'));
    } else {
      final p = answeredPresentation(questions, settledAnswers, t);
      summary = p.summary;
      transcript = p.transcript;
    }
  } else if (call is ToolResult && model.state == ToolRowState.ok) {
    final text = singleResultText(call);
    if (text != null) {
      final questions = questionEntries(argsRaw);
      final pending = isPendingResult(text);
      if (pending && answerable) {
        summary = t('ask.pending');
        transcript = unanswered(questions, t('ask.pendingDetail'));
      } else if (pending &&
          (settledAnswers == null || settledAnswers.isEmpty)) {
        summary = t('ask.closed');
        transcript = unanswered(questions, t('ask.closedDetail'));
      } else {
        final answers = settledAnswers ?? answerEntries(text);
        final p = answers == null
            ? null
            : answeredPresentation(questions, answers, t);
        summary = p?.summary ?? answeredSummary(text, t) ?? model.summary;
        transcript = p?.transcript;
      }
    }
  }
  return AskPresentation(summary, state, transcript);
}
