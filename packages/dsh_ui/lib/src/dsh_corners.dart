import 'dart:math' as math;

import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/widgets.dart';

import 'dsh_diff_block.dart' show blendLikeChromium;
import 'dsh_pixel_snap.dart';
import 'theme_access.dart';

/// The curvature parameter of dsh's corner shape: `--dsw-corner-shape` is
/// `superellipse(1.5)` (ui-theme corner-shape.css gives every rounded surface
/// that corner, circles opt out with `corner-shape: round`). CSS defines the
/// corner curve `|x|^n + |y|^n = 1` with `n = 2^parameter`, so `round` is
/// `superellipse(1)` (the circle) and `squircle` `superellipse(2)`.
double dshCornerCurvature(DshThemeData theme) {
  final raw = theme.strings['--dsw-corner-shape'];
  if (raw == null || raw == 'round') return 1;
  final match = RegExp(r'^superellipse\(\s*(-?[\d.]+)\s*\)$').firstMatch(raw);
  return match == null ? 1 : double.parse(match.group(1)!);
}

/// The closed outline of [rect] with every corner a superellipse of [radius]
/// (clamped to half the shorter side, like CSS) and [curvature] (see
/// [dshCornerCurvature]); a curvature of 1 is the ordinary circular corner.
Path dshSuperellipsePath(Rect rect, double radius, double curvature) {
  final r = math.max(
    0.0,
    math.min(radius, math.min(rect.width, rect.height) / 2),
  );
  final path = Path();
  if (r == 0) return path..addRect(rect);
  if (curvature == 1) {
    return path..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)));
  }
  final exponent = 2 / math.pow(2, curvature);
  // One corner as offsets from its centre, from the horizontal-edge tangent
  // point (0, r) to the vertical-edge one (r, 0): x = r sin(t)^e, y = r cos(t)^e.
  const steps = 48;
  final corner = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    final t = (math.pi / 2) * i / steps;
    final x = math.pow(math.sin(t), exponent).toDouble() * r;
    final y = math.pow(math.cos(t), exponent).toDouble() * r;
    corner.add(Offset(x, y));
  }
  final l = rect.left, t = rect.top, rr = rect.right, b = rect.bottom;
  path.moveTo(l + r, t);
  path.lineTo(rr - r, t);
  // top-right: from (rr - r, t) down to (rr, t + r)
  for (final p in corner) {
    path.lineTo(rr - r + p.dx, t + r - p.dy);
  }
  path.lineTo(rr, b - r);
  // bottom-right: from (rr, b - r) to (rr - r, b)
  for (final p in corner) {
    path.lineTo(rr - r + p.dy, b - r + p.dx);
  }
  path.lineTo(l + r, b);
  // bottom-left: from (l + r, b) to (l, b - r)
  for (final p in corner) {
    path.lineTo(l + r - p.dx, b - r + p.dy);
  }
  path.lineTo(l, t + r);
  // top-left: from (l, t + r) to (l + r, t)
  for (final p in corner) {
    path.lineTo(l + r - p.dy, t + r - p.dx);
  }
  path.close();
  return path;
}

/// A rounded rectangle whose corners follow dsh's `corner-shape`
/// ([dshCornerCurvature]), with an optional border drawn inside the outline
/// like a CSS border (inner radius = radius - width).
class DshCornerBorder extends OutlinedBorder {
  const DshCornerBorder({
    required this.radius,
    this.curvature = 1.5,
    super.side = BorderSide.none,
  });

  /// Outer corner radius.
  final double radius;

  /// The CSS `superellipse()` parameter; 1 is circular.
  final double curvature;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      dshSuperellipsePath(rect, radius, curvature);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      dshSuperellipsePath(
        rect.deflate(side.width),
        math.max(0, radius - side.width),
        curvature,
      );

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addPath(getOuterPath(rect), Offset.zero)
      ..addPath(getInnerPath(rect), Offset.zero);
    canvas.drawPath(
      ring,
      Paint()
        ..color = side.color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true,
    );
  }

  @override
  DshCornerBorder copyWith({BorderSide? side, double? radius}) =>
      DshCornerBorder(
        radius: radius ?? this.radius,
        curvature: curvature,
        side: side ?? this.side,
      );

  @override
  ShapeBorder scale(double t) => DshCornerBorder(
    radius: radius * t,
    curvature: curvature,
    side: side.scale(t),
  );

  @override
  bool operator ==(Object other) =>
      other is DshCornerBorder &&
      other.radius == radius &&
      other.curvature == curvature &&
      other.side == side;

  @override
  int get hashCode => Object.hash(radius, curvature, side);
}

