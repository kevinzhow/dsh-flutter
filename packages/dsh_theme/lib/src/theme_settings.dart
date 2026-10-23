import 'dart:ui' show Brightness;

import 'theme_exception.dart';

/// Built-in colour scheme preference, as dsh's `THEME_PREFERENCES`.
enum ThemePreference {
  /// Always the light palette.
  light,

  /// Always the dark palette.
  dark,

  /// Follow the platform brightness.
  system;

  /// Parses a stored preference name; null when unknown.
  static ThemePreference? tryParse(Object? value) {
    for (final p in values) {
      if (p.name == value) return p;
    }
    return null;
  }
}

/// The three independently configurable font roles, as dsh's `FONT_ROLES`.
enum FontRole {
  /// Interface and conversation text.
  text,

  /// Code blocks, inline code and other code text.
  code,

  /// The sidebar terminal.
  terminal,
}

/// Accepted integer px range and default of one role's font size, matching
/// dsh `FONT_SIZE_SPECS` (ui-theme `theme-settings.ts`).
class FontSizeSpec {
  const FontSizeSpec({
    required this.field,
    required this.min,
    required this.max,
    required this.defaultSize,
  });

  /// Settings JSON field carrying the size.
  final String field;

  /// Smallest accepted size.
  final int min;

  /// Largest accepted size.
  final int max;

  /// Size when nothing is stored.
  final int defaultSize;
}

/// Size specs by role: text 10..22 (default 14), code 10..16 (11), terminal 10..20 (13).
const Map<FontRole, FontSizeSpec> fontSizeSpecs = {
  FontRole.text: FontSizeSpec(
    field: 'fontSize',
    min: 10,
    max: 22,
    defaultSize: 14,
  ),
  FontRole.code: FontSizeSpec(
    field: 'codeFontSize',
    min: 10,
    max: 16,
    defaultSize: 11,
  ),
  FontRole.terminal: FontSizeSpec(
    field: 'terminalFontSize',
    min: 10,
    max: 20,
    defaultSize: 13,
  ),
};

/// Settings JSON field carrying each role's font-family list.
const Map<FontRole, String> fontFamilyFields = {
  FontRole.text: 'textFontFamily',
  FontRole.code: 'codeFontFamily',
  FontRole.terminal: 'terminalFontFamily',
};

/// Integer px font sizes by role (dsh `FontSizes`).
class FontSizes {
  /// Creates sizes; no clamping here, use [ThemeSettings] for validated values.
  const FontSizes({
    required this.text,
    required this.code,
    required this.terminal,
  });

  /// The default sizes.
  static const FontSizes defaults = FontSizes(text: 14, code: 11, terminal: 13);

  /// Conversation content size.
  final int text;

  /// Code-block size.
  final int code;

  /// Terminal cell font size.
  final int terminal;

  /// Size of [role].
  int operator [](FontRole role) => switch (role) {
    FontRole.text => text,
    FontRole.code => code,
    FontRole.terminal => terminal,
  };

  /// JSON object keyed by role name.
  Map<String, Object?> toJson() => {
    'text': text,
    'code': code,
    'terminal': terminal,
  };

  @override
  bool operator ==(Object other) =>
      other is FontSizes &&
      other.text == text &&
      other.code == code &&
      other.terminal == terminal;

  @override
  int get hashCode => Object.hash(text, code, terminal);

  @override
  String toString() =>
      'FontSizes(text: $text, code: $code, terminal: $terminal)';
}

/// Normalized CSS font-family lists by role; `''` selects the built-in stack
/// (dsh `FontFamilies`).
class FontFamilies {
  /// Creates lists; values are used as given, see [normalizeFontFamily].
  const FontFamilies({
    required this.text,
    required this.code,
    required this.terminal,
  });

  /// All three built-in stacks.
  static const FontFamilies empty = FontFamilies(
    text: '',
    code: '',
    terminal: '',
  );

  /// Text font list.
  final String text;

  /// Code font list.
  final String code;

  /// Terminal font list.
  final String terminal;

  /// List of [role].
  String operator [](FontRole role) => switch (role) {
    FontRole.text => text,
    FontRole.code => code,
    FontRole.terminal => terminal,
  };

  /// JSON object keyed by role name.
  Map<String, Object?> toJson() => {
    'text': text,
    'code': code,
    'terminal': terminal,
  };

  @override
  bool operator ==(Object other) =>
      other is FontFamilies &&
      other.text == text &&
      other.code == code &&
      other.terminal == terminal;

  @override
  int get hashCode => Object.hash(text, code, terminal);

  @override
  String toString() =>
      'FontFamilies(text: "$text", code: "$code", terminal: "$terminal")';
}

/// CSS generic and system family keywords, which stay unquoted (dsh `GENERIC_FAMILIES`).
const Set<String> genericFontFamilies = {
  'serif',
  'sans-serif',
  'monospace',
  'cursive',
  'fantasy',
  'system-ui',
  'ui-serif',
  'ui-sans-serif', //
  'ui-monospace',
  'ui-rounded',
  'emoji',
  'math',
  'fangsong',
  '-apple-system',
  'blinkmacsystemfont',
};

