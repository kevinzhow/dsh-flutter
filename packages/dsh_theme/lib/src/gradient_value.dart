import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter/painting.dart' show Alignment, LinearGradient;

import 'color_value.dart';
import 'shadow_value.dart' show splitTopLevel;
import 'theme_exception.dart';

/// One colour stop; [position] is 0..1 along the gradient line.
class GradientStopValue {
  /// Creates a stop.
  const GradientStopValue(this.color, this.position);

  /// Stop colour including alpha.
  final Color color;

  /// Position along the gradient, 0..1.
  final double position;

  @override
  bool operator ==(Object other) =>
      other is GradientStopValue &&
      other.color == color &&
      other.position == position;

  @override
  int get hashCode => Object.hash(color, position);
}

/// A CSS gradient token: `linear-gradient(180deg, #fff 20.19%, ...)` or a bare
/// stop list (`#2a2fb6 33.102%, #8b76f6 50.954%, #2a2fb6`) when the token only
/// supplies stops. Stops without a position are spread per the CSS rule
/// (first 0, last 100%, others evenly between neighbours).
class GradientValue {
  /// Creates a gradient from already-positioned stops.
  const GradientValue({this.angleDegrees, required this.stops});

  /// CSS angle in degrees (`180` = top to bottom); null for a bare stop list.
  final double? angleDegrees;

  /// Stops in order, positions filled in.
  final List<GradientStopValue> stops;

  /// Parses gradient text; [where] names the key in errors.
  static GradientValue parse(Object? value, {required String where}) {
    if (value is! String) {
      throw ThemeException(
        'a gradient is CSS text, got ${value.runtimeType}',
        where: where,
      );
    }
    final text = value.trim();
    double? angle;
    final call = RegExp(
      r'^linear-gradient\((.*)\)$',
      dotAll: true,
    ).firstMatch(text);
    var parts = splitTopLevel(call == null ? text : call.group(1)!, ',');
    if (call != null && parts.isNotEmpty) {
      final head = RegExp(r'^(-?[0-9.]+)deg$').firstMatch(parts.first);
      if (head != null) {
        angle = double.parse(head.group(1)!);
        parts = parts.sublist(1);
      }
    }
    if (parts.length < 2) {
      throw ThemeException(
        'a gradient needs at least two stops: "$text"',
        where: where,
      );
    }
    final colors = <Color>[];
    final positions = <double?>[];
    for (final part in parts) {
      final m = RegExp(r'^(.*?)(?:\s+(-?[0-9.]+)%)?$').firstMatch(part.trim())!;
      colors.add(ColorValue.parse(m.group(1), where: where));
      positions.add(
        m.group(2) == null ? null : double.parse(m.group(2)!) / 100,
      );
    }
    return GradientValue(angleDegrees: angle, stops: _fill(colors, positions));
  }

  static List<GradientStopValue> _fill(List<Color> colors, List<double?> raw) {
    final p = [...raw];
    p[0] ??= 0;
    p[p.length - 1] ??= 1;
    var i = 0;
    while (i < p.length) {
      if (p[i] != null) {
        i++;
        continue;
      }
      final before = i - 1;
      var after = i;
      while (p[after] == null) {
        after++;
      }
      final span = after - before;
      for (var k = i; k < after; k++) {
        p[k] = p[before]! + (p[after]! - p[before]!) * (k - before) / span;
      }
      i = after;
    }
    return [
      for (var k = 0; k < colors.length; k++)
        GradientStopValue(colors[k], p[k]!),
    ];
  }

  /// This gradient as a Flutter [LinearGradient] (180deg when no angle is set).
  LinearGradient toLinearGradient() {
    final radians = (angleDegrees ?? 180) * math.pi / 180;
    return LinearGradient(
      begin: Alignment(_clean(-math.sin(radians)), _clean(math.cos(radians))),
      end: Alignment(_clean(math.sin(radians)), _clean(-math.cos(radians))),
      colors: [for (final s in stops) s.color],
      stops: [for (final s in stops) s.position],
    );
  }

  // Rounds away -0.0 and floating-point dust (sin(pi) is 1.2e-16).
  static double _clean(double v) => v.abs() < 1e-9 ? 0.0 : v;

  @override
  bool operator ==(Object other) {
    if (other is! GradientValue ||
        other.angleDegrees != angleDegrees ||
        other.stops.length != stops.length) {
      return false;
    }
    for (var i = 0; i < stops.length; i++) {
      if (stops[i] != other.stops[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(angleDegrees, Object.hashAll(stops));
}
