import 'package:dsh_i18n/dsh_i18n.dart';

/// Machine value of the preset that requires an explicit risk acknowledgement.
const String fullAccessPreset = 'danger-full-access';

/// Machine value of the experimental current-session review preset.
const String autoReviewPreset = 'auto';

/// Locale namespace of the Settings row copy.
const String settingsPermissionNs = 'settings.permission';

/// Locale namespace of the current-session picker and its confirmations.
const String permissionAccessNs = 'permission.access';

const Map<String, String> _labelKeys = {
  'read-only': 'preset.readOnly',
  'workspace-write': 'preset.workspaceWrite',
  fullAccessPreset: 'preset.fullAccess',
};

/// Convert conventional kebab-case preset names into user-facing title case;
/// a name that is not kebab-case is returned unchanged (dsh `displayPresetName`).
String displayPresetName(String name) {
  if (!RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$').hasMatch(name)) return name;
  return name
      .split('-')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

/// Render a permission preset under its product label (dsh
/// `displayPermissionPreset`): the built-in label when the host's [name] is
/// the key itself or already the English label, else the host's own name in
/// title case.
String displayPermissionPreset(
  String value,
  String name,
  DshI18n i18n, {
  String namespace = settingsPermissionNs,
}) {
  final key = _labelKeys[value];
  if (key != null) {
    final english = DshI18n(DshLocale.en).t(namespace, key);
    if (name == value || name == english) return i18n.t(namespace, key);
  }
  return displayPresetName(name);
}
