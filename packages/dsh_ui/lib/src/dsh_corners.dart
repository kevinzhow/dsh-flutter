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

/// The same CSS corner curve with independent elliptical radii. CSS scales
/// all radii together when adjacent corners overlap an edge.
Path dshSuperellipseCornersPath(
  Rect rect,
  BorderRadius corners,
  double curvature,
) {
  if (rect.isEmpty) return Path();
  final radii = [
    for (final r in [
      corners.topLeft,
      corners.topRight,
      corners.bottomRight,
      corners.bottomLeft,
    ])
      if (r.x <= 0 || r.y <= 0) Radius.zero else r,
  ];
  var scale = 1.0;
  void limit(double extent, double sum) {
    if (sum > 0) scale = math.min(scale, extent / sum);
  }

  limit(rect.width, radii[0].x + radii[1].x);
  limit(rect.width, radii[3].x + radii[2].x);
  limit(rect.height, radii[0].y + radii[3].y);
  limit(rect.height, radii[1].y + radii[2].y);
  final normalized = [
    for (final r in radii)
      Radius.elliptical(math.max(0, r.x * scale), math.max(0, r.y * scale)),
  ];
  if (curvature == 1) {
    return Path()..addRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: normalized[0],
        topRight: normalized[1],
        bottomRight: normalized[2],
        bottomLeft: normalized[3],
      ),
    );
  }
  final exponent = 2 / math.pow(2, curvature);
  final path = Path()..moveTo(rect.left + normalized[0].x, rect.top);
  void corner(int index, double cx, double cy, double startAngle) {
    final r = normalized[index];
    if (r.x == 0 || r.y == 0) {
      path.lineTo(cx, cy);
      return;
    }
    for (var i = 0; i <= 48; i++) {
      final angle = startAngle + i * math.pi / 96;
      final x = math.cos(angle), y = math.sin(angle);
      path.lineTo(
        cx + x.sign * math.pow(x.abs(), exponent) * r.x,
        cy + y.sign * math.pow(y.abs(), exponent) * r.y,
      );
    }
  }

  final tl = normalized[0],
      tr = normalized[1],
      br = normalized[2],
      bl = normalized[3];
  path.lineTo(rect.right - tr.x, rect.top);
  corner(1, rect.right - tr.x, rect.top + tr.y, -math.pi / 2);
  path.lineTo(rect.right, rect.bottom - br.y);
  corner(2, rect.right - br.x, rect.bottom - br.y, 0);
  path.lineTo(rect.left + bl.x, rect.bottom);
  corner(3, rect.left + bl.x, rect.bottom - bl.y, math.pi / 2);
  path.lineTo(rect.left, rect.top + tl.y);
  corner(0, rect.left + tl.x, rect.top + tl.y, math.pi);
  return path..close();
}

/// A rounded rectangle whose corners follow dsh's `corner-shape`
/// ([dshCornerCurvature]), with an optional border drawn inside the outline
/// like a CSS border (inner radius = radius - width).
class DshCornerBorder extends OutlinedBorder {
  const DshCornerBorder({
    required this.radius,
    this.curvature = 1.5,
    this.corners,
    super.side = BorderSide.none,
  });

  /// Outer corner radius.
  final double radius;

  /// The CSS `superellipse()` parameter; 1 is circular.
  final double curvature;

  /// Omitted keeps the original uniform-radius path byte for byte.
  final BorderRadius? corners;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      corners == null
      ? dshSuperellipsePath(rect, radius, curvature)
      : dshSuperellipseCornersPath(rect, corners!, curvature);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final shape = corners;
    if (shape == null) {
      return dshSuperellipsePath(
        rect.deflate(side.width),
        math.max(0, radius - side.width),
        curvature,
      );
    }
    Radius inset(Radius r) => Radius.elliptical(
      math.max(0, r.x - side.width),
      math.max(0, r.y - side.width),
    );
    return dshSuperellipseCornersPath(
      rect.deflate(side.width),
      BorderRadius.only(
        topLeft: inset(shape.topLeft),
        topRight: inset(shape.topRight),
        bottomLeft: inset(shape.bottomLeft),
        bottomRight: inset(shape.bottomRight),
      ),
      curvature,
    );
  }

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
  DshCornerBorder copyWith({
    BorderSide? side,
    double? radius,
    BorderRadius? corners,
  }) => DshCornerBorder(
    corners: corners ?? this.corners,
    radius: radius ?? this.radius,
    curvature: curvature,
    side: side ?? this.side,
  );

  @override
  ShapeBorder scale(double t) => DshCornerBorder(
    corners: corners == null ? null : corners! * t,
    radius: radius * t,
    curvature: curvature,
    side: side.scale(t),
  );

  @override
  bool operator ==(Object other) =>
      other is DshCornerBorder &&
      other.radius == radius &&
      other.corners == corners &&
      other.curvature == curvature &&
      other.side == side;

  @override
  int get hashCode => Object.hash(radius, curvature, side, corners);
}

/// Shorthand for the surfaces of the product: a [ShapeDecoration] of [radius]
/// in the theme's corner shape, filled with [color] and optionally bordered.
extension DshCornerDecoration on DshThemeData {
  /// The corner border of [radius] for this theme.
  DshCornerBorder cornerBorder(
    double radius, {
    Color? borderColor,
    double? borderWidth,
    BorderRadius? corners,
  }) {
    assert(
      borderColor == null || borderWidth != null,
      'a border needs its width, resolved at the display density '
      '(dshBorderWidthOf / dshHairlineOf)',
    );
    return DshCornerBorder(
      radius: radius,
      corners: corners,
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
    BorderRadius? corners,
  }) => ShapeDecoration(
    color: color,
    shape: cornerBorder(
      radius,
      borderColor: borderColor,
      borderWidth: borderWidth,
      corners: corners,
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
