# Actual loaded-card capture preparation

This cohort renders the **actual published PluginManagerPage** and the actual
Flutter `PluginManagerPage`. It adds no styled test card and changes no product,
recipe, font, scorer or existing preview fixture. Existing Manager16, reported108
and preservation96 case identities and data remain unchanged.

The reference is `@deepseek-ai/dsh-client-ui-plugin-manager@0.2.1-rc.2`, pinned
DSH commit `687f282e8625c6b8d11ff58211a90524be2e4317`. The source runner verifies
the actual archive SHA-512 and published `client.js` SHA-256, then exposes only
the existing Manager binding and CSS class map at the factory's final return.
The factory/component bodies and published styles are not rewritten. Supporting
primitives, locale text, theme sheets and Web mount CSS come from the same pinned
source/locked outputs, with the unchanged parity font manifest. The source
contract's 13-archive/86-output reconstruction remains the integrator's separate
gate; rendering one archive does not certify all of those outputs.

## One offline data source

`apps/dsh_flutter/test/parity/helpers/plugin_card_fixture.dart` contains one
compiled JSON literal. The Python plan builder and browser source runner extract
that exact literal; native Dart imports the same helper without asset or file
reads. `SyntheticPluginCardFixture.fromId(id)` exposes the real manager/market,
fake Host, package name, accepted `enabled` state, attempt/refusal/request counters,
`load()` and `dispose()`. The existing `SyntheticPluginsPreview` is composed and
its business handlers overridden; it is not changed.

The eleven scenarios are `default`, `no-description`, `long-tags`,
`problem-enabled`, `metadata-error`, `busy`, `read-only`, `error-disabled`,
`missing-recovery`, `refused-toggle` and `image-failed`. Localized title and
description objects are shared. The long case combines Beta, Problem, missing
files and update tags. Metadata errors retain their own diagnostic line.
The failed image is invalid `data:image/png;base64,AAAA`, so neither native nor
browser needs an external request. It exercises fallback, not SVG decoding.

Both actual pages receive the installed/Discover tabs. The published page takes
Discover through its normal plugin-tab input; the Flutter manager already mounts
that real market tab. Omitting it would change the source page layout and would
not be the same fixture. Earlier source-only preparation outputs without this
mounting input are retained and are not the final reference set.

The refused browser toggle is a controlled-store callback probe: one actual
switch click reaches the refusal adapter, the accepted value stays unchanged and
the card does not open. It does not reproduce the production Host/store failure
toast transaction. Native preparation separately exercises the actual model and
the actual page's detail/back UI; a synthetic open counter is not its acceptance.

## Additive plan and paired capture

`build-plugin-cards.py` emits 224 unique cases: eleven idle scenarios and three
additional default hover/held/focus states, crossed with light/dark, English/
Chinese, desktop800/phone390 and native DPR1/2.625. Every viewport is900CSSpx tall.
The manifest contains data, capture dimensions and actual input steps; no card
style values are supplied by it. Ordinary Tab traversal reaches the actual card.

The generic Web renderer intentionally refuses this new kind. It must not
silently substitute source TypeScript or a reconstructed card for the published
reference. The dedicated source runner writes standard `react` PNGs and metadata
plus a `flutter-plan.json`. The new Flutter kind is discovered through the
existing parity case-map glob and runs only the actual app package. Example,
after sourcing the absolute workspace `scripts/pr16-env.sh`:

```bash
python3 tool/parity-ext/build-plugin-cards.py --out build/card-plan/cases.json
nice -n 15 node tool/design-system/capture-plugin-cards.mjs \
  --repo "$PWD" --archives /absolute/retained-archive-cache \
  --plan "$PWD/build/card-plan/cases.json" --out "$PWD/build/card-source"
python3 tool/parity_case_map.py
cd apps/dsh_flutter
PARITY_PLAN=/absolute/card-source/flutter-plan.json PARITY_PACKAGE=dsh_flutter \
  nice -n 15 flutter test --no-pub test/parity/parity_capture_test.dart \
  --reporter expanded -j 1
```

The integrator owns that final Flutter capture batch and the unchanged pipeline
comparison. Preparation runs only source rendering and focused fixture/schema
tests. Full viewport source images are retained with actual DOM/card/artwork/tag/
switch/focus geometry. No crop is selected from observed pixel scores. Source
shots, plan, helper, archive, bundle, source files and fonts have hash provenance;
the source runner refuses changed inputs before completing. This is source-only
preparation until exact combined-tree Flutter/native evidence exists.

## Focused checks and remaining boundaries

`plugin_cards_fixture_test.dart` exercises all eleven real-page branches and
sixteen long localized cases across the theme/locale/viewport/DPR matrix. It
checks actual switch locking and refusal behavior, metadata ownership and missing
description, with no self-authored visual golden or pixel-equality requirement.
`test_plugin_card_capture_plan.py` checks the complete matrix, one data source,
published-source requirement, rejection of duplicate/schema-invalid data and
preservation of existing cohorts.

The earlier source224 runs are retained as preparation history. The schema-valid
matched-tab source224 run in `build/plugin-card-source-final` is the reference
candidate, using `build/plugin-card-plan-final/cases.json`.
One intermediate focused-test compilation failure used a nonexistent enum
getter; its log is retained and the corrected matrix passed. No product code was
changed for that fixture error. An actual manifest-schema RED also rejected an
unsupported extra case key; the builder was corrected and all five focused plan
tests passed without changing the shared manifest schema.

Highlight lifecycle, Chromium post-touch sticky hover, metadata SVG/native image
formats, browser-native tooltip paint and whole-page differences outside the
loaded card remain pending. Source captures and fixture test counts do not prove
pixel parity, real-device accessibility, native contour acceptance or production
camera/network behavior. All differences must remain visible in final paired
results; no fitting, score thresholds or approved platform exceptions are added.
