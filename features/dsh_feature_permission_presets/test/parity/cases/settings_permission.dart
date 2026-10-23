// dsh's PermissionRow (ui-permission-presets) with the Flutter row of this feature, over the same props
// as the React host (tool/parity-ext/build-settings.py, kind settings.permission). The row's state is
// fixed, as the React host's store snapshot is; only the closed selector pill is captured.
import 'package:dsh_feature_permission_presets/dsh_feature_permission_presets.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_parity/dsh_parity.dart';

/// A [PermissionDefaults] that holds the state a case describes and does nothing else.
class FixedPermissionDefaults implements PermissionDefaults {
  FixedPermissionDefaults(PermissionSettingsState state)
    : state = Observable(state);

  /// Reads the `state` prop of the manifest (`status`, `error`, `writable`, `currentValue`, `options`).
  factory FixedPermissionDefaults.fromJson(Map<String, dynamic> json) =>
      FixedPermissionDefaults(
        PermissionSettingsState(
          status: PermissionRowStatus.values.byName(json['status'] as String),
          error: json['error'] as String?,
          writable: json['writable'] as bool,
          currentValue: json['currentValue'] as String,
          options: [
            for (final o
                in (json['options'] as List).cast<Map<String, dynamic>>())
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

final Map<String, ParityCase> settingsPermissionCases = {
  'settings.permission': ParityCase(
    widgets: const ['dsh_feature_permission_presets:PermissionRow'],
    build: (ctx) => ParityStack(
      layout: ctx.layout,
      children: [
        PermissionRow(
          controller: FixedPermissionDefaults.fromJson(
            (ctx.props['state'] as Map).cast<String, dynamic>(),
          ),
          i18n: DshI18n(DshLocale.fromTag(ctx.locale)),
        ),
      ],
    ),
  ),
};
