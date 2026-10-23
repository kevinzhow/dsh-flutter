import 'dart:ui' show Color;

import 'theme_exception.dart';

/// Reads and writes the colour syntax a theme pack uses.
///
/// Accepted: `#rgb`, `#rrggbb`, `#rrggbbaa`, `rgb(r, g, b)`, `rgba(r, g, b, a)`,
/// `rgb(r g b / a)` with alpha as a number (0..1) or a percentage, and
/// `transparent`. Channels are 0..255 numbers or percentages. Alpha keeps its
/// fractional value (`rgb(0 0 0 / 4%)` is alpha 0.04, not 10/255) because the
/// dsh tokens carry such alphas. Anything else is a [ThemeException] naming
/// the key; a typo must fail loudly instead of falling back to a default.
abstract final class ColorValue {
  /// Parses [value] (a string) into a [Color]; [where] names the key in errors.
  static Color parse(Object? value, {required String where}) {
    if (value is! String) {
      throw ThemeException(
        'a colour is a string, got ${value.runtimeType}',
        where: where,
      );
    }
    final text = value.trim().toLowerCase();
    if (text == 'transparent') return const Color(0x00000000);
    if (text.startsWith('#')) return _hex(text, where);
    final call = RegExp(r'^rgba?\((.*)\)$').firstMatch(text);
    if (call == null) {
      throw ThemeException('not a colour: "$value"', where: where);
    }
    final body = call.group(1)!.trim();
    final List<String> channels;
    double alpha = 1;
    if (body.contains('/')) {
      final parts = body.split('/');
      if (parts.length != 2) {
        throw ThemeException('not a colour: "$value"', where: where);
      }
      channels = _words(parts[0]);
      alpha = _alpha(parts[1].trim(), where);
    } else {
      channels = _words(body);
      if (channels.length == 4) alpha = _alpha(channels.removeLast(), where);
    }
    if (channels.length != 3) {
      throw ThemeException('rgb() needs 3 channels: "$value"', where: where);
    }
    return Color.from(
      alpha: alpha.clamp(0.0, 1.0),
      red: _channel(channels[0], where),
      green: _channel(channels[1], where),
      blue: _channel(channels[2], where),
    );
  }

  /// Canonical text for [color]: `#rrggbb` when opaque, else `rgb(r g b / n%)`.
  static String format(Color color) {
    final r = (color.r * 255).round(),
        g = (color.g * 255).round(),
        b = (color.b * 255).round();
    if (color.a >= 1) {
      String h(int v) => v.toRadixString(16).padLeft(2, '0');
      return '#${h(r)}${h(g)}${h(b)}';
    }
    final pct = (color.a * 100 * 1000).round() / 1000;
    final text = pct == pct.roundToDouble() ? '${pct.round()}' : '$pct';
    return 'rgb($r $g $b / $text%)';
  }

  static List<String> _words(String text) =>
      text.split(RegExp(r'[\s,]+')).where((w) => w.isNotEmpty).toList();

  static Color _hex(String text, String where) {
    var digits = text.substring(1);
    if (!RegExp(r'^[0-9a-f]+$').hasMatch(digits)) {
      throw ThemeException('not a colour: "$text"', where: where);
    }
    if (digits.length == 3 || digits.length == 4) {
      digits = digits.split('').map((c) => '$c$c').join();
    }
    if (digits.length == 6) digits = '${digits}ff';
    if (digits.length != 8) {
      throw ThemeException(
        'hex colours are #rgb, #rrggbb or #rrggbbaa: "$text"',
        where: where,
      );
    }
    int at(int i) => int.parse(digits.substring(i, i + 2), radix: 16);
    return Color.from(
      alpha: at(6) / 255,
      red: at(0) / 255,
      green: at(2) / 255,
      blue: at(4) / 255,
    );
  }

  static double _channel(String text, String where) {
    if (text.endsWith('%')) {
      return (_number(text.substring(0, text.length - 1), where) / 100).clamp(
        0.0,
        1.0,
      );
    }
    return (_number(text, where) / 255).clamp(0.0, 1.0);
  }

  static double _alpha(String text, String where) {
    if (text.endsWith('%')) {
      return _number(text.substring(0, text.length - 1), where) / 100;
    }
    return _number(text, where);
  }

  static double _number(String text, String where) {
    final value = double.tryParse(text.trim());
    if (value == null) {
      throw ThemeException('expected a number, got "$text"', where: where);
    }
    return value;
  }
}
