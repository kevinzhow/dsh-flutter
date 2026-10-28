# Bounded published Toast source contract

This change retains and compiles the published Toast primitive's source inputs.
It introduces `DshToastRecipe`; it does not change a widget, icon, feature caller,
native fixture or application behavior. The implementation lane separately owns
the canonical Toast and the three existing open-in-app/upload notice owners.
Actions, anchors and other notice consumers remain unimplemented/pending.

The pin is DSH `687f282e8625c6b8d11ff58211a90524be2e4317`, published
`@deepseek-ai/dsh-client-ui-primitives@0.2.1-rc.2`. The integrity-verified npm
archive supplies exact `package/lib/Toast.module.css` bytes and the complete
`lib/types/Toast.js` region from `package/lib/index.js`. Extraction never
executes package JavaScript. Source `Toast.tsx` and the actual glyph source are
also hash-locked; they are not substitutes for published archive verification.

| Published input | SHA256 |
| --- | --- |
| archive | `576dc4a46ed55db70ae45b4b956e0d886a5700da32aeaed5bafb478f043f59ff` |
| primitive index.js | `333ea89e7518ec1f1d33111bb9c65d382454bcc3638ebac7116253c92fe5d566` |
| Toast.module.css | `74cab625e372a6cdaff92fa468b7d59bc037212d738e476ea0f8d485e4f8dbcb` |
| complete Toast region, UTF-8 | `c08d10dca4664f1898856239f589321210e06bfff54b88eca4dd10a2667271ed` |

The region includes both timing constants, latest callback, effect dependencies,
timer cleanup, optional icon/success precedence, alert role, body portal,
anchor measurement and the entire action branch. Region whitespace, comments,
literal contents and token boundaries are preserved. Only the two supported
numeric constant values are substituted in the frozen behavior fingerprint.

## Generated schema and sizing ownership

`DshToastRecipe` contains the following source-derived fields. All are intended
for the separate bounded canonical consumer; fields for deferred actions and
anchor behavior are deliberately absent.

| Type | Fields |
| --- | --- |
| double | `top`, `maxContentWidth`, `viewportInset`, `horizontalPadding`, `verticalPadding`, `gap`, `fontSize`, `lineHeight` |
| String | `radiusToken`, `backgroundToken`, `labelToken`, `shadowToken`, `iconLabelToken`, `successIconLabelToken` |
| double | `holdMs`, `fadeMs`, `enterMs`, `enterOffsetY` |
| String | `enterCurve`, `fadeCurve` |

Current values include top40, content cap640, viewport inset48, padding12/16,
gap10, text14/22, hold3000/fade1000/entry160, entry offset−6, and source curve
keywords `ease-out`/`ease`. These are generated values, not page overrides.
The cap applies to the CSS **content box**: add horizontal padding afterward.
Thus a saturated long notice has outer width672 at a desktop viewport800,
and374 at viewport390, with8px outer side margins. Do not turn the content cap
into a640px outer Flutter box or retain24px outer phone padding.

The source centers intrinsically sized content at50% and translates it−50%.
That structural rule, body portal, z-index1100, natural wrapping, grid icon seat,
root alert role, click-through banner and final visibility:hidden remain frozen.
Z-index is not emitted as an unused numeric field: the separate UI host owns
real source-equivalent layer ordering. Radius and shadow reuse canonical theme
contour/material implementations; no Toast-only fitted paint is introduced.

There is no invented font-weight or forced custom glyph size. Source warning
and success glyphs happen to default to16, but their actual asset metadata owns
that size; callers elsewhere use18. The icon implementation lane generates the
real `IconCheckCircleOutlineRegular` artwork. Success overrides a custom icon;
omitting both icon and success produces no icon seat or extra gap. The existing
warning callers must request their warning glyph explicitly when adapting to
the source default.

## Closed CSS and behavior handling

The full logical Toast stylesheet is fingerprinted in source order, retaining
selectors, conditions, declarations and meaningful literal contents. Only
explicit translated slots are masked. Generic/ancestor selectors, custom
properties, new active/conditional rules, structural changes and pending action
rules cannot silently pass unchanged Dart. Every masked value is parsed through
its supported grammar and consumed by the generated recipe.
The Toast input also rejects non-CSS Unicode whitespace in syntactic positions
before the shared reader can trim it into an unchanged selector or unit.
Comments and quoted literal contents are preserved by the existing reader.

