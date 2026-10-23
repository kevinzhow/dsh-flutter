import 'package:flutter/widgets.dart';

/// Where Chromium puts the baseline of a line of text, which Flutter's
/// paragraph does not reproduce.
///
/// Chromium lays text out in device pixels: the font's ascent and descent are
/// rounded to whole device pixels at the zoomed size, the half-leading of a
/// fixed `line-height` is `(line - ascent - descent) / 2` rounded half up,
/// and the baseline sits `ascent + halfLeading` below the line's top. Flutter
/// paints a paragraph's baseline at the line's top plus its *logical*-pixel
/// rounded baseline offset. At 2x the two differ by a whole device pixel for
/// many size and line-height pairs (14px on 22px: Chromium 33, Flutter 32),
/// which shifts every glyph row of the line and shows up as a vertical text
/// offset against dsh's web client.
///
/// Returns the vertical paint offset (logical pixels) that moves [style]'s
/// baseline from Flutter's to Chromium's at [devicePixelRatio]; 0 when they
/// agree, when the style has no fixed line height, or on a font without
/// metrics.
double dshBaselineNudge(TextStyle style, double devicePixelRatio) {
  final size = style.fontSize;
  final height = style.height;
  if (size == null || height == null) return 0;
  final key = _NudgeKey(style, devicePixelRatio);
  return _nudges[key] ??= _nudge(style, size, height, devicePixelRatio);
}

final Map<_NudgeKey, double> _nudges = {};

class _NudgeKey {
  const _NudgeKey(this.style, this.dpr);
  final TextStyle style;
  final double dpr;

  @override
  bool operator ==(Object other) =>
      other is _NudgeKey && other.dpr == dpr && other.style == style;

  @override
  int get hashCode => Object.hash(style, dpr);
}

double _nudge(TextStyle style, double size, double height, double dpr) {
  // The style's own face without its fixed line height: the font's natural
  // ascent and descent.
  final plain = TextStyle(
    fontFamily: style.fontFamily,
    fontFamilyFallback: style.fontFamilyFallback,
    fontSize: size,
    fontWeight: style.fontWeight,
    fontStyle: style.fontStyle,
  );
  ({double ascent, double descent, double baseline})? measure(TextStyle s) {
    final painter = TextPainter(
      text: TextSpan(text: 'Hg', style: s),
      textDirection: TextDirection.ltr,
    )..layout();
    final lines = painter.computeLineMetrics();
    painter.dispose();
    if (lines.isEmpty) return null;
    return (
      ascent: lines.first.ascent,
      descent: lines.first.descent,
      baseline: lines.first.baseline,
    );
  }

  final font = measure(plain);
  final fixed = measure(style);
  if (font == null || fixed == null) return 0;
  final ascent = (font.ascent * dpr).roundToDouble();
  final descent = (font.descent * dpr).roundToDouble();
  final line = height * size * dpr;
  final halfLeading = ((line - ascent - descent) / 2 + 0.5).floorToDouble();
  final chromium = ascent + halfLeading;
  final flutter = fixed.baseline.roundToDouble() * dpr;
  return (chromium - flutter) / dpr;
}

/// Paints [child] (one text with [style]) with its baseline where Chromium
/// puts it ([dshBaselineNudge]); layout is untouched.
class DshChromeBaseline extends StatelessWidget {
  const DshChromeBaseline({
    super.key,
    required this.style,
    required this.child,
  });

  final TextStyle style;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final nudge = dshBaselineNudge(
      style,
      MediaQuery.devicePixelRatioOf(context),
    );
    return nudge == 0
        ? child
        : Transform.translate(offset: Offset(0, nudge), child: child);
  }
}

/// A strut that pins every line of a text with [style] to the style's own line
/// height and primary-font baseline, like CSS `line-height` with a fixed
/// length: a line with ideographs (drawn in a fallback font with other
/// metrics) otherwise grows taller and sits lower than Chromium's.
StrutStyle dshStrut(TextStyle style) =>
    StrutStyle.fromTextStyle(style, forceStrutHeight: true);
