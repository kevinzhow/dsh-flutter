import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'question_card.dart';

/// What a question card says about its wait, as dsh's composer header does
/// (`QuestionComposer.module.css` `.waitStatus` and `.waitButton`): while the
/// countdown counts, its remaining seconds and a "Take time" button; once the
/// person asked for time or started answering, that the wait is held; once the
/// agent went on without an answer, that the question stays answerable. Draws
/// nothing for a question that has no deadline.
class QuestionWaitStrip extends StatelessWidget {
  const QuestionWaitStrip({
    super.key,
    required this.card,
    required this.i18n,
    required this.onTakeTime,
  });

  final QuestionCardSnapshot card;
  final DshI18n i18n;

  /// The button's action; null disables it (a submission is in flight).
  final VoidCallback? onTakeTime;

  /// Whether [card] has anything to say about its wait.
  static bool shows(QuestionCardSnapshot card) =>
      card.phase == QuestionPhase.continued || (card.countdown != null);

  String _q(String key, [Map<String, Object?> params = const {}]) =>
      i18n.t('question', key, params: params);

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final countdown = card.countdown;
    final counting =
        countdown != null &&
        card.waitState != QuestionWaitState.waiting &&
        card.waitState != QuestionWaitState.editing &&
        card.waitState != QuestionWaitState.continued;
    final held =
        countdown != null &&
        (card.waitState == QuestionWaitState.waiting ||
            card.waitState == QuestionWaitState.editing);
    final String? text;
    if (card.phase == QuestionPhase.continued) {
      text = _q('wait.continued');
    } else if (counting) {
      text = _q(countdown.running ? 'wait.countdown' : 'wait.paused', {
        'seconds': countdown.seconds,
      });
    } else if (held) {
      text = _q('wait.held');
    } else {
      text = null;
    }
    if (text == null) return const SizedBox.shrink();
    // 12px on a 24px line, `--dsw-alias-label-secondary`, one line.
    final style = theme
        .textStyle('--dsw-font-xxs-12')
        .copyWith(color: theme.labelSecondary, height: 2);
    return Row(
      key: const ValueKey('question-wait-strip'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: DshChromeText(
            text,
            key: const ValueKey('question-wait-status'),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        if (counting && card.phase != QuestionPhase.continued) ...[
          const SizedBox(width: 4),
          DshButton(
            key: const ValueKey('question-take-time'),
            variant: DshButtonVariant.outline,
            onPressed: onTakeTime,
            child: DshChromeText(_q('wait.takeTime'), softWrap: false),
          ),
        ],
      ],
    );
  }
}
