# Loaded PluginCard source contract

This bounded profile derives the loaded package list/card and status-tag
geometry from `@deepseek-ai/dsh-client-ui-plugin-manager@0.2.1-rc.2`, reference
commit `687f282e8625c6b8d11ff58211a90524be2e4317`. It supplies recipes and a
closed published behavior input for the canonical UI/feature migration. It
does not implement widgets, migrate routes or certify their pixels or input.

The existing `PluginManagerPage.module.css` and class map are unchanged. One
new `loaded-card-behavior.json` retains both complete decoded bundle regions:
`PluginManagerPage.js` and `presentation.js`. Its bundle identity remains
`b4efaa441258a547a0d7b3cab559fe073c69e69fe2bbb617c710ded134e7c4f9`.
The archive SHA512 and full bundle hash are verified before its output is
compared, without executing JavaScript. The decoder must report this output;
omitting it from the lock or rehashing a corrupted snapshot cannot bypass the
archive comparison. The retained release set is now 13 packages / 86 outputs.
The source ledger remains 57 UI packages / 209 CSS inputs, 36 retained CSS /
173 pending. One behavior output is not an additional CSS input or implemented
component. The source TSX, presentation module and original stylesheet each
have an exact pinned-source hash in the package lock.

## Generated schema

Numeric fields are generated doubles; token and prefix fields are strings.
There is no fixed card height or new palette.

| Recipe | Fields |
| --- | --- |
| `DshPluginCardListRecipe` | `gap` |
| `DshPluginCardRecipe` | `horizontalMargin`, `radiusToken`, `hoverToken`, `headGap`, `headPadding`, `iconWidth`, `iconHeight`, `iconBorderWidth`, `iconBorderToken`, `iconRadiusToken`, `iconLabelToken`, `artworkSize`, `mainGap`, `titleRowGap`, `titleFontSize`, `titleLineHeight`, `titleWeight`, `titleMaxLines`, `descriptionFontSize`, `descriptionLineHeight`, `descriptionMaxLines`, `descriptionToken`, `endGap`, `focusWidthToken`, `focusToken`, `focusFallbackToken`, `focusOffset`, `errorFontSize`, `errorLineHeight`, `errorToken`, `experimentalPrefix` |
| `DshPluginStatusTagRecipe` | `contentHeight`, `verticalPadding`, `horizontalPadding`, `fontSize`, `lineHeightFactor` |

The frame width/height are **48 content pixels**, followed by the source
border. Artwork is36. The head gap is14; the gap between trailing controls is8.
They are different source fields. Header padding8, main gap4 and wrapping title
gap8 produce natural height. `titleMaxLines` comes from the closed `nowrap`
structure, while description clamp comes from the explicit CSS line-clamp.
Description weight has no local override and inherits normal text weight;
the duplicate title/open declarations both supply weight500 and must agree.

Status-tag content height18 precedes padding and the canonical Tag tone's
border. At DPR1 an outline tag therefore occupies20 outer pixels while an
unbordered tag occupies18. Its font10/line-height factor1 and padding0/7 are
overrides; all palette, weight, radius and border ownership stay with Tag.
Neither primitive Tag nor Switch recipes change. Fractional border snapping,
content-box composition, the source superellipse contour and extended negative
margin hit ownership require canonical UI and actual source acceptance; this
generator does not fit an outer height to a particular capture or density.

## Closed CSS and behavior

The whole-sheet contract keeps rule/declaration order, conditions, selectors
and untranslated values. The prior 29 button/add/menu property slots remain;
only34 explicitly consumed loaded-card/tag slots are added. Unknown generic
or ancestor rules still fail. Source/published values in the new slots are
compared independently, accounting only for the known source pseudo-element
spelling and existing minifier transformations. The two authored `.cards`
rules and their one published merged rule remain separately frozen full-sheet
forms; this is not permission for general rule merging.

Transparent padding/border/background resets, relative card ownership, the
absolute inset-zero title pseudo-element, separate z-index1 trailing controls,
flex/wrapping/ellipsis, `object-fit:contain`, focus suppression and reason
whitespace behavior remain fixed. Duplicate title typography and card/focus
radii must agree. Numeric parsing uses the shared finite ASCII CSS grammar.
Natural dimensions and typography are positive, gaps/padding/border are
nonnegative, and horizontal margin and outline offset remain signed finite
values. Clamp counts are positive integers. Token roles are checked.

The behavior fingerprint preserves both entire released regions byte for byte
apart from exactly two translated values: `CARD_ARTWORK_SIZE` and the scoped
`packageText` experimental-prefix literal consumed by the adapter. The row-text
prefix and all other presentation/lifetime behavior remain frozen. No regex
removes whitespace from labels, strings or identifiers. An unsupported change
to any predicate, callback, ARIA relationship, image branch, pending highlight
or surrounding manager behavior stops generation.

The complete source functions establish the adapter contract:

- `packageText` falls back to the **full package name** only when metadata
  title is absent; metadata description alone supplies the optional one-liner,
  with absent/empty description omitted. No bundle-description fallback is
  added. Beta uses the generated package-name prefix.
- `packageStatus` is problem when the package error exists; otherwise it uses
  enabled state. Only metadata error supplies the extra diagnostic paragraph.
  Metadata diagnostics do not alter management permission.
- `EnableSwitch` disables for busy, read-only, or an off package with error,
  except missing packages with an install target remain recoverable. It calls
  the supplied enabled callback; the controlled child does not optimistically
  accept host-refused state.
- `updateAvailable` requires installed, removable, non-installation
  availability and a target, then compares version and link-source changes.
  Missing-tag wording depends on installed state. Retaining these full branches
  is not certification of every missing/link/update runtime combination.
- `CardHead` owns the title action and its description ARIA relation; trailing
  controls retain separate ownership. `PackageArtwork` retains a failed URL
  until the keyed URL changes and uses the same source size for fallback and
  image. Browser SVG image success does not certify native image decoding.

The shared `.reason` typography/token is generated only for the card's metadata
diagnostic. This does not migrate its other install/detail consumers.

## Proof and remaining work

The pre-lock generator silently accepted seven complete behavior mutations;
the retained RED log records those failures. Focused tests then verify actual
source values, positive field propagation without changes to unrelated recipe
maps, structural/token/range rejection, complete predicate/callback/label
closure and extraction of both full regions without executing their code.
Archive tests require all five plugin-package outputs and reject omitted,
missing, duplicated or rehashed behavior inputs. Full Python tests, actual
13-archive reconstruction, actual-source/snapshot generation and ledger/family
guards accompany the contract commit. Their receipts/logs are retained in the
isolated worktree's `.local/plugin-card-*` files.

Generated theme runtime outputs and every pre-existing recipe map remain
unchanged; only provenance metadata and these three new maps are added.
The global numeric debt stays892 in this contract-only work. The proposed
12-match loaded-card migration to880 belongs to the UI integration and has
not occurred here.

Highlight CSS, keyframes, reduced-motion branch, HIGHLIGHT_MS, parent scrolling
and lifetime remain frozen and **pending** in the first UI batch. Pending also
includes loading skeletons, official ItemCard/renderSlot content, detail/row/
install flows, sticky touch hover, native tooltip/accessibility bounds, native
metadata image formats and the remaining real-device layout/focus acceptance.
Retained source is not implemented or visually accepted coverage.
