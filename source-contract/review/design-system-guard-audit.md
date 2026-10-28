# Design-system generator/guard audit — 2026-10-28

Reviewed primary main `ac8d066aa10802679e5e7c3c1d897c1bea613981`, tree
`03c31b58f212046cb82e1d9bc79d67081ba78115`, for task20. Kevin's directive
`#dsh de915b41` requires design-system derivation for every component. Current
passing checks establish a partial migration and a count ratchet; they do not
establish that stronger invariant.

Only this note is written. No product/test/build/native changes or network
requests occurred. Audits and mutation probes used read-only source and deep
copies in memory with the absolute pr16-env.sh sourced. For generator probes,
the final Dart formatter call was replaced with an identity function; no Dart
process, generated output or committed test was executed/changed.

## Measured existing exceptions

| Item | Current value |
|---|---:|
| Production Dart files scanned by check.py |531|
| Files with nonzero ratchet findings |137|
| Actual / budgeted manual-metric matches |899 /905|
| Raw platform-control matches outside wrapper allowances |11|
| Duplicate DshIconButton matches |4|
| Whole-file platform wrapper allowances |2|
| Files omitted solely by the `.g.dart` suffix |33|
| Declared families |16|
| Canonical path entries / unique files |29 /27|
| Inventory-only families |5|
| Families with empty canonical list |1: banners|
| Generated recipe classes / fields |29 /666|
| Locked packages |13|

The six spare metric slots are one in
`features/dsh_feature_commands/lib/src/popup_view.dart` (11 allowed/10 actual)
and five in `packages/dsh_ui/lib/src/dsh_settings.dart` (20/15). They permit new
hits immediately without increasing any baseline.

The two platform wrapper allowances are dsh_text_field.dart (one actual native
control) and dsh_settings.dart (zero actual matches, stale allowance). Their
allowance has no occurrence, symbol or expression bound.

The regex does not recognize common styling syntax. Across scanned files there
are500 EdgeInsets constructor matches,43 Color constructor matches and48
FontWeight enum matches outside its vocabulary. These are syntax counts, not
proof that each occurrence is wrong: many belong to existing source-backed
renderers. Other agents own the individual styling/consumer inventory.

## 1. Count ratchets do not freeze existing styling

`tool/design-system/check.py:24–50` scans only six regex patterns, then compares
their per-file counts. Editing width12 to999, or removing one styled widget
and inserting another in the same file, does not increase the count. The guard
also accepts these in-memory examples with zero findings:

```dart
const localSize = 999.0;
SizedBox(width: localSize);
final c = Color(0xff123456);
Padding(padding: EdgeInsets.all(29), child: child);
```

Named-property matching also omits letterSpacing, fontWeight, duration, border
width and most inset forms. Merely expanding the numeric regex leaves local
constants and expression aliases outside it. Thus899 matches are a lower bound
on legacy debt, not a complete exception ledger.

`sources()` skips every `.g.dart` file without checking generator ownership.
The33 current files have other generator roles; this guard alone also permits
a newly handwritten file with that suffix. Existing codegen checks for known
outputs are not an ownership declaration for an arbitrary new output.

Minimal enforceable transition: replace count allowances with exact existing
finding fingerprints (file, enclosing symbol/property, normalized expression
and resolved const value), each marked legacy debt. No new fingerprint and no
changed resolved styling value may appear without a registered source-derived
recipe. Removing legacy findings must remove their allowance immediately.
Use Dart AST/resolved constant expressions for styling sinks; this is needed
for named constants and aliases, not only literal regexes. Start by eliminating
the six spare slots and stale wrapper exemption. Source-derived layout math
must be classified and traced, not automatically excused as arbitrary code.

Meaningful tests: changing an existing allowed value fails; replacing one
exception with a different one at equal count fails; a local const alias fails;
comments/formatting-only edits pass; replacing a legacy expression with the
registered canonical recipe passes and retires its exception.