/// Shorthand for the surfaces of the product: a [ShapeDecoration] of [radius]
/// in the theme's corner shape, filled with [color] and optionally bordered.
extension DshCornerDecoration on DshThemeData {
  /// The corner border of [radius] for this theme.
  DshCornerBorder cornerBorder(
    double radius, {
    Color? borderColor,
    double? borderWidth,
  }) {
    assert(
      borderColor == null || borderWidth != null,
      'a border needs its width, resolved at the display density '
      '(dshBorderWidthOf / dshHairlineOf)',
    );
    return DshCornerBorder(
      radius: radius,
      curvature: dshCornerCurvature(this),
      side: borderColor == null
          ? BorderSide.none
          : BorderSide(color: borderColor, width: borderWidth ?? 0),
    );
  }

  /// A filled (and optionally bordered) surface in the theme's corner shape.
  ShapeDecoration cornerDecoration(
    double radius, {
    Color? color,
    Color? borderColor,
    double? borderWidth,
  }) => ShapeDecoration(
    color: color,
    shape: cornerBorder(
      radius,
      borderColor: borderColor,
      borderWidth: borderWidth,
    ),
  );

  /// Clips a child to the outline of [radius] in the theme's corner shape.
  Widget clipCorners(double radius, Widget child) => ClipPath(
    clipper: ShapeBorderClipper(shape: cornerBorder(radius)),
    child: child,
  );
}

/// [context.dsh] sugar for the helpers above.
extension DshCornerContext on BuildContext {
  /// A bordered surface as dsh paints it: [radius] in the theme's corner shape,
  /// an opaque [fill] and a [border] hairline of [borderWidth] that the web
  /// client blends over that fill ([DshSurface.paint]). [fill] null is a
  /// surface with no fill of its own, the border then blends over the declared
  /// [DshSurface]. [over] names the surface behind when it is not the
  /// ambient one (the caller sits outside the [DshSurface] it declares).
  ShapeDecoration dshOutlined(
    double radius, {
    Color? fill,
    Color? border,
    Color? over,
    double? borderWidth,
  }) {
    final paintedFill = fill == null
        ? null
        : DshSurface.paint(this, fill, over: over);
    return dsh.cornerDecoration(
      radius,
      color: paintedFill,
      borderColor: border == null
          ? null
          : DshSurface.paint(
              this,
              border,
              over: paintedFill != null && paintedFill.a >= 1
                  ? paintedFill
                  : over,
            ),
      borderWidth: borderWidth ?? dshHairlineOf(this),
    );
  }

  /// The theme's [DshCornerBorder] of [radius].
  DshCornerBorder cornerBorder(double radius) => dsh.cornerBorder(radius);
}

/// The opaque colour a widget sits on. dsh's translucent fills and hairlines
/// (`rgb(0 0 0 / 10%)`) composite onto it in Chromium's 8-bit arithmetic, which
/// differs from Skia's float blend by one level; widgets that know their
/// surface pre-composite those colours ([blendLikeChromium]) so the pixels
/// agree. Defaults to the page background; a card or composer that draws its
/// own opaque fill wraps its content in a [DshSurface].
class DshSurface extends InheritedWidget {
  const DshSurface({super.key, required this.color, required super.child});

  final Color color;

  /// The surface behind [context]: the nearest [DshSurface], else `bg-base`.
  static Color of(BuildContext context) =>
      maybeOf(context) ?? context.dsh.bgBase;

  /// The surface behind [context] when a [DshSurface] declares it, else null.
  static Color? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DshSurface>()?.color;

  /// A translucent dsh colour as Chromium paints it. Chromium holds an alpha as
  /// 8 bits and blends in 8-bit arithmetic that rounds the source share and
  /// floors the backdrop's ([blendLikeChromium]); Skia blends in float, one
  /// level off on many channels. With a declared [DshSurface] the colour is
  /// composited onto it (opaque result, exact); without one the backdrop is
  /// unknown (a card, an image), so it stays translucent with Chromium's
  /// 8-bit alpha, which is as close as a blend over an unknown colour gets.
  static Color paint(BuildContext context, Color colour, {Color? over}) {
    if (colour.a >= 1) return colour;
    final under = over ?? maybeOf(context);
    if (under != null) return blendLikeChromium(colour, under);
    return quantizeAlpha(colour);
  }

  /// [colour] with Chromium's 8-bit alpha (`0.5` is 128/255, not one half).
  static Color quantizeAlpha(Color colour) =>
      colour.withValues(alpha: (colour.a * 255).round() / 255);

  @override
  bool updateShouldNotify(DshSurface old) => old.color != color;
}
