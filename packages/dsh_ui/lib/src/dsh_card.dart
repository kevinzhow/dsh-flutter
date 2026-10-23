import 'package:flutter/widgets.dart';

import 'theme_access.dart';

/// A bordered surface on `--dsw-alias-bg-layer-*` with a hairline stroke, the
/// container dsh uses for tool rows, sheets and settings cards.
class DshCard extends StatelessWidget {
  const DshCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(DshSpace.md),
    this.layer = 2,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// 1, 2 or 3: which `--dsw-alias-bg-layer-N` fills the card.
  final int layer;

  /// Overrides the fill with a theme colour (already resolved by the caller).
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint ?? theme.color('--dsw-alias-bg-layer-$layer'),
        border: Border.all(
          color: theme.color('--dsw-alias-border-l4'),
          width: 0.5,
        ),
        borderRadius: BorderRadius.circular(theme.radiusLg),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
