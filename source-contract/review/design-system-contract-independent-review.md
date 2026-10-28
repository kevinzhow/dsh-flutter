# Independent design-system contract review — 2026-10-28

Reviewed final clean integrated head
`9e885323416526664a510bf77d84b7b049aaa450`, tree
`18e41cef957ec5ae3181609c418a16aa3687872e`, in
`scratch/whalee-design-system-contract`. Initial review was at ebc28f6, including
the preflight/docs wiring. The archive-output finding and typed-token follow-up
below were fixed and independently rechecked at the final head. No apps/,
features/ or packages/ runtime paths differ from main
`ac8d066aa10802679e5e7c3c1d897c1bea613981`.

No blocking finding remains. The initial missing refusal gate is preserved
below with its final verification, rather than omitted from the review history.
Only this note is written. Read-only probes use in-memory metadata copies and
the existing archive cache; no tests, builds, native replay, network fetch,
repository code or retained evidence are changed.

## Resolved: declared locked files need complete decoder coverage

At the initially reviewed ebc28f6:

`tool/design-system/verify_release_inputs.py:157–179` delegates reconstruction
to published.verify_snapshot and then reports `len(package['files'])` as the
number verified. The decoder does not enforce that its output set equals that
declared file set:

- For plain-files, `published.py:266–271` iterates archiveFiles rather than
  requiring its keys to equal files. Omitting a CSS mapping leaves that retained
  CSS outside archive comparison. In-memory removal of dockkit.module.css from
  the actual dockkit archiveFiles map still returns verified=true and reports
  all3 snapshot files, using the unchanged real release archive.
- For fixed bundle decoder branches such as plugin-css, an additional declared
  file is ignored. Adding `unverified-manual-style.json` to a copied actual
  plugin-manager files map still returns verified=true and reports5 files,
  while that decoder reconstructs only its fixed4 outputs. The probe even
  succeeds without the extra file existing at that lower-level verifier call.

The complete top-level inventory gate does require declared files to exist and
match the editable lock. That does not close this finding: altered CSS and
its recorded hash can agree, while an omitted archiveFiles mapping prevents
the independent archive comparison. Updating the editable ledger consistently
then passes its snapshot-only consistency check. This defeats the central
promise that editing a snapshot and its recorded hash together cannot bypass
the released archive check. Full source mode adds separate source comparisons,
but source-free CI deliberately cannot rely on those.

The requested correction was exact declared-file coverage before reconstruction:
plain
archiveFiles keys must equal files keys, and every static decoder kind must
have an exact validated output-name set, including metadata and behavior
JSON. Unknown or omitted names must fail. Count verified outputs from that
validated set. Add negative controls for both omitted plain CSS mapping and
extra declared bundle output, alongside the existing rehashed-CSS mutation.
No package code execution or extraction to disk is required for this fix.

This was a missing future refusal gate, not a finding that the original13
packages/83 snapshot inputs were incorrect.

At final9e885323, every decoder branch returns the exact set of reconstructed
output names, rejects a differing declared set, and the receipt counts those
returned names. Plain archiveFiles keys must equal files keys. Independently
replaying all13 actual cached archives exercised all10 extraction kinds
(sidebar-component-css has4 packages), returned83 exact outputs and left the
worktree clean. The three in-memory metadata controls now fail with explicit
coverage errors: missing dockkit CSS map, extra plugin-manager output, and
omitted plugin-manager classes.json. No network, package execution or file
mutation was used for those controls.

## Generator behavior and compatibility

The12 new fixed SegmentedTabs declarations, inset/padding relation, shared
indicator/tab radius, duplicate-state rejection and required exclusive
reduced-motion rule close the demonstrated older fail-open cases. The positive
geometry test retains valid source-derived changes. Current generated Dart and
theme/runtime data remain unchanged.

Required token references now reject nonexistent theme names. The narrow
statistics separator exception correctly preserves published CSS behavior:
`.sep` references undefined `--dsw-alias-separator-primary`; CSS inherits color,
and the existing StatPillView optional colors lookup falls back to the inherited
pill text color. This is source semantics rather than an invented fallback for
a required recipe field. Allowing a different undefined variable at that exact
CSS color declaration preserves the same inheritance behavior; the published
archive/source gates still establish which declaration is actually released.

