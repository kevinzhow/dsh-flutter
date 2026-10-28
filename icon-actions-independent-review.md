# IconAction evidence and visual report review

**PASS for the final frozen stage and report payload. No further
blocking finding remains.** The responsive-layout finding and the subsequently
observed DPR-filter failure were corrected in the external renderer. This
verdict concerns accurate evidence and reporting; it does not certify the
unfinished overall visual target, reverse keyboard navigation, CI/merge state
or publication authority.

Review was read-only except for this note. No product/source/Git/device/build
change, native replay, test suite, network request or publication was run.
Completed native/source/raster validators were invoked as read-only checks;
final stage hashes, raw/sanitized bindings, payload images and preview receipts
were independently inspected. Root owns publication.

## Exact reviewed identities

- Product and runtime head: `1911e77e68d43c3badf83f22edd763071e8e7740`.
- Product and runtime tree: `90a20ee9bf221367a3fe865ca7bc997a3081a02d`.
- DSH source: `687f282e8625c6b8d11ff58211a90524be2e4317`, release0.2.1-rc.2.
- Committed native manifest:
  `579e6be262553255877289ea0cab7b12f5fab58c59db394749aa5a89a36d01f9`.
- Evidence script SHA-256:
  `ea45439068764316361b03b55a72594337f4bf3244eadf48b57d210fe18cb6cf`.
- Final renderer SHA-256:
  `89d0aab0bec6f981f96a42c94a20430e3aa14a691ceec1d69b2246d56f29edd1`.
- Android driver SHA-256:
  `df7b631a78f0e0b79a0121c7a63ccbdbfd2c4abfab60e03cf4082430ce77e574`.

The stage at `scratch/icon-actions-stage` contains **2,874 unique registered
files, 2,875 including files.json**. Every registered SHA/length and the exact
file set were checked: no missing/extra files, symlinks or digest differences.
Its manifest SHA is
`b7163b344264a23344c5f6b06a473b540b65b72c0bc46fb6846f55c8abbfbc8a`.
All2,922 sanitized raw-input path records are unique, and every copied file's
raw SHA maps to its recorded original input. Sanitized JSON/text hashes remain
separate from raw producer, committed manifest and archive hashes; the report
does not compare those distinct domains as if their bytes were identical.

## Native, archive and source checks

The actual before/after product identity is clean and exact; no post-runtime
change allowance is accepted. The final local preflight records all13 required
checks in `ok` state with `fast:false`. Four build products bind the same
runtime head/tree and actual binary/library hashes.

The independent read-only validators pass for **GPU76 assertions /76 PNGs**,
including the four desktop/phone × light/dark cases, literal manifest inputs,
per-assertion results, actual screenshot sets, native Wayland, hardware render
node, equal before/after binaries and absence of recorded owned PIDs. Linux
fixture executable SHA is
`b8b47657d8ef97d1e0a1cdbda0798784222d279d72c7a7fdc95056f1dfee41ce`;
its application-library SHA is
`d266e77c3605bef43be2fb6791191e6272a6194003f2ef3ff0d3304c3d201616`.

The final Android validator passes **12 captures /20 inputs /27 checks**.
It binds the exact driver and committed manifest, source-sized semantic tap
bounds and focused descendants of the same action subtree. Fixture installation
readback equals the built APK
`0c65c68abed517d05d427364d3af6585e8d2bc111fd34309db2ef5cbd82d4602`.
Both successful `installed-fixture.apk` and `installed-normal.apk` readbacks
are now retained and rehashed, including the restored normal APK. Physical
1080×2400/density420, shell UID2000, no root/display override, stopped owned
emulator/app and retained shared ADB are checked. Reverse-tab injection remains
explicitly pending; ordinary forward Tab is the accepted committed sequence.

Actual archive reconstruction independently passes **13 locked releases /85
retained outputs**, with exact archive integrity, decoded output-set equality,
current lock/ledger/verifier fingerprints and snapshot hashes. This Icon batch
does not include the separate PluginCard branch's86th output. The actual family
guard is892 numeric pattern matches /0 duplicate-button matches /11 platform
control matches. The source ledger is retained-input coverage, not implemented
component coverage.

The source matrix has all144 immutable source PNGs and8 theme/DPR/input
contexts. Source files/fonts match the recorded provenance; the actual source
checkout is clean at the pin. Both saved instrumented factory hosts were also
independently reconstructed from the verified plugin-manager/sidebar archives:
the only change is the single declared `globalThis` exposure immediately before
the unique factory return. The original component bodies and CSS are unchanged.