/// Normalizes user input into a CSS font-family list, as dsh's `normalizeFontFamily`.
///
/// Names are comma separated; quotes, backslashes, angle brackets and control
/// characters are dropped, runs of whitespace collapse, and every non-generic
/// name is double-quoted. Returns `''` when no name remains. Normalizing a
/// result returns it unchanged.
String normalizeFontFamily(String value) {
  final drop = RegExp('["\'\\\\<>\\u0000-\\u001f\\u007f]');
  return value
      .split(',')
      .map(
        (name) =>
            name.replaceAll(drop, '').replaceAll(RegExp(r'\s+'), ' ').trim(),
      )
      .where((name) => name.isNotEmpty)
      .map(
        (name) =>
            genericFontFamilies.contains(name.toLowerCase()) ? name : '"$name"',
      )
      .join(', ');
}

/// The family names of a normalized list, unquoted, in order.
List<String> fontFamilyNames(String normalized) => normalized
    .split(',')
    .map((n) => n.trim())
    .map(
      (n) => n.length >= 2 && n.startsWith('"') && n.endsWith('"')
          ? n.substring(1, n.length - 1)
          : n,
    )
    .where((n) => n.isNotEmpty)
    .toList();

/// Renders [names] as a CSS font-family list (generics unquoted, others double-quoted).
String fontStackCss(List<String> names) => names
    .map((n) => genericFontFamilies.contains(n.toLowerCase()) ? n : '"$n"')
    .join(', ');

/// The palette a preference resolves to under [platformBrightness].
Brightness resolveBrightness(
  ThemePreference preference,
  Brightness platformBrightness,
) => switch (preference) {
  ThemePreference.light => Brightness.light,
  ThemePreference.dark => Brightness.dark,
  ThemePreference.system => platformBrightness,
};

/// The durable theme settings section (dsh `ThemeSettings`): preference, three
/// font sizes and three font-family lists.
///
/// The constructor validates: sizes are rounded and clamped to the dsh range of
/// their role, font lists are normalized. [fromJson] is strict about types and
/// forgiving about ranges, like dsh's bootstrap reading hand-edited documents.
class ThemeSettings {
  /// Creates settings; every value is validated or clamped.
  ThemeSettings({
    this.preference = ThemePreference.system,
    int fontSize = 14,
    int codeFontSize = 11,
    int terminalFontSize = 13,
    String textFontFamily = '',
    String codeFontFamily = '',
    String terminalFontFamily = '',
  }) : fontSize = clampFontSize(FontRole.text, fontSize),
       codeFontSize = clampFontSize(FontRole.code, codeFontSize),
       terminalFontSize = clampFontSize(FontRole.terminal, terminalFontSize),
       textFontFamily = normalizeFontFamily(textFontFamily),
       codeFontFamily = normalizeFontFamily(codeFontFamily),
       terminalFontFamily = normalizeFontFamily(terminalFontFamily);

  /// Reads the settings JSON object (field names as in dsh). Missing fields take
  /// defaults; a field of the wrong type throws a [ThemeException] naming it.
  factory ThemeSettings.fromJson(Map<String, Object?> json) {
    ThemePreference preference = ThemePreference.system;
    if (json.containsKey('preference')) {
      final parsed = ThemePreference.tryParse(json['preference']);
      if (parsed == null) {
        throw ThemeException(
          'preference must be light, dark or system, got ${json['preference']}',
          where: 'preference',
        );
      }
      preference = parsed;
    }
    int size(FontRole role) {
      final spec = fontSizeSpecs[role]!;
      final raw = json[spec.field];
      if (raw == null) return spec.defaultSize;
      if (raw is! num || raw.isNaN || raw.isInfinite) {
        throw ThemeException(
          'a font size is a number, got $raw',
          where: spec.field,
        );
      }
      return clampFontSize(role, raw.round());
    }

    String family(FontRole role) {
      final field = fontFamilyFields[role]!;
      final raw = json[field];
      if (raw == null) return '';
      if (raw is! String) {
        throw ThemeException(
          'a font list is a string, got ${raw.runtimeType}',
          where: field,
        );
      }
      return raw;
    }

    return ThemeSettings(
      preference: preference,
      fontSize: size(FontRole.text),
      codeFontSize: size(FontRole.code),
      terminalFontSize: size(FontRole.terminal),
      textFontFamily: family(FontRole.text),
      codeFontFamily: family(FontRole.code),
      terminalFontFamily: family(FontRole.terminal),
    );
  }

  /// Selected preference.
  final ThemePreference preference;

  /// Conversation content size in px (10..22).
  final int fontSize;

  /// Code-block size in px (10..16).
  final int codeFontSize;

  /// Terminal size in px (10..20).
  final int terminalFontSize;

  /// Normalized text font list placed before the built-in stack; `''` keeps it.
  final String textFontFamily;

