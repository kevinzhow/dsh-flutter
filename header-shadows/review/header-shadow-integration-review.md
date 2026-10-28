# Header and source-shadow integration review

Reviewed read-only on 2026-10-28, against baseline
`875ef6936bc5337afcc3a187b2de80ad22963ccb` in
`scratch/whalee-source-shadows`. HEAD was Header cherry-pick
`81459925c8cce4c595b216b02d3e468a719ffcdf`, tree
`b37159348422790325868709b92d3c2369149069`.

The reviewed unstaged files were `dsh_shadow_box.dart`, `published.py`, and
`source-inventory.generated.json`; `css_shadow_source_test.dart` was untracked.
No product, test, generated, build or native files were changed by this review.

## Finding requiring resolution before fractional-edge acceptance

**The derived reach can become an additional antialiased clip on a visible
shadow edge.** At the reviewed `dsh_shadow_box.dart:63–79`, the clip rectangle
is the exact union of shifted/spread shadow bounds plus `3*sigma`. When blur
is zero, a far shadow's visible edge can coincide exactly with that clip edge.
`canvas.clipPath(outside)` has `doAntiAlias:true` by default, and the shadow
paint is independently antialiased. At fractional device coordinates this
introduces a second coverage mask on the same visible edge; it can attenuate
the painted edge relative to an exterior-only source clip.

Concrete regression to resolve this: the existing 40×40, radius12 fixture at
left450/top90, opaque red shadow, offset `(350.25, 0)`, blur0, DPR1. The right
shadow edge is at device840.25; sample the far-right straight-edge pixel near
`(840,110)` against a control with the identical draw and card-interior
exclusion but no finite reach edge there. Mirror the negative offset, and
include a nonempty negative spread such as `-0.25`. Compare the actual edge
alpha rather than only the fully covered center pixel. DPR2.625 or a
fractionally translated canvas should also exercise device rounding.

This is a source/API-derived concern, **not an independently measured failing
pixel receipt**: the review does not execute new Flutter tests or edit the
test driver. Root was notified immediately with the reproducer. The current
integer ±350 tests sample the fully covered center and cannot resolve it.
Root accepted this as a real blocker and owns a new standalone-draw reference
regression for ±350.25 at DPR1 and2.625 plus the clip correction. The earlier
three smoke captures are retained as pre-correction diagnostics only.

A bounded correction is to use the actual finite canvas clip bounds for the
exterior rectangle, then subtract the card outline. Another acceptable approach
would prove a device enclosure from the renderer's rounding rules that does
not coincide with a visible shadow edge. Do not add an empirical padding or
disable antialiasing on the interior boundary to make the test pass.

The pinned Flutter API explicitly states:

- `Paint.isAntiAlias` defaults to true (`painting.dart:1381–1393`).
- `Canvas.clipPath` defaults to `doAntiAlias:true` (`painting.dart:7112–7117`,
  native forwarding at7862–7868).
- `Canvas.getLocalClipBounds` returns conservative bounds rounded to integer
  pixel boundaries before conversion back to local space, accounting for
  antialiasing (`painting.dart:7119–7133`,7171).

The source Blink normal-box-shadow path subtracts the card/border geometry
from the existing context clip (`box_painter_base.cc:302–315`) and then draws
the shadow. It does not add an authored outer reach rectangle at the shadow
edge.

The pinned engine implementation was also inspected rather than relying only
on API prose: `lib/ui/painting/canvas.cc:209–217` forwards to
`DisplayListBuilder::GetLocalClipCoverage` (`dl_builder.h:145–147`), which uses
`DisplayListMatrixClipState::GetLocalCullCoverage`
(`utils/dl_matrix_clip_tracker.cc:235–252`). A singular transform returns an
empty rectangle; perspective returns the finite engine `kMaxCullRect`
(`dl_builder.h:32–33`, ±1e9); ordinary transforms inverse-map the existing cull.
No production nonfinite result has been established to justify a3σ fallback.

