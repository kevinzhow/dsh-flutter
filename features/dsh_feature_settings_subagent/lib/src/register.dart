import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'subagent_card.dart';
import 'subagent_limits_card_controller.dart';

final Slot<PluginItemOwner, Widget> _itemSlot = DshSlots.pluginsItem
    .typed<PluginItemOwner, Widget>();

/// Register the Subagent page into `plugins.item` (id `subagent`, order 10, as
/// dsh's `ui-settings-subagent` does) while the host serves the `subagent`
/// namespace. dsh keeps the card while either of its two namespaces is served;
/// this page has only the limits, so it follows `subagent` alone and never
/// shows an empty card on a host that serves only the model selection.
/// Returns the disposer, which withdraws the card and releases the form
/// subscription.
void Function() registerSubagentSettingsFeature(
  SlotRegistry slots, {
  required ConfigForms forms,
  required DshI18n Function() i18n,
}) {
  final controller = SubagentLimitsCardController(forms.get(subagentNamespace));
  final off = forms.whileServed(
    [subagentNamespace],
    (_) => slots.register<PluginItemOwner, Widget>(
      _itemSlot,
      (owner) =>
          SubagentCard(controller: controller, i18n: i18n(), view: owner.view),
      id: 'subagent',
      order: 10,
      label: () => i18n().t(subagentLocale, 'subagentTitle'),
    ),
  );
  return () {
    off();
    controller.dispose();
  };
}