The whole animation expressions are parsed, including exact animation names,
hold custom property, forwards fill and the reduced-motion branch. Base and
reduced fade values must agree with each other and the published JS constants.
Supported curve keywords are `linear`, `ease`, `ease-in`, `ease-out` and
`ease-in-out`; unfamiliar expressions fail closed. Reduced motion removes entry
only; the delayed fade and completion deadline remain source behavior.

Numeric parsing reuses the finite ASCII CSS parser. JS literals have an
additional strict ESM lexical gate, retaining the release's `3e3`/`1e3` while
rejecting Unicode digits, legacy leading-zero integers, nonfinite overflow and
expressions. CSS signs, leading zeros, fractions and exponents remain valid
where the supported expression permits them. Length dimensions and text metrics
must be positive; padding/gap/inset and durations may be zero and must not be
negative. Placement/entry offsets remain signed finite values. Theme token kinds
are validated before Dart emission.

The source uses an independent timeout for hold+fade, latest completion callback
and hold-only effect dependency. A new hold resets the JS deadline from its
update while the existing CSS animation receives a new delay; this is not a
fresh display identity. Rerendering with the same hold does not extend lifetime.
Owners remount by sequence for a new notice. The contract freezes all of these
predicates, including deferred anchor/actions, without claiming they are
implemented by this input/compiler change.

## Retention and archive verification

Two new inputs are retained in the existing primitives snapshot: one stylesheet
and `toast-behavior.json`. The primitive decoder independently enumerates its
22 retained outputs and rejects extra or omitted declarations, including either
Toast input. The complete behavior must reconstruct from the integrity-verified
archive; editing/re-hashing a local snapshot or editable lock cannot bless a
different body. Missing or ambiguous Toast regions fail extraction.

The existing13 locked archives now reconstruct88 retained outputs. The exhaustive
source inventory still has57 UI packages and209 source CSS inputs; this one new
retained sheet changes retained CSS36→37 and pending173→172. Those are retention
counts, not implemented component percentages. Parent caller archives inspected
during the audit stay audit references: this compiler does not add them to the
production package count or label their whole source packages complete.

The previous33 recipe maps and Dart classes remain unchanged. New lock/source
bindings refresh generated audit provenance and inventory/theme metadata; no
theme runtime value is intentionally changed. The family migration status and
its current three metric matches stay unchanged until the actual UI integration.

## Verification and remaining acceptance

New source-contract tests first ran against the old compiler and demonstrated
silent acceptance of generic/ancestor/media CSS, behavior/ARIA/portal/lifetime
drift and invalid fields, with no Toast recipe. Focused checks now cover those
negatives, positive geometry/token/curve propagation, JS/CSS/reduced timing
agreement, zero/fraction/exponent boundaries, unique complete region extraction,
exact decoder output coverage and rehashed snapshot drift against archive bytes.
Synthetic archive fixtures contain throwing JS to make clear that no evaluation
is involved; they are not visual fixtures.

Reproduction uses the repository's pinned environment before each invocation:

```sh
python3 -B -m unittest discover -s tool/tests -p test_toast_source_contract.py -v
python3 -B -m unittest discover -s tool/tests -v
python3 -B tool/design-system/generate.py --check
python3 -B tool/design-system/generate.py --check --snapshot-only
python3 -B tool/theme-adapters/build_official_pack.py --check --quiet
python3 -B tool/design-system/source_inventory.py --check
python3 -B tool/design-system/verify_release_inputs.py --cache-dir /persistent/owned/archive-cache --offline
python3 -B tool/design-system/check.py
```

Source-free checks validate retained bytes and bindings; they do not independently
prove source-universe completeness. Final pixel/native acceptance belongs to the
canonical implementation and integration lanes: actual source/Flutter warning,
success and no-icon notices, long wrapping at phone/desktop and fractional DPR,
both themes/locales, motion/deadline/update/replacement, real existing failure and
upload owners, alert semantics, click-through, root portal and layer ordering.
Actions, anchors, other notice consumers, native screen-reader delivery and
backend raster differences remain pending until their own evidence exists.
