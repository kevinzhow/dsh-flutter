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
  });

  factory QuestionItem.fromWire(Map<String, Object?> json) => QuestionItem(
    id: '${json['id']}',
    question: '${json['question']}',
    detail: json['detail'] as String?,
    header: json['header'] as String?,
    multiSelect: json['multiSelect'] == true,
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
