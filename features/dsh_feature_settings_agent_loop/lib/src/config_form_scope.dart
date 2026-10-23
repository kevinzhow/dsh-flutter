import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';

/// Adapts the shared configuration form of one Host entry ([ConfigForm], the
/// models layer) to what the staged form model reads ([SettingsFormScope], the
/// ui layer, which imports neither the client nor the models).
///
/// Every `ui-settings-*` page needs the same adapter; features never import
/// each other, so each carries this one.
class ConfigFormScope implements SettingsFormScope {
  ConfigFormScope(this._form);

  final ConfigForm _form;

  @override
  SettingsFormScopeSnapshot get snapshot {
    final s = _form.snapshot;
    return SettingsFormScopeSnapshot(
      status: switch (s.status) {
        ConfigFormStatus.loading => SettingsScopeStatus.loading,
        ConfigFormStatus.ready => SettingsScopeStatus.ready,
        ConfigFormStatus.unavailable => SettingsScopeStatus.unavailable,
      },
      value: s.value,
      base: s.base,
      user: s.user,
      writable: s.writable,
      revision: s.revision,
    );
  }

  @override
  void Function() subscribe(void Function() listener) =>
      _form.subscribe(listener);

  @override
  Future<bool> mutate(List<SettingsFormPathOp> ops, {int? expectedRevision}) =>
      _form.mutate([
        for (final op in ops)
          switch (op) {
            SettingsFormSetOp() => SetOp(op.path, op.value),
            SettingsFormUnsetOp() => UnsetOp(op.path),
          },
      ], expectedRevision: expectedRevision);
}
