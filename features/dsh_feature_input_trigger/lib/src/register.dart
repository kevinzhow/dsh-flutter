import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'menu_view.dart';

final Slot<SessionOwner, Widget> _overlay = DshSlots.conversationInputOverlay
    .typed<SessionOwner, Widget>();

/// Occupy `conversation.input.overlay` with the candidate menu (id
/// `slash-menu`, order 0, as in dsh). The disposer withdraws it.
void Function() registerInputTriggerFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
}) => slots.register<SessionOwner, Widget>(
  _overlay,
  (owner) => owner.input?.triggers == null
      ? const SizedBox.shrink()
      : TriggerMenuOverlay(
          key: ValueKey('slash-menu-${owner.sessionId}'),
          sessionId: owner.sessionId,
          controller: owner.input!.triggers!,
          i18n: i18n(),
        ),
  id: 'slash-menu',
  order: 0,
);
