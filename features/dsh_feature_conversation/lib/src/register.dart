import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'session_header.dart';
import 'shell.dart';
import 'todo_panel.dart';

/// `conversation.session` as this feature uses it.
final Slot<SessionOwner, Widget> sessionSlot = DshSlots.conversationSession
    .typed<SessionOwner, Widget>();

/// `conversation.header` as this feature uses it.
final Slot<SessionOwner, Widget> headerSlot = DshSlots.conversationHeader
    .typed<SessionOwner, Widget>();

final Slot<SessionOwner, Widget> _viewSlot = DshSlots.conversationView
    .typed<SessionOwner, Widget>();
final Slot<SessionOwner, Widget> _composerSlot = DshSlots.conversationComposer
    .typed<SessionOwner, Widget>();

/// Occupy `conversation.session` (the shell) and `conversation.header` (title
/// and model indicator). The shell composes the view list and the composer
/// chain that other features fill.
void registerConversationFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
}) {
  slots.register<SessionOwner, Widget>(
    sessionSlot,
    (owner) => ConversationShell(
      owner: owner,
      slots: slots,
      i18n: i18n(),
      viewSlot: _viewSlot,
      composerSlot: _composerSlot,
      dockSlot: DshSlots.conversationInputDock.typed<SessionOwner, Widget>(),
    ),
  );
  slots.register<SessionOwner, Widget>(
    DshSlots.conversationInputDock.typed<SessionOwner, Widget>(),
    (owner) => TodoDock(owner: owner, i18n: i18n()),
    id: 'todo',
    order: 0,
  );
  slots.register<SessionOwner, Widget>(
    headerSlot,
    (owner) => SessionHeader(owner: owner, i18n: i18n()),
  );
}
