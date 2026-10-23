import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import '../model/ask_model.dart';

/// The ask-user transcript: answered questions with their answers, or the
/// unanswered list under a verdict (dsh `AskQuestionCard`).
class AskCardView extends StatelessWidget {
  const AskCardView({super.key, required this.card});

  final AskCard card;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final base = theme.textStyle('--dsw-font-s-14').copyWith(height: 24 / 14);
    final tertiary = theme.color('--dsw-alias-label-tertiary');
    final Widget body = switch (card) {
      UnansweredAsk(:final questions, :final verdict) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(verdict, style: base.copyWith(color: theme.labelPrimary)),
          const SizedBox(height: 16),
          for (var i = 0; i < questions.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(
                questions[i].question,
                style: base.copyWith(color: tertiary),
              ),
            ),
          ],
        ],
      ),
      AnsweredAsk(:final questions, :final skippedLabel) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < questions.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            Text(questions[i].question, style: base.copyWith(color: tertiary)),
            const SizedBox(height: 2),
            if (questions[i].answers.isEmpty)
              Text(skippedLabel, style: base.copyWith(color: tertiary))
            else
              for (final a in questions[i].answers)
                Text(a, style: base.copyWith(color: theme.labelPrimary)),
          ],
        ],
      ),
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: Container(
        key: const ValueKey('ask-card'),
        decoration: BoxDecoration(
          color: theme.bgBase,
          borderRadius: BorderRadius.circular(theme.radiusLg),
          border: Border.all(
            color: theme.color('--dsw-alias-border-l1'),
            width: dshHairline,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: SizedBox(width: double.infinity, child: body),
        ),
      ),
    );
  }
}
