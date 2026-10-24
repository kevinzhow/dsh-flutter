/// Physical-key protocol shared by in-app commands and desktop adapters
/// (dsh `shortcuts/src/binding.ts`); no UI and no runtime state. Codes are the
/// DOM `KeyboardEvent.code` names dsh stores in its preference documents.
library;

/// Operating system of the device receiving input.
enum ShortcutPlatform { macos, windows, linux }

/// Application shell selecting the default bindings: the desktop app, or a
/// browser. Whalee's desktop builds run as [desktop].
enum ShortcutRuntime { desktop, web }

/// Logical primary expands to Meta on macOS and Control elsewhere.
enum ShortcutModifier { primary, control, alt, shift, meta }

/// The four physical modifiers, in normalized (keycap) order.
const List<ShortcutModifier> modifierOrder = [
  ShortcutModifier.control,
  ShortcutModifier.alt,
  ShortcutModifier.shift,
  ShortcutModifier.meta,
];

/// Runtime and operating system selecting one explicit default and preference
/// profile: `desktop:macos`, `web:linux`, ...
String shortcutProfile(ShortcutRuntime runtime, ShortcutPlatform platform) =>
    '${runtime.name}:${platform.name}';

/// Every profile name.
final List<String> allProfiles = [
  for (final r in ShortcutRuntime.values)
    for (final p in ShortcutPlatform.values) shortcutProfile(r, p),
];

/// One or two distinct physical keys held together, plus an exact set of modifiers.
class ShortcutBinding {
  const ShortcutBinding(
    this.code, [
    this.modifiers = const [],
    this.secondCode,
  ]);

  final String code;
  final String? secondCode;
  final List<ShortcutModifier> modifiers;

  @override
  bool operator ==(Object other) =>
      other is ShortcutBinding &&
      other.code == code &&
      other.secondCode == secondCode &&
      _listEq(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(code, secondCode, Object.hashAll(modifiers));

  /// The JSON form dsh persists.
  Map<String, Object?> toJson() => {
    'code': code,
    'modifiers': [for (final m in modifiers) m.name],
    if (secondCode != null) 'secondCode': secondCode,
  };

  @override
  String toString() =>
      'ShortcutBinding($code${secondCode == null ? '' : '+$secondCode'}, $modifiers)';
}

/// Normalized modifier order is also the keycap order.
class NormalizedBinding {
  const NormalizedBinding(this.code, this.modifiers, [this.secondCode]);

  final String code;
  final String? secondCode;

  /// Only [ShortcutModifier.control], `alt`, `shift` and `meta`, in that order.
  final List<ShortcutModifier> modifiers;

