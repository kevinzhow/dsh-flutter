import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'general_section.dart';

final Slot<SettingsOwner, Widget> _sectionSlot = DshSlots.settingsSection
    .typed<SettingsOwner, Widget>();
final Slot<SettingsOwner, Widget> _itemSlot = DshSlots.settingsGeneralItem
    .typed<SettingsOwner, Widget>();

/// Fill `settings.section` with the General section (order 0) and
/// `settings.general.item` with the current version row (order 100), as dsh's
/// `ui-settings-general` does; every other row and page belongs to the feature
/// that owns the preference. [hostVersion] reads the release the host reports
/// (null while unknown: the row then shows nothing). Returns the disposer.
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
  return () {
    for (final off in offs) {
      off();
    }
  };
}
