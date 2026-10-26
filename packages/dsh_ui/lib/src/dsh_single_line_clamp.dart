import 'package:flutter/widgets.dart';

/// A one-line CSS line clamp: wrap first, then add an ellipsis to that line.
/// Unlike TextOverflow.ellipsis this does not pull part of the next word back
/// onto the first line. The complete value remains available to accessibility.
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
        var visible = text;
        if (constraints.hasBoundedWidth && constraints.maxWidth > 0) {
          final painter = TextPainter(
            text: TextSpan(text: text, style: effectiveStyle),
            textDirection: direction,
            textScaler: scaler,
            locale: locale,
          )..layout(maxWidth: constraints.maxWidth);
          if (painter.computeLineMetrics().length > 1) {
            final end = painter
                .getLineBoundary(const TextPosition(offset: 0))
                .end;
            var first = text.substring(0, end).trimRight();
            bool fits(String value) {
              painter.text = TextSpan(
                text: '$value\u2026',
                style: effectiveStyle,
              );
              painter.layout();
              return painter.width <= constraints.maxWidth;
            }

            // Latin words move as units when there is a previous break. For
            // unbroken words and CJK, remove complete grapheme clusters.
            if (!fits(first)) {
              final boundary = RegExp(r'\s+[A-Za-z0-9][^\s]*$')
                  .firstMatch(first);
              if (boundary != null) first = first.substring(0, boundary.start);
              while (first.isNotEmpty && !fits(first)) {
                first = first.characters.skipLast(1).toString().trimRight();
              }
            }
            visible = '$first\u2026';
          }
          painter.dispose();
        }
        return Text(
          visible,
          semanticsLabel: text,
          style: style,
          maxLines: 1,
          overflow: TextOverflow.clip,
        );
      },
    );
  }
}
