import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'approval_panel.dart';
import 'approval_tracker.dart';

/// The typed view of dsh's `conversation.composer` slot for this feature; the
/// owner is the open session (`SessionOwner`, from `dsh_slots`).
final Slot<SessionOwner, Widget> composerSlot = DshSlots.conversationComposer
    .typed<SessionOwner, Widget>();

/// Register the approval takeover into `conversation.composer`, as dsh's
/// `ui-approval` does: the chain entry matches while the session has a pending
/// approval and renders the panel instead of the composer. The feature touches
/// nothing but the slot, the tracker and the i18n catalog.
void registerApprovalFeature(
  SlotRegistry slots, {
  required ApprovalTracker tracker,
  required DshI18n Function() i18n,
}) {
  slots.registerChain<SessionOwner, PendingApproval, Widget>(
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
