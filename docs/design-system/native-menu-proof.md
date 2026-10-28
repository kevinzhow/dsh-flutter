# Native model-root clearance proof

The native menu replay retains 84 assertions and the same inputs, captures,
references and changed/unchanged expectations. Two rectangle coordinates
change because the original compact-root guard intersected a legitimate
source shadow after correcting CSS blur-radius conversion. This is a test
geometry correction, not a rendering tolerance or appearance adjustment.

The original guard's intent is to catch a wrongly retained two-row root after
selecting Pro. The synthetic Pro model has no reasoning configuration. Actual
`ModelSelect.tsx` renders its Model row unconditionally and its Effort row only
when `reasoning !== undefined`; therefore Pro's root must have one row. The
existing replay preparation note records this same one-row-versus-two-row
intent. The separate guards for root content, selection result, directory
closure, Escape and viewport masking remain unchanged.

## Derivation from the pinned design system

Reference: DSH `687f282e8625c6b8d11ff58211a90524be2e4317`, published packages
0.2.1-rc.2. The locked `ModelSelect.module.css` and generated
`DshModelMenuRecipe` specify cell height 34, menu padding 4 on both vertical
edges and anchor gap 8. The native fixture places its trigger 24 above the
viewport bottom, with trigger height 28. These determine:

- One-row outer height: `34 + 2×4 = 42`.
- Two-row outer height: `2×34 + 2×4 = 76`.
- Menu bottom: `viewportHeight − 24 − 28 − 8`.

The published `--dsw-elevation-prominent` layers have vertical
offset/blur/spread `(0,0,0.5)`, `(3,8,0)` and `(0,20,0)` in both themes.
Pinned Blink converts CSS blur radius to sigma with `radius/2`; pinned Skia's
local blur fast bounds extend by `3×sigma`. The largest upward extent is
therefore `max(0.5, 3×(8/2)−3, 3×(20/2)) = 30`.

For a one-row menu whose top is `T`, the entire interval `[T−34,T−30)` is
outside its correct shadow but inside the top of a wrongly retained two-row
card. The interval exists because the extra source row34 exceeds the maximum
shadow reach30. It is selected by those source values; its edges are not
chosen from the first changed screenshot pixel. The existing horizontal
interval remains unchanged.

| Case | One-row top | Two-row top | Correct shadow starts | Replacement rectangle |
| --- | ---: | ---: | ---: | --- |
| Desktop1280×720 | 618 | 584 | 588 | `[1028,584,1248,588]` |
| Phone390×844 | 742 | 708 | 712 | `[138,708,358,712]` |

The older desktop band `[1028,594,1248,606]` and its phone translation lie
inside the correct source shadow envelope. Pixel equality there can no
longer distinguish a valid shadow from an incorrect extra root row.

Source inputs are retained in:

- `tool/design-system/upstream/ui-model-selection/ModelSelect.module.css` and
  `model-behavior.json`, with generated row/padding/gap fields in
  `tool/design-system/recipes.generated.json`.
- `packages/dsh_theme/assets/themes/official.theme.json`, both modes'
  `--dsw-elevation-prominent` values.
- The actual `ModelSelect.tsx` root branch at lines507–527 and the native
  synthetic model fixture in
  `features/dsh_feature_model_selection/lib/testing.dart`.
- Pinned [Blink CSS sigma conversion](https://chromium.googlesource.com/chromium/src/+/47e20adcc15fc15f01825aa17e570c8f5492ac0f/third_party/blink/renderer/core/style/shadow_data.h)
  and [Skia local fast bounds](https://chromium.googlesource.com/skia/+/2ab8add5be2c46eb6238f4c217f6d6dbc9bccd23/src/core/SkBlurMaskFilterImpl.cpp).

## Positive and negative controls

Read-only Chromium145.0.7632.6 observation of the actual upstream component,
using its existing synthetic data and callbacks, confirmed:

| Viewport/theme | Two-row DOM bounds | Pro DOM bounds | Correct Pro band changes | Actual two-row control band changes |
| --- | --- | --- | ---: | ---: |
| Desktop/light | `(1008,584,248,76)` | `(1008,618,248,42)` | 0 pixels | 880 pixels, max channel8 |
| Phone/dark | `(118,708,248,76)` | `(118,742,248,42)` | 0 pixels | 880 pixels, max channel23 |

Both source DOMs reported padding4 and one remaining Model row of height34
after Pro selection. The observed shadows retained their authored blur8 and20
layers. The positive control is the real initial two-row Flash root, not a
hand-drawn approximation of an invalid menu. Thus the replacement still
rejects the specific extra-row regression the original guard was designed
to detect.

The retained failed native desktop captures at
`build/native-header-shadows-menu-gpu/reported-families.desktop/` independently
show the old band changing220 pixels by one channel level from the legitimate
shadow. The source-derived replacement band changes0 pixels for correct Pro
and880 pixels for the actual two-row control, matching the source result.
Those failed captures and their runtime receipt remain intact.

All comparisons above use exact pixel equality, with no threshold, scorer,
font, alpha, color, blur or product geometry change. The new rectangle does
not certify visual similarity or all possible model-menu errors. Native
execution against the final compiled runtime remains required. The separate
Header manifest remains unchanged at 72 assertions; every Header rectangle
was checked against its own viewport, including phone callback edges at 390.

## Retained source control artifacts

`build/native-menu-proof/` contains the reproducible
`capture-source.mjs`, its execution log and
`native-control-comparison.json` for the retained failed native desktop run.
`source-controls/geometry.json` records Chromium version, actual source
file hashes, locked-input matches, host bundle hashes, pinned font hashes,
source DOM bounds, authored/computed shadows and both exact comparisons.
The same directory retains eight actual source PNGs: closed, two-row root,
Pro selected and Pro root for desktop/light and phone/dark.

The script imports the existing actual-source parity host rather than
recreating menu CSS or controls. It derives the vertical band from the
generated row height and authored shadow values, checks the DOM geometry,
and fails if no source clearance interval exists. Reproduction requires
the pinned environment and explicit `--repo`, `--host-dist` and fresh `--out`
arguments. The source checkout commit and locked source hashes are checked
before capture; all PNGs and failure receipts are preserved.