  @override
  bool operator ==(Object other) =>
      other is NormalizedBinding &&
      other.code == code &&
      other.secondCode == secondCode &&
      _listEq(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(code, secondCode, Object.hashAll(modifiers));

  ShortcutBinding toBinding() => ShortcutBinding(code, modifiers, secondCode);

  @override
  String toString() =>
      'NormalizedBinding($code${secondCode == null ? '' : '+$secondCode'}, $modifiers)';
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

const Map<String, String> _keyNames = {
  'Slash': '/',
  'Comma': ',',
  'Period': '.',
  'Backslash': '\\',
  'Backquote': '`',
  'Minus': '-',
  'Equal': '=',
  'BracketLeft': '[',
  'BracketRight': ']',
  'Semicolon': ';',
  'Quote': "'",
  'Enter': 'Enter',
  'Escape': 'Esc',
  'Space': 'Space',
  'Tab': 'Tab',
  'Backspace': 'Backspace',
  'Delete': 'Delete',
  'ArrowUp': '↑',
  'ArrowDown': '↓',
  'ArrowLeft': '←',
  'ArrowRight': '→',
};

final RegExp _supportedCode = RegExp(
  r'^(Key[A-Z]|Digit[0-9]|F([1-9]|1[0-9]|2[0-4]))$',
);

/// Thrown for an unsupported physical key code or an invalid combination.
class ShortcutBindingError extends Error {
  ShortcutBindingError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Whether [code] is a physical key a binding may name.
bool isSupportedShortcutCode(String code) =>
    _supportedCode.hasMatch(code) || _keyNames.containsKey(code);

/// Expand logical modifiers, deduplicate, and validate the physical code.
/// Unsupported codes throw [ShortcutBindingError].
NormalizedBinding normalizeBinding(
  ShortcutBinding binding,
  ShortcutPlatform platform,
) {
  final codes = [
    binding.code,
    if (binding.secondCode != null) binding.secondCode!,
  ]..sort();
  for (final code in codes) {
    if (!isSupportedShortcutCode(code)) {
      throw ShortcutBindingError('Unsupported shortcut code: $code');
    }
  }
  if (codes.length == 2 && codes[0] == codes[1]) {
    throw ShortcutBindingError('Shortcut keys must be distinct');
  }
  final modifiers = {
    for (final value in binding.modifiers)
      value == ShortcutModifier.primary
          ? (platform == ShortcutPlatform.macos
                ? ShortcutModifier.meta
                : ShortcutModifier.control)
          : value,
  };
  return NormalizedBinding(codes[0], [
    for (final value in modifierOrder)
      if (modifiers.contains(value)) value,
  ], codes.length > 1 ? codes[1] : null);
}

/// Exact-match index of a normalized binding: stable, used for both matching
/// and conflict checks.
String bindingKey(NormalizedBinding binding) {
  final codes = binding.secondCode == null
      ? [binding.code]
      : ([binding.code, binding.secondCode!]..sort());
  return [...binding.modifiers.map((m) => m.name), ...codes].join('+');
}

/// Visible keycaps plus the ARIA shortcut string.
class PresentedBinding {
  const PresentedBinding(this.keys, this.aria);

  final List<String> keys;
  final String? aria;

  @override
  bool operator ==(Object other) =>
      other is PresentedBinding &&
      other.aria == aria &&
      _listEq(other.keys, keys);

  @override
  int get hashCode => Object.hash(aria, Object.hashAll(keys));

  @override
  String toString() => 'PresentedBinding($keys, $aria)';
}

String _keyLabel(String code) =>
    _keyNames[code] ?? code.replaceFirst(RegExp(r'^(Key|Digit)'), '');

/// Format keycaps and ARIA; Windows separates modifiers with plus signs, while
/// chord keys remain adjacent. Two-key chords omit ARIA, which only supports
/// one non-modifier key.
PresentedBinding presentBinding(
  NormalizedBinding? binding,
  ShortcutPlatform platform,
) {
  if (binding == null) return const PresentedBinding([], null);
  final key = _keyLabel(binding.code);
  const macSymbols = {
    ShortcutModifier.control: '⌃',
    ShortcutModifier.alt: '⌥',
    ShortcutModifier.shift: '⇧',
    ShortcutModifier.meta: '⌘',
  };
  const otherSymbols = {
    ShortcutModifier.control: 'Ctrl',
    ShortcutModifier.alt: 'Alt',
    ShortcutModifier.shift: 'Shift',
    ShortcutModifier.meta: 'Meta',
  };
  const ariaNames = {
    ShortcutModifier.control: 'Control',
    ShortcutModifier.alt: 'Alt',
    ShortcutModifier.shift: 'Shift',
    ShortcutModifier.meta: 'Meta',
  };
  final symbols = platform == ShortcutPlatform.macos
      ? macSymbols
      : otherSymbols;
  final ariaKey = binding.code == 'Space'
      ? 'Space'
      : binding.code == 'Escape'
      ? 'Escape'
      : binding.code.startsWith('Arrow')
      ? binding.code
      : key;
  final second = binding.secondCode == null
      ? <String>[]
      : [_keyLabel(binding.secondCode!)];
  final keys = [...binding.modifiers.map((m) => symbols[m]!), key];
  final shown = platform == ShortcutPlatform.windows
      ? [
          for (var i = 0; i < keys.length; i++)
            ...(i == 0 ? [keys[i]] : ['+', keys[i]]),
        ]
      : keys;
  return PresentedBinding(
    [...shown, ...second],
    binding.secondCode == null
        ? [...binding.modifiers.map((m) => ariaNames[m]!), ariaKey].join('+')
        : null,
  );
}

/// Check Web combinations: Windows and macOS also admit any three or four
/// modifiers; Linux retains the limited set. Admission does not guarantee
/// browser or system delivery.
bool isWebBindingAllowed(NormalizedBinding binding, ShortcutPlatform platform) {
  if (binding.secondCode != null) return false;
  if (platform == ShortcutPlatform.windows ||
      platform == ShortcutPlatform.macos) {
    if (binding.modifiers.length >= 3) return true;
    final primary = platform == ShortcutPlatform.macos
        ? ShortcutModifier.meta
        : ShortcutModifier.control;
    if (binding.modifiers.length == 1 &&
        ((['Comma', 'Backslash'].contains(binding.code) &&
                binding.modifiers[0] == primary) ||
            (binding.code == 'Backquote' &&
                binding.modifiers[0] == ShortcutModifier.control))) {
      return true;
    }
    if (binding.modifiers.length == 2 &&
        binding.modifiers.contains(primary) &&
        (binding.modifiers.contains(ShortcutModifier.alt) ||
            binding.modifiers.contains(ShortcutModifier.shift))) {
      return true;
    }
  }
  return [
    const ShortcutBinding('Slash', [ShortcutModifier.primary]),
    const ShortcutBinding('Comma', [
      ShortcutModifier.primary,
      ShortcutModifier.shift,
    ]),
    const ShortcutBinding('Period', [
      ShortcutModifier.primary,
      ShortcutModifier.shift,
    ]),
  ].any(
    (candidate) =>
        bindingKey(binding) ==
        bindingKey(normalizeBinding(candidate, platform)),
  );
}
