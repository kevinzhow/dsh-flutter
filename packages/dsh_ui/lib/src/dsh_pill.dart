import 'package:flutter/widgets.dart';

import 'dsh_text_scale.dart';
import 'theme_access.dart';

/// A read-only capsule at the 24px text-line size (dsh `Pill`); the terminal
/// card's exit status is the case this serves. [height] caps it to a line.
class DshPill extends StatelessWidget {
  const DshPill({super.key, required this.child, this.color, this.height = 24});

  final Widget child;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.color('--dsw-alias-bg-layer-2'),
        borderRadius: BorderRadius.circular(999),
      ),
      child: DefaultTextStyle.merge(
        style: theme
            .textStyle('--dsw-font-xs-13')
            .sized(12, line: 18)
            .copyWith(
              color: color ?? theme.color('--dsw-alias-label-secondary'),
            ),
        child: child,
      ),
    );
  }
}
