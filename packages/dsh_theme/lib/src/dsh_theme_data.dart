import 'dart:ui'
    show
        Brightness,
        Color,
        FontStyle,
        FontWeight,
        TextLeadingDistribution,
        lerpDouble;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/painting.dart'
    show BoxShadow, LinearGradient, TextDecoration, TextStyle;
import 'package:flutter/material.dart' show ThemeExtension;

import 'gradient_value.dart';
import 'shadow_value.dart';
import 'theme_exception.dart';
import 'theme_settings.dart';
import 'typography_value.dart';

/// The resolved theme: every contract token for one colour scheme plus the
/// user's font settings, as a [ThemeExtension].
///
/// Components read it with `Theme.of(context).extension<DshThemeData>()` and
/// look tokens up by their exact dsh name (`colors['--dsw-alias-bg-base']`, or
/// [color]); they never branch on which pack produced it. Build one with
/// `resolveTheme`.
class DshThemeData extends ThemeExtension<DshThemeData> {
  /// Creates a resolved theme. Prefer `resolveTheme`.
  const DshThemeData({
    required this.packId,
    required this.brightness,
    required this.colors,
    required this.numbers,
    required this.shadows,
    required this.gradients,
    required this.typography,
    required this.strings,
    required this.settings,
    required this.fontStacks,
    required this.brandFontStack,
  });

  /// Id of the pack this theme was resolved from (informational only).
  final String packId;

  /// The colour scheme these values belong to.
  final Brightness brightness;

  /// Colour tokens by exact name.
  final Map<String, Color> colors;

  /// Number tokens by exact name (px; durations in ms).
  final Map<String, double> numbers;

  /// Shadow tokens by exact name.
  final Map<String, List<ShadowValue>> shadows;

  /// Gradient tokens by exact name.
  final Map<String, GradientValue> gradients;

  /// Type ladder by exact name.
  final Map<String, TypeStyleValue> typography;

  /// Raw CSS string tokens by exact name.
  final Map<String, String> strings;

  /// The settings this theme was resolved with (sizes drive the ladder).
  final ThemeSettings settings;

  /// Effective family names by role: the user's list first, then the built-in stack.
  final Map<FontRole, List<String>> fontStacks;

  /// Family names of the brand font (not user-configurable).
  final List<String> brandFontStack;

  /// Colour token [name]; throws [ThemeException] if it is not a colour token.
  Color color(String name) => _get(colors, name, 'colour');

  /// Number token [name].
  double number(String name) => _get(numbers, name, 'number');

  /// Shadow token [name] as layers.
  List<ShadowValue> shadow(String name) => _get(shadows, name, 'shadow');

  /// Shadow token [name] as Flutter box shadows.
  List<BoxShadow> boxShadow(String name) => [
    for (final s in shadow(name)) s.toBoxShadow(),
  ];

  /// Gradient token [name] as a Flutter gradient.
  LinearGradient linearGradient(String name) =>
      _get(gradients, name, 'gradient').toLinearGradient();

  /// Raw string token [name].
  String string(String name) => _get(strings, name, 'string');

  /// Duration token [name] (stored in ms).
  Duration duration(String name) =>
      Duration(microseconds: (number(name) * 1000).round());

  /// The type ladder step [name] as a [TextStyle] under the current font sizes
  /// and stacks. Size and line height include the user's size delta.
  TextStyle textStyle(String name) {
    final style = _get(typography, name, 'typography');
    final size = style.size.resolve(settings.fontSizes);
    final line = style.line.resolve(settings.fontSizes);
    return _style(
      style.role,
      size: size,
      height: size == 0 ? null : line / size,
      weight: style.weight,
      italic: style.italic,
    );
  }

  /// A text-stack style at a literal size and line height, for the few places
  /// dsh's stylesheets spell a pixel size instead of a ladder step (a session
  /// row's 10px time). Like the CSS, it ignores the user's size delta.
  TextStyle fixedTextStyle({
    required double size,
    required double line,
    int weight = 400,
  }) => _style(
    FontRole.text,
    size: size,
    height: line / size,
    weight: weight,
    italic: false,
  );

  /// A style for the terminal at the user's terminal size.
  TextStyle get terminalTextStyle {
    final size = settings.terminalFontSize.toDouble();
    return _style(
      FontRole.terminal,
      size: size,
      height: 1.2,
      weight: 400,
      italic: false,
    );
  }

  TextStyle _style(
    FontRole role, {
    required double size,
    double? height,
    required int weight,
    required bool italic,
  }) {
    final stack = fontStacks[role] ?? const <String>[];
    return TextStyle(
      fontFamily: stack.isEmpty ? null : stack.first,
      fontFamilyFallback: stack.length > 1 ? stack.sublist(1) : null,
      fontSize: size,
      height: height,
      leadingDistribution: TextLeadingDistribution.even,
      fontWeight: FontWeight.values[weight ~/ 100 - 1],
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      decoration: TextDecoration.none,
    );
  }

  T _get<T>(Map<String, T> table, String name, String what) {
    final value = table[name];
    if (value == null) {
      throw ThemeException(
        'no $what token "$name" in theme "$packId"',
        where: name,
      );
    }
    return value;
  }

  // Convenience getters for tokens most components read.

