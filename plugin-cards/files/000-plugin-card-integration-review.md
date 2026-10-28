# Loaded PluginCard integration review

Reviewed on k172, 2026-10-29. The initial candidate is
`4de33f2a61893a1f7be8a7d942f695bd1cec6c59`, tree
`57b87b54301096061f0294b6160429255beea9a5`, in
`scratch/whalee-plugin-cards`. Review covers the nine UI/feature integration
paths, their generated Card/List/status recipes, and the complete locked
PluginManager/presentation bodies. It follows
`design-system-replication/SKILL.md` and its failure modes.

The reference is published DSH `0.2.1-rc.2`, pinned source
`687f282e8625c6b8d11ff58211a90524be2e4317`. The actual behavior boundary and
source-only Chromium measurements are retained in
`notes/plugin-card-source-audit.md`. Source locations below are relative to
that checkout; implementation locations are relative to the candidate.

Verdict for the initial candidate: three concrete issues, one affecting the
current input behavior and two affecting accepted source-drift domains. Root
subsequently fixed the margin and status-height issues in `87a339ea`; I checked
the changed expressions. The keyboard-to-mouse focus issue remained open at
the completion of this read-only review.

## 1. Card retains a visible focus ring after pointer modality takes over

Priority P2. In `packages/dsh_ui/lib/src/dsh_button.dart:518`, the new Card
profile still uses generic `_focusVisible`; `:521` applies the shared
`pointerOwnsOutline` suppression only to Header. A keyboard-focused Card that
receives mouse-down on the same title therefore retains its painted ring.

The source rule is explicit. `ui-plugin-manager/src/client/
PluginManagerPage.module.css:342` paints the stretched title pseudo-element
using inherited `--dsw-focus-ring-color`. `ui-theme/src/styles/focus.css:23`
sets that variable to transparent for noneditable focus-visible controls in
pointer modality. The real `ui-primitives/src/input-modality.ts:30` publishes
pointer modality on every pointer-down, even when the native button retains
focus-visible history.

An isolated three-test probe at
`scratch/plugin-card-integration-review-probe/card_review_test.dart` imports
the candidate's real canonical widgets. It Tabs to the Card, verifies its
ring, then holds mouse-down on the same title for 200ms. The shared tracker is
active and reports `pointerOwnsOutline=true`, yet the ring remains with alpha
`1.0` and width `2.0`. The source-derived no-ring expectation fails. The
stronger retained log is `probe-confirmed.log`; `probe-final.log` is the first
successful compilation/reproduction. Earlier `probe.log` and
`probe-with-graph.log` are setup failures, not acceptance evidence.

The bounded fix is to opt `pluginCard` into the existing source focus
presentation and pointer-outline suppression path. Keep unrelated Button
profiles unchanged, retain the generated ring geometry/colors, and verify
that subsequent keyboard navigation restores the ring. This requires no
page styling, fixture removal, metric change or new modality mechanism.

## 2. Accepted margin values can generate invalid Flutter padding

Priority P2; root fixed in `87a339ea`.

At the initial candidate, `tool/design-system/plugin_card_recipes.py:103`
accepted any finite horizontal margin. `DshPluginCardInset` at
`packages/dsh_ui/lib/src/dsh_plugin_card.dart:63` constructs padding equal to
the negative margin, while `DshPluginCardCanvas.bleedPadding` at `:26` adds the
margin to the original page inset. Flutter's RenderPadding requires
nonnegative padding.

Full generator reproductions, using in-memory rules only, established both
boundaries:

| Source mutation | Generated value | Runtime consequence |
| --- | ---: | --- |
| `.card { margin:0 8px }` | `horizontalMargin=8` | ordinary-content padding−8 |
| `.card { margin:0 -25px }` | `horizontalMargin=-25` | phone page inset24−25=−1 |

The frozen source `.page` padding is
`0 clamp(24px,4vw,48px) 48px`. Its minimum horizontal inset therefore gives
the supported native canvas range `[-24,0]`. The fix derives that bound from
the existing frozen source rule, accepts both endpoints, and rejects values
outside it. It does not introduce handwritten24px styling or expand the
page-layout migration. The root helper now parses the clamp and validates
this range at `plugin_card_recipes.py:126`. Source snapshot freezing remains
responsible for all other page syntax/behavior.

