# Source shadow conversion and exterior coverage

`DshShadowBox` consumes the generated theme's CSS shadow offsets, blur radii,
spreads and colors. It converts the authored blur radius to sigma with
`radius / 2`. The former `max(0.5, 0.45 * radius - 2.1)` was a screenshot fit
and has been removed, together with the fixed 200px exterior clipping bound.

The conversion follows Chromium 145.0.7632.6, commit
`47e20adcc15fc15f01825aa17e570c8f5492ac0f`:

- Blink `core/style/shadow_data.h`, `ShadowData::BlurRadiusToStdDev` and
  `BlurAsSigma`, defines the conversion. SHA256:
  `8a4f620e196502c3f9cd1188bebe92e42092ac9dbce3bb7e93ce639dfd07f563`.
- `core/paint/box_painter_base.cc` excludes the shadow owner's border shape
  from the existing context clip, skips empty eroded shapes and preserves CSS
  layer order. SHA256:
  `bb6718a8cb3885693a35ec51b14cae7c44ab1f26d518e27fab4ca077d3bd9995`.
- `platform/graphics/graphics_context.cc` forwards rounded difference clips
  with antialiasing. SHA256:
  `9593e9d4cee4332d0b6e70280960448b0c7f8a18f6ef7d0b686a6ccd29493da9`.

Chromium's DEPS pins Skia `2ab8add5be2c46eb6238f4c217f6d6dbc9bccd23`.
Skia's legacy radius converter, also used by Flutter `Shadow`, is a separate
algorithm; it is not the CSS conversion above. These renderer sources explain
the translation, while the actual pinned DSH screens remain the acceptance
reference. They do not replace the published theme inputs with a new style.

## Flutter translation

Dart Canvas has no inverse-path clip API. Each shadow therefore gets its own
unbounded `saveLayer`, followed by an opaque `dstOut` mask of the original
rounded card outline. For card coverage `m`, this contributes
`shadow * (1 - m)` before that shadow composites onto the parent. Masking a
combined stack once would change partially covered pixels, so each layer is
masked and restored independently. The first-listed CSS shadow paints last.
Zero blur has no mask filter; a spread that erodes the rectangle to empty is
skipped.

An intermediate implementation used the union of shadow bounds plus three
sigma as an exterior path. Six raster regressions demonstrated why that was
incorrect: the new antialiased outer boundary attenuated a fractional shadow
edge and softened a fractional hard ancestor clip. The final implementation
adds no exterior rectangle and preserves the parent's clip.

`css_shadow_source_test.dart` checks the source sigma, zero blur, far offsets,
empty negative spread, translucent interiors and layer order. Its independent
standalone draw controls compare the entire far-shadow raster at offsets
±350.25 and DPR1/2.625, including a fractional hard ancestor clip. Those
controls omit the disjoint card, rather than reproducing the production mask.

## Scope and remaining differences

This change removes unsupported fitting and reach limits for the current
rounded translucent panels. It does not certify all CSS box-shadow branches.
Blink insets the excluded shape for an authored opaque background and uses a
hard difference clip for a square border. Those branches are not newly modeled
here. A Flutter menu material preblended to opaque does not establish that the
CSS shadow owner had an opaque authored background: the real MenuSurface has
a separate material child. General transformed and superellipse contours also
need their own source comparisons before claiming equivalence.

Existing screen rasters can intentionally change when the source sigma is
restored. Report those changes against the real source, with the old images
retained as regression history; equality to the former fitted appearance is
not acceptance. Fonts, thresholds, source colors and generated shadow inputs
are unchanged.
