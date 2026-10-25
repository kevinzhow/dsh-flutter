// The question vocabulary of dsh's `user-questions` service: one question of a
// request, its options and the answer to it.

/// One option of a question (`AskUserQuestionOption`).
class QuestionOption {
  const QuestionOption(this.label, this.description);
  final String label;
  final String? description;
}

/// One question of a request (`AskUserQuestionItem`).
class QuestionItem {
  const QuestionItem({
    required this.id,
    required this.question,
    this.detail,
    this.header,
    this.options = const [],
    this.multiSelect = false,
    this.intent,
  });

  factory QuestionItem.fromWire(Map<String, Object?> json) => QuestionItem(
    id: '${json['id']}',
    question: '${json['question']}',
    detail: json['detail'] as String?,
    header: json['header'] as String?,
    multiSelect: json['multiSelect'] == true,
    intent: json['intent'] is Map<String, Object?>
        ? json['intent'] as Map<String, Object?>
        : null,
    options: [
      if (json['options'] is List)
        for (final o in json['options']! as List)
          if (o is Map<String, Object?>)
            QuestionOption('${o['label']}', o['description'] as String?),
    ],
  );

  final String id;
  final String question;
  final String? detail;
  final String? header;
  final List<QuestionOption> options;
  final bool multiSelect;
  final Map<String, Object?>? intent;
}

/// The answer to one question (`AskUserQuestionAnswerItem`).
class QuestionAnswer {
  const QuestionAnswer(this.id, this.selected, {this.custom});
  final String id;
  final List<String> selected;
  final String? custom;

  Map<String, Object?> toJson() => {
    'id': id,
    'selected': selected,
    if (custom != null && custom!.isNotEmpty) 'custom': custom,
  };
}

/// Exactly one plan-review question, with a named approval option and at most
/// one alternative. All other shapes retain the generic question flow.
class PlanReview {
  const PlanReview({
    required this.id,
    required this.question,
    required this.plan,
    required this.approve,
    this.decline,
    this.callId,
  });
  final String id, question, plan;
  final String? callId;
  final QuestionOption approve;
  final QuestionOption? decline;
}

PlanReview? planReviewOf(List<QuestionItem> questions) {
  if (questions.length != 1) return null;
  final q = questions.single;
  final intent = q.intent;
  if (intent?['kind'] != 'plan-review' ||
      q.detail == null ||
      q.multiSelect ||
      q.options.length > 2) {
    return null;
  }
  final approve = q.options
      .where((o) => o.label == intent?['approve'])
      .firstOrNull;
  if (approve == null) return null;
  final call = intent?['callId'];
  if (call != null && call is! String) return null;
  return PlanReview(
    id: q.id,
    question: q.question,
    plan: q.detail!,
    approve: approve,
    decline: q.options.where((o) => o.label != approve.label).firstOrNull,
    callId: call as String?,
  );
}