One additional boundary test was requested of root: preserve an existing
fractional `clipRect(..., doAntiAlias:false)` without softening it with the
new antialiased envelope. The engine's own
`display_list_unittests.cc:1982–2013` preserves fractional hard-clip cull
bounds rather than rounding them. This is a requested regression, not a second
measured failing receipt. `canvas.cc` SHA256 is
`06d68cba33733cfa795fed5607d904851f080f84bf2640c15dc06e77330d3c67`;
`dl_matrix_clip_tracker.cc` SHA256 is
`8683b4a5ac8ada077cc7fe8fded0fe9a9abeef098c5039d449ba3e7f34d1d005`.

## Header integration and shared-focus preservation

The integrated Header product files, focused tests and recipe builder are
byte-identical to bounded commit
`93fd6586fb7d771ff45b7722e1d729454894d7ed`. The full comparison against that
commit for these paths is empty. No new Header integration blocker was found.

For every pre-existing button profile, `header` is false. The new branches in
radius, fill, foreground, dimensions, stroke, cursor, disabled opacity and
pointer focus reduce to their previous expressions. The default focus paint
predicate still uses `_focusVisible`; only Header uses shared focus-visible
history plus `pointerOwnsOutline`. Header-only pointer focus is inside the
existing onTapDown callback; callbacks for the other profiles remain unchanged.

The shared tracker adds pointer-outline ownership and a key focus origin. It
does not change the previous `_keyboard`, per-node visible or explicit
suppression update rules. `_setPointerOwnsOutline` snapshots the state values
before notification, and each state's notifier snapshots its listeners.
The current subscribers are canonical buttons; their callback checks
`mounted` and schedules `setState`, without changing focus or invoking user
actions. The extra notifications do not introduce a synchronous focus transfer
or a default-profile paint-state rewrite.

During focus transfer the existing per-node visible state is updated before
new outline-ownership notifications are emitted. Native-equivalent Header
pointer focus occurs after the global pointer route has established pointer
ownership. Navigation then releases ownership; Enter without transfer retains
it. Non-navigation key followed by focus moving to a different registered
control releases ownership. These cases have the original source receipts and
targeted RED/GREEN tests; root owns the integration rerun.

The disclosed boundaries remain: window blur/composition originating in a
separate editor are not certified; Web aria-keyshortcuts has no equivalent
mapping added; actual AppFrame/platform mounting is outside this Header lock.
Native Chromium outline:auto paint/geometry remains visibly different from
the existing canonical theme stroke, particularly in dark mode. No UA colors,
outline offsets or score-derived geometry were added in this integration.

The root's `published.py` integration correction is necessary and correct:
`verified_outputs` now includes `*result['behavior']` in addition to sidebar
CSS/classes/metadata. `sidebar_component_snapshot` always returns the behavior
map (empty for packages without Header), so both Header behavior verification
and decoder output coverage remain closed. The source inventory adds the two
new retained JSON inputs and updates only the corresponding snapshot lock
hash; it does not claim implementation coverage from input retention.

## Shadow source trace and preserved behavior

The CSS conversion is correct: `_cssShadowSigma(blur) = blur/2`, with no mask
filter for blur0. This follows pinned Blink
`ShadowData::BlurRadiusToStdDev`/`BlurAsSigma`, not Flutter's legacy
radius-to-sigma conversion. No alpha/theme branches or fitted values remain
in the changed conversion.

The first-listed CSS shadow still paints last/on top. Generated offset,
spread and color inputs are preserved. Interior exclusion still subtracts
the original card outline before drawing any shadow, preserving translucent
card interiors. Negative spread that empties the rectangle is now skipped in
both reach calculation and painting, matching Blink's empty fill-rect check.
For nonempty spreads, rounded and corner-shape paths remain the pre-existing
implementation; this review does not certify all CSS corner-contour cases.

The `3*sigma` arithmetic is an actual Skia local fast-bounds formula. That is
a valid source algorithm, **not** a proof that putting an antialiased clip
at those exact continuous bounds is equivalent to the source context clip.
Actual masks use device transforms and integer rounding. General skew,
perspective and nonuniform transforms are not proven by these eight tests.
The visible-edge concern above must be separated from the correct sigma
conversion and should not be addressed by refitting sigma.

