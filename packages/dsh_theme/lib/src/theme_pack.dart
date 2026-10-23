import 'dart:convert';
import 'dart:ui' show Brightness, Color;

import 'color_value.dart';
import 'contract_names.g.dart';
import 'gradient_value.dart';
import 'shadow_value.dart';
import 'theme_exception.dart';
import 'typography_value.dart';

/// The file format this parser reads.
const String dshThemePackFormat = 'dsh-theme/1';

/// The token tables a pack carries, keyed by the exact dsh CSS custom property
/// name (leading `--` kept: `--dsw-alias-bg-base`, `--dsh-scrollbar-width`).
class TokenTables {
  /// Creates tables; any may be empty.
  const TokenTables({
    this.colors = const {},
    this.numbers = const {},
    this.shadows = const {},
    this.gradients = const {},
    this.typography = const {},
    this.strings = const {},
  });

  /// No tokens at all.
  static const TokenTables empty = TokenTables();

  /// Colour tokens.
  final Map<String, Color> colors;

  /// Number tokens: px for lengths, ms for durations.
  final Map<String, double> numbers;

  /// Shadow tokens.
  final Map<String, List<ShadowValue>> shadows;

  /// Gradient tokens.
  final Map<String, GradientValue> gradients;

  /// Type ladder styles.
  final Map<String, TypeStyleValue> typography;

  /// Raw CSS strings the engine does not interpret (`superellipse(1.5)`...).
  final Map<String, String> strings;

  /// Number of tokens across all tables.
  int get length =>
      colors.length +
      numbers.length +
      shadows.length +
      gradients.length +
      typography.length +
      strings.length;

  /// These tokens laid over [base]: this table wins per name.
  TokenTables mergedWith(TokenTables base) => TokenTables(
    colors: {...base.colors, ...colors},
    numbers: {...base.numbers, ...numbers},
    shadows: {...base.shadows, ...shadows},
    gradients: {...base.gradients, ...gradients},
    typography: {...base.typography, ...typography},
    strings: {...base.strings, ...strings},
  );

  /// Whether a token called [name] is present in the table for its kind.
  bool contains(String name, String kind) => switch (kind) {
    'color' => colors.containsKey(name),
    'number' => numbers.containsKey(name),
    'shadow' => shadows.containsKey(name),
    'gradient' => gradients.containsKey(name),
    'typography' => typography.containsKey(name),
    'string' => strings.containsKey(name),
    _ => false,
  };
}

const Map<String, String> _tableKinds = {
  'colors': 'color',
  'numbers': 'number',
  'shadows': 'shadow',
  'gradients': 'gradient',
  'typography': 'typography',
  'strings': 'string',
};

const Set<String> _packKeys = {
  'format',
  'id',
  'name',
  'version',
  'extends',
  'author',
  'source',
  'fonts',
  'common',
  'modes',
  r'$schema', //
};

/// A parsed `dsh-theme/1` file.
///
/// Layout: `common` holds tokens identical in both modes, `modes.light` and
/// `modes.dark` hold the rest; `fonts` maps a role (text, code, terminal, brand)
/// to its built-in family stack. A pack may set any subset when it names a
/// parent in `extends`; [resolve] folds the chain and requires the result to be
/// complete. Every token name must be one of the contract names and sit in the
/// table of its kind; unknown keys are errors, because a typo must fail loudly.
class ThemePack {
  /// Creates a pack from parsed parts; prefer [parse] or [fromJson].
  const ThemePack({
    required this.id,
    required this.name,
    required this.version,
    this.extendsId,
    this.author,
    this.source = const {},
    this.fonts = const {},
    this.common = TokenTables.empty,
    this.light = TokenTables.empty,
    this.dark = TokenTables.empty,
  });