All144 raster mappings and source-derived crop bounds pass the raw validators,
including original frame hashes, source metadata, callback effects, raw RGBA
statistics and crop/difference bytes. The independently read1,140 native/build/
archive/source/raster inputs stayed unchanged during validation. All144 report
`rgb-difference-visible.png` files were separately checked against the actual
source/Flutter RGB differences; no amplified or blank replacement is used.

## Reporting limits and history

The raster result is honestly shown as **0/144 exact crops**, with80 IconAction
and64 Header frames, **64 pending frames and36 focus-ownership differences**.
Every actual focus mismatch retains its pending label. Pointer-hold source and
Flutter images and the filtered pending gallery were viewed directly. Callback
effect equality is not represented as equal focus or pixels. The retained
limits also distinguish route-pop effects from raw callback invocation counts,
and GPU image-change assertions from exact numeric counter reading.

Fresh identities exist for Manager16, preservation108 and preservation96,
all at the final head/tree. Current108 has100 equal dimensions,0 pairs≥99.5%
non-text agreement and mean68.1437685185%, unchanged from its original baseline.
Its216 provider comparisons are RGBA-equal. Current96 has72 equal dimensions,
0 strict pairs and mean93.3618958333%; its192 provider comparisons are equal to
the original96 baseline. The stage's cohort validator checks immutable source
plans, provider hashes and before/after pixels; the report keeps **historical192
separate from these fresh192** and marks historical acceptance false.

Manager16 page pairs remain distinct from the144 isolated control-region
comparisons. The report does not infer a complete Web counterpart for the three
native connection pages, production camera/network parity, a successful overall
99.5% target, or an approved exception for sticky touch hover, UA outline or
focus ownership. Current numeric matches are labeled `数值模式匹配`, not proven
violations. The old wrapper is described as retired and its three callers as
migrated, rather than treating those callers as deleted product actions.

## Corrected renderer findings and final artifact

The initial reviewed CSS had a330px minimum grid track with28px side padding,
which could not fit a300px viewport. Root corrected the track to
`minmax(min(100%,330px),1fr)`, clamped outer padding and fixed the Artifact's
light color scheme. Actual preview subsequently found a separate DPR-token
bug: serialized `1.0` did not match the selector's value `1`. The final renderer
uses general numeric formatting for the filter token; this is a report-only
change, not a product/pixel-input change.

The failed preview is preserved at
`scratch/whalee-icon-actions/.local/icon-actions-report-preview.log`, SHA
`23017eb8b4b34d8cf3e9bb11b517808304e2291f5cbe29df60bf0e450f6a7650`.
It records `IconAction pending-state filter differs`. Its stage/artifact remain
in `scratch/icon-actions-stage-before-dpr-filter` and
`scratch/icon-actions-artifact-before-dpr-filter`; neither is certified here.

Final HTML at `scratch/icon-actions-artifact/index.html` is **3,005,687 bytes**,
SHA `f17fd9e96dbcd5c4a286968c3d811f4aadeb6e767acbb276c9edd3cf8df77457`.
The stored publication payload contains exactly those UTF-8 bytes; payload SHA is
`6cab1f6957a94ad6b3a9f88f798aae2ec9885adfa50aeb7c78c74107c2076d7a`.
Its existing Artifact ID, base `c406f169-e158-4e15-9cf7-ed3319c874f3` and seen3
match the cached owner read. No online publication was checked by this review.
After these local checks, root reported Artifactv4 revision
`78dc164a-b751-495e-afa7-7defc2e51c5b` with downloaded service bytes matching
the same HTML SHA, and evidence commit
`56f04161aa633559d0b930cc5c9c126668445bb2` under `icon-actions`.
Those publication/readback actions belong to root; the local evidence verdict
remains tied to the exact stage and HTML reviewed here.

All **464 inline PNG bytes** exactly match the expected SHA multiset:
144 source/Flutter/visible-difference trios plus16 Manager page pairs. The
final preview receipt, SHA
`b9f815837b1aa504e9de4a6c921d33135eb508ef80f0fb13b8a991b8a0c40efe`,
binds that HTML at300 and1280px: all464 images decode, the chosen pending filter
shows5 results, scroll width equals viewport, color scheme is light, and browser
errors/external requests are empty. The narrow overview and wide pending preview
were viewed and agree with these claims.

All staged non-PNG text and report text were independently scanned for common
credential/key/bearer forms and personal home paths: no finding. Images and
native XML are synthetic fixture evidence; no unrelated DM or network material
is included. Only this review note was changed.

There is no remaining blocker to publishing this accurately bounded evidence.
A different manifest, HTML/payload, renderer or runtime generation requires a
review of the changed bytes; this verdict is not a release/deployment grant.
