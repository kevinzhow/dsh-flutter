import 'theme_exception.dart';
import 'theme_settings.dart';

/// Which user font size a ladder step follows.
enum SizeScale {
  /// The text size setting: delta = text size - 14.
  content,

  /// The secondary tier derived from the text size: delta = secondary - 13,
  /// where secondary = min(text - 1, max(13, text - 2)).
  secondary,

  /// The code size setting: delta = code size - 11.
  code;

  /// Parses a pack value; null when unknown.
  static SizeScale? tryParse(Object? value) {
    for (final s in values) {
      if (s.name == value) return s;
    }
    return null;
  }

  /// The px delta this scale adds for [sizes] (dsh `--dsh-*-font-delta`).
  int delta(FontSizes sizes) => switch (this) {
    SizeScale.content => sizes.text - 14,
    SizeScale.secondary => secondarySize(sizes.text) - 13,
    SizeScale.code => sizes.code - 11,
  };
}

/// dsh `--dsh-content-font-size-secondary`: text size - 1 up to 14px, then
/// text size - 2 (10 -> 9, 14 -> 13, 15 -> 13, 22 -> 20).
int secondarySize(int textSize) {
  final minusTwo = textSize - 2;
  final floored = minusTwo > 13 ? minusTwo : 13;
  final minusOne = textSize - 1;
  return minusOne < floored ? minusOne : floored;
}

/// A size (or line height) in px: a fixed [base], or [base] plus the delta of a
/// user size setting. This is how dsh writes its ladder, `calc(21px + var(--dsh-content-font-delta))`.
class SizeExpr {
  /// Creates an expression.
  const SizeExpr(this.base, [this.scale]);

  /// Reads a pack value: a number, or `{base, scale}`.
  static SizeExpr parse(Object? value, {required String where}) {
    if (value is num) return SizeExpr(value.toDouble());
    if (value is Map) {
      for (final key in value.keys) {
        if (key != 'base' && key != 'scale') {
          throw ThemeException('unknown key "$key"', where: '$where.$key');
        }
      }
      final base = value['base'];
      if (base is! num) {
        throw ThemeException('base is a number in px', where: '$where.base');
      }
      final scale = value['scale'];
      if (scale == null) return SizeExpr(base.toDouble());
      final parsed = SizeScale.tryParse(scale);
      if (parsed == null) {
        throw ThemeException(
          'scale must be content, secondary or code, got $scale',
          where: '$where.scale',
        );
      }
      return SizeExpr(base.toDouble(), parsed);
    }
    throw ThemeException('a size is a number or {base, scale}', where: where);
  }

  /// Fixed part in px.
  final double base;

  /// Setting the size follows; null for a fixed size.
  final SizeScale? scale;

  /// The size in px under the user [sizes].
  double resolve(FontSizes sizes) => base + (scale?.delta(sizes) ?? 0);

  @override
  bool operator ==(Object other) =>
      other is SizeExpr && other.base == base && other.scale == scale;

  @override
  int get hashCode => Object.hash(base, scale);
}

/// One rung of the type ladder (`--dsw-font-s-14`, `--dsw-font-markdown-h1`...).
class TypeStyleValue {
  /// Creates a style.
  const TypeStyleValue({
    required this.role,
    required this.size,
    required this.line,
    this.weight = 400,
    this.italic = false,
  });

  /// Reads a pack value: `{family, size, line, weight, style}`.
  static TypeStyleValue parse(Object? value, {required String where}) {
    if (value is! Map) {
      throw ThemeException('a type style is an object', where: where);
    }
    const known = {'family', 'size', 'line', 'weight', 'style'};
    for (final key in value.keys) {
      if (!known.contains(key)) {
        throw ThemeException('unknown key "$key"', where: '$where.$key');
      }
    }
    for (final key in known) {
      if (!value.containsKey(key)) {
        throw ThemeException('"$key" is required', where: where);
      }
    }
    final family = value['family'];
    final role = switch (family) {
      'text' => FontRole.text,
      'code' => FontRole.code,
      _ => throw ThemeException(
        'family must be text or code, got $family',
        where: '$where.family',
      ),
    };
    final weight = value['weight'];
    if (weight is! int || weight < 100 || weight > 900 || weight % 100 != 0) {
      throw ThemeException(
        'weight must be 100..900 in steps of 100, got $weight',
        where: '$where.weight',
      );
    }
    final style = value['style'];
    if (style != 'normal' && style != 'italic') {
      throw ThemeException(
        'style must be normal or italic, got $style',
        where: '$where.style',
      );
    }
    return TypeStyleValue(
      role: role,
      size: SizeExpr.parse(value['size'], where: '$where.size'),
      line: SizeExpr.parse(value['line'], where: '$where.line'),
      weight: weight,
      italic: style == 'italic',
    );
  }

  /// Font role (family stack) the style uses.
  final FontRole role;

  /// Font size.
  final SizeExpr size;

  /// Line height.
  final SizeExpr line;

  /// CSS weight, 100..900.
  final int weight;

  /// Whether the style is italic.
  final bool italic;

  @override
  bool operator ==(Object other) =>
      other is TypeStyleValue &&
      other.role == role &&
      other.size == size &&
      other.line == line &&
      other.weight == weight &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(role, size, line, weight, italic);
}
