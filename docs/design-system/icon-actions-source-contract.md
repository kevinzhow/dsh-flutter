# PluginManager action source contract

The IconAction source guard covers the **whole logical PluginManager
stylesheet**, not only selectors containing `.iconButton`. This closes a drift
gap where `button:active { background:red }`, `button { min-width:100px }`, or
an inherited `.page { --dsw-alias-label-caption:red }` override could affect the
actual source button while leaving generated Dart unchanged.

The inputs remain published `@deepseek-ai/dsh-client-ui-plugin-manager`
`0.2.1-rc.2` and source commit
`687f282e8625c6b8d11ff58211a90524be2e4317`. The released CSS string and class
export are statically extracted from the integrity-verified archive, then class
names are unhashed. The actual source input is
`packages/client/ui-plugin-manager/src/client/PluginManagerPage.module.css`.
No package JavaScript is executed by this generator.

## Translated fields and frozen context

`generate.py` declares 29 dynamic CSS property slots. They are the existing
inputs to three recipe maps; no new product style is introduced here.

| Selectors | Supported translated values |
| --- | --- |
| `.iconButton`, `.infoButton` | Width, height, label color; `.iconButton` radius |
| `.iconButton:hover:not(:disabled)` | Hover fill and label tokens |
| `.iconButton:disabled` | Group opacity |
| `.iconButton:focus-visible` | Solid outline's width/color/fallback tokens and offset |
| `.addButton, .addPrimary, .addMore` | Shared radius, height, padding and typography |
| `.addMore` | Divider expression and width |
| `.addMenu` | Width and viewport width limit |
| `.addMenu [role=menuitem]` | Row gap, height and padding |
| `.addMenuItem` | Description gap |
| `.addMenuDescription` | Maximum height, label token and typography |

Each slot still passes its existing scalar, token-kind, expression and
structural checks. For example, making the whole outline dynamic does not
permit a different outline style: the compiler still requires the supported
solid outline expression. Valid changes reach `DshIconActionRecipe`,
`DshAddButtonRecipe` or `DshPluginAddMenuRecipe`. The tests verify that unrelated
recipe maps remain unchanged.

All other rules and values are **retained, frozen context**. The fingerprint
preserves rule order, declaration order, selectors, conditional scopes and the
literal bytes of parsed values. It replaces only the explicit translated slots
in unconditional known rules. It does not strip whitespace inside literals,
ignore custom properties, discard unknown selectors, or infer that a new
generic/ancestor rule cannot affect a button. Added, removed, duplicated,
reordered or changed pending rules fail generation until classified and
translated deliberately.

The locked release has 211 parsed logical rules; the pinned source has 212
because minification combines and rewrites other pending rules. Their full
forms are frozen independently. An exact normalized-release logical form is
also retained for the existing source-comparison API. These are specific
fingerprints, not a general minifier or CSS-equivalence algorithm. The source
role-attribute spelling is recognized only for locating its already supported
menu-row fields; its original selector remains in the fingerprint. Known
source/release button and menu values must still agree under the existing
explicit minifier comparison.

This freezes pending card/layout/style context; it **does not implement those
families** or prove full card, route, state or visual parity. It also does not
evaluate every external stylesheet in the browser cascade. External published
inputs and source identities retain their separate release/source contracts.
An upstream change to frozen context intentionally blocks this generator even
if it might eventually prove unrelated to IconAction.

## CSS-to-Flutter numeric boundary

The shared scalar parser follows the ASCII numeric-token grammar in
[CSS Syntax 3's number algorithm](https://www.w3.org/TR/css-syntax-3/#consume-a-number)
and its [digit definition](https://www.w3.org/TR/css-syntax-3/#digit).
It accepts ASCII signs, leading zeros, fractions and exponent notation. Thus
`028px`, `+.5`, `-003px` and `1e2px` are valid supported scalars; fullwidth or
Arabic-Indic digits are not CSS numbers. This is not the stricter JavaScript
integer-literal grammar. Conversion must also produce a finite value.

All numeric values in the 29 translated property slots use that gate. The
divider percentage uses the scalar parser instead of direct Python `float`;
its width must be nonnegative and its percentage in `0..100`. The menu viewport
literal is also validated before the menu compiler's existing narrower
expression parser converts it. Unsupported expression forms still fail closed.
This blocks invalid Unicode and overflow without changing current generated
values or translating an arbitrary new CSS expression.

IconAction and info width/height must be finite and strictly positive before
Dart emission. Negative CSS widths are invalid/ignored by a browser; emitting
the same negative scalar into Flutter constraints is unsupported. Zero-sized
actions likewise require an explicit implementation decision. Fractional
positive dimensions remain supported.

Disabled opacity must be in the shared `0..1` domain, including both endpoints.
CSS clamps out-of-range opacity, while Flutter `Opacity` rejects it; this
compiler rejects the unsupported source input rather than silently emitting
an invalid value or claiming to implement CSS clamping. Outline offsets remain
finite signed values: valid negative offsets are not rejected as negative
geometry. Decimal overflow is rejected for dimensions and outline offset.
This bounded change does not extend range validation or behavior coverage of
unrelated recipes.

## Validation and unchanged outputs

`tool/tests/test_icon_action_source_contract.py` first reproduced 36 missing
rejections on the pre-fix generator. The final 15-test file, including the
overflow regression, records 37 failing assertions and no errors against that
same base; all 15 passed with the first hardening. The numeric follow-up
reproduces three Unicode-number rejection failures on that first version and
extends the passing suite to 22 tests. It covers generic active
and size rules, ancestor/custom-property changes, conditional generic rules,
pending values/literals, order/duplicate/missing rules, existing state/property
and token-role gates, numeric boundaries and valid field propagation.
The numeric cases include valid leading-zero/signed/fractional/exponent forms,
opacity endpoints, direct divider/viewport inputs, nonfinite conversion and
collateral primitive-button compatibility.

On the unchanged real inputs, both generated Dart and `recipes.generated.json`
remain byte-identical. Full Python tests, actual-source generation checking,
the existing family guard and actual 13-archive / 85-output verification are
run separately from UI/native acceptance. No lock, snapshot, inventory,
generated output, family policy or product widget changes are part of this
hardening. The existing icon adoption's guard reduction remains 895 to 892
numeric matches, four to zero duplicate-button matches and unchanged eleven
platform-control matches; those counts are not completed component coverage.

From a configured checkout, use the absolute environment script for the pinned
toolchains, then run:

```sh
python3 -B -m unittest discover -s tool/tests -p test_icon_action_source_contract.py
python3 -B -m unittest discover -s tool/tests -p 'test_*.py'
python3 -B tool/design-system/generate.py --check --src "$DSH_SRC"
python3 -B tool/design-system/generate.py --check --snapshot-only
python3 -B tool/design-system/check.py
python3 -B tool/design-system/verify_release_inputs.py \
  --cache-dir "$DSH_RELEASE_CACHE" --offline --receipt "$RELEASE_INPUT_RECEIPT"
```

The archive cache and receipt paths must be supplied explicitly; offline mode
revalidates existing archives and does not download missing ones. Current
generator behavior and source drift checks are not a substitute for root's
final UI, build and native validation.
