import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'shell_card.dart';
import 'shell_card_controller.dart';

final Slot<PluginItemOwner, Widget> _itemSlot = DshSlots.pluginsItem
    .typed<PluginItemOwner, Widget>();

/// Register the shell executor's page into `plugins.item` (id `shell`, order
/// 40, as dsh's `ui-settings-shell` does) while the host serves the shell
/// executor's namespace, so a deployment without a local shell executor shows
/// no trace of it. The base bundle composes exactly one executor per platform;
/// the card binds the served one (PowerShell when both are served). Returns the
/// disposer, which withdraws the card and releases the form subscriptions.
void Function() registerShellSettingsFeature(
  SlotRegistry slots, {
  required ConfigForms forms,
  required DshI18n Function() i18n,
}) {
  final bash = ShellCardController(forms.get(bashNamespace));
  final pwsh = ShellCardController(forms.get(pwshNamespace));
  final off = forms.whileServed([bashNamespace, pwshNamespace], (served) {
    final controller = served.contains(pwshNamespace) ? pwsh : bash;
    return slots.register<PluginItemOwner, Widget>(
      _itemSlot,
      (owner) =>
          ShellCard(controller: controller, i18n: i18n(), view: owner.view),
      id: 'shell',
      order: 40,
      label: () => i18n().t(shellLocale, 'title'),
    );
  });
  return () {
    off();
    bash.dispose();
    pwsh.dispose();
  };
}