## 3. Status content-box height omitted translated vertical padding

Priority P2; root fixed in `87a339ea`.

The helper explicitly supports vertical `.statusTag` padding. The initial
`packages/dsh_ui/lib/src/dsh_tag.dart:106` set outer height to
`contentHeight + border`, then placed vertical padding inside that height.
For the valid source change `padding:1px 8px`, CSS content-box height requires
two more pixels outside the content; the native expression stayed 2px short.
Current source padding 0 concealed the issue.

The root expression now adds `2 * verticalPadding` before border dimensions.
Its current-source output is unchanged, and the supported padding field now
has a complete layout consumer.

## Rejected suspicions and verified integration behavior

The loaded adapter's presence checks match actual source behavior, including
empty strings. Source EnableSwitch uses `readOnlyReason !== undefined` and
`error !== undefined`; MetadataError uses `error === undefined`; artwork uses
`src === undefined || src === failedSource`. Changing Dart null-presence
tests to truthiness/nonempty tests would introduce a mismatch.

`features/dsh_feature_plugins/lib/src/manager_page.dart:591` follows the
locked loaded PackageCard predicates: full package-name title fallback only
when metadata title is absent, localized metadata-only description with empty
resolved strings omitted, actual experimental prefix, package error versus
metadata diagnostic ownership, installed/removable/availability/install-target
update checks including link-source changes, and the missing-target recovery
exception to the off/error switch lock. `common.dart:7` preserves empty
string values, including valid en/zh localized map entries, matching the
source resolver's nullish fallback. This review does not certify unrelated
detail-page or list-membership behavior.

The two remaining isolated widget probes pass:

- A short `A` title and status Tag share the same centerY (`289.0` each), so
  there is no reproduced short-title alignment/wrapping defect.
- An unchanged failed ImageProvider loads once, retains fallback after a
  normal rerender, and still loads once after a DPR1→2 dependency change.
  Flutter's existing image stream/cache behavior satisfies this bounded
  failure-lifetime probe; no retry-lifetime fix is justified by it. Format
  decoding capabilities and other lifecycles remain separate boundaries.

The reused `DshPluginDefaultArtwork` is the actual default source glyph, not
merely a same-sized substitute. Its 1110-character SVG path is byte-identical
to `ui-primitives/src/plugin-artwork.tsx:101`, SHA256
`43c683d8c394aa721a850a5af87889c0cdb6e60979149025b1fd897dd219814d`.
The viewBox36 scale, user-space gradient endpoints `(15.1481,9.94188)` and
`(15.1481,13.6375)`, and colors `#54ECE7`/`#658EFF` match. This is a source
geometry/palette check, not a claim of identical browser/Flutter rasterization.

Static inspection also confirms generated head gap 14 versus inner control
gap 8, content-box 48 artwork frame plus source-resolved borders, artwork 36,
natural title/tag wrapping, optional description spacing, and separately
layered trailing controls. The contour restricts input without clipping the
outer focus paint. Disabled trailing controls absorb input above the Card
target. Palette/weight/radius/border remain canonical Tag responsibilities;
the status profile adds only its bounded generated geometry. No additional
handwritten styling bypass was found in the reviewed new paths.

## Review limits and handoff

This review changed no product, generator, committed test, fixture, index,
SDK, source capture or native process. Only this note and the explicitly
authorized isolated probe were written. Toolchain commands sourced the
workspace's absolute `scripts/pr16-env.sh`. No full suite, application build,
ADB/GPU run, service write, push or PR operation was performed.

The source title's own DOM rectangle and its stretched pseudo-element are
different. They do not establish browser AX bounds by themselves; native
semantic/contour acceptance belongs to the final device replay. Highlight
animation/lifecycle, official ItemCard slots, browser title tooltips, sticky
post-touch hover and browser-native metadata image formats remain disclosed
pending boundaries. Retained complete source bodies are drift constraints,
not evidence that those pending behaviors are implemented. The parent owns
the focus fix, final integration tests, actual paired captures and native
acceptance. This review does not establish full Card-family or 99.5% parity.