## 2. The guard's own policy can be silently weakened

`check.py:53–64` checks only numeric baseline growth. It does not constrain
changes to patterns, wrapperAllowlist, family names, canonical lists or schema.
Three independent in-memory amendments to the actual current contract all
produced zero inspect failures AND zero baseline-history failures:

- Replace manual-metric's regex with `(?!)`.
- Add every baseline file to a whole-file manual-metric wrapper allowance.
- Delete the complete families array.

Whole-file allowances remove every observed occurrence before counts are
checked. A prose reason alone can therefore authorize unbounded new native
controls in that file.

Minimal contract: validate a closed versioned JSON schema; keep required rule
identities and compare their definitions against the authoritative base; reject
rule removal/weakening, blanket exemption growth and family/profile deletion.
An exception should identify an exact wrapper symbol/constructor and declared
source contract, with bounded occurrences and an owner/removal condition.
Tests should show each of the three amendments is refused, while a stricter
new rule and migration-driven exception removal succeed. These checks assume
the CI checker itself is trusted/reviewed; mutable repository code cannot prove
its own integrity against an actor allowed to rewrite the checker and tests.

## 3. Some generated CSS states are shape-checked but not consumed or fixed

`generate.py:279–301` checks selector/property names for the older Button,
SegmentedTabs and ShortcutKeys schemas. Its structural-value checks are
incomplete for SegmentedTabs. Eleven independent mutations of the pinned
SegmentedTabs input were accepted and emitted byte-identical Dart:

| Declaration | Original → diagnostic amendment |
|---|---|
| `.tabs position` |relative → static|
| `.tabs display` |grid → block|
| `.indicator inset` |4px auto 4px 4px →4px|
| `.indicator pointer-events` |none → auto|
| `.tab background` |transparent → a different theme fill|
| `.tab border-radius` |radius-md → radius-lg|
| `.tab position` |relative → static|
| `.tab justify-content` |center → flex-start|
| `.tab:focus-visible outline` |none →2px solid red|
| `.tab:focus-visible text-decoration` |underline → none|
| hover/selected background |transparent → a different theme fill|

Removing the required reduced-motion rule also succeeds unchanged. Conversely,
adding the same reduced-motion rule to Button is accepted: the conditional
branch does not bind it to its owning stylesheet or require its presence.
A positive tab-height mutation did change emitted Dart, confirming that these
probes distinguish consumed from silently ignored inputs.

This does not imply the pinned current appearance uses the amended values.
It means a later reviewed source/snapshot update can pass generation while
its changed behavior remains unimplemented.

Minimal fix: use the stronger existing menu/tooltip builder pattern everywhere:
track consumed `(sheet, selector, condition, property)` inputs, and require every
unconsumed input to equal an exact pinned structural contract. Require the exact
rule multiset, including conditional ownership, presence and duplicate checks.
Every consumed input must either change generated data or be an explicitly
checked invariant. Add rejection tests for the11 ignored declarations and the
two conditional cases, plus positive numeric/token propagation tests.

## 4. Unknown/incorrectly typed theme tokens reach runtime

`generate.py:38–42` validates only `var(--name)` syntax. Mutating primitive
primary background to `var(--dsw-does-not-exist)` is accepted by render and
emits that unknown primaryToken. `DshThemeData.color/number/textStyle` throws
for unknown or wrong-type tokens; this becomes a later runtime error rather
than a generation failure. This is not a runtime silent color fallback.

Require each emitted token field to declare its kind and resolve in the exact
generated theme contract for all applicable modes/platform scopes. Preserve
source-defined CSS fallback expressions explicitly; do not invent replacements
when a source input or token is absent. Tests should reject missing tokens and
a typography/number token supplied to a color field, while valid source tokens
propagate unchanged.

## 5. Provenance verifies editable snapshots, not archive reconstruction in CI

