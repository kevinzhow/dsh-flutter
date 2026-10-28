# Loaded PluginCard final evidence/report review

**PASS: no further local evidence or report-binding blocker found.** Independently reviewed frozen `scratch/plugin-cards-stage-final` and `scratch/plugin-cards-artifact-final` for exact candidate/runtime `4e4b656612bdf02f1925c672ea0e49265d5e9567`, tree `453e3cfca2a95d7ee8b3c2c5872621d172c27b49`.

Stage manifest SHA-256: `a8dcfbd5fc9d64145329c1f28eddc2d57de9ea7efe1b6b5e8fd2a0bc2725a6ab`.
Final report HTML SHA-256: `5d6da464d18811418c12f87714f3a2c35d042e8572e7fccdc2e7e44b25ca7f7e`.

The report is too large for a single inline JSON publication request; the builder correctly withheld that request. Root is using the separately reviewed, supported incremental Artifact API rather than changing images or guessing transport. Local report acceptance and remote publication/readback are distinct; this worker performed no publication or network operations.

## Independent checks and receipts

Read-only verification scripts and machine-readable receipts are in `scratch/plugin-cards-independent-review/`. Only that external directory and this note were written; product, staged evidence, source capture inputs, report bytes and native resources were not changed. No classifier replay, application build, native input or additional capture ran.

| Independent receipt | SHA-256 |
|---|---|
| `stage-review.json` | `7a2277f1b04e26a69155acfbfe456fa85aabd64fbffeb48c19e99d163fa37c97` |
| `report-review.json` | `62ad0488b90ed432e94f15ca8108839a2a78d33c893c867bcaa2d4c1b4f5b973` |
| `privacy-review.json` | `ed507b7b73b78c784cecdf8a2201ebbfac92109cee57f9594bcea8974c2c9a5d` |

Verified every one of **4,013 registered files**, with exactly4,014 actual files including `files.json`. Independently resolved/rehashed all **5,352 raw input files** using their explicit workspace-relative domains. All raw→sanitized bindings agree;72 copied files have changed sanitized bytes, correctly distinct from their original producer/source hashes. No missing, duplicate, symlinked or foreign staged file was accepted.43 implementation copies bind to actual Git blobs at the final head; all three product subtree identities match the candidate. The source Git tree remained clean.

All thirteen final checks are `ok`, `fast:false`, at the exact final tree. Four build success logs, runtime head/tree files and actual local binary/library/APK hashes match the staged receipts. There are no post-runtime changes or carried-over test-only exceptions in this batch.

## Native identity and cleanup

Hardware GPU evidence binds the same manifest/build identity before and after replay. All four desktop/phone × light/dark cases use native Wayland, actual Mesa Intel Graphics(LNL) and `/dev/dri/renderD128`;112 assertions,80 PNGs and192 literal inputs agree with manifest/environment/runtime records. Assertion contents match their actual manifest expectations. Recorded app/Weston PIDs were checked absent during this review.

Android records17 scenes,57 checks,30 inputs and14 geometry proofs, all at the exact final head/tree/manifest. Fixture installed readback SHA matches the actual built fixture APK. Normal restored/installed readback SHA matches the normal build. Restoration/force-stop/emulator-stop/shared-ADB retention receipts are present; the owned emulator PID was checked absent, while the retained shared ADB PID was still present. The replay used the recorded physical1080×2400 display/density420, shell uid2000, with no display override or adb-root operation.

Key actual binary identities:

- Android fixture: `81eb0eb0b3297e06eecb280e3386f367889e7d236787718cd74bf030ea5075d8`.
- Android normal/restored: `487912169b722fd2ff23b540422f78f7c383f5075acd178b6c8b30534af4407e`.
- Linux launcher: `c379210cecad8a5ce89773e3c41355320419dd156a2378377636dcefeaae5d4c`.
- Linux fixture `libapp.so`: `f6bde14f97e4672b5017ead891bbd82a861b13737b93e578fb902c57a44f32c3`.

These are evidence/installed-readback checks; this review issued no ADB or runtime control command.

## Actual source/provider verification

Independently reconstructed all13 integrity-verified locked archives in offline mode: **86 exact retained outputs**, matching this Card batch's receipt. This is distinct from the later isolated Toast contract's88-output count. Metadata, source lock, source inventory and source archive identities agree.

Reopened the actual manager archive and compared its complete factory bundle with the raw prepared `host/plugin-manager.js`: the only byte change is the single explicit export hook exposing actual `PluginManagerPage` and its actual CSS export. The bundle/CSS behavior was not replaced by a mock or TypeScript fallback. All pinned source-file inputs match actual `687f282e8625c6b8d11ff58211a90524be2e4317` Git blobs. The capture-time source tool hash matches the exact final Git blob.