The initial typed-token follow-up was also resolved at final9e885323. A
post-metrics role check now distinguishes colors, numbers, shadows, typography
and strings. Independent source mutations reject color←number, radius←color
and shadow←color with token-kind errors. All198 current token fields validate:
133 colors,27 numbers,27 typography,3 shadows,3 strings and5 explicitly
unresolved references. Each resolved name is available with its expected kind
in both current modes. The unresolved set is precisely4 focus references whose
source declares a fallback, plus the inheriting statistics separator above;
the fallback token fields are themselves validated. No required arbitrary
unknown reference is exempted by that set.

`published.verify_packages(source)` now checks the actual source Git HEAD
against referenceCommit after its existing package/source checks. Inventory's
full-source path additionally requires a clean checkout. The supplied
same-bytes/different-commit test is meaningful. Snapshot-only mode intentionally
does not make this source-checkout claim.

## Policy guard integration

The integrated guard is consistent with the bounded independently tested
change. It validates policy shape and duplicate keys, rejects removal/editing
of existing patterns, shrinking family/canonical coverage, new whole-file
exemptions and growth inside existing exemptions. Additive new rules and actual
debt reductions remain possible; legacy inspection/test APIs remain compatible.
Banners is explicitly pending. The six spare metric slots were removed;
the899 existing metric occurrences,11 raw controls and4 known button duplicates
remain historical debt. This work neither removes899 styles nor proves that
all possible Dart styling expressions are source-derived.

## Source ledger and retained inputs

The ledger distinguishes source retention from implementation. Its current
scope is57 UI packages,209 UI CSS inputs,36 retained CSS bindings and173 pending
inputs;9 CSS-free UI packages have explicit source evidence. There are also9
support-style packages with10 CSS inputs. These are inventory counts, not
component or state-acceptance completion counts.

The source path discovers workspace manifests and dependencies from the actual
pinned checkout, preserves runtime versus build-only reachability, rejects
unresolved workspace dependencies, inventories CSS for all discovered public
UI packages, and requires explicit classification of unknown CSS-free UI
packages. All301 current package-manifest/CSS/classification evidence paths
were independently checked to exist in the pinned Git tree. Full checks
regenerate and compare the complete ledger; snapshot-only checks explicitly
cannot re-establish the source universe. The docs retain this ceiling and
exclude inline styles, SVG and state acceptance from the ledger's claim.

Archive reconstruction binds locked package/version/URL/integrity to the
publication record and compares actual archive manifest dependencies. It checks
integrity before/after decoding, preserves bad cache entries, publishes only
verified missing downloads atomically and never executes JavaScript. Complete
declared-file coverage now also passes the independent checks above.

Remaining inherited limits should stay explicit: one legacy missing
extractionKind still selects plugin-css by default; the ledger is not a
family→recipe-field→production-consumer implementation ledger; count-based
legacy style allowances remain. These have not been represented as complete.

## Cold source-free CI and preflight

The preflight order is archives → recipes → inventory → guard. It stops after
the first failure and concatenates every executed command's output, preserving
the explicit source-free ceiling instead of discarding earlier logs. CI can
reconstruct locked archives and validate retained snapshots without DSH source,
npm installation or package runtime. Its absent-source flag is selected for
both recipe and inventory commands; actual source mode checks the pin.

All21 design-system Python scripts plus preflight parse under Python3.12's
grammar. Their relevant Path, urllib, concurrent-futures, hashlib, tarfile and
atomic-file APIs exist in Python3.12; the decoder uses extractfile rather than
version-sensitive extractall filters. Hosted Ubuntu supports the same-directory
hard-link publication used by the cache. Cold CI needs public npm HTTPS access
and available exact archives; missing or corrupt inputs fail rather than skip.
The30-second per-request timeout and64MiB download limit are explicit. The
cache is repository-local by default and configured separately from SDK caches.

This review does not claim an actual cold Python3.12 Actions/network run. The
initial retained local191-tool-test log was green; the parent additionally
reports194 focused tool tests and successful final source/archive/generation
checks after the correction. Parent owns the final exact-tree full13 run,
publication and PR decisions. This review approves the bounded tool contract;
it does not claim that899 styles were removed or that source retention proves
component implementation or visual acceptance.
