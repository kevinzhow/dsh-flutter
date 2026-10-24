// The wait status and Take time button of a timed question's card (dsh ui-user-questions QuestionComposer header).
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

QuestionCardSnapshot _card(String state, int seconds) {
  final countdown = Duration(seconds: seconds);
  return switch (state) {
    'counting' => QuestionCardSnapshot(
      phase: QuestionPhase.open,
      waitState: QuestionWaitState.counting,
      countdown: QuestionCountdown(countdown, true),
      channel: QuestionChannel.waterfall,
      closed: false,
      hidden: false,
    ),
    'paused' => QuestionCardSnapshot(
      phase: QuestionPhase.open,
      waitState: QuestionWaitState.focused,
      countdown: QuestionCountdown(countdown, false),
      channel: QuestionChannel.waterfall,
      closed: false,
      hidden: false,
    ),
    'held' => QuestionCardSnapshot(
      phase: QuestionPhase.open,
      waitState: QuestionWaitState.waiting,
      countdown: QuestionCountdown(Duration.zero, false),
      channel: QuestionChannel.waterfall,
      closed: false,
      hidden: false,
    ),
    _ => const QuestionCardSnapshot(
      phase: QuestionPhase.continued,
      waitState: QuestionWaitState.continued,
      countdown: null,
      channel: QuestionChannel.rpc,
      closed: false,
      hidden: false,
    ),
  };
}

final Map<String, ParityCase> questionWaitCases = {
  'question.wait': ParityCase(
    widgets: const ['dsh_feature_user_questions:QuestionWaitStrip'],
    // The element sits on the composer card's fill, not on the page's.
    framed: false,
    // The strip sits on the composer card's fill (`--dsw-specific-input-major`).
    build: (ctx) => Builder(
      builder: (context) => ColoredBox(
        color: context.dsh.color('--dsw-specific-input-major'),
        child: Align(
          alignment: Alignment.topLeft,
          child: parityItem(
            'wait-actions',
            QuestionWaitStrip(
              card: _card(
                ctx.props['state'] as String,
                (ctx.props['seconds'] as num? ?? 20).toInt(),
              ),
              i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
              onTakeTime: () {},
            ),
          ),
        ),
      ),
    ),
  ),
};
