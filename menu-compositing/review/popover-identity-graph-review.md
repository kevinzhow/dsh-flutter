# Identity backdrop graph review

The identity→direct mirror blur→saturation graph has a concrete source basis:
it creates the finite card image that was missing before the blur. The current
single outer ClipPath is also structurally appropriate. The original prototype's
three default srcOver restores are not equivalent to a single backdrop filter
on transparent input. Replacing only the internal blur/saturation restores
with src is the appropriate direction; retain srcOver for the outer identity
restore. Corner/fractional-edge and native equivalence still require evidence,
so this remains research rather than final native acceptance.

This review is read-only. I inspected retained captures, product diffs, the
experimental test source and pinned renderer sources; I did not change the
product, SDK, tests, builds or captures, and did not rerun tests/native scenes.

## Reviewed evidence

Base is80a1b160d15b7287789604cef69bc38a6a1fa1ad. The retained three-filter
default-srcOver prototype patch at
`build/parity-popover-identity-probe/prototype.patch` has SHA256
`6e884c4a345ed228103d641991708c1ba64686ba5f63f39b85bf7780b0bbc53d`.
All three retained source/baseline/trial cards are300x159. I inspected the
generic light and macOS dark source/baseline/trial images.

Independent receipt readback confirms the three non-text changes:
generic light21.017→56.690, macOS light69.616→93.407,
macOS dark45.497→49.597. Full48 readback confirms48 equal dimensions,
32 improvements,16 regressions, mean31.7375625→46.0059375. These measurements
show the graph changes pixels; they do not establish universal equivalence or
justify adjusting material values to optimize a score.

## Impeller source trace

Installed Flutter remains3.47.6, framework5fc346839b5d0eef006ed8404392afb4dfae428d.
The additional installed Impeller files were compared byte-for-byte with that
immutable upstream commit; all matched:

| File | SHA256 |
| --- | --- |
| impeller/display_list/canvas.cc |695f583433eebd5afd0bab136fe71cbe740d3db9a4535a61fdddd425a9fae596|
| impeller/display_list/image_filter.cc |a56cfc104d08c9ba434821d95308013c8309baa2fd486642ca966df7c5947f55|
| impeller/entity/entity_pass_clip_stack.cc |298ddad23a9fae5bb18e1d562fb7a370b4d043daf49664f11af5cfe133d4dd06|

