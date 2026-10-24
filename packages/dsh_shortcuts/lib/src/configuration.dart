/// Validated preference documents and deterministic conflict resolution, without
/// UI or storage dependencies (dsh `shortcuts/src/configuration.ts`).
library;

import 'dart:convert';

import 'binding.dart';

/// Overrides are platform-local; absent commands inherit defaults and a null
/// binding explicitly unbinds.
class ShortcutDocument {
  const ShortcutDocument({required this.schemaVersion, required this.profiles});

  /// An empty version 1 document: nothing is overridden.
  const ShortcutDocument.empty() : schemaVersion = 1, profiles = const {};

  final int schemaVersion;
  final Map<String, Map<String, ShortcutBinding?>> profiles;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'profiles': {
      for (final p in profiles.entries)
        p.key: {for (final o in p.value.entries) o.key: o.value?.toJson()},
    },
  };

  @override
  bool operator ==(Object other) {
    if (other is! ShortcutDocument || other.schemaVersion != schemaVersion) {
      return false;
    }
    if (other.profiles.length != profiles.length) return false;
    for (final entry in profiles.entries) {
      final o = other.profiles[entry.key];
      if (o == null || o.length != entry.value.length) return false;
      for (final e in entry.value.entries) {
        if (!o.containsKey(e.key) || o[e.key] != e.value) return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(schemaVersion, profiles.length);
}

/// Serializable command definitions. Fixed actions reserve one or more
/// combinations instead of exposing an editable default.
class ShortcutDefinition {
  const ShortcutDefinition({
    required this.id,
    this.defaults = const {},
    this.fixed,
  });

  final String id;
  final Map<String, ShortcutBinding> defaults;
  final List<ShortcutBinding>? fixed;
}

/// Validation failures select localized copy in the UI.
enum BindingIssue {
  reserved('reserved'),
  unsupportedBrowser('unsupported-browser'),
  modifierRequired('modifier-required'),
  unsupportedKey('unsupported-key');

  const BindingIssue(this.key);

  /// The dictionary key of the issue's copy.
  final String key;
}

/// A conflicting row keeps its requested binding visible but cannot execute it.
class EffectiveShortcut {
  const EffectiveShortcut({
    required this.id,
    required this.binding,
    required this.modified,
    required this.conflicts,
    required this.issue,
  });

  final String id;
  final NormalizedBinding? binding;
  final bool modified;
  final List<String> conflicts;
  final BindingIssue? issue;
}

/// One revision-checked preference edit, limited to the current runtime and platform.
sealed class ShortcutEdit {
  const ShortcutEdit();
}

class SetShortcut extends ShortcutEdit {
  const SetShortcut(this.id, this.binding);

  final String id;
  final ShortcutBinding? binding;
}

class ResetShortcut extends ShortcutEdit {
  const ResetShortcut(this.id);

  final String id;
}

class ResetAllShortcuts extends ShortcutEdit {
  const ResetAllShortcuts();
}

final RegExp _commandPattern = RegExp(
  r'^[a-z][a-zA-Z0-9-]*(?:\.[a-zA-Z][a-zA-Z0-9-]*)+$',
);
final RegExp _profilePattern = RegExp(r'^(desktop|web):(macos|windows|linux)$');

bool _isRecord(Object? value) => value is Map<String, Object?>;

/// Validate JSON binding fields before normalization; unknown fields are
/// rejected to prevent lossy rewrites. Null is explicit removal. Throws
/// [ShortcutBindingError] on any malformed input.
ShortcutBinding? parseBinding(Object? value) {
  if (value == null) return null;
  if (value is! Map<String, Object?> ||
      value.keys.any(
        (k) => k != 'code' && k != 'secondCode' && k != 'modifiers',
      ) ||
      value['code'] is! String ||
      value['modifiers'] is! List ||
      (value.containsKey('secondCode') && value['secondCode'] is! String)) {
    throw ShortcutBindingError('Invalid shortcut binding');
  }
  final modifiers = <ShortcutModifier>[];
  for (final m in value['modifiers'] as List) {
    final parsed = m is String
        ? ShortcutModifier.values.where((v) => v.name == m).firstOrNull
        : null;
    if (parsed == null) throw ShortcutBindingError('Invalid shortcut binding');
    modifiers.add(parsed);
  }
  final binding = ShortcutBinding(
    value['code'] as String,
    modifiers,
    value['secondCode'] as String?,
  );
  normalizeBinding(binding, ShortcutPlatform.windows);
  return binding;
}

/// A classified read failure of a stored document.
enum ShortcutDocumentError { invalid, future }

/// The result of reading a document: the document, or why it was refused.
class ParsedShortcutDocument {
  const ParsedShortcutDocument._(this.document, this.error);

  final ShortcutDocument? document;
  final ShortcutDocumentError? error;
}

/// Decode the complete document while preserving dormant command overrides.
/// A missing document (null) is an empty version 1 document.
ParsedShortcutDocument parseShortcutDocument(String? raw) {
  const invalid = ParsedShortcutDocument._(null, ShortcutDocumentError.invalid);
  if (raw == null) {
    return const ParsedShortcutDocument._(ShortcutDocument.empty(), null);
  }
  try {
    final value = jsonDecode(raw);
    if (!_isRecord(value)) return invalid;
    final map = value as Map<String, Object?>;
    final version = map['schemaVersion'];
    if (version is num && version > 2) {
      return const ParsedShortcutDocument._(null, ShortcutDocumentError.future);
    }
    if ((version != 1 && version != 2) ||
        !_isRecord(map['profiles']) ||
        map.keys.any((k) => k != 'schemaVersion' && k != 'profiles')) {
      return invalid;
    }
    final profiles = <String, Map<String, ShortcutBinding?>>{};
    for (final entry in (map['profiles']! as Map<String, Object?>).entries) {
      if (!_profilePattern.hasMatch(entry.key) || !_isRecord(entry.value)) {
        return invalid;
      }
      final bindings = <String, ShortcutBinding?>{};
      for (final o in (entry.value! as Map<String, Object?>).entries) {
        if (!_commandPattern.hasMatch(o.key)) return invalid;
        final parsed = parseBinding(o.value);
        if (version == 1 && parsed?.secondCode != null) return invalid;
        bindings[o.key] = parsed;
      }
      profiles[entry.key] = bindings;
    }
    return ParsedShortcutDocument._(
      ShortcutDocument(schemaVersion: version! as int, profiles: profiles),
      null,
    );
  } on Object {
    // Invalid JSON and invalid binding fields both preserve the original document.
    return invalid;
  }
}

/// Check system, editor and browser reservations using expanded physical
/// modifiers. The rejection reason, or null when the combination is allowed.
BindingIssue? bindingIssue(
  NormalizedBinding binding,
  ShortcutRuntime runtime,
  ShortcutPlatform platform,
) {
  final code = binding.code;
  final modifiers = binding.modifiers;
  if (runtime == ShortcutRuntime.desktop &&
      (platform == ShortcutPlatform.windows ||
          platform == ShortcutPlatform.macos)) {
    return null;
  }
  if (binding.secondCode != null) return BindingIssue.unsupportedKey;
  if (modifiers.isEmpty ||
      modifiers.every((m) => m == ShortcutModifier.shift)) {
    return BindingIssue.modifierRequired;
  }
  if ((platform == ShortcutPlatform.windows ||
          platform == ShortcutPlatform.macos) &&
      modifiers.length >= 3) {
    return null;
  }
  if (runtime == ShortcutRuntime.web &&
      (platform == ShortcutPlatform.windows ||
          platform == ShortcutPlatform.macos) &&
      isWebBindingAllowed(binding, platform)) {
    return null;
  }
  final primary = modifiers.contains(
    platform == ShortcutPlatform.macos
        ? ShortcutModifier.meta
        : ShortcutModifier.control,
  );
  const navigation = [
    'Escape',
    'Tab',
    'Space',
    'Backspace',
    'Delete',
    'ArrowUp',
    'ArrowDown',
    'ArrowLeft',
    'ArrowRight',
  ];
  final isMac = platform == ShortcutPlatform.macos;
  if (navigation.contains(code) ||
      (code == 'Enter' && !modifiers.contains(ShortcutModifier.alt)) ||
      (primary &&
          [
            'KeyC',
            'KeyV',
            'KeyX',
            'KeyZ',
            'KeyY',
            'KeyQ',
            'KeyH',
          ].contains(code)) ||
      (primary &&
          code == 'KeyA' &&
          !modifiers.contains(ShortcutModifier.shift)) ||
      (!isMac &&
          (modifiers.contains(ShortcutModifier.meta) ||
              (modifiers.contains(ShortcutModifier.alt) &&
                  ['F4', 'F2'].contains(code)))) ||
      (isMac &&
          modifiers.contains(ShortcutModifier.control) &&
          modifiers.contains(ShortcutModifier.meta)) ||
      (isMac && modifiers.contains(ShortcutModifier.alt) && !primary)) {
    return BindingIssue.reserved;
  }
  if (runtime == ShortcutRuntime.web &&
      !isWebBindingAllowed(binding, platform)) {
    return BindingIssue.unsupportedBrowser;
  }
  return null;
}

/// The command owner's explicit default for one device profile, or null for an
/// unbound action.
ShortcutBinding? resolveShortcutDefault(
  ShortcutDefinition definition,
  ShortcutRuntime runtime,
  ShortcutPlatform platform,
) => definition.defaults[shortcutProfile(runtime, platform)];

/// Detect identical combinations or a single key contained in a two-key chord:
/// both bindings must require the same modifiers and overlap.
bool overlappingBindings(NormalizedBinding left, NormalizedBinding right) {
  if (left.modifiers.map((m) => m.name).join('+') !=
      right.modifiers.map((m) => m.name).join('+')) {
    return false;
  }
  if (left.secondCode != null && right.secondCode != null) {
    return bindingKey(left) == bindingKey(right);
  }
  return [left.code, left.secondCode].any(
    (code) => code != null && (code == right.code || code == right.secondCode),
  );
}

/// Resolve overrides and conflicts independently of registration order.
/// Explicit overrides displace defaults. Every active command, including
/// unavailable conflicting bindings.
List<EffectiveShortcut> effectiveShortcuts(
  List<ShortcutDefinition> definitions,
  ShortcutDocument document,
  ShortcutRuntime runtime,
  ShortcutPlatform platform,
) {
  final overrides =
      document.profiles[shortcutProfile(runtime, platform)] ?? const {};
  final fixed = [
    for (final row in definitions)
      for (final b in row.fixed ?? const <ShortcutBinding>[])
        (id: row.id, binding: normalizeBinding(b, platform)),
  ];
  final rows = [
    for (final d in definitions)
      if (d.fixed == null)
        () {
          final modified = overrides.containsKey(d.id);
          final candidate = modified
              ? overrides[d.id]
              : resolveShortcutDefault(
                  ShortcutDefinition(id: d.id, defaults: d.defaults),
                  runtime,
                  platform,
                );
          final binding = candidate == null
              ? null
              : normalizeBinding(candidate, platform);
          return (
            id: d.id,
            binding: binding,
            modified: modified,
            issue: binding == null
                ? null
                : bindingIssue(binding, runtime, platform),
          );
        }(),
  ];
  return [
    for (final row in rows)
      EffectiveShortcut(
        id: row.id,
        binding: row.binding,
        modified: row.modified,
        issue: row.issue,
        conflicts: row.binding == null
            ? const []
            : {
                ...rows
                    .where(
                      (o) =>
                          o.id != row.id &&
                          o.binding != null &&
                          o.issue == null &&
                          overlappingBindings(o.binding!, row.binding!) &&
                          (!row.modified || o.modified),
                    )
                    .map((o) => o.id),
                ...fixed
                    .where((o) => overlappingBindings(o.binding, row.binding!))
                    .map((o) => o.id),
              }.toList(),
      ),
  ];
}

/// Apply an edit without modifying other profiles or dormant overrides. The
/// candidate document, pending conflict checks and durable storage.
ShortcutDocument editShortcutDocument(
  ShortcutDocument document,
  ShortcutEdit edit,
  ShortcutRuntime runtime,
  ShortcutPlatform platform,
) {
  final schemaVersion =
      runtime == ShortcutRuntime.desktop &&
          (platform == ShortcutPlatform.macos ||
              platform == ShortcutPlatform.windows)
      ? 2
      : document.schemaVersion;
  final profile = shortcutProfile(runtime, platform);
  var overrides = {...?document.profiles[profile]};
  switch (edit) {
    case SetShortcut():
      overrides[edit.id] = edit.binding;
    case ResetShortcut():
      overrides.remove(edit.id);
    case ResetAllShortcuts():
      overrides = {};
  }
  return ShortcutDocument(
    schemaVersion: schemaVersion,
    profiles: {...document.profiles, profile: overrides},
  );
}

/// Validate a preference edit at an IPC-like boundary. Malformed requests throw
/// [ShortcutBindingError].
ShortcutEdit parseShortcutEdit(Object? value) {
  if (value is! Map<String, Object?>) {
    throw ShortcutBindingError('Invalid shortcut edit');
  }
  if (value['type'] == 'reset-all' && value.length == 1) {
    return const ResetAllShortcuts();
  }
  final id = value['id'];
  if (id is! String || !_commandPattern.hasMatch(id)) {
    throw ShortcutBindingError('Invalid shortcut command');
  }
  if (value['type'] == 'reset' && value.length == 2) return ResetShortcut(id);
  if (value['type'] == 'set' && value.length == 3) {
    return SetShortcut(id, parseBinding(value['binding']));
  }
  throw ShortcutBindingError('Invalid shortcut edit');
}

/// Validate a serializable command catalog (JSON form: `id`, `defaults`,
/// `fixed`): duplicate ids, overlapping defaults and unsupported combinations
/// throw [ShortcutBindingError].
List<ShortcutDefinition> parseShortcutDefinitions(Object? value) {
  if (value is! List) throw ShortcutBindingError('Invalid shortcut catalog');
  final ids = <String>{};
  final definitions = <ShortcutDefinition>[];
  for (final entry in value) {
    if (entry is! Map<String, Object?> ||
        entry['id'] is! String ||
        !_commandPattern.hasMatch(entry['id']! as String) ||
        ids.contains(entry['id']) ||
        entry['defaults'] is! Map<String, Object?> ||
        entry.keys.any((k) => k != 'id' && k != 'defaults' && k != 'fixed')) {
      throw ShortcutBindingError('Invalid shortcut definition');
    }
    final id = entry['id']! as String;
    ids.add(id);
    final defaultsJson = entry['defaults']! as Map<String, Object?>;
    List<ShortcutBinding>? fixed;
    if (entry.containsKey('fixed')) {
      final f = entry['fixed'];
      if (f is! List || f.isEmpty || defaultsJson.isNotEmpty) {
        throw ShortcutBindingError('Invalid fixed shortcut definition');
      }
      fixed = [
        for (final b in f)
          parseBinding(b) ??
              (throw ShortcutBindingError('Invalid fixed shortcut binding')),
      ];
    }
    final defaults = <String, ShortcutBinding>{};
    for (final d in defaultsJson.entries) {
      if (!_profilePattern.hasMatch(d.key)) {
        throw ShortcutBindingError('Invalid shortcut profile');
      }
      defaults[d.key] =
          parseBinding(d.value) ??
          (throw ShortcutBindingError('Invalid shortcut default'));
    }
    definitions.add(
      ShortcutDefinition(id: id, defaults: defaults, fixed: fixed),
    );
  }
  validateDefaults(definitions);
  return definitions;
}

/// Reject overlapping or reserved defaults across every profile.
void validateDefaults(List<ShortcutDefinition> definitions) {
  for (final runtime in ShortcutRuntime.values) {
    for (final platform in ShortcutPlatform.values) {
      final bindings = <NormalizedBinding>[];
      for (final entry in definitions) {
        final binding = resolveShortcutDefault(entry, runtime, platform);
        if (binding == null) continue;
        final normalized = normalizeBinding(binding, platform);
        if (bindings.any((o) => overlappingBindings(o, normalized)) ||
            bindingIssue(normalized, runtime, platform) != null) {
          throw ShortcutBindingError(
            'Conflicting or reserved shortcut default',
          );
        }
        bindings.add(normalized);
      }
    }
  }
}
