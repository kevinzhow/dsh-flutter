// The General section as the app composes it (kind settings.general, props as the React host's): the
// real GeneralSection over the `settings.general.item` slot, with the theme feature's real rows and the
// permission row in its dsh order (permission -20, appearance 10, font-size 11). The permission state is
// fixed, as the React host's store snapshot is.
import 'package:dsh_feature_permission_presets/dsh_feature_permission_presets.dart';
import 'package:dsh_feature_settings/dsh_feature_settings.dart';
import 'package:dsh_feature_theme/dsh_feature_theme.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_parity/dsh_parity.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/widgets.dart';

class _FixedPermission implements PermissionDefaults {
  _FixedPermission(Map<String, dynamic> json)
    : state = Observable(
        PermissionSettingsState(
          status: PermissionRowStatus.values.byName(json['status'] as String),
          error: json['error'] as String?,
          writable: json['writable'] as bool,
          currentValue: json['currentValue'] as String,
          options: [
            for (final o in (json['options'] as List).cast<Map<String, dynamic>>())
              PermissionDefaultOption(o['id'] as String, o['label'] as String),
          ],
        ),
      );

  @override
  final Observable<PermissionSettingsState> state;
  @override
  Future<void> load() async {}
  @override
  Future<void> select(String preset) async {}
}

final Map<String, ParityCase> settingsGeneralCases = {
  'settings.general': ParityCase(
    widgets: const [
      'dsh_feature_settings:GeneralSection',
      'dsh_feature_theme:AppearanceRow',
      'dsh_feature_theme:FontSettingsGroup',
      'dsh_feature_permission_presets:PermissionRow',
    ],
    build: (ctx) {
      final props = ctx.props;
      final i18n = DshI18n(DshLocale.fromTag(ctx.locale));
      final sizes = (props['fontSizes'] as Map).cast<String, dynamic>();
      final families = (props['fontFamilies'] as Map).cast<String, dynamic>();
      final settings = ThemeSettings(
        preference: ThemePreference.tryParse(props['preference'])!,
        fontSize: (sizes['text'] as num).toInt(),
        codeFontSize: (sizes['code'] as num).toInt(),
        terminalFontSize: (sizes['terminal'] as num).toInt(),
        textFontFamily: families['text'] as String,
        codeFontFamily: families['code'] as String,
        terminalFontFamily: families['terminal'] as String,
      );
      final permission = _FixedPermission(
        (props['permission'] as Map).cast<String, dynamic>(),
      );
      final service = ThemeSettingsService(
        host: FakeConfigForm(
          ConfigFormSnapshot(
            status: ConfigFormStatus.ready,
            value: settings.toJson(),
            base: ThemeSettings().toJson(),
            user: const {},
            revision: 0,
            writable: (permission.state.value.writable),
          ),
        ),
      );
      final slots = SlotRegistry();
      for (final s in DshSlots.all) {
        slots.declare(s);
      }
      registerThemeFeature(slots, service: service, i18n: () => i18n);
      slots.register<SettingsOwner, Widget>(
        DshSlots.settingsGeneralItem.typed<SettingsOwner, Widget>(),
        (_) => PermissionRow(controller: permission, i18n: i18n),
        id: 'permission',
        order: -20,
      );
      // The section is a scroll view in the app; the frame gives its column the content height here.
      return GeneralColumn(slots: slots);
    },
  ),
};
