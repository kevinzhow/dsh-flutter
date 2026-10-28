# Card clamp repair: independent final review

PASS for the bounded repair at
`6d986e98f26304b20c7c7593154382704ac18429`, tree
`50f715ee3e21ee3fc320d5af4c8781d9a2dceeb4`, k172, 2026-10-29.
The prior Noto unbroken-word blocker is **resolved**. The earlier final2
min/max comparison failure is historical and must not be cited as a hold on
this commit. I found no additional blocking defect in the reviewed scope.

## Exact implementation boundary

I read the eight-path change from0581 to6d. The canonical helper collapses
only ASCII CSS whitespace, measures the original first wrapping line, and
removes complete graphemes from that line only when adding the ellipsis.
It never pulls a prefix of the next original word onto line1. The prior ASCII
whole-final-word regex and broad Unicode trim are gone.

The sole-run decision now compares two minimum-intrinsic calculations: an
end-space measurement of the original normalized text and a measurement-only
copy joined with U+2060 between complete grapheme clusters, also with the same
end space. Both use the same style, locale, direction and scaler. The rendered
text and full semantics never contain inserted joiners or the end-space probe.
No epsilon, glyph-width offset, pixel-rounding threshold or source font change
is used.

This corrects an observed SDK problem with the prior min/max comparison:
pinned Noto reported393.614227 versus393.614349 for the same unbroken string.
Flutter delegates these values to SkParagraph. The pinned Skia
[ParagraphImpl source](https://raw.githubusercontent.com/google/skia/8df24be66531469e576a806749a0202ae26b8d08/modules/skparagraph/src/ParagraphImpl.cpp)
also documents that minimum and maximum widths use different calculations and
can round differently. The new decision compares the same quantity instead.

Card description alone calls the helper. Title nowrap behavior is untouched.
Rendering remains through `DshChromeText`, with clip and complete original
semantics. The parity geometry locator accepts that full semantics label when
finding a shortened description; it does not alter layout or scoring. The
source-contract check now rejects line-clamp2, because this consumer supports
exactly one line. No generated recipe value changed.

## Pinned-font shaping proof

Own probe:
`scratch/plugin-card-integration-review-probe/clamp_shaping_test.dart`.
It imports the current actual canonical widgets through the product's package
path and loads these pinned files:

| Input | SHA256 |
| --- | --- |
| NotoSans-Regular.ttf | `89c3c497f618fdaa0b2d1e98fef93582f28c71debd2c4a8cdf41f190ced2909d` |
| NotoSansCJKsc-Regular.subset.otf | `1007e807974399f50ce8c654e2434fa1283dbeb20a160a931c4c6a742467775d` |

Seventeen cases cover repeated fi, office/ffi, AV/VA kerning sequences,
precomposed accents, combining accents, combining marks adjacent to ligatures,
CJK, single/repeated emoji ZWJ clusters, variation sequences, flags, skin-tone
sequences and spaced controls. For every case, the actual end-space paragraph
and its WJ counterfactual painted RGBA-identical images, with nonempty ink in
both. All17 minimum-intrinsic classifications and complete semantics matched
their stated expectations. The real helper was also built for each input.

These are paragraph raster comparisons, not17 new PNG acceptance pairs or a
native app replay. The probe retains changed-pixel/ink counts and exact numeric
measurements. Ligature *sub-selection* boxes can differ with the inserted
measurement characters; they are not used by the decision. Their difference
did not change the full paragraph paint or relevant classifier results.

Raw receipt: `scratch/plugin-card-clamp-shaping/receipt.json`, SHA
`a50993dd1b1fa6b930ca748feb2a5bec492cc9b43348693c7bbcec8430efac33`.
Final log: `scratch/plugin-card-integration-review-probe/clamp-shaping-final.log`.
The earlier shaping run lacked an explicit nonempty-ink assertion; the final
run added that assertion so two empty images could not produce a false pass.

## Whitespace source proof and RED/GREEN

The isolated `scratch/plugin-card-clamp-whitespace/probe.cjs` served the existing
actual published Manager build and styles with synthetic description values.
It verified the known instrumented factory hash
`aef3cde87abbf361ddd33965891403d0580ebcf59ccfe388a6ad69dd56229707`,
reused hash-checked pinned fonts, and allowed only its own loopback requests.
Source224 and all existing evidence were untouched. Chromium145.0.7632.6
reported no page errors or external requests and disconnected after cleanup.

Source spaces, tab, newlines and their mix retain a description element of
height0. The Card still keeps the source gap4; its title is therefore2px above
the absent-description case. NBSP is retained as a real18px line. These are
actual DOM measurements, not an assumption that all whitespace is equivalent.

The own Flutter probe captured the pre-fix18px whitespace line box and failed
the zero-height expectation. That receipt/log are preserved as
`flutter-before-empty-fix.{json,log}` in the whitespace directory. After the
root's helper-only zero-height wrapper, the same probe passes: collapsed
whitespace and empty text measure0, NBSP remains18, and Card keeps the2px title
difference from an absent description. The owning description branch and gap
remain intact. This headless host does not pin DPR, so I compare the
line-height/gap consequence, not its absolute frame rectangle against the
source DPR1 rectangle.

Source receipt: `scratch/plugin-card-clamp-whitespace/source.json`, SHA
`c1d681835b3e02e2fb5f974323d91c6b02e61af446c7ee5fcee1a0bea2b8e706`.
Fixed Flutter receipt: `scratch/plugin-card-clamp-whitespace/flutter.json`, SHA
`dfe6f1804422d8d65402993800821d49bc40bfb3d51d403f7c004aeb5476f1c5`.
Green log: `scratch/plugin-card-integration-review-probe/clamp-whitespace-green.log`.

## Scope and remaining limits

Machine summary: `scratch/plugin-card-clamp-shaping/review.json`, SHA
`eecda1595b52c9275cb5c9bda45ba9016a74fbc9bbb934e998e26bc279a5aa35`.
It binds the exact reviewed helper/Card Git bytes, font hashes, raw receipts
and final probe logs. The root's source-controlled13-case final3 Noto probe
also records the complete sole unbroken input with clip and the expected
word/accent/CJK elisions; its earlier final2 failure is superseded.

This bounded evidence does not certify every Unicode line-break context,
discretionary hyphen, mandatory separator, bidi layout, font or fallback.
Emoji measurements use the selected fallback of this font stack, whose platform
emoji artwork identity is not certified here. No such general coverage claim
is required to accept these measured source controls. Header/Icon pending
issues, highlight lifecycle, sticky touch hover and native image formats remain
separate.

I changed no product, source input, index, native fixture, application build or
existing capture. Own writes are the external probes/receipts and this note.
Every toolchain invocation sourced the absolute workspace `scripts/pr16-env.sh`.
Only bounded headless tests/source diagnostics ran; final full checks, rebuilt
native applications and source/Flutter224 acceptance remain the root's work.
