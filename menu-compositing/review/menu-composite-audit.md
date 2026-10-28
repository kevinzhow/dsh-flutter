# Menu composition audit — 2026-10-28

Read-only task6 audit. No product, build, native, ADB, font, filter, classifier or threshold changes. Audited final captures in `scratch/whalee-reported-families/build/parity-reported-final/visual-testing-results/{react,flutter}`. Reference DSH commit687f282e8625c6b8d11ff58211a90524be2e4317, published primitives/theme/model-selection0.2.1-rc.2, Chromium145.0.7632.6. Audited scratch head37fbe33; all nine inspected source/CSS files are byte-identical to merged main80a1b160d15b7287789604cef69bc38a6a1fa1ad (`scratch/menu-composite-audit/provenance.json`). Final capture hashes and dominant/corresponding colors are in `scratch/menu-composite-audit/pixels.json`.

## Actual final pixels and state

Inspected all16 root/effort card pairs (desktop/phone, en/zh, light/dark) and visually viewed desktop dark Effort source/Flutter. Both show the same filled Max row/checkmark; root cards have no focused fill. These are the final pointer-away/programmatic-focus captures, not the pre-focus candidate. Desktop card sizes match248×76(root)/248×110(effort); phone enclosing crops match651×200/651×290 at2.625DPR. Desktop metadata gives the same source/Flutter crop rect (root828,664,248,76) and pinned fonts/context.

| Interior | Source RGBA | Flutter RGBA | Scope |
|---|---|---|---|
| dark plain menu |41,42,46,255|41,42,46,255|all root/effort contexts|
| dark focused Max |57,58,62,255|58,59,62,255|desktop+phone, both locales|
| light plain menu |251,252,252,255|251,252,252,255|all root/effort contexts|
| light focused Max |238,240,241,255|238,240,241,255|desktop+phone, both locales|

The dark discrepancy is R/G each+1; alpha is255 in both. Exact corresponding flat fill differences occupy7873 desktop pixels per locale and54552 phone pixels per locale. Root corner/stroke and glyph differences also exist and are separate from this interior-row mismatch.

## Source and Flutter paint paths

Released `tool/design-system/upstream/ui-primitives/MenuSurface.module.css` makes `.surface { isolation:isolate }`; its absolute inset0 `.material` has z-index−1, the source fill, and `blur(40px) saturate(150%)`. Filtering is confined to that material; the row children paint afterwards. The source model CSS `.option:focus-visible` / `.cell:focus-visible` uses the generated `--dsw-alias-interactive-bg-hover`.

Released theme values (`ui-theme/design-platform.css`) are:

- light page#ffffff, material#f8f9fa94, hover#2631480f;
- dark page#151517, material#43454a73, hover#ffffff14.

The hex alphas are exactly148/255,115/255,15/255,20/255. CSS metadata serializes dark material as rgba(67,69,74,0.45); that serialization is not permission to change the authored alpha. `ColorValue.parse` correctly preserves these hex-byte fractions through `Color.from`.

Model MenuSurface reads `--dsw-menu-surface-fill` even in the desktop darwin fixture. The platform stylesheet overrides `--dsw-specific-menu`, a separate token; the final desktop source metadata confirms this model material remains rgba(67,69,74,0.45).

`DshMenuSurface.build` currently preblends the material onto `saturateLikeChromium(theme.bgBase,1.5)` using `blendLikeChromium`, then paints an opaque `DshShadowBox`. This yields the observed plain base in both themes. `DshShadowBox` clips its shadows outside the card; they cannot explain a large flat interior row offset. `DshContainer`/`DshDecoratedBox` snap geometry and pass the raw ShapeDecoration paint through.

The canonical `DshMenuItemButton` chooses the correct generated hover token but calls `theme.cornerDecoration(radius,color:fill)` directly. That helper does not invoke `DshSurface.paint`; the raw translucent fill is raster-composited over the already opaque menu. `DshMenuSurface` also does not declare its computed fill as a descendant `DshSurface`. Thus both declaring the true surface and consuming its paint helper would be needed; a wrapper alone changes no row pixels.

## Exact arithmetic for these source contexts

For the dark material, saturation maps page(21,21,23) to rounded(21,21,24). Existing bounded 8-bit composition computes material source shares(30,31,33) plus destination shares(11,11,13), producing(41,42,46), which matches both final images.

For white hover a=20/255 over that base, the existing helper's independent source/destination quantization is:

`round(255*20/255) + floor(base*235/255)`

`=(20+37,20+38,20+42)=(57,58,62)`.

The raw float SrcOver totals are(57.7843137,58.7058824,62.3921569), rounding to the actual Flutter(58,59,62). Alpha quantization alone cannot fix this: #ffffff14 already has exactly20/255. It is the color composition/rounding path, not a wrong hover token or an alpha value needing adjustment.

For light hover the helper gives(2+236,3+237,4+237)=(238,240,241). Float SrcOver also rounds to(238,240,241), explaining why light currently matches despite using the same raw row path.

## Independent pinned-browser diagnostic

`scratch/menu-composite-audit/variants.cjs` mounts the retained MenuSurface CSS over these exact released uniform page colors, with a plain focused-fill rectangle; it changes no production/reference files. Browser145.0.7632.6, DPR1 and2.625, four images and sampled/computed styles in `variants.json`.

| CSS diagnostic | dark base / hover | light base / hover |
|---|---|---|
| source isolated material+filter |41,42,46 /57,58,62|251,252,252 /238,240,241|
| replace only material with derived opaque base; same row |same|same|
| direct derived opaque base; same raw row |same|same|
| remove filter, retain isolated material |41,42,45 /57,58,61|same|
| source material; derived opaque hover |same as source|same as source|

Every result repeats at both DPRs. Therefore preblending the uniform material is not intrinsically forcing the focused-row error: Chromium's same raw hover over that opaque base still matches its real source output. Source filter saturation remains necessary for the blue channel of the dark base. Removing isolation in the negative-z material experiment puts that material behind the body; it changes stacking ownership and does **not** isolate a mere numerical blend effect.

This establishes the observed mechanism in the current uniform opaque-page contract. It is not a universal claim that the helper reproduces every Chromium GPU/color-space path or arbitrary isolated translucent group.

## Bounded correction direction

Keep generated fill/hover values unchanged. The canonical menu surface can expose its genuinely opaque computed material via the existing `DshSurface`; canonical menu rows can consume `DshSurface.paint`/the context outline helper for translucent fills. For these known uniform menus the existing source-derived arithmetic then predicts both final themes without fitted colors. This belongs in shared surface/row components, with a behavioral paint regression grounded in the released CSS and light preservation.

Do not declare a made-up uniform `DshSurface` for a dynamically filtered image/text backdrop. A future real backdrop-filter graph needs either the actual opaque result under the row or a compositor preserving the correct paint order; static preblending cannot represent arbitrary varying pixels. Parent owns that separate implementation. This proposed correction also does not settle corner masks, shadows, text rasterization or the overall99.5 target.
