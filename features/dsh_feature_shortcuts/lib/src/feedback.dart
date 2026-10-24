import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_shortcuts/dsh_shortcuts.dart';

/// Identify the unreadable preferences, their recovery path, and the bindings
/// still in use (dsh `shortcutReadFailure`). Localized recovery guidance that
/// never replaces the stored document.
String shortcutReadFailure(
  ShortcutConfigSnapshot config,
  ShortcutRuntime runtime,
  DshI18n i18n,
) {
  String t(String key, [Map<String, Object?> params = const {}]) =>
      i18n.t('shortcuts', key, params: params);
  final location = t(
    runtime == ShortcutRuntime.desktop ? 'desktop-document' : 'web-document',
  );
  final reload = t(
    runtime == ShortcutRuntime.desktop ? 'desktop-reload' : 'web-reload',
  );
  final error = switch (config.error) {
    ShortcutReadError.invalid => 'invalid',
    ShortcutReadError.future => 'future',
    _ => 'read',
  };
  return '${t(error, {'location': location, 'reload': reload})} '
      '${t(config.usingDefaults ? 'using-defaults' : 'using-accepted')}';
}

/// Describe an unsuccessful preference write without losing command names
/// (dsh `shortcutFailure`).
String shortcutFailure(
  ShortcutSaveResult result,
  List<({String id, String label})> catalog,
  DshI18n i18n,
  ShortcutRuntime runtime,
) {
  String t(String key, [Map<String, Object?> params = const {}]) =>
      i18n.t('shortcuts', key, params: params);
  if (result.status == ShortcutSaveStatus.unreadable) {
    return shortcutReadFailure(result.snapshot, runtime, i18n);
  }
  final issue = result.issue;
  if (issue != null) return t(issue.key);
  if (result.status == ShortcutSaveStatus.conflict) {
    final names = (result.conflicts ?? const <String>[])
        .map(
          (id) =>
              catalog
                  .where((row) => row.id == id)
                  .map((r) => r.label)
                  .firstOrNull ??
              id,
        )
        .join(', ');
    return t('conflict', {'commands': names});
  }
  return t(switch (result.status) {
    ShortcutSaveStatus.stale => 'stale',
    ShortcutSaveStatus.writeFailed => 'write-failed',
    ShortcutSaveStatus.notReady => 'not-ready',
    _ => 'write-failed',
  });
}
