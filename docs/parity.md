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
tool/parity run [--cases 'components.button.*'] [--refresh-react]
tool/parity summary
tool/parity-ext/run run --cases 'components.button.matrix.*'
tool/parity selftest                    # offline: manifests (dsh schema + the vendored CLI's validate), font pins, builders,
                                        # the CLI's diff on synthetic captures, bucket metrics (tool/preflight runs it)
```

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

- Fixed viewport and `deviceScaleFactor` / `devicePixelRatio` per case; one fresh browser context or widget test per capture.
- Chromium runs with `--disable-lcd-text --font-render-hinting=none` (grayscale text) and Playwright `animations: "disabled"`,
  `caret: "hide"`, reduced motion; Flutter uses `disableAnimations` and a transparent caret.
- Element crops follow Playwright's element screenshot: the enclosing CSS-pixel box (floor/ceil), then scaled.
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
