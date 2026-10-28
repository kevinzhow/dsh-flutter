import 'package:flutter/widgets.dart';

import 'dsh_text_baseline.dart';

/// CSS normal whitespace and a one-line clamp: wrap the original value first,
/// then make room for the ellipsis within that line. A sole unbreakable run
/// overflows horizontally and is clipped, as in the published card stylesheet.
/// The complete original value remains available to accessibility.
class DshSingleLineClamp extends StatelessWidget {
  const DshSingleLineClamp(this.text, {super.key, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final locale = Localizations.maybeLocaleOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final normalized = text
            .replaceAll(RegExp(r'[ \t\r\n\f]+'), ' ')
            .replaceAll(RegExp(r'^ +| +$'), '');
        var visible = normalized;
        if (constraints.hasBoundedWidth && constraints.maxWidth > 0) {
          final painter = TextPainter(
            text: TextSpan(text: normalized, style: effectiveStyle),
            textDirection: direction,
            textScaler: scaler,
            locale: locale,
          )..layout(maxWidth: constraints.maxWidth);
          if (painter.computeLineMetrics().length > 1) {
            final end = painter
                .getLineBoundary(const TextPosition(offset: 0))
                .end;
            // The terminal space gives the native line breaker an explicit
            // end opportunity; otherwise minIntrinsicWidth can exclude the
            // last grapheme of an unbroken run. It is measurement-only.
            final endBreak = TextPainter(
              text: TextSpan(text: '$normalized ', style: effectiveStyle),
              textDirection: direction,
              textScaler: scaler,
              locale: locale,
            )..layout();
            // Compare the same intrinsic calculation with an otherwise
            // identical, measurement-only unbreakable copy. Native min/max
            // intrinsic calculations round differently, even for one word.
            final joined = normalized.characters.join('\u2060');
            final unbreakable = TextPainter(
              text: TextSpan(text: '$joined ', style: effectiveStyle),
              textDirection: direction,
              textScaler: scaler,
              locale: locale,
            )..layout();
            final singleRun =
                endBreak.minIntrinsicWidth == unbreakable.minIntrinsicWidth;
            endBreak.dispose();
            unbreakable.dispose();
            var first = normalized
                .substring(0, end)
                .replaceFirst(RegExp(r' +$'), '');
            bool fits(String value) {
              painter.text = TextSpan(
                text: '$value\u2026',
                style: effectiveStyle,
              );
              painter.layout();
              return painter.width <= constraints.maxWidth;
            }

            if (!singleRun) {
              // Chromium may shorten the last word to make room, but never
              // pulls a word from the next original line into this one.
              while (first.isNotEmpty && !fits(first)) {
                first = first.characters
                    .skipLast(1)
                    .toString()
                    .replaceFirst(RegExp(r' +$'), '');
              }
              visible = '$first\u2026';
            }
          }
          painter.dispose();
        }
        final line = DshChromeText(
          visible,
          semanticsLabel: text,
          style: style,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.clip,
        );
        // A CSS-normal block containing only collapsed whitespace has no
        // line box. Its owning Card still retains the description-row gap.
        return normalized.isEmpty ? SizedBox.shrink(child: line) : line;
      },
    );
  }
}
