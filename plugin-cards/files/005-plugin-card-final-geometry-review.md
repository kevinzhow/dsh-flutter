# Loaded PluginCard final source/geometry review

The 0581b8450cf12ed958b9f51f5ab357f7fb45e1a6 candidate, tree
7146bcb95f2ef9f88a6ea1e937d283f276ed4f8a, has one reproduced rendering
regression: description elision consumes a partial next word that the actual
published source places on its second, clamped line. This is a text-selection
behavior difference, not glyph antialiasing or incorrect outer geometry.
Root is fixing it before the PR. The 0581 captures remain diagnostic evidence;
this note does not certify the later replacement candidate.

The completed normal-provider output is
`scratch/whalee-plugin-cards/build/parity-plugin-cards-final1`. All 224 raw
source and Flutter metadata files were read, including the actual DOM and raw
Flutter component rectangles. The fixed non-text 99.5% target is reached by
**166/224**, with **224/224** matching screenshot dimensions. Arithmetic means
from the individual rows are non-text **99.59072767857143%**, RGB
**99.82724107142857%**, and exact-pixel **98.90574553571427%**. The vendor's
`pass=224` is a separate, looser status, not the fixed-target count.

There were no part-presence, switch checked/disabled, hover, focused-title or
visible-focus-cue disagreements across these 224 measured states. Source and
Flutter card geometry agree to source serialization precision: the maximum
card-height delta is 0.000004722959 logical pixels and card-width delta
0.000007266091. The largest title intrinsic-width delta is 0.0107421875.
These are observations, not a new acceptance tolerance. The long English tag
case retains the actual natural 112px card, with the description at y334 and
all four status tags on their source rows. Metadata error cards retain the
source 102px natural height and separate 36px diagnostic region.

## Concrete description regression

The actual source at `packages/client/ui-plugin-manager/src/client/
PluginManagerPage.module.css:347` uses normal whitespace and a wrapping
`display:-webkit-box`, `-webkit-box-orient:vertical`,
`-webkit-line-clamp:1`, `overflow:hidden` description. It is not the title's
`white-space:nowrap;text-overflow:ellipsis` contract.

The candidate's `packages/dsh_ui/lib/src/dsh_plugin_card.dart:219` instead
uses `DshChromeText(maxLines:1, overflow:TextOverflow.ellipsis)`.
`dsh_text_baseline.dart:254` forwards these arguments directly to `Text` and
has no wrapping-CSS-clamp mode. In the raw pair
`components.plugin-card.long-tags-idle-phone-dpr1-en.dark`, both description
boxes are exactly `[88,334,228,18]` and contain the same complete input.
The source paints `A deliberately long synthetic…`; Flutter paints
`A deliberately long synthetic descri…`. The extra next-word prefix cannot be
explained by the measured title advance differences or antialiasing.

## Browser-derived clamp boundary

The isolated `scratch/plugin-card-elision-audit/` probe serves the **existing
0581 actual-published Manager bundle and styles**, without rebuilding or
rewriting them. It changes only synthetic description input and viewport
width. Fonts are byte-checked against the same pinned manifest. The browser
is Chromium145.0.7632.6; external requests and page errors are absent, and the
browser/server are closed in `finally`. Source captures in the final224
folder were untouched. Each probe line is saved as an unscaled PNG of its
actual source element, together with computed style, per-character DOM
rectangles, scroll dimensions and canvas text advances. Those diagnostic
crops are not fitted acceptance images.

`source-browser.json` contains the first eight cases;
`source-browser-extended.json` contains thirteen cases after the targeted
extensions. Both record the raw input identities. `audit-receipt.json` binds
this review's score summary and probe file hashes.

| Synthetic source input / description width | Actual source outcome |
| --- | --- |
| Long final224 description /228 | Natural first line ends after `synthetic`; adds ellipsis there, without pulling `descri` from line2 |
| `Alpha beta gamma delta epsilon` /115 or100 | `Alpha beta…`; later-word prefix is not pulled onto line1 |
| `Alpha beta gamma delta` /66 | `Alpha be…`: last **existing** first-line word may be cut by grapheme to make room for ellipsis |
| `Alpha éclair résumé naïve` /76 | `Alpha écla…`: accented existing word is cut, not removed as a whole |
| `你好世界你好世界` /52 | `你好世…`: complete existing CJK characters are removed to fit ellipsis |
| Sole long unbroken ASCII word /100 | One overflowing natural line, scrollWidth394/height18; **clips without ellipsis**, including partial edge glyph |
| Same oversized first word plus ` tail` /100 | Two natural lines, scrollHeight36; first line is truncated with ellipsis |
| `abcdefghijklmnop tail` /100 | Same oversized-first-word rule; ellipsis is present |
| Double spaces, tab and newline /100 | CSS normal whitespace collapses them; paints `Alpha beta…` |
| `Short` /228 | Complete value, no ellipsis |