  /// Parses and validates pack JSON text. This is the loader for user packs;
  /// the official pack goes through [fromJson] with its generated const data.
  static ThemePack parse(String source, {String origin = 'theme'}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw ThemeException('not valid JSON: ${error.message}', where: origin);
    }
    if (decoded is! Map) {
      throw ThemeException('a theme pack is a JSON object', where: origin);
    }
    return fromJson(decoded, origin: origin);
  }

  /// Validates decoded pack JSON; [origin] prefixes the path in errors.
  static ThemePack fromJson(
    Map<Object?, Object?> json, {
    String origin = 'theme',
  }) {
    for (final key in json.keys) {
      if (!_packKeys.contains(key)) {
        throw ThemeException('unknown key "$key"', where: '$origin.$key');
      }
    }
    if (json['format'] != dshThemePackFormat) {
      throw ThemeException(
        'format must be "$dshThemePackFormat"',
        where: '$origin.format',
      );
    }
    String text(String key, {bool required = true}) {
      final value = json[key];
      if (value is String && value.isNotEmpty) return value;
      if (value == null && !required) return '';
      throw ThemeException(
        '$key must be a non-empty string',
        where: '$origin.$key',
      );
    }

    final id = text('id');
    final extendsRaw = json['extends'];
    if (extendsRaw != null && extendsRaw is! String) {
      throw ThemeException(
        'extends must be a theme id',
        where: '$origin.extends',
      );
    }
    if (extendsRaw == id) {
      throw ThemeException(
        'a theme cannot extend itself',
        where: '$origin.extends',
      );
    }

    final source = json['source'];
    if (source != null && source is! Map) {
      throw ThemeException('source must be an object', where: '$origin.source');
    }

    final fonts = <String, List<String>>{};
    final rawFonts = json['fonts'];
    if (rawFonts != null) {
      if (rawFonts is! Map) {
        throw ThemeException('fonts must be an object', where: '$origin.fonts');
      }
      for (final entry in rawFonts.entries) {
        final role = '${entry.key}';
        final path = '$origin.fonts.$role';
        if (!dshPackFontRoles.contains(role)) {
          throw ThemeException(
            'unknown font role "$role" (${dshPackFontRoles.join(', ')})',
            where: path,
          );
        }
        final stack = entry.value;
        if (stack is! List ||
            stack.isEmpty ||
            stack.any((n) => n is! String || n.trim().isEmpty)) {
          throw ThemeException(
            'a font stack is a non-empty list of family names',
            where: path,
          );
        }
        fonts[role] = [for (final n in stack) (n as String).trim()];
      }
    }

    var light = TokenTables.empty, dark = TokenTables.empty;
    final modes = json['modes'];
    if (modes != null) {
      if (modes is! Map) {
        throw ThemeException('modes must be an object', where: '$origin.modes');
      }
      for (final key in modes.keys) {
        if (key != 'light' && key != 'dark') {
          throw ThemeException(
            'unknown mode "$key" (light, dark)',
            where: '$origin.modes.$key',
          );
        }
      }
      light = _tables(modes['light'], '$origin.modes.light');
      dark = _tables(modes['dark'], '$origin.modes.dark');
    }

    return ThemePack(
      id: id,
      name: text('name'),
      version: text('version'),
      extendsId: extendsRaw as String?,
      author: json['author'] is String ? json['author'] as String : null,
      source: {
        for (final e
            in (source as Map?)?.entries ??
                const <MapEntry<Object?, Object?>>[])
          '${e.key}': e.value,
      },
      fonts: fonts,
      common: _tables(json['common'], '$origin.common'),
      light: light,
      dark: dark,
    );
  }

  /// Pack id (`official`, or the id a user pack gives itself).
  final String id;

  /// Display name.
  final String name;

  /// Pack version string.
  final String version;

  /// Id of the pack this one extends; null for a standalone pack.
  final String? extendsId;

  /// Optional author.
  final String? author;

  /// Free-form provenance (the official pack records the dsh commit here).
  final Map<String, Object?> source;

  /// Built-in family stacks by role, as written in this pack.
  final Map<String, List<String>> fonts;

  /// Tokens identical in both modes.
  final TokenTables common;

  /// Tokens specific to the light mode.
  final TokenTables light;

  /// Tokens specific to the dark mode.
  final TokenTables dark;

  /// Folds the `extends` chain into one complete pack.
  ///
  /// [available] maps ids to the packs a parent may be looked up in (this pack
  /// need not be in it). Throws [ThemeException] for an unknown parent, a cycle
  /// in the chain, or a resulting pack that lacks a contract token or font role.
  ResolvedThemePack resolve([Map<String, ThemePack> available = const {}]) {
    final chain = <ThemePack>[this];
    final seen = <String>{id};
    var cursor = extendsId;
    while (cursor != null) {
      final parent = cursor == id ? this : available[cursor];
      if (parent == null) {
        throw ThemeException(
          '"$id" extends unknown theme "$cursor"',
          where: 'extends',
        );
      }
      if (!seen.add(parent.id)) {
        throw ThemeException(
          'the extends chain loops: ${[...chain.map((p) => p.id), parent.id].join(' -> ')}',
          where: 'extends',
        );
      }
      chain.add(parent);
      cursor = parent.extendsId;
    }
    // Root first; within one pack its mode table beats its common table, and a
    // child's common table still beats a parent's mode table.
    TokenTables foldMode(Brightness brightness) {
      var out = TokenTables.empty;
      for (final pack in chain.reversed) {
        out = pack.common.mergedWith(out);
        out = (brightness == Brightness.dark ? pack.dark : pack.light)
            .mergedWith(out);
      }
      return out;
    }

    final fonts = <String, List<String>>{};
    for (final pack in chain.reversed) {
      fonts.addAll(pack.fonts);
    }
    final merged = {
      Brightness.light: foldMode(Brightness.light),
      Brightness.dark: foldMode(Brightness.dark),
    };
    for (final entry in merged.entries) {
      final missing = [
        for (final name in dshContractNames)
          if (!entry.value.contains(name, dshContractKinds[name]!)) name,
      ];
      if (missing.isNotEmpty) {
        final shown = missing.take(5).join(', ');
        throw ThemeException(
          '${missing.length} contract token(s) missing after folding ${chain.map((p) => p.id).join(' <- ')}: '
          '$shown${missing.length > 5 ? ', ...' : ''} (add them or extend a complete pack)',
          where: 'modes.${entry.key.name}',
        );
      }
    }
    final missingRoles = [
      for (final r in dshPackFontRoles)
        if (!fonts.containsKey(r)) r,
    ];
    if (missingRoles.isNotEmpty) {
      throw ThemeException(
        'font stack(s) missing: ${missingRoles.join(', ')}',
        where: 'fonts',
      );
    }
    return ResolvedThemePack._(
      id: id,
      chain: [for (final p in chain) p.id],
      light: merged[Brightness.light]!,
      dark: merged[Brightness.dark]!,
      fonts: fonts,
    );
  }
}

