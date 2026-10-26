import 'package:flutter/widgets.dart';

import 'dsh_corners.dart';
import 'dsh_diff_block.dart' show blendLikeChromium, saturateLikeChromium;
import 'dsh_recipes.g.dart';
import 'dsh_shadow_box.dart';
import 'theme_access.dart';

/// The one menu material used by cards and contributed menu content. Only
/// its material is painted; nested overlays and focus outlines stay free.
class DshMenuSurface extends StatelessWidget {
  const DshMenuSurface({
    super.key,
    required this.child,
    this.padding,
    this.compact = false,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final radius = theme.number(
      compact
          ? DshMenuSurfaceRecipe.compactRadiusToken
          : DshMenuSurfaceRecipe.radiusToken,
    );
    final shape = theme.cornerBorder(radius);
    return DshShadowBox(
      // Published MenuSurface's isolated material is uniform over the opaque
      // page ground on the supported desktop/phone surfaces. Keep that bounded
      // result: Flutter BackdropFilter samples outside the card and incorrectly
      // pulls the trigger into it. Arbitrary content backdrops and transparent
      // macOS windows still need a bounded-backdrop implementation.
      color: blendLikeChromium(
        theme.color(DshMenuSurfaceRecipe.fillToken),
        saturateLikeChromium(theme.bgBase, DshMenuSurfaceRecipe.saturation),
      ),
      radius: radius,
      shape: shape,
      shadows: [
        for (final (i, shadow)
            in theme.boxShadow(DshMenuSurfaceRecipe.shadowToken).indexed)
          i == 0
              ? BoxShadow(
                  color: theme.color(
                    theme.brightness == Brightness.dark
                        ? DshMenuSurfaceRecipe.darkStrokeToken
                        : DshMenuSurfaceRecipe.strokeToken,
                  ),
                  spreadRadius: shadow.spreadRadius,
                )
              : shadow,
      ],
      padding:
          padding ??
          EdgeInsets.all(
            compact ? DshMenuRecipe.compactPadding : DshMenuRecipe.padding,
          ),
      child: child,
    );
  }
}
