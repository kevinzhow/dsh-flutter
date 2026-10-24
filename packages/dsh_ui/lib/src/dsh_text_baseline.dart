import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Where Chromium puts the baseline of a line of text, which Flutter's
/// paragraph does not reproduce.
///
/// Both engines place the baseline of a fixed `line-height` line at the line's
/// top plus the font's ascent plus half of the leading, but they compute it
/// differently:
///
/// - Blink rounds the font's ascent and descent to whole CSS pixels, then puts
///   `floor((line - ascent - descent) / 2)` of the leading above the text
///   (`FontHeight::AddLeading`): `ascent + floor((line - ascent - descent) / 2)`.
///   Layout is in CSS pixels, so the result does not depend on the display
///   density.
/// - Flutter keeps the metrics fractional, adds exactly half of the leading and
///   rounds the sum: `round(ascent + (line - ascent - descent) / 2)`.
///
/// The two agree for 14px on 22px (dsh's body text) and differ by one CSS pixel
/// whenever the rounding goes the other way: 12px on 18px, 12 on 20, 17 on 26
/// and 20 on 28 with the pinned Noto Sans (the captions, settings descriptions
/// and large titles), at every density. Measured over 24 size and line-height
/// pairs of dsh's type ladder, 2 weights and 5 densities
/// (`docs/parity.md`, "The text baseline").
///
/// Returns the vertical paint offset (logical pixels) that moves [style]'s
/// baseline from Flutter's to Blink's; 0 when they agree, when the style has no
/// fixed line height, or on a font without metrics.
double dshBaselineNudge(TextStyle style) {
  final size = style.fontSize;
  final height = style.height;
  if (size == null || height == null) return 0;
  return _nudges[style] ??= _nudge(style, size, height);
}

final Map<TextStyle, double> _nudges = {};

double _nudge(TextStyle style, double size, double height) {
  // The style's own face without its fixed line height: the font's natural
  // ascent and descent.
  final plain = TextStyle(
    fontFamily: style.fontFamily,
    fontFamilyFallback: style.fontFamilyFallback,
    fontSize: size,
    fontWeight: style.fontWeight,
    fontStyle: style.fontStyle,
  );
  double? baseline(TextStyle s, {StrutStyle? strut}) {
    final painter = TextPainter(
      text: TextSpan(text: 'Hg', style: s),
      strutStyle: strut,
      textDirection: TextDirection.ltr,
    )..layout();
    final lines = painter.computeLineMetrics();
    painter.dispose();
    return lines.isEmpty ? null : lines.first.baseline;
  }

  ({double ascent, double descent})? metrics(TextStyle s) {
    final painter = TextPainter(
      text: TextSpan(text: 'Hg', style: s),
      textDirection: TextDirection.ltr,
    )..layout();
    final lines = painter.computeLineMetrics();
    painter.dispose();
    if (lines.isEmpty) return null;
    return (ascent: lines.first.ascent, descent: lines.first.descent);
  }

  final font = metrics(plain);
  final flutter = baseline(style, strut: dshStrut(style));
  if (font == null || flutter == null) return 0;
  final ascent = _roundHalfUp(font.ascent);
  final descent = _roundHalfUp(font.descent);
  // Layout units are 1/64 px; `height * size` carries float noise below that.
  final line = (height * size * 64).roundToDouble() / 64;
  final blink = ascent + ((line - ascent - descent) / 2).floor();
  // The paragraph reports the fractional baseline but paints at the rounded
  // one (layout is in logical pixels, whatever the density).
  return blink - _roundHalfUp(flutter);
}

double _roundHalfUp(double v) => (v + 0.5).floorToDouble();

/// Paints [child] (one text with [style]) with its baseline where Chromium
/// puts it; layout is untouched.
///
/// The baseline moves to Blink's rounding ([dshBaselineNudge]). Blink in the
/// parity captures also lays out in CSS pixels and paints a line at a whole
/// CSS pixel: a line whose top lands on a half pixel (a block centred in a
/// box of the other parity) is rounded half up, where Flutter paints at the
/// fraction and lets the device round it. The child is therefore moved to the
/// whole logical pixel it sits at as well.
class DshChromeBaseline extends SingleChildRenderObjectWidget {
  const DshChromeBaseline({super.key, required this.style, super.child});

  final TextStyle style;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderChromeBaseline(dshBaselineNudge(style));

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderChromeBaseline).nudge = dshBaselineNudge(style);
}

class _RenderChromeBaseline extends RenderProxyBox {
  _RenderChromeBaseline(this._nudge);

  double _nudge;

  set nudge(double value) {
    if (value == _nudge) return;
    _nudge = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final top = localToGlobal(Offset.zero).dy;
    final snap = (top + 0.5).floorToDouble() - top;
    super.paint(context, offset + Offset(0, _nudge + snap));
  }
}

/// A strut that pins every line of a text with [style] to the style's own line
/// height and primary-font baseline, like CSS `line-height` with a fixed
/// length: a line with ideographs (drawn in a fallback font with other
/// metrics) otherwise grows taller and sits lower than Chromium's.
StrutStyle dshStrut(TextStyle style) =>
    StrutStyle.fromTextStyle(style, forceStrutHeight: true);

/// The product's text: a [Text] whose lines sit where Chromium puts them.
///
/// A line height that is a fixed length (every dsh type style) pins each line
/// to the style's own height and primary-font baseline ([dshStrut]), and the
/// baseline is moved to Blink's rounding ([dshBaselineNudge]); layout is the
/// one [Text] would have. A style without a fixed line height is a plain
/// [Text].
class DshChromeText extends StatelessWidget {
  const DshChromeText(
    this.data, {
    super.key,
    this.style,
    this.strutStyle,
    this.textAlign,
    this.textDirection,
    this.softWrap,
    this.overflow,
    this.maxLines,
    this.textWidthBasis,
    this.semanticsLabel,
  });

  final String data;
  final TextStyle? style;
  final StrutStyle? strutStyle;
  final TextAlign? textAlign;
  final TextDirection? textDirection;
  final bool? softWrap;
  final TextOverflow? overflow;
  final int? maxLines;
  final TextWidthBasis? textWidthBasis;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    var effective = style;
    if (effective == null || effective.inherit) {
      effective = DefaultTextStyle.of(context).style.merge(effective);
    }
    final fixed = effective.fontSize != null && effective.height != null;
    final text = Text(
      data,
      style: style,
      strutStyle: strutStyle ?? (fixed ? dshStrut(effective) : null),
      textAlign: textAlign,
      textDirection: textDirection,
      softWrap: softWrap,
      overflow: overflow,
      maxLines: maxLines,
      textWidthBasis: textWidthBasis,
      semanticsLabel: semanticsLabel,
    );
    return fixed ? DshChromeBaseline(style: effective, child: text) : text;
  }
}
