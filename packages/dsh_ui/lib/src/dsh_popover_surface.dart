import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'dsh_corners.dart';
import 'dsh_platform_material.dart';
import 'dsh_recipes.g.dart';
import 'dsh_shadow_box.dart';
import 'theme_access.dart';

/// A source popover material, used by statistic panels. Unlike MenuSurface,
/// these overlays have no opaque macOS backing. Their nearly opaque macOS
/// fill is supplied by the platform token scope; the actual backdrop remains
/// filtered behind the material and the foreground stays sharp.
class DshPopoverSurface extends StatelessWidget {
  const DshPopoverSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.fill,
    this.radiusToken = DshStatPanelRecipe.radiusToken,
    this.strokeToken = DshStatPanelRecipe.strokeToken,
    this.shadowToken = DshStatPanelRecipe.shadowToken,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? fill;
  final String radiusToken, strokeToken, shadowToken;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final radius = theme.number(radiusToken);
    final shape = theme.cornerBorder(radius);
    final saturation = DshMenuSurfaceRecipe.saturation;
    final inverse = 1 - saturation;
    // The CSS saturate() matrix uses the sRGB luminance coefficients below.
    final r = .213 * inverse, g = .715 * inverse, b = .072 * inverse;
    final filter = ui.ImageFilter.compose(
      outer: ui.ColorFilter.matrix([
        r + saturation,
        g,
        b,
        0,
        0,
        r,
        g + saturation,
        b,
        0,
        0,
        r,
        g,
        b + saturation,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
      inner: ui.ImageFilter.blur(
        sigmaX: DshMenuSurfaceRecipe.blurSigma,
        sigmaY: DshMenuSurfaceRecipe.blurSigma,
      ),
    );
    return DshShadowBox(
      color: const Color(0),
      radius: radius,
      shape: shape,
      shadows: [
        for (final (index, shadow) in theme.boxShadow(shadowToken).indexed)
          index == 0
              ? BoxShadow(
                  color: theme.color(strokeToken),
                  spreadRadius: shadow.spreadRadius,
                )
              : shadow,
      ],
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: BackdropFilter(
          filter: filter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fill ?? dshSpecificMenuFillOf(context),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
