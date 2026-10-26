import 'package:flutter/widgets.dart';

import 'dsh_corners.dart';
import 'dsh_diff_block.dart' show blendLikeChromium, saturateLikeChromium;
import 'dsh_recipes.g.dart';
import 'dsh_shadow_box.dart';
import 'dsh_snapped_box.dart';
import 'dsh_pixel_snap.dart';
import 'theme_access.dart';

enum DshMenuSurfaceProfile { standard, dock }

/// The one menu material used by cards and contributed menu content. Only
/// its material is painted; nested overlays and focus outlines stay free.
class DshMenuSurface extends StatelessWidget {
  const DshMenuSurface({
    super.key,
    required this.child,
    this.padding,
    this.compact = false,
    this.profile = DshMenuSurfaceProfile.standard,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final bool compact;
  final DshMenuSurfaceProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final radius = theme.number(
      compact
          ? DshMenuSurfaceRecipe.compactRadiusToken
          : DshMenuSurfaceRecipe.radiusToken,
    );
    final shape = theme.cornerBorder(radius);
    final fill = blendLikeChromium(
      theme.color(DshMenuSurfaceRecipe.fillToken),
      saturateLikeChromium(theme.bgBase, DshMenuSurfaceRecipe.saturation),
    );
    if (profile == DshMenuSurfaceProfile.dock) {
      final inset = (padding ?? const EdgeInsets.all(DshDockMenuRecipe.padding))
          .resolve(Directionality.of(context));
      final border = dshBorderWidthOf(context, DshDockMenuRecipe.borderWidth);
      // dockkit's div keeps CSS content-box sizing; its min-width excludes
      // padding and border, unlike the primitive Menu's explicit border-box.
      return DshContainer(
        constraints: BoxConstraints(
          minWidth: DshDockMenuRecipe.minWidth + inset.horizontal + border * 2,
        ),
        padding: inset,
        decoration: theme.cornerDecoration(
          radius,
          color: fill,
          borderColor: theme.color(DshDockMenuRecipe.borderToken),
          borderWidth: dshBorderWidthOf(context, DshDockMenuRecipe.borderWidth),
        ),
        child: child,
      );
    }
    return DshShadowBox(
      // Published MenuSurface's isolated material is uniform over the opaque
      // page ground on the supported desktop/phone surfaces. Keep that bounded
      // result: Flutter BackdropFilter samples outside the card and incorrectly
      // pulls the trigger into it. Arbitrary content backdrops and transparent
      // macOS windows still need a bounded-backdrop implementation.
      color: fill,
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
