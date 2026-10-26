import 'package:flutter/widgets.dart';

import 'dsh_pixel_snap.dart';
import 'dsh_recipes.g.dart';
import 'dsh_snapped_box.dart';
import 'theme_access.dart';

/// Source footer geometry. The border occupies layout space, as in CSS;
/// the caller places this outside the scrolling items to keep it visible.
class DshMenuFooter extends StatelessWidget {
  const DshMenuFooter({super.key, required this.child, this.separated = true});
  final Widget child;
  final bool separated;
  @override
  Widget build(BuildContext context) => DshContainer(
    margin: separated
        ? const EdgeInsets.only(top: DshMenuFooterRecipe.marginTop)
        : EdgeInsets.zero,
    padding: separated
        ? const EdgeInsets.only(top: DshMenuFooterRecipe.paddingTop)
        : EdgeInsets.zero,
    decoration: BoxDecoration(
      border: separated
          ? Border(
              top: BorderSide(
                color: context.dsh.color(DshMenuFooterRecipe.borderToken),
                width: dshBorderWidthOf(
                  context,
                  DshMenuFooterRecipe.borderWidth,
                ),
              ),
            )
          : null,
    ),
    child: child,
  );
}
