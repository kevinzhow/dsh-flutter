import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'approval_panel.dart';
import 'approval_tracker.dart';

/// Owner props of `conversation.composer` (a chain slot, session scope): the
/// session whose composer is being rendered. In dsh the owner is
/// `ComposerChainProps`; phase 0 needs only the session id.
class ComposerOwner {
  const ComposerOwner(this.sessionId);
  final String sessionId;
}

/// The typed view of dsh's `conversation.composer` slot for this feature.
final Slot<ComposerOwner, Widget> composerSlot = DshSlots.conversationComposer
    .typed<ComposerOwner, Widget>();

/// Register the approval takeover into `conversation.composer`, as dsh's
/// `ui-approval` does: the chain entry matches while the session has a pending
/// approval and renders the panel instead of the composer. The feature touches
/// nothing but the slot, the tracker and the i18n catalog.
void registerApprovalFeature(
  SlotRegistry slots, {
  required ApprovalTracker tracker,
  required DshI18n Function() i18n,
}) {
  slots.registerChain<ComposerOwner, PendingApproval, Widget>(
    composerSlot,
    id: 'approval',
    select: (owner) => tracker.forSession(owner.sessionId),
    builder: (owner, matched) => ApprovalPanel(
      key: ValueKey(matched.key),
      approval: matched,
      i18n: i18n(),
    ),
  );
}
