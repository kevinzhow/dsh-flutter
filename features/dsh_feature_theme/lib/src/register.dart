import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:flutter/widgets.dart';

import 'theme_rows.dart';
import 'theme_service.dart';

final Slot<SettingsOwner, Widget> _generalItem = DshSlots.settingsGeneralItem
    .typed<SettingsOwner, Widget>();

/// Register the Appearance row (order 10) and the font settings group (order
/// 11) into `settings.general.item`, as dsh's `ui-theme` does. The `touch`
/// flag keeps the font stepper arrows visible where there is no hover.
void registerThemeFeature(
  SlotRegistry slots, {
  required ThemeSettingsService service,
  required DshI18n Function() i18n,
  bool touch = false,
}) {
  slots.register<SettingsOwner, Widget>(
    _generalItem,
    (owner) => AppearanceRow(service: service, i18n: i18n()),
    id: 'appearance',
    order: 10,
  );
  slots.register<SettingsOwner, Widget>(
    _generalItem,
    (owner) => FontSettingsGroup(service: service, i18n: i18n(), touch: touch),
    id: 'font-size',
    order: 11,
  );
}