[Canvas::SaveLayer](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/impeller/display_list/canvas.cc#L1710)
computes coverage from the current clip. A backdrop floods its input coverage
before that clip limit is applied. It flips the **current** pass to obtain the
backdrop texture, then creates the new subpass and renders the filter into it
(lines1740-1750,1796-1856,1900-1937). Thus the blur reads the initialized
identity card texture, and saturation reads the blurred card texture. It does
not reread the original viewport at every stage. Default independent backdrop
keys are required for this sequence; grouped/shared keys are a different graph.

`image_filter.cc:26-37` forwards the blur's mirror mode to its Gaussian filter.
`gaussian_blur_filter_contents.cc:40-57` selects mirror texture addressing.
Its actual downsample/blur implementation differs from Skia's; source graph
agreement does not imply identical rounding or kernels across renderers.

Subpass allocations without a paint image filter round their physical bounds
out and adjust the origin; restore aligns the texture to a floor/round position
(`canvas.cc:1758-1780,1990-2014`). Consequently fractional placement and the
phone2.625 density remain material checks for the finite image boundary.

## Rounded clipping and src replacement

The actual prototype keeps one common rounded ClipPath outside all stages,
with the existing shadow outside it. This avoids filtering the foreground or
adding a fresh rounded clip around each intermediate stage.

Impeller
[PushSubpass](https://github.com/flutter/flutter/blob/5fc346839b5d0eef006ed8404392afb4dfae428d/engine/src/flutter/impeller/entity/entity_pass_clip_stack.cc#L32)
starts a new clip state containing only the subpass's rectangular coverage.
The parent's rounded clip geometry remains on the parent render target.
Final restore renders the outer card back into that clipped target. The source
therefore does not predict automatic triple multiplication of the same rounded
AA mask for the existing single-clip hierarchy.

Internal src is suitable when replacing the full intermediate card image:
the new filtered result replaces its unsaturated/unblurred intermediate,
including transparent pixels, rather than compositing another copy over it.
Impeller carries the saveLayer paint's blend mode to restore and deliberately
floods coverage for destructive src; the shared outer card clip limits that
coverage. Keeping srcOver on the outer identity layer preserves the final
composition with the original backdrop. Applying src to that outer restore
would be a different material operation.

This reasoning does not prove pixel equality at partial AA coverage. Moving
rounded clips into the internal stages, introducing another parent saveLayer,
or differing integer expansion at a fractional edge can alter edge coverage.
These cases need actual edge RGBA comparison, without masking the corners out
of acceptance or changing the source radius/material values.

## Transparency regression must isolate the operation

For uniform neutral backdrop alpha a and transparent fill, blur and saturation
leave color/alpha unchanged when sampled from the correct finite domain.
One backdrop layer restored over the original has alpha1−(1−a)^2. Three
default-srcOver backdrop restores produce1−(1−a)^4; at a=0.5 these are0.75
and0.9375. Identity→compose with two default restores instead gives0.875.
Internal src replacement reduces the artificial stage copies to the one-layer
result. This is a compositing argument, not a chosen pixel similarity threshold.

I inspected main's two experimental tests in `popover_probe_test.dart`.
The transparent offscreen RGBA setup and one bounded identity-layer reference
are appropriate. Main reports reference alpha192, prototype192 and baseline168.
The baseline168 must be described accurately: its unbounded blur imports the
transparent exterior of the120x80 input patch. That comparison demonstrates
input-domain correction, not a uniform-global-alpha counterexample to srcOver.

Before accepting the transparency fix, keep the same bounded graph and switch
only its internal restores back to srcOver as a negative control. That separates
extra compositing from the different input domain. Compare full RGBA to the
bounded one-layer reference; check more than the center. The current reference
uses ClipRect while production uses a rounded ClipPath, so the center assertion
does not establish rounded-edge equivalence. A companion reference using the
same generated shape is needed for that claim.

## Identity→compose remains a backend distinction

A finite identity card is useful, but composition still leaves the Skia
saveLayer's source tile mode at clamp. Pinned Skia
[FilterResult crop handling](https://github.com/google/skia/blob/8df24be66531469e576a806749a0202ae26b8d08/src/core/SkImageFilterTypes.cpp)
expands non-decal layer bounds to the requested input region. The blur's
legacy mirror then takes those expanded child bounds, not necessarily the
original card rectangle. A later mirror flag therefore does not establish
mirror-at-card after the saveLayer source was already prepared with clamp.
This is a source-derived prediction, not a new runtime observation by me.

Impeller's compose conversion directly wraps inner then outer filters and
does not execute SkCanvas's prior-source clamp step. The composed variant can
therefore differ across these backends even with the same Dart filter object.
Use an asymmetric colored ramp inside the card and distinct exterior colors
to discriminate mirror from clamp at its input edge. Uniform-color domain
invariance alone cannot distinguish those two tile modes.

## Evidence required before final acceptance

1. Preserve the source-generated sigma40, saturation1.5, fill, stroke, radius
   and shadow. Keep actual-source reference captures and full dimension/metric
   results, including generic dark regressions; do not select a graph by mean
   score alone.
2. Complete the bounded-domain negative control and transparent one-layer RGBA
   equivalence with the same rounded shape. Check center, all corner edges and
   unchanged exterior, including fractional origins and1/2.625 densities.
3. Check the asymmetric edge-ramp behavior against the real Chromium reference
   to distinguish mirrored input from clamped input.
4. Bind a fresh actual Impeller native build to its runtime hashes, and inspect
   clipped corners, sharp foreground, switching/dismissal and textured backdrop
   on desktop/phone. A prior build's successful replay does not cover this graph.

Main's decision to retain this as research in the current batch is consistent
with the remaining corner/alpha/backend evidence requirements.

Follow-up from main after this audit handoff: the same bounded three-layer
srcOver negative control passed the domain test but failed the alpha assertion
(expected192, actual240). Main's src version passed. This isolates the extra
compositing from the baseline's different sampling domain, as requested above.
The rounded-edge/native requirements remain open; I did not rerun these tests.
