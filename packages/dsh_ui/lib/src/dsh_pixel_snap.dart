import 'package:flutter/widgets.dart';

/// How the web client snaps lengths to the display, which is what the product
/// has to reproduce: dsh draws on a phone through Chromium, so the reference
/// is Chromium running at the phone's density.
///
/// Blink (zoom-for-device-scale-factor, `--force-device-scale-factor=N` or any
/// real phone) multiplies every CSS length by the device scale factor `N`
/// before layout, so layout units are device pixels and every rounding rule
/// below works on device pixels. That is [native], the default, and the only
/// mode of the shipped app.
///
/// [emulated] is the older measuring setup (Playwright's `deviceScaleFactor`
/// emulation): Blink lays out in CSS pixels at density 1 and scales the
/// finished page, so every rule works on CSS pixels. It exists for
/// `tool/parity --reference emulated`, which compares against that capture
/// (`docs/parity.md`, "What Blink does at a native density"). Parity tooling
/// sets it; nothing else may.
enum DshPixelModel { native, emulated }

/// The pixel model in force. [DshPixelModel.native] unless the parity tooling
/// runs against an emulated-density reference.
DshPixelModel dshPixelModel = DshPixelModel.native;

/// The device pixel ratio the snapping rules work with: the view's in the
/// native model, 1 (CSS pixels are the layout unit) in the emulated one.
double dshSnapDensity(double devicePixelRatio) =>
    dshPixelModel == DshPixelModel.native ? devicePixelRatio : 1;

/// The device pixel ratio of the view [context] is in (1 without a view).
double dshDevicePixelRatioOf(BuildContext context) =>
    MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;

/// A CSS border width as Blink lays it out at [devicePixelRatio], in logical
/// pixels.
///
/// The width is multiplied by the device scale factor and snapped to whole
/// device pixels (`StyleBuilderConverter::ConvertBorderWidth` and
/// `ComputedStyleBuilder::SetBorder*Width`): a width between 0 and one device
/// pixel is one device pixel, anything larger is floored. So `0.5px` is one
/// device pixel at every density (0.5 logical at 2x, 0.38 at 2.625x, 0.33 at
/// 3x), and `1px` is `floor(density)` device pixels (2 of 2.625). Measured on
/// Chromium 145: `tool/parity-ext/probes/hairline-width.mjs`.
///
/// In the emulated model the same rule runs on CSS pixels, where `0.5px`
/// becomes a full pixel.
double dshSnapBorderWidth(double cssWidth, double devicePixelRatio) {
  if (cssWidth <= 0) return 0;
  final density = dshSnapDensity(devicePixelRatio);
  final device = cssWidth * density;
  // Layout units are 1/64 px: absorb float noise like 0.1 * 30 = 3.0000000000000004.
  final snapped = device < 1 ? 1.0 : (device + 1e-6).floorToDouble();
  return snapped / density;
}

/// dsh's `0.5px` hairline (card borders, dividers) at [context]'s density.
double dshHairlineOf(BuildContext context) => dshBorderWidthOf(context, 0.5);

/// A CSS border of [cssWidth] at [context]'s density ([dshSnapBorderWidth]).
double dshBorderWidthOf(BuildContext context, double cssWidth) =>
    dshSnapBorderWidth(cssWidth, dshDevicePixelRatioOf(context));

/// [logical] (one coordinate of the display's origin) rounded to a whole
/// device pixel, halves up: `SnapSizeToPixel` / `PixelSnappedIntRect`, which
/// Blink paints every box edge with.
double dshSnapToPixel(double logical, double devicePixelRatio) {
  final density = dshSnapDensity(devicePixelRatio);
  return (logical * density + 0.5).floorToDouble() / density;
}

/// [rect] (in the display's coordinates) with every edge snapped to a whole
/// device pixel; the width and height are the difference of the snapped
/// edges, not the rounded sizes, so neighbours that touch keep touching.
Rect dshSnapRect(Rect rect, double devicePixelRatio) => Rect.fromLTRB(
  dshSnapToPixel(rect.left, devicePixelRatio),
  dshSnapToPixel(rect.top, devicePixelRatio),
  dshSnapToPixel(rect.right, devicePixelRatio),
  dshSnapToPixel(rect.bottom, devicePixelRatio),
);

/// Layout units: Blink holds lengths as multiples of 1/64 px.
double dshLayoutUnit(double v) => (v * 64).roundToDouble() / 64;

/// Blink's `FontHeight::AddLeading` for a fixed line height, in layout pixels:
/// the ascent and descent round to whole pixels, and `floor` of half the
/// leading goes above the text. Returns the baseline's distance from the top
/// of the line box.
double dshBlinkBaseline({
  required double ascent,
  required double descent,
  required double lineHeight,
}) {
  final a = (ascent + 0.5).floorToDouble();
  final d = (descent + 0.5).floorToDouble();
  return a + ((dshLayoutUnit(lineHeight) - a - d) / 2).floorToDouble();
}
