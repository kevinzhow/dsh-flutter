import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'tool_card.dart';

/// `conversation.chat.node` as this feature uses it.
final Slot<ChatNodeOwner, Widget> chatNodeSlot = DshSlots.conversationChatNode
    .typed<ChatNodeOwner, Widget>();

/// `tool.call.toolview` as this feature uses it.
final Slot<ToolViewOwner, Widget> toolViewSlot = DshSlots.toolCallToolview
    .typed<ToolViewOwner, Widget>();

/// Occupy `conversation.chat.node[tool-call]`: the chat renders a tool row by
/// asking `tool.call.toolview` for a view keyed by the tool's wire name and
/// falling back to the generic [ToolCard].
void registerToolFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
}) {
  slots.register<ChatNodeOwner, Widget>(chatNodeSlot, (owner) {
    final data = owner.node.data as ToolData;
    final specific = slots.renderKeyed(
      toolViewSlot,
      data.root.name,
      ToolViewOwner(session: owner.session, call: data.root),
    );
    return specific ?? ToolCard(call: data.root, i18n: i18n());
  }, key: 'tool-call');
}
