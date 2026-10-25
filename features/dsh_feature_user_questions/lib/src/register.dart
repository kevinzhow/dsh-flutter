import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'question_panel.dart';
import 'plan_review_panel.dart';
import 'question_tracker.dart';
import 'question_reply_view.dart';

/// `conversation.composer` as this feature uses it.
final Slot<SessionOwner, Widget> composerSlot = DshSlots.conversationComposer
    .typed<SessionOwner, Widget>();

/// Register the question takeover into `conversation.composer`, as dsh's
/// `ui-user-questions` does: the chain entry matches while the session has a
/// pending question and renders the panel instead of the composer.
void registerUserQuestionsFeature(
  SlotRegistry slots, {
  required QuestionTracker tracker,
  required DshI18n Function() i18n,
}) {
  slots.register<ChatNodeOwner, Widget>(
    DshSlots.conversationChatNode.typed<ChatNodeOwner, Widget>(),
    (owner) => QuestionReplyView(
      data: owner.node.data as QuestionReplyData,
      i18n: i18n(),
    ),
    key: 'question-reply',
  );
  slots.registerChain<SessionOwner, PendingQuestion, Widget>(
    composerSlot,
    id: 'user-questions',
    select: (owner) => tracker.forSession(owner.sessionId),
    builder: (owner, matched) {
      final review = planReviewOf(matched.questions);
      return review == null
          ? QuestionPanel(
              key: ValueKey(matched.key),
              pending: matched,
              i18n: i18n(),
            )
          : PlanReviewPanel(
              key: ValueKey(matched.key),
              pending: matched,
              review: review,
              owner: owner,
              slots: slots,
              i18n: i18n(),
            );
    },
  );
}
