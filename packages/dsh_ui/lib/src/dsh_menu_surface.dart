import 'package:flutter/widgets.dart';

import 'dsh_diff_block.dart' show blendLikeChromium, saturateLikeChromium;
import 'dsh_shadow_box.dart';
import 'theme_access.dart';

/// dsh's `MenuSurface`: the translucent menu material (`--dsw-specific-menu`
/// over the page, `backdrop-filter: saturate(150%)`), the prominent elevation
/// with its stroke rebound to the l1 hairline, and the large radius. Menus,
/// candidate lists and popups sit on it.
class DshMenuSurface extends StatelessWidget {
  const DshMenuSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DshShadowBox(
      color: blendLikeChromium(
        theme.color('--dsw-specific-menu'),
        saturateLikeChromium(theme.bgBase, 1.5),
      ),
      radius: theme.radiusLg,
      shadows: [
        for (final (i, s)
            in theme.boxShadow('--dsw-elevation-prominent').indexed)
          i == 0
              ? BoxShadow(
                  color: theme.color('--dsw-alias-border-l1'),
                  spreadRadius: s.spreadRadius,
                )
              : s,
      ],
      padding: padding,
      child: child,
    );
  }
}
