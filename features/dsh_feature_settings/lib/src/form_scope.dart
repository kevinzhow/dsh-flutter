import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_ui/dsh_ui.dart';

/// A feature adapter: the pure UI form does not import the models layer.
class ConfigFormScope implements SettingsFormScope {
  ConfigFormScope(this.form);
  final ConfigForm form;
  @override
  SettingsFormScopeSnapshot get snapshot {
    final v = form.snapshot;
    return SettingsFormScopeSnapshot(
      status: switch (v.status) {
        ConfigFormStatus.loading => SettingsScopeStatus.loading,
        ConfigFormStatus.ready => SettingsScopeStatus.ready,
        ConfigFormStatus.unavailable => SettingsScopeStatus.unavailable,
      },
      value: v.value,
      user: v.user,
      base: v.base,
      revision: v.revision,
      writable: v.writable,
    );
  }

  @override
  void Function() subscribe(void Function() listener) =>
      form.subscribe(listener);
  @override
  Future<bool> mutate(List<SettingsFormPathOp> ops, {int? expectedRevision}) =>
      form.mutate([
        for (final op in ops)
          switch (op) {
            SettingsFormSetOp() => SetOp(op.path, op.value),
            SettingsFormUnsetOp() => UnsetOp(op.path),
          },
      ], expectedRevision: expectedRevision);
}

/// A number field with the extra whole-number constraints of Subagent limits.
SettingsFieldSpec settingsLimitField(String field, int minimum) {
  final numeric = settingsNumberField(field);
  return SettingsFieldSpec(
    field: field,
    format: numeric.format,
    parse: (text) {
      final write = numeric.parse(text);
      if (write is! SettingsFieldSet) return write;
      final value = write.value;
      return value is num &&
              value.isFinite &&
              value >= minimum &&
              value <= 9007199254740991 &&
              value == value.truncateToDouble() &&
              !(value == 0 && value.isNegative)
          ? write
          : null;
    },
  );
}
