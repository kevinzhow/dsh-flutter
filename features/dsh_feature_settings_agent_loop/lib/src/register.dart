import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'agent_loop_card.dart';
import 'agent_loop_card_controller.dart';

final Slot<PluginItemOwner, Widget> _itemSlot = DshSlots.pluginsItem
    .typed<PluginItemOwner, Widget>();

/// Register the agent loop's page into `plugins.item` (id `agent-loop`, order
/// 30, as dsh's `ui-settings-agent-loop` does) while the host serves the
/// `agent-loop` namespace, so a deployment that exposes no agent-loop settings
/// shows no trace of it. Returns the disposer, which withdraws the card and
/// releases the form subscription.
void Function() registerAgentLoopSettingsFeature(
  SlotRegistry slots, {
  required ConfigForms forms,
  required DshI18n Function() i18n,
}) {
  final controller = AgentLoopCardController(forms.get(agentLoopNamespace));
  final off = forms.whileServed(
    [agentLoopNamespace],
    (_) => slots.register<PluginItemOwner, Widget>(
      _itemSlot,
      (owner) =>
          AgentLoopCard(controller: controller, i18n: i18n(), view: owner.view),
      id: 'agent-loop',
      order: 30,
      label: () => i18n().t(agentLoopLocale, 'title'),
    ),
  );
  return () {
    off();
    controller.dispose();
  };
}
