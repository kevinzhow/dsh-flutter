# Actual published Toast capture preparation

The additive `toast.source` family renders the actual ui-primitives0.2.1-rc.2
ESM `Toast` export and the actual Flutter `DshToast`/`DshToastHost`. Its source
is pinned to `687f282e8625c6b8d11ff58211a90524be2e4317`. The published archive's
SHA512, complete bundle hash, locked whole Toast region and exact Toast CSS are
verified before rendering. Toast and the real warning/success glyphs already
have ESM exports, so there is no exposure hook or component-body/style rewrite.
The normal Vite module/CSS compilation is retained as rendering machinery.

The runner extracts regular archive files into its own new host directory,
rejecting duplicate/escaping paths. All extracted bytes are hashed. Supporting
package dependencies, pinned theme sheets, real Web mount CSS and the existing
parity font files are used without style, alpha, font or scorer adjustments.
Requests are restricted to the runner's own loopback origin/data URLs.

## Shared fixture and exact scope

The single compiled JSON literal in
`apps/dsh_flutter/test/parity/helpers/toast_fixture.dart` is extracted by both
the plan builder and source host. Native imports that same helper without asset
or file reads. APIs are `toastScenarios`, `toastScenario(id)`,
`toastFixtureText(id, locale)` and
`toastFixtureWidget(id, locale, {key,onDone,hold})`; locale is a String.
Omitted hold preserves the real default lifecycle.

There are seven synthetic inputs: `no-icon`, `success`, `warning`, `long-warning`,
`long-no-icon`, `whitespace` and `unbroken-word`. Text is localized English/
Chinese. Newline/tab/repeated-space/NBSP and oversized unbroken token data is
retained verbatim. The native component applies its actual CSS-normal text
contract; neither provider alters fixture strings to hide differences. Native
geometry records raw/original and displayed text separately.

The builder emits224 cases: seven inputs ×normal/reduced motion ×light/dark
×English/Chinese ×800/390 viewport widths ×DPR1/2.625. Height is600CSSpx. Normal
motion is the default cohort; reduced motion is an additional explicit state.
Both use source-supported `holdMs:60000` solely as an explicit stable-PNG input.
After pinned fonts are ready the owner remounts once, the source's real entry
duration elapses, and settled animation frames complete. Flutter advances from
that same source entry duration and settled-frame sequence. Both record actual
steady opacity/transform/geometry before the long hold ends. This is not a
sample chosen from a score or an animation comparison claiming exact timestamps.

Full viewport originals are preserved, including any text overflow outside the
Toast. Source metadata records actual portal-to-body, alert role, pointer
behavior, content box, icon/text bounds, CSS gap, opacity, transform and animation
timing. Native `componentGeometry` records raw root-relative Toast/text/icon
boxes, unrounded coordinates, actual opacity/translation and actual row seats.
Native row children include its explicit generated-gap SizedBox; source flex
children exclude CSS gap. Those structures are labeled separately rather than
declared equivalent.

## Normal harness dispatch

The normal React provider routes only `toast.source` to the new dedicated
published source runner. Prior Card dispatch and the generic capture body remain
unchanged. Existing selected-entry keys, results, cache and comparator paths are
preserved. A direct generic host renderer fails closed so it cannot substitute
source TypeScript or a reconstructed Toast. Source results are copied to shared
results only after all selected keys, check states, hashes, PNG decodes and
metadata validate. Native and emulated reference modes are forwarded explicitly.

After sourcing the absolute workspace `scripts/pr16-env.sh`, a final integrated
batch can use the ordinary entrypoint:

```bash
PARITY_EXT_ALL_THEMES=1 tool/parity-ext/run run \
  --cases 'components.toast.*' --refresh-react
```

Source-only preparation and separate actual lifecycle probes can use:

```bash
python3 tool/parity-ext/build-toasts.py --out build/toast-plan/cases.json
nice -n 15 node tool/design-system/capture-toasts.mjs --repo "$PWD" \
  --archives /absolute/retained-archive-cache \
  --plan "$PWD/build/toast-plan/cases.json" --out "$PWD/build/toast-source" \
  --behavior run
```

Output contains `provenance.json`, exact extracted archive bytes, source224
PNG/metadata, `source-trace.json` and a standard app-only `flutter-plan.json`.
`--behavior run` additionally writes four actual-source probes in
`behavior-probes.json`: unoverridden default3000/latest callback/original
deadline, changed hold, unmount cancellation and a portal escaping a transformed
owner. These use actual source effects and normal motion, separately from stable
PNG props. Their timers/props are not inferred from the long-hold capture cases.

The existing archive helper/cache supplies the package; `PARITY_SOURCE_ARCHIVES`
selects an explicit cache and `PARITY_SOURCE_ARCHIVES_OFFLINE=1` refuses missing
archive downloads. Capture tools do not execute package-install scripts or use
human account credentials.

## Verification and limits

Preparation has24 focused Flutter fixture tests, five plan/data/schema checks,
seven new routing/transport checks and seven existing Card-routing checks. The
old generic capture body is AST-identical, and an actual existing Manager
reference re-render in a mixed normal-CLI source-only run is RGBA-identical to
the retained pre-Toast reference. The mixed run honestly has no paired Flutter
results. Transport-unit fixture PNGs are not visual acceptance.

Actual source224 and the four lifecycle probes are preparation evidence, not
the final combined-tree authority. Root must recapture after Card/Toast
integration and retain all paired raw differences. No full paired Flutter
batch, application build, native input, push, PR or release runs in this lane.

CSS ASCII whitespace/empty spans and sole unbreakable-run overflow now have
actual-source controls and canonical corrections. The authored-opaque shadow
exclusion branch is explicit, with previous callers preserved. Mixed paragraphs
containing oversized runs, broader Unicode/bidi, Chromium retained-origin inner
contours, animation rasterization and native
announcement/contour delivery remain pending.
Toast now retains source pre-transform border snapping and the authored-opaque
exclusion inset of one internal paint pixel. The unchanged software cohort still
exposes renderer differences in shadow coverage colorization and final integer
blending against the actual backdrop; these source-correct geometry rules do not
certify exact raster parity.
The three real feature owners are covered by the separate native preparation
lane; these primitive screenshots do not pretend to be complete browser owner
or production Host/network flows. Actions/anchor and fourteen other source
owners remain frozen/pending. Source retention and test counts do not prove
implementation completion or the overall99.5% target.