  /// Normalized code font list; `''` keeps the built-in stack.
  final String codeFontFamily;

  /// Normalized terminal font list; `''` keeps the built-in stack.
  final String terminalFontFamily;

  /// Whether [px] is an accepted size for [role]: an integer in the role's range.
  static bool isValidFontSize(FontRole role, num px) {
    final spec = fontSizeSpecs[role]!;
    final integral = px is int || px == px.roundToDouble();
    return integral && px >= spec.min && px <= spec.max;
  }

  /// [px] rounded and clamped into the range of [role].
  static int clampFontSize(FontRole role, num px) {
    final spec = fontSizeSpecs[role]!;
    if (px.isNaN) return spec.defaultSize;
    return px.round().clamp(spec.min, spec.max);
  }

  /// Integer px sizes by role.
  FontSizes get fontSizes =>
      FontSizes(text: fontSize, code: codeFontSize, terminal: terminalFontSize);

  /// Normalized font lists by role.
  FontFamilies get fontFamilies => FontFamilies(
    text: textFontFamily,
    code: codeFontFamily,
    terminal: terminalFontFamily,
  );

  /// Copy with some values replaced (validated again).
  ThemeSettings copyWith({
    ThemePreference? preference,
    int? fontSize,
    int? codeFontSize,
    int? terminalFontSize,
    String? textFontFamily,
    String? codeFontFamily,
    String? terminalFontFamily,
  }) => ThemeSettings(
    preference: preference ?? this.preference,
    fontSize: fontSize ?? this.fontSize,
    codeFontSize: codeFontSize ?? this.codeFontSize,
    terminalFontSize: terminalFontSize ?? this.terminalFontSize,
    textFontFamily: textFontFamily ?? this.textFontFamily,
    codeFontFamily: codeFontFamily ?? this.codeFontFamily,
    terminalFontFamily: terminalFontFamily ?? this.terminalFontFamily,
  );

  /// JSON object with the dsh field names.
  Map<String, Object?> toJson() => {
    'preference': preference.name,
    'fontSize': fontSize,
    'codeFontSize': codeFontSize,
    'terminalFontSize': terminalFontSize,
    'textFontFamily': textFontFamily,
    'codeFontFamily': codeFontFamily,
    'terminalFontFamily': terminalFontFamily,
  };

  /// The immutable snapshot of these settings under [platformBrightness].
  ThemeSnapshot snapshot(
    Brightness platformBrightness, {
    String? themeId,
    int revision = 0,
  }) {
    final scheme = resolveBrightness(preference, platformBrightness);
    return ThemeSnapshot(
      preference: preference,
      fontSizes: fontSizes,
      fontFamilies: fontFamilies,
      colorScheme: scheme,
      themeId: themeId ?? scheme.name,
      revision: revision,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeSettings &&
      other.preference == preference &&
      other.fontSize == fontSize &&
      other.codeFontSize == codeFontSize &&
      other.terminalFontSize == terminalFontSize &&
      other.textFontFamily == textFontFamily &&
      other.codeFontFamily == codeFontFamily &&
      other.terminalFontFamily == terminalFontFamily;

  @override
  int get hashCode => Object.hash(
    preference,
    fontSize,
    codeFontSize,
    terminalFontSize,
    textFontFamily,
    codeFontFamily,
    terminalFontFamily,
  );
}

/// Immutable theme state, the shape of dsh's `ThemeSnapshot` for what a native
/// client resolves: the persisted preference, sizes and font lists, the
/// resolved colour scheme with the id of the active theme, and a change counter.
class ThemeSnapshot {
  /// Creates a snapshot.
  const ThemeSnapshot({
    required this.preference,
    required this.fontSizes,
    required this.fontFamilies,
    required this.colorScheme,
    required this.themeId,
    required this.revision,
  });

  /// The persisted preference (may be `system`).
  final ThemePreference preference;

  /// Integer px sizes by role.
  final FontSizes fontSizes;

  /// Normalized user font lists by role.
  final FontFamilies fontFamilies;

  /// The resolved palette (`system` resolved through the platform brightness).
  final Brightness colorScheme;

  /// Id of the active theme (`light`/`dark` for the built-ins, else a pack id).
  final String themeId;

  /// Monotonic change counter.
  final int revision;

  /// JSON in the dsh shape: `active` carries `{id, colorScheme}`.
  Map<String, Object?> toJson() => {
    'preference': preference.name,
    'fontSizes': fontSizes.toJson(),
    'fontFamilies': fontFamilies.toJson(),
    'active': {'id': themeId, 'colorScheme': colorScheme.name},
    'revision': revision,
  };

  @override
  bool operator ==(Object other) =>
      other is ThemeSnapshot &&
      other.preference == preference &&
      other.fontSizes == fontSizes &&
      other.fontFamilies == fontFamilies &&
      other.colorScheme == colorScheme &&
      other.themeId == themeId &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(
    preference,
    fontSizes,
    fontFamilies,
    colorScheme,
    themeId,
    revision,
  );
}
