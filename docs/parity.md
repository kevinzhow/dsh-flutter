# Visual parity: dsh web vs dsh-flutter

Pixel parity is measured against dsh's real web client. Both sides render the same fixed case, the two PNGs are diffed
and scored, and a report shows where they differ. Nothing is compared by eye or by hand-made screenshots.

```
case manifest (JSON)                 React provider                    Flutter provider
tool/parity-shared/cases.json   -->  tool/parity-web                   tool/parity_flutter (package dsh_parity)
tool/parity-ext/build-*.py           dsh's real components from the    the real dsh_ui / app widgets in
                                     pinned dsh checkout, Vite host    flutter_test, official theme pack
                                     + Playwright Chromium
                                              \                         /
                                    visual-testing-results/{react,flutter}/<key>.png + .metadata.json
                                                          |
                       vendored raft visual-testing CLI (tool/vendor/raft-visual-testing, FSL-1.1-ALv2, unchanged):
                       validate -> diff --pairs react__flutter (metrics + side-by-side) -> site (HTML report)
                                                          |
                              tool/parity_lib: glue + dsh's non-text/bucket analysis -> summary.md
```

The scoring, side-by-side images and HTML report are raft's own visual-testing tool, vendored unchanged and run as a separate
process (the same way raft-flutter plugs Flutter into raft's official CLI); see
[`tool/vendor/raft-visual-testing/README-VENDOR.md`](../tool/vendor/raft-visual-testing/README-VENDOR.md) for its origin and
license (FSL-1.1-ALv2, not MIT). dsh-flutter adds the two providers, the glue in `tool/parity_lib/vt.py` and the geometry
analysis the CLI lacks.

Two suites, the same split raft-flutter uses:

| | `tool/parity` | `tool/parity-ext/run` |
|---|---|---|
| cases | committed, hand written: `tool/parity-shared/cases.json` | generated every run by `tool/parity-ext/build-*.py` (never committed) |
| themes | light and dark, all of them | light complete, dark sampled to 1-2 cases per surface |
| host files | `tool/parity-web/host/cases/*.tsx` | `tool/parity-ext/host/*.tsx` |
| output | `build/parity/` (`$PARITY_OUT`) | `build/parity-ext/` (`$PARITY_EXT_OUT`) |

Adding a case or a surface: [parity-ext-quickstart.md](parity-ext-quickstart.md).

## Run it

```sh
tool/parity setup                       # once: installs the pinned dependencies under $PARITY_WEB_DEPS (npm, React provider)
                                        # and $PARITY_VT_DEPS (`corepack pnpm`, the vendored CLI's sharp); never global
tool/parity run [--cases 'components.button.*'] [--refresh-react] [--reference native|emulated]
tool/parity summary
tool/parity-ext/run run --cases 'components.button.matrix.*'
tool/parity selftest                    # offline: manifests (dsh schema + the vendored CLI's validate), font pins, builders,
                                        # the CLI's diff on synthetic captures, bucket metrics (tool/preflight runs it)
```

`--reference` is how the React reference gets its device density (below, "What Blink does at a native density"): `native`
(the default) launches Chromium with `--force-device-scale-factor=<density>`, which is what a phone does; `emulated` is
the older Playwright `deviceScaleFactor` emulation, kept to compare against. Density 1 is the same pixels either way, so
1x captures are shared and unchanged. The Flutter side follows with the matching pixel model (`DshPixelModel`).

Requirements: the pinned dsh checkout at `.local/dsh-src` (or `DSH_SRC`), Node >= 24 (`PARITY_NODE_BIN` names its bin
directory, default: `node` on `PATH`), a Playwright Chromium matching the pinned `playwright-core` (1.58.2 uses
chromium-headless-shell 1208; `PARITY_BROWSERS` points at an existing browser cache, otherwise
`node $PARITY_WEB_DEPS/node_modules/playwright-core/cli.js install chromium-headless-shell` once), Flutter 3.47.6 (`FLUTTER_SDK`), and `numpy` and `Pillow`
(`pip install -r tool/parity-requirements.txt`; numpy only feeds the non-text analysis, the official scores need neither).
The vendored CLI needs Node >= 20 and `sharp`, installed by `tool/parity setup` through `corepack pnpm` (or `pnpm`) from
`tool/parity-vt/pnpm-lock.yaml`. Heavy children run under `nice -n 15`. Environment variables are listed
in `tool/parity_lib/env.py`; publishing needs `PARITY_REPORTS_ROOT` (and optionally `PARITY_BASE_URL` to verify).

`run` writes, under the output directory: `visual-testing-results/{react,flutter}/` (the provider captures),
`visual-testing-results/diff/react__flutter.json` and `.../react__flutter/<key>.{side-by-side.png,metrics.json}` (the CLI's diff),
`cli-cases.json` (the manifest as the CLI reads it), `summary.json`, `summary.md`, `site/index.html` (the CLI's report;
`publish` copies `site/`). The dsh checkout
is only read. Generated images and reports live under `build/` (git-ignored) and are not committed: attach the summary
table to the PR instead.

## The case manifest

One JSON object `{"schema": "dsh-parity-cases/1", "name", "cases": [...]}`; `tool/parity validate` checks it. Two layers run on
every load and every `run`: dsh's schema (`tool/parity_lib/manifest.py`: id convention, `kind`, theme and locale, interaction
steps, regions) and the vendored CLI's own `validate` over the flattened manifest (below). A case:

| field | meaning |
|---|---|
| `id` | `components.<area>.<surface>.<name>.<theme>` (or `screens.<...>.<theme>`); lower-case dot segments, last segment is the theme |
| `kind` | renderer key. The React host registry and the Flutter case map are both keyed by `kind` (an exact id wins), so one renderer serves a generated family |
| `viewport` | `{width, height, density}`: CSS px page size and device pixel ratio |
| `theme` | `light` or `dark`: dsh's `body[data-ds-dark-theme]`; on Flutter the official pack in that mode |
| `locale` | `en` or `zh-CN` (zh-CN needs CJK fonts, see Fonts) |
| `variants` | state variants: `[{id, name, props, interactions}]`; the first is `default`. `props` is the renderer input, identical for both providers |
| `capture` | `{selector, flutterKey, crop}`: element to crop (default the parity frame), or `crop: "viewport"` |
| `regions` | optional named rectangles `{name, x, y, width, height}` (CSS px) scored separately |
| `fixture` | optional JSON file in the suite's `fixtures/` directory |
| `skip`, `notes`, `tolerance`, `reactPathHint`, `flutterCaseHint` | bookkeeping |

A capture key names one (case, variant): the id for `default`, `<id>~<variantId>` otherwise. `--cases` takes comma lists of
keys, case ids or globs (`*` crosses dots; a case id also selects its variants).

The CLI diffs one `<provider>/<case id>.png` per case, so `tool/parity_lib/vt.py` flattens the manifest: every capture key
(case, variant) becomes one CLI case with that key as its id (`cli-cases.json` in the output directory). The report therefore lists
the variants of a dsh case as separate cases.

Interaction steps (the same real input on both sides): `hover` / `press` / `click` with a `target`, `tab` (real Tab key,
optional `count`; this is how keyboard focus-visible is reached), `type` (`target`, `text`), `wait` (`ms`). A `target` is a
`parity-id`: `data-parity-id` on the web element, `ValueKey<String>` on the Flutter widget (`parityItem`).

Capture type is inferred from the id prefix: `components.*` are component fixtures that render the real component with
fixture data; `screens.*` must be real screens (see Plugging in screens).

## Provider output contract

The vendored CLI's contract: `<results>/<provider>/<captureKey>.png` and `<captureKey>.metadata.json` for `react` and `flutter`
(compared as the pair `react__flutter`, React is the baseline). The metadata records
provider, source (`dsh-react` / `dsh-flutter`), case id, variant, theme (and on Flutter `themeResolved`), locale, viewport,
crop rectangle, renderer facts (browser version, Chromium flags, animation policy; Flutter target platform and density),
font provenance, and the `typography` / `styleTokens` probes that the CLI's report shows side by side. Anything that writes this
contract can be diffed: a future third provider (Android, iOS) only has to produce the same files.

## Determinism rules

- The Flutter frame declares itself the page (`DshSurface`, `bg-base`) so translucent fills inside it composite like Blink's (below).
- Fixed viewport and device density per case (one Chromium per density in the native mode, see below); one fresh browser
  context or widget test per capture. Every native capture proves its mode from the page it captured: the metadata's
  `react.densityMode` holds `devicePixelRatio` and the computed width of a `0.5px` and a `1px` border, and the capture fails
  when they are not what Blink gives at that density.
- Chromium runs with `--disable-lcd-text --font-render-hinting=none` (grayscale text) and Playwright `animations: "disabled"`,
  `caret: "hide"`, reduced motion; Flutter uses `disableAnimations` and a transparent caret.
- Element crops follow Playwright's element screenshot: the enclosing box of the element, in device pixels for a native
  reference (a 420 CSS px element at 2.625x is 1102.5 device px, captured as 1103) and in CSS pixels, then scaled, for an
  emulated one.
- The React side is a static Vite bundle with no network; Flutter never reads the platform brightness (the theme is explicit
  per capture, `resolveParityTheme`, and every capture verifies it: tree brightness, pack id and the frame's pixel colour).
- Fonts are pinned (below). The React cache key includes every input that can change pixels (dsh commit, case JSON without
  Flutter-only fields, fixtures, host sources, fonts, Chromium flags, lockfile, Playwright version). It is shared by all
  worktrees under `$PARITY_CACHE` (default `<main checkout>/../dsh-flutter-wt/.parity-cache`); `--refresh-react` ignores it.

## Fonts

dsh bundles one font, Montserrat (brand wordmark, OFL); its text stack (`-apple-system, BlinkMacSystemFont, 'Segoe UI',
'PingFang SC', ...`) is system fonts, so unpinned captures would depend on the machine. Both providers therefore draw
Latin text with the same Noto Sans files (SIL OFL 1.1, from Debian `fonts-noto-core` 20201225) and code text with Noto Sans Mono (`fonts-noto-mono`, registered under the code stack's leading name `SF Mono`), committed under
`tool/parity-fonts/` with sha256 pins and the license: React serves them through `@font-face` for the stack's leading names,
Flutter registers them with `FontLoader` (flutter_test ignores a fallback list when the primary family is unknown, so the
leading names must exist). Only Regular and Bold exist, so 500/600 resolve to Regular/Bold on both sides. Chinese text
(`zh-CN` cases) is drawn with a Noto Sans CJK SC subset (Regular and Bold, SIL OFL 1.1, from Ubuntu/Debian `fonts-noto-cjk`
1:20240730+repack1-1build1, upstream Noto Sans CJK 2.004; about 1.3 MB for both) registered under `PingFang SC`, the first
CJK name of both the text and the code stack, on both providers. The subset holds the 3000 most frequent GB 2312
hanzi plus CJK and fullwidth punctuation and every hanzi of dsh's conversation dictionary (`cjk-charset.txt`, rebuilt by
`tool/parity-fonts/subset-cjk.py`); a builder asserts that the text of its Chinese cases is inside the charset, because a
glyph outside it would fall back to a system font on the React side and to a missing glyph on the Flutter side. Not
vendored yet: Montserrat (Flutter cannot load woff2; needed once a case shows the wordmark) and the other CJK stack
entries (`Hiragino Sans GB`, `Microsoft YaHei`: they come after `PingFang SC` and are never reached for a glyph in the
subset). Metadata of both providers lists the files and digests; the React metadata also lists the faces Chromium really used.
`tool/parity fonts` verifies the pins.

## What Blink does at a native density

A phone's Chromium (zoom-for-device-scale-factor) multiplies every CSS length by the device scale factor before layout:
layout units, border snapping, font metric rounding and paint snapping all work in **device pixels**. The reference is
therefore captured the same way: Chromium launched with `--force-device-scale-factor=<density>` (one browser per density,
`tool/parity-web/capture.mjs`), the page's own `devicePixelRatio` and computed border widths recorded in the metadata
(`react.densityMode`) and checked on every capture. Playwright's `deviceScaleFactor` emulation (`--reference emulated`)
keeps layout in CSS pixels and scales the finished page, so it shows a different page: it was the reference until the step
that added this mode, and Whalee's hairlines, baselines and box edges were fitted to it (about 2 to 3 times thicker
hairlines than dsh web draws on a phone).

Measured on Chromium 145, a `0.5px` and a `1px` `border` ("border widths": `tool/parity-ext/probes/hairline-width.mjs`;
"outline button": the thickness of the outline button's top edge in the captures of `components.button.variants.md-*x`,
`tool/parity-ext/probes/capture-hairlines.py`):

| density | `0.5px`, emulated | `0.5px`, native | `1px`, native | outline button edge, emulated | outline button edge, native |
|---|---|---|---|---|---|
| 1x | 1 device px | 1 device px | 1 device px | | |
| 2x | 2 device px (1 CSS px) | **1 device px (0.5 CSS px)** | 2 device px | 2 px | 1 px |
| 2.625x | 3 device px (1.14 CSS px) | **1 device px (0.38 CSS px)** | 2 device px (floored from 2.625) | 3 px | 1 px |
| 3x | 3 device px (1 CSS px) | **1 device px (0.33 CSS px)** | 3 device px | 3 px | 1 px |

The rules, as Blink applies them at a native density, and where `dsh_ui` reproduces them (all in
`packages/dsh_ui/lib/src/dsh_pixel_snap.dart`, `dsh_snapped_box.dart` and `dsh_text_baseline.dart`; no per-widget or
per-theme code):

- **Border width** (`StyleBuilderConverter::ConvertBorderWidth`, `ComputedStyleBuilder::SetBorder*Width`): the CSS width times the
  density; `0 < w < 1` device px becomes one device pixel, `w >= 1` is floored to whole device pixels. `dshSnapBorderWidth`,
  `dshHairlineOf(context)` (`0.5px`) and `dshBorderWidthOf(context, css)`. The old `dshHairline = 1.0` is gone. The border
  takes layout space as it is snapped (an outline button is `2 * width` wider than its label's box), so Flutter's box
  and the label agree with Blink's.
- **Box edges** (`PhysicalRect::PixelSnappedRect`, `SnapSizeToPixel`): every box paints at its edges rounded to whole device
  pixels, halves up; the painted size is the difference of the snapped edges. `DshDecoratedBox` / `DshContainer` (what
  every `DecoratedBox` / decorated `Container` in the product is) paint the decoration at `dshSnapRect` of the box's
  rectangle on the display. Layout is not changed. It is invisible where the box is already on device pixels (whole
  densities, whole logical sizes) and is the difference between a crisp 1-device-pixel border and one smeared over two rows
  at 2.625x.
- **Text baseline**: below.

`DshPixelModel.emulated` (set by `tool/parity run --reference emulated` and only by it) switches the three rules to CSS
pixels, so the same primitives reproduce the emulated reference: `0.5px` is one CSS pixel, edges snap to CSS pixels, metrics
round in CSS pixels. The number comparison in the step that introduced the native mode is made with it.

Also in `dsh_ui`, independent of the density:

- **Translucent colours** (`DshSurface.paint`): Blink holds an alpha as 8 bits and blends in 8-bit arithmetic that rounds
  the source share and floors the backdrop's, one level away from Skia's float blend on many channels. A fill or hairline
  over a surface the widget knows (`DshSurface`, which the parity frame declares as `bg-base`) is composited like
  Blink's; over an unknown one it stays translucent with Blink's 8-bit alpha. Inside an `opacity` group (a disabled
  button) it must stay translucent, the group composites onto the page.
- **Corner shape**: every rounded surface uses `DshCornerBorder` (`corner-shape: superellipse(1.5)`), including the
  button, its focus ring and the connection pill.

## The text baseline

Both engines put the baseline of a fixed-`line-height` line at the top of the line plus the ascent plus half the
leading, and compute it differently:

| | ascent, descent | half-leading | baseline | line top |
|---|---|---|---|---|
| Blink (`FontHeight::AddLeading`) at a native density | rounded to whole **device** px (font size times the density) | `floor((line - ascent - descent) / 2)` in device px, line height in 1/64 px | `ascent + floor(leading / 2)` | rounded to a device px, halves up |
| Flutter (`ParagraphSkia`) | fractional | exactly `(line - ascent - descent) / 2` | rounded to a whole logical px | wherever the layout put it |

They agree for dsh's body text at 1x (14px on 22px, Noto Sans: Blink 16, Flutter `round(16.43)` = 16) and differ by one
pixel whenever the two roundings go opposite ways: 12px on 18px, and 12 on 14, 16 and 20, 13 on 15, 16 on 19, 17 on 26, 20 on
28 at 1x. At 2x to 3x the device-pixel rounding moves the two apart for most sizes, including 14 on 22 (Blink at 2x: ascent
30, descent 8, line 44, baseline 33 device px; Flutter: 16 logical = 32).

`tool/parity-ext/text-baseline-sweep.py` measures it: a line of capitals per size/line-height pair, weight, family and
density, drawn in Chromium at the same density mode as the captures (`--reference`, native by default) and in Flutter, baseline compared at the
ink's bottom edge. Result over 29 size/line-height pairs x 2 weights x 2 families x 5 densities (1, 1.5, 2, 2.625, 3) = 580
baselines against **native** Chromium:

| density | plain `Text` | the PR #9 model (CSS-pixel rounding) | the native model (`DshChromeText`) |
|---|---:|---:|---:|
| 1x | 84 / 116 | 116 / 116 | 116 / 116 |
| 1.5x | 52 / 116 | 76 / 116 | 116 / 116 |
| 2x | 40 / 116 | 40 / 116 | 116 / 116 |
| 2.625x | 48 / 116 | 40 / 116 | 116 / 116 |
| 3x | 44 / 116 | 44 / 116 | 116 / 116 |
| **all** | 268 / 580 | 316 / 580 | **580 / 580** |

Against the emulated reference the same sweep (`--reference emulated`) gives plain `Text` 420 and the CSS-pixel model 580,
the numbers of the step that fitted it. The sweep therefore changed the model, as the mismatch (a model right for the
emulated reference, wrong for 264 of 580 native baselines) demanded; the formula is the same one with the unit changed:
`dshBlinkBaseline` (ascent and descent rounded, half the leading floored, in layout pixels) with the layout pixel
being a device pixel, `dshBaselineNudge(style, devicePixelRatio)` the paint offset from Flutter's rounded baseline, and
`DshChromeBaseline` moving the line to the device pixel Blink paints it at (a block at 10.5 device px paints its baseline
from 11). `DshChromeText` is a `Text` that applies it (and the strut that pins mixed CJK/Latin lines to the primary font's
height, as CSS does); every `Text` in `dsh_ui` and the feature packages is one.

Chromium's glyph rasterisation is not reproduced: stems are heavier than Skia's (summed ink of the same capitals,
Chromium over Flutter, mean of the sweep: 1.17 at 1x, 1.08 at 2x, 1.05 at 3x) and Skia snaps cap heights to whole device
pixels where Blink leaves a partial top row. That is what the `text` bucket and the `outside-glyph` number of
`glyph-mask.py` separate out.

## Known engine differences

Differences that cannot be reproduced in Flutter's own pipeline, with the evidence:

- **`backdrop-filter: blur(40px) saturate(150%)` over a flat page** (the to-do panel and every menu surface, dsh's
  `--dsw-menu-backdrop-filter`). With an **emulated** 2x density Chromium leaves four values in the dark to-do panel
  (`41,42,46`, `42,43,45`, `41,42,45`, `42,43,46`) in horizontal bands and a checkerboard, rounding in the downscaled 8-bit
  blur (a plain `div` over the page background shows it, with and without the shadow;
  `tool/parity-ext/probes/backdrop-banding.mjs` prints both density modes): the banding belonged to the emulated reference, not to
  dsh. At a **native** 2x the same panel is one flat `41,42,46` (47204 px of the capture) and the dark to-do captures score
  92.0 and 87.2% instead of 79.1 and 51.7%. What is left is the fill bucket: Flutter's `BackdropFilter` over the same flat
  page gives `42,43,46` (no saturate; a Flutter shader filter is not available outside Impeller), one level off on two
  channels over the whole panel. The panel is drawn flat (the fill over `saturate(150%)` of the page).
- **Translucent blending**: `blendLikeChromium` (rounded source share, floored backdrop share) reproduces 1056 of the 1248
  pixels of a probe grid (12 backdrops x 8 greys x 13 alphas, `rgba()` over `rgb()` in Chromium); the other 15% sit one
  level away and no rounding/flooring/quantisation of a single formula explains them (the 8-bit path has stages the model
  does not have). A fill that lands there stays one level off whatever Flutter does.
- **Faint shadow halos**: Chromium truncates the Gaussian tails of faint shadows with 8-bit floor arithmetic, Flutter blends in
  float: +-1/255 over a halo of a few thousand pixels around the panel (to-do panel, 2x).
- **The focus ring in a dark page**: dsh sets only `outline-width` and `outline-color`; the button keeps the UA's
  `outline-style: auto`, which Chromium draws centred on the border edge in the outline colour in a light page and as a
  white ring with a dark (`#101010`) outer ring in a dark one, whatever the colour (`color-scheme: dark`; checked with a
  plain button and four colours). The Flutter ring keeps the geometry (2px centred on the edge) and the token colour in both.

## Reading the scores

The official numbers come from the vendored CLI. For each capture both rasters are flattened on white and the smaller one is
padded with white (a different size is a failure in dsh's summary, whatever the padded comparison says). Percentages are of pixels:

- **pixel-perfect** (CLI): identical RGBA. The strict number; `status` is `same` (identical file), `pass` (> 99%), `basic-pass`
  (> 96%) or `different`.
- **RGB similarity** (CLI): the mean channel closeness after resizing both to one canvas; a coarse colour score.
- **close** (dsh): every channel within 4/255. Colour rounding noise (for example a translucent fill that blends to 169 on one
  side and 170 on the other) is invisible here but costs pixel-perfect.
- **non-text** (dsh, geometry): pixel-perfect plus the pixels classified as glyph anti-aliasing. Chromium and Skia rasterise
  glyphs differently, so text edges never match exactly; they are not worth iterating on. The CLI scores every pixel the same
  and does not have this number, so it is computed by `tool/parity_lib/diffmetrics.py` from the same two PNGs.
- **buckets** (dsh): every mismatching pixel falls in the first bucket that explains it: `fill` (flat colour that differs by <= 4:
  blending/rounding), `hairline` (thin band on a long straight edge: border snapping), `corner` (where a horizontal and a
  vertical edge meet: radius arcs), `offset` (the neighbourhood matches after a whole-pixel shift: real geometry offsets),
  `text` (dense glyph ink no shift explains), `other` (wrong colour, missing or extra content).
- **regions** (dsh): named rectangles from the case plus the five worst 32 CSS px grid cells, scored with the same buckets.

Statuses in `summary.md`: `same`, `pass`, `basic pass` (the CLI's), `geometry pass` (non-text >= 99.5%, the target for extension
work; dsh's own), `fail`. `not covered` means the React side renders it and Flutter has no mapped widget (`ParityGap` says why);
a case that exists is coverage, not a pass. The HTML report (`site/latest/index.html`, home `site/index.html`) shows React | Flutter
side by side with the metrics, metadata probes and the case tree. `tool/parity-ext/analyze-diffs.py` ranks buckets by leverage
(pixel-perfect % if that bucket matched; `--viz` writes bucket maps), `tool/alignment-audit.py` reports vertical-edge and
text-start offsets in CSS px (<= 0.75 aligned), and `tool/parity-ext/inventory.py` lists every dsh surface with its computed
coverage status.

## Plugging in screens (phase 1a and later)

Flutter side. A screen's widgets live in an app, feature or package. Give that package `test/parity/` with
`parity_capture_test.dart` (`void main() => runParityCapture(cases: parityCases, uncovered: parityUncovered);`), `case_map.dart`
(`export 'case_map.g.dart';`) and `cases/*.dart` declaring `final Map<String, ParityCase> ...` keyed by manifest `kind` (or
exact case id), with `dsh_parity` as a dev dependency. `tool/parity_case_map.py` (run by `tool/parity`, `tool/parity-ext/run` and
preflight) generates the git-ignored `case_map.g.dart`; `tool/parity` runs every package that has such an entry point and
merges the coverage maps. Use `ParityCase(framed: false)` and `capture.crop: "viewport"` for full screens; build them from
fixtures with fake controllers, the same fixtures the React host receives.

React side. A `screens.*` case needs the real dsh component tree: add a host file whose `kind` mounts the real ui-chat / ui-tool
components with fixture state (`tool/parity-web/host/cases/*.tsx`, or `tool/parity-ext/host/*.tsx` for the extension suite; the host
already imports dsh sources through the `@dsh` alias, and new dsh packages that need more npm dependencies add them to
`tool/parity-web/package.json` + lockfile). The host mocks that real components need are in `tool/parity-web/host/mocks/`:
`locale.ts` (a translator over dsh's real dictionaries with its lookup order and interpolation), `tool-blocks.ts` (call, started
and settled tool blocks built the way ui-chat's Definitions build them, with the real lazy argument view) and `primitives.ts` (the
ui-primitives barrel narrowed to the modules the mounted surfaces import). `tool/parity-ext/host/tools.tsx` is the worked example:
`tool.card` mounts the keyed toolview row of each item's tool name (`BashRow`, `FileMutationRow`, ...), `plan.todo-panel` the
`TodoPanel`, `plan.card` / `plan.preview` the plan cards and document.

Kinds whose content settles asynchronously (images decoding, a lazy highlight grammar, a rejecting image loader) publish a
promise as `window.__parityReady` (`tool/parity-ext/host/settle.ts`: `publishSettle(ready, what)`); `capture.mjs` awaits it
after `document.fonts.ready` and before the interactions, and a timeout fails the capture instead of recording a
half-rendered page. The Flutter counterpart is `precacheTreeImages(tester)` (decodes the `Image`s in the tree) and, for the
code cases, loading the grammars outside the fake clock in the case's `interact` hook.

Synthetic images come from `tool/parity-ext/synthetic_images.py` (generated pixels, shipped as base64 in the case props, so
both providers draw identical bytes). Frames in dsh have a 1px border and `object-fit` snaps the picture to whole CSS
pixels, so the builders size every source to the frame's content box in device pixels: nothing is resampled, and a
mismatch inside a picture is a real geometry difference.

## Reading a text-heavy case

The `non-text` column counts glyph anti-aliasing only where it is dense ink; a glyph stem (a long, thin vertical edge) is
classified as `hairline` and a stem pair as `offset`, so a screen full of text cannot reach 99.5% however the layout
matches: Chromium's glyph coverage (a little heavier than Skia's) differs on every stem. To judge the layout of such a
case, read it with the glyphs masked: an `outside-glyph` agreement (pixels outside every word-sized ink component, within
3px) is far higher and what remains there is sub-pixel anti-aliasing of rounded corners and icon edges (a level or two).
`tool/parity-ext/glyph-mask.py --out build/parity-ext --cases <glob> [--viz DIR]` prints that number next to the exact one and
draws what is left.

## Owner decisions

- **2026-10-24, align everything with dsh web first, on every width.** Kevin: "直接都跟网页对齐吧", changes follow after he has
  seen it. A phone renders what dsh web renders at that viewport width, not a phone adaptation of it: menus and popups keep
  dsh's rows (34px, the popup's 27px), the workspace picker is the popover anchored under the chip, the directory picker is
  the dialog (`min(680px, 100%)` by `min(500px, 100dvh - 32px)`, two panes of at least 256px that scroll sideways, the child
  pane pinned into view), New folder is the centered card, the blank-session hero is the centered stack (minus the DeepSeek
  brand mark, which stays `na`), and the composer is dsh's single rounded card with the draft on top and the controls row
  (attach, permission, model, send) inside it. What stays Whalee's: the keyboard (the web layout simply sits above it), the
  cap that keeps floating menus below the session header, and the app's own navigation around the conversation (no icon
  rail). Parity is scored against dsh web at the same width, phone widths included, with the same bar as desktop.
- **2026-10-24, the phone drawer (the one exception to "align with web first").** Kevin approved the mockups ("手机抽屉设计没问题"):
  below 600 logical pixels the page is a 52px top bar (menu, Session title, new Session) and the sidebar is a modal drawer
  (85% of the width, at most 320px; the menu button or a swipe from the left edge opens it, a tap on the scrim, a swipe toward
  the edge, the system back button or picking a Session closes it). The drawer holds dsh's real sidebar content and visuals
  (the browsing region, Plugins, Automation tasks, the foot) under Whalee's own header with no brand mark. From 600 to 1023 px the
  frame is dsh's: the 56px rail, with the sidebar expanding over the centre; from 1024 px the sidebar is docked. The top bar and
  the drawer chrome have no dsh counterpart, so the phone captures score the page behind them and the drawer's content separately.

## Provenance and licenses

- dsh (MIT, pinned in `docs/upstream-sync.json`) components are imported at run time from the checkout, never copied.
- `tool/vendor/raft-visual-testing/` is raft's `packages/visual-testing` (tag `v1.21.23-source.1`, commit `db5e399f`), copied
  without any change and licensed **FSL-1.1-ALv2, not MIT** (Copyright 2026 Botiverse, Inc.): manifest validation, diff metrics,
  the side-by-side compositor and the HTML report. It is used as an internal development and test tool, which the license
  names a Permitted Purpose; origin, license reasoning and the update procedure are in its `README-VENDOR.md`, its terms in
  `LICENSE` beside it, and the notice in `THIRD_PARTY_NOTICES.md`. Everything else under `tool/` stays MIT: the glue
  (`tool/parity_lib/vt.py`, `pipeline.py`, `summary.py`, the providers) is dsh-flutter's, run as a separate process; the
  non-text/bucket analysis (`diffmetrics.py`) is a fresh implementation of the approach documented for raft-flutter's
  parity-ext (no code copied).
- Noto Sans, Noto Sans Mono and the Noto Sans CJK SC subset: SIL OFL 1.1, see `tool/parity-fonts/OFL.txt`,
  `tool/parity-fonts/OFL-NotoSansCJK.txt` and `THIRD_PARTY_NOTICES.md`.

## Whole desktop pages

`tool/parity-desktop/run` compares whole pages of the real dsh web client with the Whalee Linux build: the same fixture host, the
same size, theme and language, the parity fonts pinned on both sides, density 1. The scoring is `tool/parity_lib/diffmetrics` (the
bucket analysis of the component suite) over each capture, and the named regions of `tool/parity-desktop/cases.json` (sidebar brand,
New Session, panels, workspaces, foot, header, conversation, composer, usage footer) are scored separately; the report is
`summary.json`, `summary.md` and one side-by-side image per case under `$PARITY_DESKTOP_OUT`.

```sh
tool/parity-desktop/run --list
tool/parity-desktop/run --cases session.1280x720.light.en,session.1600x1000.      # a case id or a prefix
```

Environment: `PARITY_WEB_DEPS` (as the component suite), `PARITY_DESKTOP_HOST_LOG` (the log of an isolated `dsh web --port ...` whose
`DSH_HOME` holds the fixture sessions, written through dsh's own persistence with no model call), `PARITY_DESKTOP_CHROME` (a
Chromium), `PARITY_DESKTOP_APP` (the built `build/linux/x64/*/bundle/dsh_flutter`), `PARITY_DESKTOP_HOME` (an empty directory used as
the app's HOME), `PARITY_DESKTOP_OUT`, `PARITY_NODE_BIN`; Python needs `numpy`, `Pillow` and `python-xlib`, and the machine `Xvfb`,
`xwininfo` and ImageMagick's `import`. The tool starts its own Xvfb display and its own app process per case and stops exactly those
(their PIDs are in `pids.txt`); it never touches another process and never reads or prints the launch token beyond typing it into the
app. The host itself is the caller's: start one on a loopback port with its own `DSH_HOME` and keep its PID.

Below 1024 px the left column starts as its rail, so those cases widen it first, on both sides. The dark cases set `WHALEE_PLATFORM_BRIGHTNESS=dark` for the
app (a capture hook, like `WHALEE_WINDOW_SIZE` and `WHALEE_PIN_FONTS`) and `colorScheme` for the page; the Chinese cases set `LC_ALL` and the browser locale.