/// A pack with its `extends` chain folded in; every contract token is present
/// in both modes.
class ResolvedThemePack {
  const ResolvedThemePack._({
    required this.id,
    required this.chain,
    required this.light,
    required this.dark,
    required this.fonts,
  });

  /// Id of the pack that was resolved.
  final String id;

  /// Pack ids from the resolved pack up to its root.
  final List<String> chain;

  /// All tokens in light mode.
  final TokenTables light;

  /// All tokens in dark mode.
  final TokenTables dark;

  /// Built-in family stacks by role.
  final Map<String, List<String>> fonts;

  /// The tables for [brightness].
  TokenTables tables(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

TokenTables _tables(Object? raw, String where) {
  if (raw == null) return TokenTables.empty;
  if (raw is! Map) throw ThemeException('expected an object', where: where);
  final colors = <String, Color>{};
  final numbers = <String, double>{};
  final shadows = <String, List<ShadowValue>>{};
  final gradients = <String, GradientValue>{};
  final typography = <String, TypeStyleValue>{};
  final strings = <String, String>{};
  for (final entry in raw.entries) {
    final table = '${entry.key}';
    final kind = _tableKinds[table];
    if (kind == null) {
      throw ThemeException(
        'unknown table "$table" (${_tableKinds.keys.join(', ')})',
        where: '$where.$table',
      );
    }
    final tokens = entry.value;
    if (tokens is! Map) {
      throw ThemeException('$table is an object', where: '$where.$table');
    }
    for (final token in tokens.entries) {
      final name = '${token.key}';
      final path = '$where.$table.$name';
      final expected = dshContractKinds[name];
      if (expected == null) {
        throw ThemeException('unknown token "$name"', where: path);
      }
      if (expected != kind) {
        throw ThemeException(
          'token "$name" is a $expected, not a $kind',
          where: path,
        );
      }
      final value = token.value;
      switch (kind) {
        case 'color':
          colors[name] = ColorValue.parse(value, where: path);
        case 'number':
          if (value is! num || !value.isFinite) {
            throw ThemeException(
              'a number token is a finite number',
              where: path,
            );
          }
          numbers[name] = value.toDouble();
        case 'shadow':
          shadows[name] = ShadowValue.parseList(value, where: path);
        case 'gradient':
          gradients[name] = GradientValue.parse(value, where: path);
        case 'typography':
          typography[name] = TypeStyleValue.parse(value, where: path);
        default:
          if (value is! String) {
            throw ThemeException('a string token is a string', where: path);
          }
          strings[name] = value;
      }
    }
  }
  return TokenTables(
    colors: colors,
    numbers: numbers,
    shadows: shadows,
    gradients: gradients,
    typography: typography,
    strings: strings,
  );
}
