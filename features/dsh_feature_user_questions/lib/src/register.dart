import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'question_panel.dart';
import 'question_tracker.dart';

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
  slots.registerChain<SessionOwner, PendingQuestion, Widget>(
    composerSlot,
    id: 'user-questions',
    select: (owner) => tracker.forSession(owner.sessionId),
    builder: (owner, matched) => QuestionPanel(
      key: ValueKey(matched.key),
      pending: matched,
      i18n: i18n(),
    ),
  );
}
