import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/widgets.dart';

import 'dsh_corners.dart';
import 'dsh_recipes.g.dart';
import 'dsh_shell_chrome.dart';
import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// A named group for an unpadded menu scroll viewport. Place it directly in
/// a [CustomScrollView]'s slivers; [separated] is true only when the previous
/// direct sibling is also a group. Its rows stay mounted for callers that
/// navigate with [Scrollable.ensureVisible].
class DshMenuGroup extends StatelessWidget {
  const DshMenuGroup({
    super.key,
    required this.label,
    required this.children,
    this.headingKey,
    this.separated = false,
  });

  final String label;
  final List<Widget> children;
  final Key? headingKey;
  final bool separated;

  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(
    slivers: [
      if (separated)
        const SliverToBoxAdapter(
          child: SizedBox(height: DshMenuGroupRecipe.gap),
        ),
      SliverSemantics(
        container: true,
        explicitChildNodes: true,
        label: label,
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            final style = context.dsh
                .textStyle(DshMenuGroupRecipe.fontToken)
                .copyWith(
                  color: context.dsh.color(DshMenuGroupRecipe.labelToken),
                  fontSize: DshMenuGroupRecipe.fontSize,
                  height:
                      DshMenuGroupRecipe.lineHeight /
                      DshMenuGroupRecipe.fontSize,
                  fontWeight: FontWeight
                      .values[(DshMenuGroupRecipe.fontWeight ~/ 100) - 1],
                );
            final effective = DefaultTextStyle.of(context).style.merge(style);
            final painter =
                TextPainter(
                  text: TextSpan(text: label, style: effective),
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                  locale: Localizations.maybeLocaleOf(context),
                  strutStyle: dshStrut(effective),
                )..layout(
                  maxWidth: math.max(
                    0,
                    constraints.crossAxisExtent -
                        2 * DshMenuGroupRecipe.paddingHorizontal,
                  ),
                );
            final extent =
                painter.height +
                DshMenuGroupRecipe.paddingTop +
                DshMenuGroupRecipe.paddingBottom;
            painter.dispose();
            return SliverMainAxisGroup(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _GroupHeading(
                    label: label,
                    headingKey: headingKey,
                    style: style,
                    extent: extent,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ],
  );
}

class _GroupHeading extends SliverPersistentHeaderDelegate {
  const _GroupHeading({
    required this.label,
    required this.headingKey,
    required this.style,
    required this.extent,
  });

  final String label;
  final Key? headingKey;
  final TextStyle style;
  final double extent;

  @override
  double get minExtent => extent;
  @override
  double get maxExtent => extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = context.dsh;
    return DshContainer(
      padding: const EdgeInsets.fromLTRB(
        DshMenuGroupRecipe.paddingHorizontal,
        DshMenuGroupRecipe.paddingTop,
        DshMenuGroupRecipe.paddingHorizontal,
        DshMenuGroupRecipe.paddingBottom,
      ),
      decoration: theme.cornerDecoration(
        ShellScope.of(context).darwin ||
                defaultTargetPlatform == TargetPlatform.macOS
            ? 0
            : theme.number(DshMenuGroupRecipe.radiusToken),
        color: shrinkOffset > 0
            ? theme.color(DshMenuGroupRecipe.stuckFillToken)
            : const Color(0x00000000),
      ),
      child: ExcludeSemantics(
        child: DshChromeText(label, key: headingKey, style: style),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _GroupHeading old) =>
      label != old.label ||
      headingKey != old.headingKey ||
      style != old.style ||
      extent != old.extent;
}
