# Independent menu-compositing review — 2026-10-28

Reviewed candidate `scratch/whalee-menu-compositing` at
`f1aac4fffc7e66b4d131a985322f947c5056015b`, tree
`03c31b58f212046cb82e1d9bc79d67081ba78115`, against merged main
`80a1b160d15b7287789604cef69bc38a6a1fa1ad`. Runtime product is
`4feb2c38e63fc61f0e2a6dab125bd5709be7ccb2`, tree
`a32ed26154623c6ee9ced491712348f44330557f`. This review only reads source,
published CSS, existing logs/receipts and publisher code. It runs no Flutter
tests/builds, native replay, staging or publishing and changes only this note.

## Production result

No substantive production issue found in the bounded correction. The publisher
gate finding below was fixed and independently verified before this review's
completion; no blocking finding remains.

- `packages/dsh_ui/lib/src/dsh_menu_surface.dart:38` already computes and
  paints an opaque fill by blending the generated released material token over
  the saturated page base. Both standard and dock branches now declare exactly
  that same painted fill to descendants at lines59/90. The declaration adds no
  layout, paint, focus, semantics or input widget; it is an InheritedWidget.
- `packages/dsh_ui/lib/src/dsh_menu_item.dart:202` only precomposites a chosen
  row fill when the nearest declared ground is opaque. A missing ground or any
  alpha below1 returns the original Color unchanged, including fractional
  alpha. Null transparent/check-only states remain null. An opaque fill remains
  unchanged through the existing paint helper. No action, focus ownership,
  selection or geometry logic changes.
- The released MenuSurface CSS isolates its material behind row children;
  model focus-visible rows use the generated hover token. The source audit's
  opaque-base and actual-material Chromium probes support this exact uniform
  composition contract at DPR1 and2.625. The code does not introduce a fitted
  replacement token or a new blend algorithm.
- This does not implement arbitrary varying backdrop composition or native
  macOS vibrancy. Those are existing explicit limits. Precomposing a rounded
  row also changes antialias coverage arithmetic at its edges; the documented
  light-phone Effort probe's net7 additional mismatched pixels must remain
  visible in final metrics rather than being described as byte preservation.

## Tests and runtime equivalence

The eight new tests provide meaningful coverage for the modified contract:
four actual raster tests cover both model profiles and themes, exercise plain,
focused, check-only, selected-fill and disabled states, check semantic action
availability, and activate the enabled row with Enter. Two dock tests verify
the declared ground. Two caller-owned tests verify exact raw fractional-alpha
preservation for absent/nonopaque grounds. They do not independently certify
all menu profiles or antialiased edge pixels; final capture/native coverage
remains necessary for that broader claim.

The model feature assertion change separates cue presence/clearing from the
canonical raster assertion. It retains actual focus, selection and check-only
assertions and verifies that the previous row clears when navigation moves
focus. Comparing a precomposited fill to the raw token was obsolete. The exact
publisher string transformation was independently reconstructed in memory and
matches the current final file byte-for-byte (after git's trailing strip).
The sole runtime-to-final changed path is this feature test; production sources
and the capture/replay contracts are unchanged.

The existing final-tree preflight JSON currently has all13 results `ok` and
matches final tree03c31b58. This review did not execute or substitute those
checks. Existing GPU receipt is passed,84/84 assertions,48 screenshots,
unchanged binaries, no owned fixture PIDs, and runtime4feb/treea32. Existing
Android receipt is passed,15 scenes/41 checks/22 inputs/2 geometry proofs, with
normal restoration/owned shutdown/shared ADB cleanup passed. The Android
receipt contains2 preserved dumpDiagnostics entries; it must not be reported
as zero diagnostics or as an input retry. No replay was repeated here.

## Publisher adaptation

`scripts/menu-compositing-publish.py` now points to the correct worktree,
base80a1b16 and fresh menu-compositing destination. Its updated defaults select
the actual menu final108/preservation96/preflight/build/GPU/Android/cleanup
paths; the before cohort is PR57's retained preservation cohort. It selects
the new menu Android/GPU/build/reproduction drivers. The final-tree13 gate,
four exact runtime build hashes, actual PNG dimensions,108 identities,
192 RGBA provider comparisons, normal APK readback, synthetic-data scans and
atomic fresh staging are retained. Final visual counts and means are computed
from actual inputs. The exact current post-runtime test-only guard succeeds.

An initial evidence-gating issue was reported and fixed before staging:

- **Resolved initial finding:** `validate_gpu` originally checked
  individual environment assertions and binary identities, but does not require
  runtime `status == passed`, `exitCode == 0`, `ownedPidsAbsent == true`, or an
  empty `ownedFixturePidsRemaining`. A replay process can finish all assertions
  and then fail during teardown; its wrapper would correctly mark the runtime
  failed, while this publisher could still accept it. Nor does the publisher
  bind the supplied `--gpu-cases` bytes to runtime `manifestSha256` and the
  committed manifest; a different replay contract can therefore be staged
  under a successful runtime receipt. Require successful wrapper/cleanup
  fields and equal runtime/supplied/committed manifest digests before staging.
  Validate the unchanged84-assertion/48-screenshot contract as well, rather
  than accepting any nonempty phone/desktop case list.

The actual currently retained GPU receipt already satisfies those conditions:
manifest SHA256
`3043538f398f175baea933f223c703374925ef30497f7177c0ea91f5cfb2a078`,
statuspassed, exitCode0,84/84 assertions,48 screenshots, ownedPidsAbsenttrue,
ownedFixturePidsRemainingempty. This was a missing refusal gate, not a finding
that the actual native evidence failed.

## Publisher fix verification

Parent added the successful wrapper/cleanup checks, before/after identity
equality, and a three-way binding of supplied manifest bytes, parsed manifest
and runtime manifest SHA to the exact committed runtime manifest. Binding that
unchanged committed manifest also retains its84 assertions and48 screenshots.

The actual completed receipt was accepted with2 cases/84 assertions/48 images.
Five independently injected in-memory controls were refused: failed runtime
status; a remaining owned PID; an altered parsed manifest; an altered manifest
file digest; and divergent before/after binary identity. No retained input,
native process, product file or evidence stage was mutated for these controls.
Receipt: `notes/menu-composite-publisher-review.json`; reviewed publisher SHA256
`8802ddfe916891aa4a1a38da765ff3fd6d4f55d861a8a6cc5b1f7096b3a93bd0`.

No blocking finding remains. Parent owns full staging/report execution, final
captures, draft PR58 and any publication/merge decision.
