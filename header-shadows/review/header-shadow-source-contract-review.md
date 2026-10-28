# Header / source-shadow contract review

Final source-contract verdict: **PASS after two review findings were fixed**.
No additional blocking defect was found in the reviewed source/retention
contracts or in the changed shadow constants. This is not final runtime,
renderer or visual acceptance.

The initial read-only review targeted `e978fcbc489005d7bcbf26982ac9c8f02ed4d075`
in `scratch/whalee-source-shadows`, after Header integration `8145992`, against
main `875ef6936bc5337afcc3a187b2de80ad22963ccb`. Root resolved the findings in
`45f8a5e` and `1e91ab4f86cf5bf92d4db09aece40ebe443dc223`;
the latter tree is `bf137421ae9e93db98a87b8f8eaee795f80e86fe`.

Only this review note was written. Review checks used read-only Python calls,
in-memory mutations, Git comparisons and the existing archive cache. No Flutter
or native process, generation write, product change or new agent was run.
The source paths and acceptance boundaries in
`notes/header-shadow-integration-review.md` were also read.

## Resolved findings

1. **Whitespace normalization changed the meaning of the closed behavior
   fingerprint.** At initial `header_leading_recipes.py:32` and `:55`, removing
   all whitespace before hashing also removed whitespace inside JS strings and
   identifiers. In-memory changes `"session.new"` → `"session. new"`,
   `"toggle.open"` → `"toggle. open"`, and `"PageDown"` → `"Page Down"` were
   accepted with unchanged generated fields. This contradicted the promised
   closed set of labels, shortcut IDs and key semantics. Root's fix preserves
   exact released text, including comments, whitespace, token boundaries and
   literal contents. Header substitutes only the supported scalar slots;
   input-modality hashes the entire exact released region. The same mutations
   and a split identifier now fail. Current checks are at
   `header_leading_recipes.py:27–44` and `:61–63`.
2. **Python's numeric grammar admitted unsupported release literals.** The first
   correction still matched `\d+`, so `delayMs: 0500`, `size: 016` and fullwidth
   `５００`/`１６` were accepted and translated to 500/16. These are outside the
   pinned ESM decimal-literal contract. At current
   `header_leading_recipes.py:30–39`, extraction and substitution now share the
   canonical ASCII integer grammar with complete comma/brace boundaries. All
   eight negative forms independently checked here fail: leading-zero delay,
   leading-zero size, fullwidth delay, fullwidth size, fractional delay,
   fractional size, hex delay and numeric-separator size. Baseline 500/16,
   supported 640/18 and zero-delay propagation still pass.

These findings concern enforcement of future/changed retained inputs; they did
not establish that the unchanged actual released Header had the wrong labels.
The exact released input bytes remain the authority.

The nonblocking stale debt statement in `docs/design-system.md:22` was also
corrected: the current guard and allowance are **895 / 895**, after four real
Header matches were removed from the foundation's 899.

## Header recipe and semantic closure

`header_leading_recipes.py:11–17,64–90` enumerates the entire three-rule source
stylesheet, including property names, selectors and conditions. Source values
that are not represented dynamically are checked against their supported
structural values. Generated dimensions/tokens, repeated icon sizes and tooltip
delays feed the one Header profile. Unknown states, properties, conditions,
structural changes or required token names/types are rejected rather than
ignored. The source skeleton additionally binds labels, shortcut IDs, callback
targets, button type, class bindings and icon identities.

`generate.py:199–206,238–245,629–633` loads the locked global focus context,
published Header behavior and CSS, compares Header CSS with the actual pinned
source when available, then builds the Header profile. Existing source hashes
and the pinned source revision remain independently checked by the published
input contract.

All **29 pre-existing recipe metric maps are unchanged** versus main875. The
only new metric map is `DshHeaderLeadingRecipe`. Generated Dart and generated
recipe JSON remain byte-identical to initial e978 after the two guard fixes:
they tighten acceptance without changing any runtime recipe values.

The feature consumer uses canonical `DshButtonProfile.headerAction`, generated
group gap/icon size/tooltip delay and the shared button state model. Its prior
hand-painted `_Control` was removed. The existing Windows host behavior remains
an explicit platform adaptation, not evidence of full AppFrame equivalence.

## Actual release output coverage and inventory

The lock changes retain exactly two additional static behavior inputs from the
same already pinned releases:

- `ui-primitives/input-modality.json`.
- `ui-sidebar/HeaderLeadingControls-behavior.json`.

Every previous locked package identity, version, tarball, integrity and retained
file hash is unchanged. Total retained files rise from **83 to 85**. The ledger
changes only those two snapshot entries and its lock digest; its package/CSS
summary and dependency scope are unchanged: 57 UI packages / 209 CSS inputs,
36 retained CSS inputs / 173 pending, plus nine support packages / ten CSS inputs.
These are input-retention counts, not implemented-family or state-acceptance
counts. The new JSON files must not be advertised as two additional CSS profiles.