`published.py:216–240` verifies snapshot SHA256 against sources.lock.json,
published manifest identity and, when supplied, reference versions/dependencies
and selected source hashes. This is useful and already prevents ordinary stale
files. However:

- `verify_packages` does not call the archive-integrity/extraction verifier at
  lines243 onward. Neither the design-system preflight nor its normal CI path
  reconstructs snapshots from the SHA512-locked published archives. Editing a
  snapshot and its lock hash together defeats that provenance layer in
  snapshot-only mode.
- No source-checkout Git identity is compared with referenceCommit. The commit
  is copied into provenance, while only selected file hashes are compared.
- `tool/preflight:134–142` automatically chooses snapshot-only when the source
  manifest is absent. CI lacks the reference checkout. The generator's success
  text nevertheless says consumer dependencies and CSS agree, without exposing
  which checks were actually possible.
- One package, ui-plugin-manager, has no explicit extractionKind or
  referenceSourceSha256 map. `verify_snapshot` silently defaults a missing kind
  to plugin-css. Its currently consumed button/menu CSS still has explicit
  source comparison; this is a schema/provenance gap, not proof its existing
  CSS is fabricated.

Minimal fix: require explicit extraction kinds and complete required source
inputs in a closed lock schema; verify actual source HEAD when source mode is
claimed; record verification mode and which dependency/source checks ran.
For snapshot-only CI, reproduce all13 packages using the existing pure archive
extractors from a cache keyed by locked integrity (fetching exact public
archives when absent), then compare decoded snapshots. A self-authored receipt
containing hashes alone does not replace archive reconstruction. No JS
execution is necessary. Include generated extractor identity and snapshot
identity in evidence.

Meaningful tests: changing snapshot bytes AND their declared hash still fails
against the unchanged archive; wrong archive integrity fails; wrong source
commit fails despite matching selected files; missing/unknown extraction kind
fails; omitted required source input fails; snapshot-only reports dependency
verification as unavailable rather than silently claiming it ran.

## 6. No machine link from families to recipes to real consumers

The16 family entries contain only names, canonical file paths and prose. The
guard checks file existence. There is no symbol, profile, generated recipe,
source selector, actual production consumer or required reference-state map.
Five families remain explicitly inventory-only (cards, list-rows, empty-states,
toasts, banners). A canonical file can remain present while its implementation
stops consuming generated recipes, and the guard still passes. New components
can be omitted from the inventory entirely.

The recipe audit has source/sheets/metrics but no per-field derivation table
for its666 fields. The13 `metrics.update(...)` merges also do not reject a
duplicate recipe class before overwriting it. Existing strict extraction and
visual evidence establish many fields' derivation; they are not a machine
enforced field-to-source or consumer-to-family closure.

Minimal next schema: family/profile → canonical Dart symbol → generated recipe
classes/fields → locked input selector/property/condition or exact behavior
fragment → production consumer symbols/entries and reference-state evidence.
Require unique recipe ownership and unique merge keys. Register every generated
output by its actual generator/check command, not its filename suffix. Detect
unregistered production styling consumers/new canonical widgets, missing
declared symbols, unused recipe claims and unresolved pending profiles.
Pending must be a machine-readable incomplete state; it must not satisfy a
claim that every component has migrated.

Tests should remove a canonical recipe use while retaining its file; add an
unregistered consumer; omit a family/profile; collide two recipe class names;
and add a handwritten `.g.dart` file. All should fail for a specific missing
source/owner mapping. Existing canonical source-backed consumers should pass
without changing their styling or visual measurements.

## Implementation priority

First close silent generator values/conditions and typed-token validation;
these can strengthen the contract without repainting components. In parallel,
freeze exact legacy exceptions and prevent policy weakening. Add archive/source
verification-mode honesty and unique recipe ownership. Then grow the typed
family/consumer ledger using the other agents' audits. These are guard and
provenance milestones;899 known metric occurrences and the inventory-only
families must remain explicitly incomplete until actually migrated.
