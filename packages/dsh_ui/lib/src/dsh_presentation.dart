import 'package:flutter/material.dart' show Material, MaterialType;
import 'package:flutter/widgets.dart';

import 'dsh_snapped_box.dart';
import 'theme_access.dart';

/// Show [builder] in a centered dialog, as dsh's `Modal` does at every width
/// (a phone gets the same card, not a sheet): the mask over the page, 24px of
/// air on every side, the card [width] wide (never wider than the room) and,
/// when [height] is given, that tall (never taller than the room). The card
/// rides above the keyboard. Answers what the route popped.
Future<T?> showDshDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  String? label,
  double width = 380,
  double? height,
  bool dismissible = true,
}) {
  final theme = context.dsh;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierLabel: label ?? '',
    barrierColor: theme.color('--dsw-alias-bg-mask-1'),
    transitionDuration: Duration.zero,
    pageBuilder: (dialogContext, _, _) => SafeArea(
      child: Padding(
        // The keyboard takes its room first: the card centers in what is left.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(dialogContext).bottom,
        ),
        child: Center(
          // Modal's root keeps 24px of air on every side.
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: DshDialogFrame(
              width: width,
              height: height,
              child: builder(dialogContext),
            ),
          ),
        ),
      ),
    ),
  );
}

/// The card of a centered dialog (dsh `Modal`'s `.dialog`): the secondary layer
/// with the panel radius and the prominent elevation, [width] wide and
/// [height] tall when given, both clamped to the room the layout offers
/// (`min(380px, 100%)`). Text inputs inside get the Material ancestor they
/// need.
class DshDialogFrame extends StatelessWidget {
  const DshDialogFrame({
    super.key,
    required this.width,
    this.height,
    required this.child,
  });

  final double width;
  final double? height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.hasBoundedWidth
            ? width.clamp(0.0, constraints.maxWidth)
            : width;
        final h = height == null
            ? null
            : (constraints.hasBoundedHeight
                  ? height!.clamp(0.0, constraints.maxHeight)
                  : height!);
        return SizedBox(
          width: w,
          height: h,
          child: DshDecoratedBox(
            decoration: BoxDecoration(
              color: theme.color('--dsw-alias-bg-layer-2'),
              borderRadius: BorderRadius.circular(theme.radiusPanel),
              boxShadow: theme.boxShadow('--dsw-elevation-prominent'),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(theme.radiusPanel),
              child: Material(type: MaterialType.transparency, child: child),
            ),
          ),
        );
      },
    );
  }
}