  /// `--dsw-alias-bg-base`.
  Color get bgBase => color('--dsw-alias-bg-base');

  /// `--dsw-alias-label-primary`.
  Color get labelPrimary => color('--dsw-alias-label-primary');

  /// `--dsw-alias-label-secondary`.
  Color get labelSecondary => color('--dsw-alias-label-secondary');

  /// `--dsw-alias-label-primary-foreground`: text on a primary fill.
  Color get labelPrimaryForeground =>
      color('--dsw-alias-label-primary-foreground');

  /// `--dsw-alias-border-l3`.
  Color get borderL3 => color('--dsw-alias-border-l3');

  /// `--dsw-alias-interactive-bg-hover`.
  Color get interactiveBgHover => color('--dsw-alias-interactive-bg-hover');

  /// `--dsw-alias-interactive-bg-active`.
  Color get interactiveBgActive => color('--dsw-alias-interactive-bg-active');

  /// `--dsw-alias-state-business-primary`, dsh's accent. dsh's focus ring uses
  /// `--dsw-focus-ring-color` and falls back to this; the stylesheets never set
  /// the former outside pointer modality, so this is the ring colour.
  Color get focusRingColor => color('--dsw-alias-state-business-primary');

  /// `--dsw-focus-ring-width` in px.
  double get focusRingWidth => number('--dsw-focus-ring-width');

  /// `--dsw-radius-sm` (8px).
  double get radiusSm => number('--dsw-radius-sm');

  /// `--dsw-radius-md` (12px).
  double get radiusMd => number('--dsw-radius-md');

  /// `--dsw-radius-lg` (16px).
  double get radiusLg => number('--dsw-radius-lg');

  /// `--dsw-radius-xl` (20px).
  double get radiusXl => number('--dsw-radius-xl');

  /// `--dsw-radius-panel` (28px).
  double get radiusPanel => number('--dsw-radius-panel');

  /// A copy with some tables replaced wholesale (not merged).
  @override
  DshThemeData copyWith({
    String? packId,
    Brightness? brightness,
    Map<String, Color>? colors,
    Map<String, double>? numbers,
    Map<String, List<ShadowValue>>? shadows,
    Map<String, GradientValue>? gradients,
    Map<String, TypeStyleValue>? typography,
    Map<String, String>? strings,
    ThemeSettings? settings,
    Map<FontRole, List<String>>? fontStacks,
    List<String>? brandFontStack,
  }) => DshThemeData(
    packId: packId ?? this.packId,
    brightness: brightness ?? this.brightness,
    colors: colors ?? this.colors,
    numbers: numbers ?? this.numbers,
    shadows: shadows ?? this.shadows,
    gradients: gradients ?? this.gradients,
    typography: typography ?? this.typography,
    strings: strings ?? this.strings,
    settings: settings ?? this.settings,
    fontStacks: fontStacks ?? this.fontStacks,
    brandFontStack: brandFontStack ?? this.brandFontStack,
  );

  /// Interpolates colours, numbers and shadows per token; gradients, type
  /// styles, strings, fonts and settings switch at `t == 0.5`.
  @override
  DshThemeData lerp(covariant ThemeExtension<DshThemeData>? other, double t) {
    if (other is! DshThemeData) return this;
    final late = t >= 0.5;
    return DshThemeData(
      packId: late ? other.packId : packId,
      brightness: late ? other.brightness : brightness,
      colors: {
        for (final e in colors.entries)
          e.key: Color.lerp(e.value, other.colors[e.key] ?? e.value, t)!,
      },
      numbers: {
        for (final e in numbers.entries)
          e.key: lerpDouble(e.value, other.numbers[e.key] ?? e.value, t)!,
      },
      shadows: {
        for (final e in shadows.entries)
          e.key: ShadowValue.lerpList(
            e.value,
            other.shadows[e.key] ?? e.value,
            t,
          ),
      },
      gradients: late ? other.gradients : gradients,
      typography: late ? other.typography : typography,
      strings: late ? other.strings : strings,
      settings: late ? other.settings : settings,
      fontStacks: late ? other.fontStacks : fontStacks,
      brandFontStack: late ? other.brandFontStack : brandFontStack,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DshThemeData &&
      other.packId == packId &&
      other.brightness == brightness &&
      other.settings == settings &&
      _mapEquals(other.colors, colors) &&
      _mapEquals(other.numbers, numbers) &&
      _mapEquals(other.strings, strings) &&
      _mapEquals(other.gradients, gradients) &&
      _mapEquals(other.typography, typography) &&
      other.shadows.length == shadows.length &&
      shadows.entries.every((e) => listEquals(e.value, other.shadows[e.key])) &&
      listEquals(other.brandFontStack, brandFontStack) &&
      fontStacks.entries.every(
        (e) => listEquals(e.value, other.fontStacks[e.key]),
      );

  @override
  int get hashCode =>
      Object.hash(packId, brightness, settings, colors.length, numbers.length);
}

bool _mapEquals<T>(Map<String, T> a, Map<String, T> b) {
  if (a.length != b.length) return false;
  for (final e in a.entries) {
    if (!b.containsKey(e.key) || b[e.key] != e.value) return false;
  }
  return true;
}