Provider receipt selects exactly224 keys, `kind:plugin-cards.manager`, native reference, no generic-cache use and no source-body/style rewrite. The complete actual source trace has all checks passing. Its scenario literal/hash matches the actual compiled Dart helper and the native manifest:11 idle scenarios plus default hover/press/focus, each over both themes/locales/widths/densities. No subset of difficult cases or failure frames was removed.

## Raw pixels, metrics and preservation

Recomputed all224 original source/Flutter **raw RGBA** deltas independently and checked the per-frame source/Flutter hashes and capture identities. Every raw changed-pixel count, maximum channel difference and mean absolute RGBA error matches. Recomputed RGB scores and pixel-perfect scores directly from these pixels. Recomputed the fixed non-text score arithmetic from the existing bound classification buckets and all aggregate means; the classifier itself was **not replayed or changed**.

Final224:

- 224 equal dimensions.
- 166 meet the fixed non-text99.5% target;58 remain below it and are retained.
- Mean non-text: **99.59141071428571%**.
- Mean RGB: **99.82754910714286%**.
- Mean pixel-perfect: **98.9066875%**.

These measurements use the complete900px-high viewport frames. They are not newly computed card-only crop scores or proof that every internal component rectangle matches. The report keeps raw internal geometry and explicitly distinguishes source text-sized button bounds from the native text line box and stretched semantic action.

Recomputed every before/after provider image, rather than treating a process exit as preservation:

| Cohort | Pairs | Provider images RGBA-equal | Changed images |
|---|---:|---:|---:|
| Old108 |108|216/216|0|
| Old96 |96|192/192|0|
| Manager16 |16|16/32|16 Flutter|
| Tag |56|112/112|0|
| Switch |48|73/96|16 Flutter +7 React|

The Switch source-image changes are real and remain disclosed; this review does not relabel that cohort as byte-preserved or infer an unmeasured cause. Summary means and fixed-target counts before/after match the staged records. The complete old108/96 total of408 provider images and Tag112 are RGBA-identical.

## Lossless report and measured limits

Independently opened all224 composite PNGs and compared both embedded rectangles with all448 original frames. Every rectangle is exactly identical in RGBA; no resizing, recoloring or crop-to-fit occurred. All225 report file hashes/sizes, source/Flutter/composite hash captions, case identities, filter attributes and logical-DPR display sizes bind to the frozen stage. Every retained case, including the58 below target, is present.

Visual inspection included ordinary desktop/light, the worst non-text case (long-tags, phone, EN, dark,98.501%), the300px overview and the1280px raw-geometry display. The report shows full frames, raw numeric differences and the remaining scope plainly. The tagged phone layout's natural wrapping and source/native geometry are exposed rather than hidden behind an aggregate.

The actual300/1280 browser preview receipt binds the same HTML hash and preview producer. Both sizes decode all224 assets, pass all filter/reset checks, keep page scrollWidth equal to viewport, and record zero errors, failed requests or external requests. Horizontal full-frame scrolling is intentional; the PNG is not fitted or cropped to make the page narrow.

Measured bytes, independently re-summed/reconstructed:

| Quantity | Bytes |
|---|---:|
| Original448 PNG files |24,044,782|
| Lossless224 composite assets |21,594,012|
| HTML |661,726|
| Final raw225-file version |22,255,738|
| Single-inline serialized JSON request |29,474,005|
| Builder's24MiB request cap |25,165,824|

Per-file inline10MiB, HTML16MiB and file-count255 bounds are satisfied, but the single inline JSON total exceeds its cap. `publish.json` is correctly absent and `missing-blob-manifest.json` binds the exact expected files/required request size.

Root's approved delivery is the already reviewed incremental Artifact API in `scripts/plugin-cards-publish-plan.py`: preserve the existing index while preloading118 new PNG paths; require the actual phase1 receipt and fresh complete readback; then atomically introduce the final index with all225 file hashes. Both prepared requests stay below20MiB. At the latest root update, phase1 had succeeded as version5 with119 files/14,202,345 raw bytes and root had verified all118 new hashes plus the unchanged prior index by physical download. This paragraph reports root's remote check; this worker's independent verdict covers the frozen local bytes and does not substitute for root's final remote readback.

## Privacy and coverage ceiling

All staged text and PNG metadata pass the sanitizer check. An additional independent scan found no actual workspace/home path or strong credential signature, and the private user screenshots/network/DM notes are not staged. Source/tool copies altered by sanitization are explicitly illustrative; raw producer hashes remain separate authorities. Historical failed/diagnostic runs remain labeled separately from final acceptance.

The report correctly retains the bounded scope: loaded cards only; Highlight frozen/pending; sticky touch hover unaccepted/pending; native SVG/general image formats unproven; broader Unicode/bidi/other font engines not certified; Manager31 remaining numeric matches. Inventory36 retained CSS/173 pending and880 scanner matches are retention/regex facts, not whole-family implementation percentages. The final mean and166 passing cases do not mark the overall99.5% task complete.

No additional local blocker was found. Root owns the final atomic Artifact publication/readback and PR62 integration.
