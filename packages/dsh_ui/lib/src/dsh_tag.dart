import 'package:flutter/widgets.dart';

import 'dsh_corners.dart';
import 'dsh_pixel_snap.dart';
import 'dsh_recipes.g.dart';
import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

enum DshTagProfile { primitive, pluginStatus }

/// The eight palettes of the published, read-only DSH Tag.
enum DshTagTone {
  outline,
  solid,
  neutral,
  quiet,
  success,
  info,
  warning,
  danger,
}

/// A non-interactive capsule whose caller supplies its content.
class DshTag extends StatelessWidget {
  const DshTag({
    super.key,
    required this.child,
    this.tone = DshTagTone.outline,
    this.profile = DshTagProfile.primitive,
  });

  /// A single unwrapped label using the reference text baseline.
  DshTag.text(
    String text, {
    super.key,
    this.tone = DshTagTone.outline,
    this.profile = DshTagProfile.primitive,
  }) : child = DshChromeText(
         text,
         maxLines: 1,
         softWrap: false,
         overflow: TextOverflow.visible,
       );

  final Widget child;
  final DshTagTone tone;
  final DshTagProfile profile;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final (labelToken, fillToken, alpha) = switch (tone) {
      DshTagTone.outline => (DshTagRecipe.outlineLabelToken, null, null),
      DshTagTone.solid => (
        DshTagRecipe.solidLabelToken,
        DshTagRecipe.solidFillToken,
        null,
      ),
      DshTagTone.neutral => (
        DshTagRecipe.neutralLabelToken,
        DshTagRecipe.neutralFillToken,
        null,
      ),
      DshTagTone.quiet => (DshTagRecipe.quietLabelToken, null, null),
      DshTagTone.success => (
        DshTagRecipe.successToken,
        DshTagRecipe.successToken,
        DshTagRecipe.successAlpha,
      ),
      DshTagTone.info => (
        DshTagRecipe.infoToken,
        DshTagRecipe.infoToken,
        DshTagRecipe.infoAlpha,
      ),
      DshTagTone.warning => (
        DshTagRecipe.warningToken,
        DshTagRecipe.warningToken,
        DshTagRecipe.warningAlpha,
      ),
      DshTagTone.danger => (
        DshTagRecipe.dangerToken,
        DshTagRecipe.dangerToken,
        DshTagRecipe.dangerAlpha,
      ),
    };
    final rawFill = fillToken == null ? null : theme.color(fillToken);
    final fill = rawFill == null
        ? null
        : DshSurface.paint(
            context,
            alpha == null
                ? rawFill
                : rawFill.withValues(alpha: rawFill.a * alpha),
          );
    final border = tone == DshTagTone.outline
        ? Border.all(
            color: theme.color(DshTagRecipe.outlineBorderToken),
            width: dshBorderWidthOf(context, DshTagRecipe.outlineWidth),
          )
        : null;
    final status = profile == DshTagProfile.pluginStatus;
    final edge = border?.dimensions.vertical ?? 0;
    return IntrinsicWidth(
      child: DshContainer(
        height: status ? DshPluginStatusTagRecipe.contentHeight + edge : null,
        alignment: status ? Alignment.center : null,
        padding: EdgeInsets.symmetric(
          horizontal: status
              ? DshPluginStatusTagRecipe.horizontalPadding
              : DshTagRecipe.horizontalPadding,
          vertical: status
              ? DshPluginStatusTagRecipe.verticalPadding
              : DshTagRecipe.verticalPadding,
        ),
        decoration: BoxDecoration(
          color: fill,
          border: border,
          borderRadius: BorderRadius.circular(DshTagRecipe.radius),
        ),
        child: DefaultTextStyle.merge(
          style: theme
              .fixedTextStyle(
                size: status
                    ? DshPluginStatusTagRecipe.fontSize
                    : DshTagRecipe.fontSize,
                line: status
                    ? DshPluginStatusTagRecipe.fontSize *
                          DshPluginStatusTagRecipe.lineHeightFactor
                    : DshTagRecipe.lineHeight,
                weight: DshTagRecipe.fontWeight.round(),
              )
              .copyWith(color: theme.color(labelToken)),
          child: child,
        ),
      ),
    );
  }
}
