# Loaded-card source provider review

Verdict: no blocker in the reviewed provider, routing or retained 224-case
source preparation. This establishes reference identity and fixture coverage;
it does not establish paired Flutter pixels, native behavior or overall parity.

Reviewed read-only on k172, 2026-10-29, against
`scratch/whalee-plugin-cards` head
`2a6b7d713c2085a8a05e8dcd629fa518c7abb0f2`.
The reference remains published DSH `0.2.1-rc.2`, source commit
`687f282e8625c6b8d11ff58211a90524be2e4317`.

## Actual published factory and styles

I reopened the retained public npm archives with Python/tarfile, without
executing their JavaScript, and independently called the current
`published.verify_snapshot` against the candidate's retained outputs:

| Package | Verified outputs | Actual archive SHA256 |
| --- | ---: | --- |
| ui-plugin-manager | 5 | `a1f1f1f2c40b68fb67b1c7263e25c631b443487905d72cd61fa95e33750e9095` |
| ui-theme | 11 | `b1efb73b6666c0e12dfd724a673d7bfb78c5ea1817e2880763e2b22d17e10370` |
| ui-primitives | 20 | `576dc4a46ed55db70ae45b4b956e0d886a5700da32aeaed5bafb478f043f59ff` |

This review directly reconstructs these three archives/36 outputs, not all
13 release packages; final full release verification remains the integrator's
separate gate. SHA512 integrity is checked against the actual locked identities.
Manager's five outputs include the complete loaded behavior snapshot as well
as the decoded stylesheet and class map.

`tool/design-system/capture-plugin-cards.mjs:53` verifies the archive integrity
and `client.js` SHA256 before preparing a host. I byte-compared the saved
`build/plugin-card-source-final/host/plugin-manager.js` with the archive's
`package/lib/client.js`. They differ by exactly this hook before the unique
factory return:

```js
globalThis.__PublishedManager = PluginManagerPage;
globalThis.__CardCss = PluginManagerPage_module_css_default;
```

The published bundle hash is
`b4efaa441258a547a0d7b3cab559fe073c69e69fe2bbb617c710ded134e7c4f9`;
the exact instrumented result is
`aef3cde87abbf361ddd33965891403d0580ebcf59ccfe388a6ad69dd56229707`.
No component function, event handler, predicate, CSS string, class map, title
button or Card layout is replaced. The metadata locator added after mounting
is a measurement attribute, without a matching source styling rule.

The surrounding host supplies controlled synthetic business state through the
Manager's real props/hooks. It mounts the full actual Manager rather than a
reconstructed Card. In particular, the normal installed/Discover tab input is
present. The `primitives.ts` adapter reexports the actual pinned Button, Tag,
Switch, artwork and input-modality source modules. It changes the barrel's
import graph, not those implementations. All seven explicitly recorded source
files equal their pinned Git blobs. The producer additionally rejects a dirty
or differently pinned source checkout. Theme sheets and font files match the
locked bytes; host additions are the normal parity canvas/font environment,
not per-card CSS.

## Shared scenarios and all selected outputs

Preparation directory:
`scratch/whalee-plugin-card-captures/build/plugin-card-source-final`.
Its `provenance.json` equals the provenance embedded in `source-trace.json`.
I regenerated the in-memory case data through the current builder and
compared it exactly with `build/plugin-card-plan-final/cases.json`, the
Flutter plan entries and the compiled Dart JSON literal. No file was generated
or overwritten during this check.

| Binding | SHA256 |
| --- | --- |
| Original plan | `40403c07d420b77f03788ae999e1f0ee9096df96eaf5f37fd14f0db2fc6419ab` |
| Shared compiled fixture helper | `66fd43b63f945b5efbce1b57f1d8202497f57198963aeb26539aeba94a36728f` |
| Scenario JSON literal | `e760ca5101ec4df93afd5e8cd63f33dadf5c19d72771015225da7688bd7a3cac` |
| Current source lock | `9abb49916af9c9fedfd2a6183d2586c72b5b08d2718a9534ae624cd68fc064d6` |
| Complete loaded behavior snapshot | `3b6cfeaef749c9f919217bae9d5d36ba0759ef44fee9d7d6c850d866227a16a9` |
| Source trace | `7b04dbdddd02bca03c9f5091a26527a7b987fd04aad106b5002ab734de9033e1` |
| Standalone provenance | `6a7bc8c45a1dcf9af2b3be05f805adadeef3ab6b33d99d21bb01f09937c6fce6` |
| Derived Flutter plan | `90aedf048599d3e31ce5a80e8659adac42a8fe13b06f14abb3bf5f92dae9439c` |