Immutable renderer files were fetched again and their bytes independently
matched the previous audit hashes:

| Source | SHA256 |
| --- | --- |
| Chromium `47e20ad.../third_party/blink/renderer/core/paint/box_painter_base.cc` | `bb6718a8cb3885693a35ec51b14cae7c44ab1f26d518e27fab4ca077d3bd9995` |
| Skia `2ab8add.../src/core/SkBlurMaskFilterImpl.cpp` | `fa016f565411ed91798f87ab756124f43df241e96b055fa254b5b2c91786f2da` |
| Skia `2ab8add.../src/core/SkBlurMask.cpp` | `eb47eaff9958c5cd44f897d6c80d939bc2e1a6caa2b49f5cb4703e6e4d90866e` |
| Skia `2ab8add.../src/core/SkMaskBlurFilter.cpp` | `ef329043114ce60c5e4a302f4ca6d611b6a42b83c90543f6b4ebd03fe324c1a9` |

`SkBlurMaskFilterImpl.cpp:111–121` transforms sigma through the CTM and caps
device sigma;569–578 defines the local fast bounds as3×sigma. Its rectangle
and rounded-rectangle mask paths use integer bounds/rounding (133–136,
318–322). `SkBlurMask.cpp:405–424` uses integer analytic-rectangle mask bounds;
`SkMaskBlurFilter.cpp:27–77` derives integer multi-pass kernel borders. These
are renderer mechanisms to preserve when studying fractional clips.

## Reviewed input fingerprints

| File | SHA256 |
| --- | --- |
| `packages/dsh_ui/lib/src/dsh_shadow_box.dart` | `cf6166a47a2462905e3b689584769afc249794246ea2aba12fbd19bfca6ea90b` |
| `packages/dsh_ui/test/css_shadow_source_test.dart` | `4b9d787580ecf2f38435f4c023572e803ca6856e79e3d5cd4f4de4ef617afdd0` |
| `packages/dsh_ui/lib/src/dsh_focus_presentation.dart` | `ebe1f68ec7dfe4f8ec8758b568b423eb41a099462c51c607e4cae266c1858a37` |
| `packages/dsh_ui/lib/src/dsh_button.dart` | `5f3f11b310341f2f4a20d7539a07f07f6c857270f128c2513a5c108c7fde7382` |
| `tool/design-system/published.py` | `5bb26ed6a23ee85c93d43941f5e5917fe93a6c229f72889e5932b94b139a3213` |
| `tool/design-system/source-inventory.generated.json` | `e82a452dddcdec4851047d51ff2e13d6858e8f82f48ddd6154c169c0a8e99697` |

Root's reported 200-tool-test and shadow-test results are not independently
rerun here; this is a read-only implementation/source review. Root owns the
fractional-edge regression, actual source captures, full checks, builds and
native validation.

## Follow-up contract for a per-shadow layer correction

Root proposes preserving the existing parent clip and replacing the finite
exterior rectangle with one layer per shadow, followed by an opaque
`BlendMode.dstOut` card mask, then restoring the layer. The implementation and
new raster results were not yet present at the last review snapshot above.

For card-edge coverage `m`, each shadow must contribute its premultiplied
color/alpha multiplied by `(1-m)` before that shadow is composited onto the
parent. A per-shadow layer plus dstOut mask can implement that operation. A
single combined layer containing all shadows followed by one mask generally
does not preserve CSS per-shadow compositing at partially covered pixels.
The original reversed layer order must remain.

Use the current ancestor clip, without deriving a new finite antialiased outer
envelope. Flutter's saveLayer/clip documentation
(`painting.dart:6909–6965`) explains that an existing clip is applied to a
group at restoration, avoiding repeated edge blending for the group's child
draws. The fractional hard-ancestor-clip control is still required to verify
the actual engine path. A new layer bound must not reintroduce the same
visible-edge crop through another rectangle.

An additional source boundary was reported to root: Blink's
`ClipToBorderEdge` (`box_painter_base.cc:169–191`) insets the excluded shape by
one CSS pixel for an authored opaque background, to avoid subpixel gaps.
The current canonical outer-only implementation does not model that branch.
Do not derive source opacity from a Flutter material already preblended to
opaque: MenuSurface's authored CSS fill is translucent even though its bounded
Flutter material becomes opaque. This is pre-existing source-coverage debt,
not permission to add an empirical inset to this batch.

