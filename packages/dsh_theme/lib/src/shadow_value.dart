import 'dart:ui' show Color, Offset, lerpDouble;

import 'package:flutter/painting.dart' show BoxShadow;

import 'color_value.dart';
import 'theme_exception.dart';

/// One layer of a CSS box shadow: offset, blur, spread, colour, inset.
///
/// A pack writes shadows as CSS text (`0px 2px 4px 0px rgb(0 0 0 / 5%)`, layers
/// comma separated), the one form both designers and CSS tooling read. `none`
/// is the empty list. Lengths may omit `px`.
class ShadowValue {
  /// Creates one shadow layer.
  const ShadowValue({
    required this.offset,
    required this.blur,
    required this.spread,
    required this.color,
    this.inset = false,
  });

  /// Offset of the shadow from the box.
  final Offset offset;

  /// CSS blur radius in px.
  final double blur;

  /// CSS spread radius in px.
  final double spread;

  /// Shadow colour including alpha.
  final Color color;

  /// Whether the layer is drawn inside the box. Flutter's [BoxShadow] cannot
  /// draw inset shadows; [toBoxShadow] ignores this flag.
  final bool inset;

  /// Parses a layer list; [where] names the key in errors.
  static List<ShadowValue> parseList(Object? value, {required String where}) {
    if (value is! String) {
      throw ThemeException(
        'a shadow is CSS text or "none", got ${value.runtimeType}',
        where: where,
      );
    }
    final text = value.trim();
    if (text.isEmpty || text.toLowerCase() == 'none') return const [];
    return [for (final layer in splitTopLevel(text, ',')) _layer(layer, where)];
  }

  /// Canonical CSS text for [layers] (`none` when empty).
  static String formatList(List<ShadowValue> layers) {
    if (layers.isEmpty) return 'none';
    return layers.map((l) => l.toString()).join(', ');
  }

  /// This layer as a Flutter [BoxShadow].
  BoxShadow toBoxShadow() => BoxShadow(
    color: color,
    offset: offset,
    blurRadius: blur,
    spreadRadius: spread,
  );

  /// Interpolates two shadow lists layer by layer; lists of different length
  /// switch at `t == 0.5`.
  static List<ShadowValue> lerpList(
    List<ShadowValue> a,
    List<ShadowValue> b,
    double t,
  ) {
    if (a.length != b.length) return t < 0.5 ? a : b;
    return [for (var i = 0; i < a.length; i++) a[i]._lerp(b[i], t)];
  }

  ShadowValue _lerp(ShadowValue other, double t) => ShadowValue(
    offset: Offset.lerp(offset, other.offset, t)!,
    blur: lerpDouble(blur, other.blur, t)!,
    spread: lerpDouble(spread, other.spread, t)!,
    color: Color.lerp(color, other.color, t)!,
    inset: t < 0.5 ? inset : other.inset,
  );

  @override
  String toString() =>
      '${inset ? 'inset ' : ''}${_px(offset.dx)} ${_px(offset.dy)} ${_px(blur)} ${_px(spread)} ${ColorValue.format(color)}';

  static String _px(double v) => '${v == v.roundToDouble() ? v.round() : v}px';

  @override
  bool operator ==(Object other) =>
      other is ShadowValue &&
      other.offset == offset &&
      other.blur == blur &&
      other.spread == spread &&
      other.color == color &&
      other.inset == inset;

  @override
  int get hashCode => Object.hash(offset, blur, spread, color, inset);

  static ShadowValue _layer(String layer, String where) {
    var text = layer.trim();
    var inset = false;
    if (text.toLowerCase().startsWith('inset ')) {
      inset = true;
      text = text.substring(6).trim();
    }
    final start = RegExp(r'(#|rgba?\(|transparent)').firstMatch(text);
    if (start == null) {
      throw ThemeException('shadow layer "$layer" has no colour', where: where);
    }
    final lengths = text.substring(0, start.start).trim();
    final color = ColorValue.parse(
      text.substring(start.start).trim(),
      where: where,
    );
    final numbers = RegExp(r'[-+]?[0-9]*\.?[0-9]+')
        .allMatches(lengths)
        .map((m) => double.parse(m.group(0)!))
        .toList();
    if (numbers.length < 2) {
      throw ThemeException(
        'shadow layer "$layer" needs x and y offsets',
        where: where,
      );
    }
    return ShadowValue(
      offset: Offset(numbers[0], numbers[1]),
      blur: numbers.length > 2 ? numbers[2] : 0,
      spread: numbers.length > 3 ? numbers[3] : 0,
      color: color,
      inset: inset,
    );
  }
}

/// Splits [text] on [separator] characters that are outside parentheses.
List<String> splitTopLevel(String text, String separator) {
  final out = <String>[];
  var depth = 0;
  final buffer = StringBuffer();
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (char == '(') depth++;
    if (char == ')') depth--;
    if (char == separator && depth == 0) {
      out.add(buffer.toString().trim());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  final last = buffer.toString().trim();
  if (last.isNotEmpty) out.add(last);
  return out;
}