`published.py:183–190` always returns a behavior map for sidebar extraction,
empty for packages without Header. `:283–291` compares each returned behavior
snapshot and includes all its keys in `verified_outputs`. This fixes the
integration risk of verifying the new file but omitting it from the decoder's
reported output set. `:314–317` reconstructs the primitive input-modality region.
Exact declared/decoded set equality remains enforced at `:259–266`.

This review independently reran only the two affected archive decoders, without
network or writes: primitives produced **20 outputs** including input-modality;
sidebar produced **7 outputs** including Header behavior. Their output sets
exactly equal their lock declarations. Removing Header behavior from an
in-memory declaration is rejected with an `undeclared` output error. The cached
archive hashes remained unchanged:

| Archive | SHA-256 |
| --- | --- |
| ui-primitives 0.2.1-rc.2 | `576dc4a46ed55db70ae45b4b956e0d886a5700da32aeaed5bafb478f043f59ff` |
| ui-sidebar 0.2.1-rc.2 | `e81aff6896a6c033b800e294d281997c1b10698f4973193acadf717614366a21` |

The parent's retained actual-release receipt records 13 packages / 85 outputs
and matches the reviewed published-decoder hash. Its full run was not repeated
here. `verify_release_inputs.py:166–173` derives its snapshot count from the
verified output set, not merely the lock's length.

## Shadow constants, controls and disclosed limits

`dsh_shadow_box.dart:44–46` uses the source CSS conversion `sigma = blur / 2`.
The removed fitted expression `max(0.5, 0.45 * radius - 2.1)` and fixed 200px
reach are absent. There are no new theme, alpha, platform, density or score
branches in the replacement. Generated offsets, colors and spread values still
flow directly to the paint; first-listed CSS shadows still paint last.

At `:63–88`, each nonempty shadow has its own `saveLayer(null, Paint())`, draws
with that sigma, removes the original rounded card path with an opaque dstOut
mask, then restores. There is no added finite outer clip or empirical padding.
The per-shadow mask preserves the intended contribution `shadow * (1-m)` before
each shadow composites onto the parent, rather than masking the combined stack
once. Empty negative-spread boxes are skipped. The pre-existing corner/spread
contour implementation remains outside a universal CSS-equivalence claim.

The far-shadow controls in `css_shadow_source_test.dart:80–101,132–183` draw a
disjoint shadow independently, compare the full relevant raster and preserve a
fractional hard ancestor clip. Their test offsets, radii and densities are
fixtures exposing coverage errors, not new production styling constants. The
sigma recording assertions follow the pinned renderer rule; the remaining tests
exercise translucent interiors, paint order and empty erosion.

The revised `docs/design-system/source-shadows.md:51–60` correctly bounds the
claim to current rounded translucent panels. Opaque authored backgrounds,
square hard clips, general transforms and superellipse contours still require
their own source comparisons. Header native UA auto-outline paint, AppFrame
mounting, cross-window/composition cases and aria-keyshortcuts are likewise
explicit in the Header document. No new source-matching or visual-percentage
claim is certified by this review. Parent owns full suites, captures, builds
and native acceptance.

## Reviewed fingerprints

| File | SHA-256 |
| --- | --- |
| `header_leading_recipes.py` | `aa127b35652d987d2fb47b14e91a26d3bb9ac8bc7739821d4154e05cecbc2022` |
| `test_header_leading_recipes.py` | `a6326b4b8b727e7cbf7c40363839a34febb4ac88f009a9a01c278edd5d776869` |
| `published.py` | `5bb26ed6a23ee85c93d43941f5e5917fe93a6c229f72889e5932b94b139a3213` |
| `sources.lock.json` | `133545002c7eddb1ba9fed0e10d94d932d252f9abd03cfe5ab51486256b72c8a` |
| `source-inventory.generated.json` | `e82a452dddcdec4851047d51ff2e13d6858e8f82f48ddd6154c169c0a8e99697` |
| `dsh_recipes.g.dart` | `bdd942b8b011ea1b7f6fffe7212ea5aa237323a5b2925c590092eb56b015625a` |
| `recipes.generated.json` | `cb455dd4091c48764b8daf5bbb84b38b800d3f71b31da9fe00d424d7ffdb4e8b` |
| `dsh_shadow_box.dart` | `8c6a5df1a8450b7171f8790d178138608d25670700548bbe0ecdda3340a6bcb8` |
| `css_shadow_source_test.dart` | `e551e6dff0012f94b7b2eccdd0ef26323cba475e3acdefc9ba75229b2793cd16` |

Approval applies to the reviewed contract files and these fingerprints. The
parent's concurrent native-fixture work and final runtime validation remain
separate integration work.
