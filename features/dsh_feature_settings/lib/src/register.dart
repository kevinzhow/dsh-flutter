import 'dart:async';

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'general_section.dart';
import 'plugins_section.dart';

final Slot<SettingsOwner, Widget> _sectionSlot = DshSlots.settingsSection
    .typed<SettingsOwner, Widget>();
final Slot<SettingsOwner, Widget> _itemSlot = DshSlots.settingsGeneralItem
    .typed<SettingsOwner, Widget>();
final Slot<PluginItemOwner, Widget> _pluginItemSlot = DshSlots.pluginsItem
    .typed<PluginItemOwner, Widget>();

/// Fill `settings.section` with the General section (order 0) and
/// `settings.general.item` with the current version row (order 100), as dsh's
/// `ui-settings-general` does; every other row and page belongs to the feature
/// that owns the preference. [hostVersion] reads the release the host reports
/// (null while unknown: the row then shows nothing).
///
/// Also owns the Plugins section (order 10, after General): it is registered
/// while at least one `plugins.item` occupant is, and withdrawn when the last
/// goes (one microtask after the slot changes), so a host that serves no plugin configuration shows no Plugins entry.
/// Returns the disposer.
void Function() registerSettingsFeature(
  SlotRegistry slots, {
  required DshI18n Function() i18n,
  required String? Function() hostVersion,
}) {
  final offs = [
    slots.register<SettingsOwner, Widget>(
      _sectionSlot,
      (owner) => GeneralSection(slots: slots),
      id: 'general',
      order: 0,
      label: () => i18n().t('settings', 'general.nav'),
    ),
    slots.register<SettingsOwner, Widget>(
      _itemSlot,
      (owner) => CurrentVersionRow(version: hostVersion(), i18n: i18n()),
      id: 'current-version',
      order: 100,
    ),
  ];
  void Function()? offPlugins;
  void syncPlugins() {
    final any = slots.entries(_pluginItemSlot).isNotEmpty;
    if (any && offPlugins == null) {
      offPlugins = slots.register<SettingsOwner, Widget>(
        _sectionSlot,
        (owner) => PluginsSection(slots: slots, i18n: i18n),
        id: 'plugins',
        order: 10,
        // dsh's own nav entry `settings.plugins` reads "Built-in plugins": that
        // is the read-only inventory, not this. The page that lists the
        // official plugins' configuration cards is dsh's Plugins page, and dsh
        // has a plain "Plugins" for it (the `pluginManager` dictionary's
        // `title`), so the client's `settings.plugins.nav` app key is not
        // needed here.
        label: () => i18n().t('pluginManager', 'title'),
      );
    } else if (!any && offPlugins != null) {
      offPlugins!();
      offPlugins = null;
    }
  }

  // The registry's change stream is synchronous and cannot be re-entered, and
  // registering the section from inside a `plugins.item` notification would
  // do exactly that: the section follows one microtask later.
  var disposed = false;
  var scheduled = false;
  final sub = slots.changes.listen((name) {
    if (name != _pluginItemSlot.name || scheduled) return;
    scheduled = true;
    scheduleMicrotask(() {
      scheduled = false;
      if (!disposed) syncPlugins();
    });
  });
  syncPlugins();
  return () {
    disposed = true;
    unawaited(sub.cancel());
    offPlugins?.call();
    offPlugins = null;
    for (final off in offs) {
      off();
    }
  };
}