## Bounded canonical repair

The existing unreferenced `dsh_single_line_clamp.dart` has the basic
wrap-first idea, but should not be adopted unchanged. Its ASCII final-word
regex removes a whole existing word when ellipsis does not fit, contrary to
the66px/76px actual-source cases. Measuring raw whitespace also contradicts
CSS normal collapsing. Finally native paragraph fallback wraps an oversized
single unbreakable run, whereas source normal wrapping leaves it on one
clipped line.

For the measured boundary, normalize CSS ASCII collapsible whitespace before
layout; distinguish a sole unbreakable run using the native intrinsic
boundary; otherwise measure the original wrapping first line without a
max-line ellipsis; add ellipsis and remove complete graphemes until it fits.
Do **not** re-wrap `firstLine + ellipsis` to select a new word boundary, and
do not pull letters from line2. Render the selected value through
`DshChromeText` using the existing generated style/baseline and
`softWrap:false, overflow:clip`. Keep the complete original input as its
semantics label. The one-run branch paints the full normalized value with
clip, preserving an edge glyph rather than forcing a new line.

Use the canonical helper only for the source-clamped description. The title
has a different nowrap contract and must retain its existing behavior.
Geometry measurement must recognize the complete `semanticsLabel` when
finding the shortened `DshChromeText`, and still record the full original
text. The source-proven tests need actual fitted and nonfitted words,
accented/CJK/grapheme inputs, whitespace, a sole oversized token and an
oversized first token plus another word. No font, size, threshold, baseline
constant, capture fit or scorer change is justified.

Other Unicode line-breaking, nonbreaking space, bidi, locale-specific segment
break transformation and platform text-engine behavior should not be claimed
closed merely by the Latin/CJK source controls above. Highlight, post-touch
sticky hover and native artwork formats remain separately pending. No source
product, Git index, native process or application build was changed in this
read-only review.

## Replacement 4e4b6566 review

Independently reviewed the replacement224 images and all448 metadata files at
`scratch/whalee-plugin-cards/build/parity-plugin-cards-final2` on
`4e4b656612bdf02f1925c672ea0e49265d5e9567`, tree
`453e3cfca2a95d7ee8b3c2c5872621d172c27b49`. The slow comparison summary was
still pending at this read, so the previous166/224 score is **not** asserted
for this replacement.

The actual long English phone pair now paints the same word boundary:
`A deliberately long synthetic…` in both images. The original full value is
still passed to `DshSingleLineClamp`, whose rendered `DshChromeText` keeps
that original as `semanticsLabel`. The canonical card's independent action
still supplies the complete description as its `semanticHint`
(`dsh_plugin_card.dart:283`). The measurement callback deliberately recognizes
`DshChromeText.semanticsLabel` as well as its shorter displayed data; it records
the full original description rather than substituting an elided string.
The title retains its separate nowrap/ellipsis path.

All224 measured states have no part-presence, complete-title/description/error
text, tag text/count, switch checked/disabled, hover, focused-title or visible
focus-cue disagreement. Description heights are18px and metadata diagnostic
heights36px in the applicable synthetic scenarios, identical to source. No
new source-proven card geometry or control-state defect was found. Maxima
remain source-serialization-sized for card geometry (height
0.000004722959, width0.000007266091 logical pixels); the maximum title
intrinsic-width delta is0.0107421875. These observations are not tolerance
waivers or a claim of identical glyph rendering.

The current producer's actual-source validator independently passed all224
cases and612 raw input identities. It reconstructed the real published
archive factory and exact export-only hook, checked the current clean source
pin, source-tool Git blob, canonical helper/selected plan, unchanged body/CSS,
fonts, full source matrix, DOM assertions and original PNG hashes. The new
provider is `published-plugin-cards-ze7cgyn2`; its source preparation identity
is exactly4e4b/453e. The plugin-manager archive, bundle and instrumented hashes
remain the exact pinned values recorded above. The provider uses no generic
source cache.

Compared with the0581 diagnostic,64 current Flutter PNG byte identities changed
and221/224 reference PNGs stayed byte-identical. The three source changes are
small actual raster differences **outside the Card** with identical DOM
metadata: default-focus desktop EN light and ZH light each change7 pixels at
`[32,107,155,110]` with maximum channel error1; default-focus desktop ZH dark
changes18 pixels at`[167,57,185,58]`, maximum8. They are retained as observed;
no reference replacement, pixel fitting or scoring adjustment was made.

The clamp repair follows the source-proven wrap-first/grapheme-backtrack,
ASCII whitespace collapse and sole-unbreakable clipping boundary. The
measurement-only word-joiner copy is never rendered. The broader Unicode,
bidi, locale segment-break and text-engine limits remain explicit; highlight,
post-touch sticky hover and native image formats are still pending. This
review ran no classifier, product edit, build, source capture or native replay.
