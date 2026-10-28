import 'dart:math' as math;
import 'dart:ui' show SemanticsRole;

import 'package:flutter/widgets.dart';

import 'dsh_icon.dart';
import 'dsh_icon_data.dart';
import 'dsh_pixel_snap.dart';
import 'dsh_popover_surface.dart';
import 'dsh_recipes.g.dart';
import 'dsh_snapped_box.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// The published stat-dialog profile shared by session and turn readings.
/// Rows use one common label column and right-aligned tabular values; sizing
/// follows CSS max-content within the source's viewport-bounded width range.
class DshStatPanel extends StatelessWidget {
  const DshStatPanel({
    super.key,
    required this.icon,
    required this.title,
    this.titleValue,
    required this.rows,
  });

  final DshIconData icon;
  final String title;
  final String? titleValue;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final base = theme.fixedTextStyle(
      size: DshStatPanelRecipe.fontSize,
      line: DshStatPanelRecipe.lineHeight,
    );
    final titleStyle = base.copyWith(
      color: theme.color(DshStatPanelRecipe.titleToken),
      fontWeight: FontWeight.values[DshStatPanelRecipe.titleWeight ~/ 100 - 1],
    );
    final valueStyle = base.copyWith(
      color: theme.color(DshStatPanelRecipe.detailValueToken),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final labelStyle = base.copyWith(
      color: theme.color(DshStatPanelRecipe.detailLabelToken),
    );
    double textWidth(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout();
      final width = painter.maxIntrinsicWidth;
      painter.dispose();
      return width;
    }

    final labelWidth = rows.fold<double>(
      DshStatPanelRecipe.labelMinWidth,
      (width, row) => math.max(width, textWidth(row.$1, labelStyle)),
    );
    final valueWidth = rows.fold<double>(
      0,
      (width, row) => math.max(width, textWidth(row.$2, valueStyle)),
    );
    final headingWidth =
        DshStatPanelRecipe.iconSize +
        DshStatPanelRecipe.iconGap +
        textWidth(title, titleStyle) +
        (titleValue == null
            ? 0
            : DshStatPanelRecipe.titleGap + textWidth(titleValue!, titleStyle));
    final naturalWidth =
        math.max(
          headingWidth,
          labelWidth + DshStatPanelRecipe.columnGap + valueWidth,
        ) +
        DshStatPanelRecipe.padding * 2;

    return Semantics(
      container: true,
      role: SemanticsRole.dialog,
      label: title,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = math.max(
            0.0,
            math.min(
              constraints.maxWidth,
              MediaQuery.sizeOf(context).width -
                  DshStatPanelRecipe.viewportMargin * 2,
            ),
          );
          final min = math.min(DshStatPanelRecipe.minWidth, available);
          final max = math.min(DshStatPanelRecipe.maxWidth, available);
          final width = naturalWidth.clamp(min, max);
          final contentWidth = math.max(
            0.0,
            width - DshStatPanelRecipe.padding * 2,
          );
          final labels = math.min(
            labelWidth,
            math.max(
              math.min(DshStatPanelRecipe.labelMinWidth, contentWidth),
              contentWidth - DshStatPanelRecipe.columnGap - valueWidth,
            ),
          );
          return SizedBox(
            key: const ValueKey('stats-panel'),
            width: width,
            child: DshPopoverSurface(
              padding: const EdgeInsets.all(DshStatPanelRecipe.padding),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            DshIcon(
                              icon,
                              size: DshStatPanelRecipe.iconSize,
                              color: theme.color(DshStatPanelRecipe.titleToken),
                            ),
                            const SizedBox(width: DshStatPanelRecipe.iconGap),
                            Flexible(
                              child: DshChromeText(title, style: titleStyle),
                            ),
                          ],
                        ),
                      ),
                      if (titleValue != null) ...[
                        const SizedBox(width: DshStatPanelRecipe.titleGap),
                        DshChromeText(
                          titleValue!,
                          style: titleStyle.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: DshStatPanelRecipe.titleBottomMargin),
                  DshContainer(
                    height: dshBorderWidthOf(
                      context,
                      DshStatPanelRecipe.ruleWidth,
                    ),
                    decoration: BoxDecoration(
                      color: theme.color(DshStatPanelRecipe.ruleToken),
                    ),
                  ),
                  const SizedBox(height: DshStatPanelRecipe.ruleBottomMargin),
                  for (final (index, row) in rows.indexed) ...[
                    if (index > 0)
                      const SizedBox(height: DshStatPanelRecipe.rowGap),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: labels,
                          child: DshChromeText(row.$1, style: labelStyle),
                        ),
                        const SizedBox(width: DshStatPanelRecipe.columnGap),
                        Expanded(
                          child: DshChromeText(
                            row.$2,
                            textAlign: TextAlign.right,
                            style: valueStyle,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