Root clarified the accepted scope: remove fitted sigma and arbitrary reach
while preserving per-shadow exterior exclusion for the translucent source
panels. It is not a claim of universal CSS box-shadow equivalence. The source
shadow owner must be distinguished from a material child before introducing
any future opacity API. In the actual upstream `MenuSurface.tsx`, the outer
`.surface` contains a separate aria-hidden `.material` child. The outer owns
the Menu `.list/.submenu` box-shadow; the material child owns its background
and backdrop filter. `MenuSurface.module.css` does not set an opaque outer
background. Thus the preblended Flutter menu material is not evidence that
Blink's authored shadow owner satisfies the opaque-background branch.

Inspected raw `MenuSurface.tsx` SHA256:
`1e9b1f476305d4076b23b42fd08b63f9429b8e1f646c06ebc39d8ded5de7fdbf`;
its stylesheet SHA256 is the retained lock's
`6230cfabdb5294b5cf174bc79842a9596f6aee6cd76a8cd5e183c67279bca9ae`.
The TSX file is checked in the pinned source checkout but is not newly added
as a locked recipe input by this review.

Rounded-card antialiasing was traced to the actual context implementation:
`graphics_context.cc:927–928` calls
`ClipContouredRect(rect, SkClipOp::kDifference)`; the declaration defaults its
antialiasing argument to `kAntiAliased` (`graphics_context.h:372–374`). The
implementation forwards that mode to rounded-rect or superellipse-path clips
(`graphics_context.cc:909–924`). This supports an antialiased inverse-card
mask for the rounded translucent panels. The no-border-radius branch of
`ClipToBorderEdge` uses hard `ClipOut` instead (`graphics_context.h:375–379`),
another reason not to claim universal square-card equivalence here.
Pinned `graphics_context.cc` SHA256:
`9593e9d4cee4332d0b6e70280960448b0c7f8a18f6ef7d0b686a6ccd29493da9`.

### Revised code inspected; runtime results pending

The revised `dsh_shadow_box.dart` SHA256 is
`8c6a5df1a8450b7171f8790d178138608d25670700548bbe0ecdda3340a6bcb8`.
At this snapshot it uses `saveLayer(null, Paint())` independently for each
nonempty shadow, draws the source-sigma shadow, removes the original card
path with opaque `BlendMode.dstOut`, and restores before the next shadow.
It contains no outer rectangle or fallback reach. No code-level blocker was
found for the accepted rounded translucent-panel scope. Sigma, input values,
reverse layer order and empty-spread skipping remain as reviewed above.

The new independent far-shadow tests compare ±350.25 at DPR1 and2.625 and
include a fractional hard-ancestor clip. Their crop excludes the card itself,
so the control legitimately omits interior exclusion and card fill. These
tests can detect the original finite-reach edge attenuation without copying
the production clipping implementation. At the time of this code snapshot,
test result logs and actual source comparisons were still pending; this is
not a runtime acceptance claim.

## Root validation and native Header fixture handoff

Root-owned `.local/source-shadows-per-layer-green.log` in the source-shadow worktree was inspected: all 27 focused shadow/menu tests passed. This is an observed root log, not an independent test rerun by this reviewer.

A later explicitly authorized native-fixture task produced clean commit `2293a830c1edecc18d5e488e67493fd2e90f2d10`, tree `25db72d02c40e38e459c6daf4e11265ffbb7488e`. It adds a fixture-only F6 Header scene around actual SidebarLeadingControls, leaves the original three toolbar controls and 84-assertion menu manifest unchanged, and has two focused callback/focus/geometry tests plus clean focused analysis. The new Header GPU manifest has 4 cases, 72 assertions and 36 named plus 4 final captures. Android preparation retains the old 15-scene/41-check/22-input method with an identical AST and extends it to 24 scenes, 54 checks and 30 inputs with 3 geometry proofs. No APK build, emulator startup or GPU run was performed in that task.