There are exactly 224 unique expected keys, 224 PNGs and 224 metadata files;
the React result directory contains no missing or extra output. Every PNG
decodes and matches its trace hash. Every metadata record binds the actual
case/variant/key, locale/theme/viewport, source commit, published bundle and
the same provenance digest. Its measured `actual` object equals the trace.

The complete matrix is eleven idle scenarios plus three extra default states,
crossed with two themes, two locales, two viewport widths and two DPRs:

- idle: 176 captures; hover, held pointer and keyboard focus: 16 each;
- default scenario: 64 captures; each other scenario: 16;
- physical PNG sizes: 800×900, 390×900, 2100×2363 and 1024×2363, 56 each.

All shared scenario inputs equal the current fixture. I also independently
checked every actual title, description, localized tag label and metadata
diagnostic against that data and the pinned en/zh dictionaries. Switch enabled
and disabled states match the scenario predicates. All trace errors are empty,
all 288 recorded checks pass, and all 64 post-capture disabled/refused-switch
probes retain accepted checked state without opening the Card. Refusal counts
are one only for refused scenarios; disabled scenarios produce zero attempts.
All keyboard-focus captures record actual title focus-visible state; hover and
held-pointer captures record the actual hovered Card.

## Preparation identity versus final producer

The preparation explicitly records its source-only repository head
`61e88e021590cab10de0cad93c73305170af9a8a`, tree
`398b66f25a28c9941d93ffc004bbdd8c4f4f4423`. It must not be relabeled as a
runtime capture from the later integrated Flutter product.

The preparation producer SHA is
`dd9b315ca4aee7af6fcd68950bc4bc868fff2b7249d5463f9ad9cd3984148c2b`,
which exactly equals the script committed at `dc9210b7`. The reviewed current
producer SHA is
`7432785e48ea9d2dd961cace25a99eae5380f003959175f8078e53d16442aeb2`.
An exact text comparison, substituting only these known changes, reproduces
the old script byte-for-byte:

- explicit native/emulated reference-mode forwarding and the corresponding
  Chromium force-device-scale-factor flag;
- `GIT_OPTIONAL_LOCKS=0` for read-only Git calls;
- the established `~` separator for nondefault variant IDs.

Every preparation variant is `default` and its reference mode is native, so
none of these changes modifies its reference rendering or input sequence.
Factory, CSS, fixture, selected case data and the source pin are unchanged.
The dedicated native/emulated provider smokes and the normal-entrypoint source
smoke also have valid selected-key, trace/plan hash and no-generic-cache
receipts. Their producer SHA
`5cd8c550cae80cf95c2c86910af5653d3f7af79516a9797dc0e183c7731aa581`
differs from current only by the optional-lock-free Git addition.

## Routing, transport and limits

`tool/parity_lib/react.py:116` separates only `plugin-cards.manager`. I compared
the old generic `capture` function from `dc9210b7` with the new
`_capture_generic`: their bytes are identical after the function rename. Old
arguments/cache keys/results are preserved; mixed selections retain selected
result order. The source-only TypeScript host for the new kind throws instead
of silently substituting another reference.

The dedicated provider validates the exact selected receipt/key/output set,
PNG hashes/decoding and metadata identity before copying any new-family result
into the shared destination. Failure preserves the dedicated output and raises;
it never falls back to the old cache/host. Archive handling reuses the existing
locked public archive policy. Seven provider/transport tests and five plan
tests passed independently during this review; their tiny mock images are
unit transport fixtures and are not counted as visual evidence.

The source producer measures actual DOM geometry before screenshot and before
releasing held pointer input. It records Card/title/description/frame/artwork/
Tag/switch bounds and styles; it does not assert that Flutter has those bounds.
The parent-requested Flutter per-case geometry comparison is still a separate
in-flight check and must preserve the held-input state until measurement.
The source-only normal-entrypoint smoke explicitly skipped Flutter and claimed
no paired score. Whole-page differences outside this bounded loaded-card
migration, highlight lifecycle, sticky post-touch hover, native metadata image
formats and browser tooltip paint remain visible pending work.

No source layout or score fitting was found. Full-view captures should remain
uncensored: a correct source provider does not make unrelated page regions
matching or turn preparation assertions into a pixel-parity claim. Native
replay and final product identity are separate integrator-owned gates.

This review wrote only this note. The bounded tests used temporary test-owned
directories; no product, fixture, capture output, SDK, index or service was
modified. All Python/toolchain invocations sourced the absolute workspace
`scripts/pr16-env.sh`; no browser capture, application build, ADB/GPU run,
network request, push or publication was performed.
