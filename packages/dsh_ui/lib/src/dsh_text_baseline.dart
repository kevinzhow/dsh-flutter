import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'dsh_pixel_snap.dart';

/// Where Chromium puts the baseline of a line of text, which Flutter's
/// paragraph does not reproduce.
///
/// Both engines place the baseline of a fixed `line-height` line at the line's
/// top plus the font's ascent plus half of the leading, but they compute it
/// differently:
///
/// - Blink rounds the font's ascent and descent to whole *layout* pixels, then
///   puts `floor((line - ascent - descent) / 2)` of the leading above the text
///   (`FontHeight::AddLeading`): `ascent + floor((line - ascent - descent) / 2)`
///   ([dshBlinkBaseline]). A phone's Chromium (zoom-for-device-scale-factor)
///   lays out in device pixels, so ascent, descent, line height and the floor
///   are device pixels: the baseline sits on a device pixel, not on a CSS one.
///   The emulated capture setup lays out in CSS pixels ([DshPixelModel]).
/// - Flutter keeps the metrics fractional, adds exactly half of the leading and
///   rounds the sum to a whole *logical* pixel.
///
/// The two agree for 14px on 22px (dsh's body text) at 1x and differ by one
/// pixel whenever the rounding goes the other way (12 on 18, 12 on 20, 17 on
/// 26, 20 on 28 with the pinned Noto Sans), and at 2x to 3x the device-pixel
/// rounding moves them apart for most sizes (`docs/parity.md`, "The text
/// baseline": 116 size, line height, weight and family combinations at 1, 1.5,
/// 2, 2.625 and 3x against Chromium running at that density).
///
/// Returns the vertical paint offset (logical pixels) that moves [style]'s
/// baseline from Flutter's to Blink's at [devicePixelRatio] (1 when omitted: CSS
/// pixels); 0 when they agree, when the style has no fixed line height, or on a
/// font without metrics.
double dshBaselineNudge(TextStyle style, [double devicePixelRatio = 1]) {
  final size = style.fontSize;
  final height = style.height;
  if (size == null || height == null) return 0;
  final density = dshSnapDensity(devicePixelRatio);
  return (_nudges[style] ??= {})[density] ??= _nudge(
    style,
    size,
    height,
    density,
  );
}

final Map<TextStyle, Map<double, double>> _nudges = {};

double _nudge(TextStyle style, double size, double height, double density) {
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
  // Blink scales the font size by the density, so the metrics are the logical
  // ones times it; `height * size` carries float noise below a layout unit.
  final blink =
      dshBlinkBaseline(
        ascent: font.ascent * density,
        descent: font.descent * density,
        lineHeight: height * size * density,
      ) /
      density;
  // The paragraph reports the fractional baseline but paints at the rounded
  // logical one.
  return blink - _roundHalfUp(flutter);
}

double _roundHalfUp(double v) => (v + 0.5).floorToDouble();

/// Paints [child] (one text with [style]) with its baseline where Chromium
/// puts it; layout is untouched.
///
/// The baseline moves to Blink's rounding ([dshBaselineNudge]). Blink also
/// paints a line box at a whole layout pixel (a device pixel on a phone, a CSS
/// pixel in the emulated capture): a line whose top lands between two (a block
/// centred in a box of the other parity, or any fractional density) is rounded
/// half up, where Flutter paints at the fraction. The child is therefore moved
/// to the pixel it sits at as well ([dshSnapToPixel]).
class DshChromeBaseline extends SingleChildRenderObjectWidget {
  const DshChromeBaseline({super.key, required this.style, super.child});

  final TextStyle style;

  @override
  RenderObject createRenderObject(BuildContext context) {
    final dpr = dshDevicePixelRatioOf(context);
    return _RenderChromeBaseline(dshBaselineNudge(style, dpr), dpr);
  }

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    final dpr = dshDevicePixelRatioOf(context);
    (renderObject as _RenderChromeBaseline)
      ..devicePixelRatio = dpr
      ..nudge = dshBaselineNudge(style, dpr);
  }
}

class _RenderChromeBaseline extends RenderProxyBox {
  _RenderChromeBaseline(this._nudge, this._devicePixelRatio);

  double _nudge;
  double _devicePixelRatio;

  set nudge(double value) {
    if (value == _nudge) return;
    _nudge = value;
    markNeedsPaint();
  }

  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final top = localToGlobal(Offset.zero).dy;
    final snap = dshSnapToPixel(top, _devicePixelRatio) - top;
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
