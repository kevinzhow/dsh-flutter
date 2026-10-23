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
                              tool/parity_lib: diff metrics -> side-by-side composites -> summary.md + site/index.html
```

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
tool/parity setup                       # once: installs the pinned npm dependencies under $PARITY_WEB_DEPS (never global)
tool/parity run [--cases 'components.button.*'] [--refresh-react]
tool/parity summary
tool/parity-ext/run run --cases 'components.button.matrix.*'
tool/parity selftest                    # offline: manifests, font pins, builders, diff metrics (tool/preflight runs it)
```

Requirements: the pinned dsh checkout at `.local/dsh-src` (or `DSH_SRC`), Node >= 24 (`PARITY_NODE_BIN` names its bin
directory, default: `node` on `PATH`), a Playwright Chromium matching the pinned `playwright-core` (1.58.2 uses
chromium-headless-shell 1208; `PARITY_BROWSERS` points at an existing browser cache, otherwise
`node $PARITY_WEB_DEPS/node_modules/playwright-core/cli.js install chromium-headless-shell` once), Flutter 3.47.6 (`FLUTTER_SDK`), and `numpy` and `Pillow`
(`pip install -r tool/parity-requirements.txt`). Heavy children run under `nice -n 15`. Environment variables are listed
in `tool/parity_lib/env.py`; publishing needs `PARITY_REPORTS_ROOT` (and optionally `PARITY_BASE_URL` to verify).

`run` writes, under the output directory: `visual-testing-results/{react,flutter}/`, `composites/<key>.png`,
`diff/<key>.json`, `summary.json`, `summary.md`, `site/index.html` (self contained; `publish` copies it). The dsh checkout
is only read. Generated images and reports live under `build/` (git-ignored) and are not committed: attach the summary
table to the PR instead.

## The case manifest

One JSON object `{"schema": "dsh-parity-cases/1", "name", "cases": [...]}`; `tool/parity validate` checks it and the
validator (`tool/parity_lib/manifest.py`) runs on every load. A case:

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

Interaction steps (the same real input on both sides): `hover` / `press` / `click` with a `target`, `tab` (real Tab key,
optional `count`; this is how keyboard focus-visible is reached), `type` (`target`, `text`), `wait` (`ms`). A `target` is a
`parity-id`: `data-parity-id` on the web element, `ValueKey<String>` on the Flutter widget (`parityItem`).

Capture type is inferred from the id prefix: `components.*` are component fixtures that render the real component with
fixture data; `screens.*` must be real screens (see Plugging in screens).

## Provider output contract

`<results>/<provider>/<captureKey>.png` and `<captureKey>.metadata.json` for `react` and `flutter`. The metadata records
provider, source (`dsh-react` / `dsh-flutter`), case id, variant, theme (and on Flutter `themeResolved`), locale, viewport,
crop rectangle, renderer facts (browser version, Chromium flags, animation policy; Flutter target platform and density),
font provenance, and typography / style-token probes that the report shows side by side. Anything that writes this
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
leading names must exist). Only Regular and Bold exist, so 500/600 resolve to Regular/Bold on both sides. Not vendored yet:
Montserrat (Flutter cannot load woff2; needed once a case shows the wordmark) and CJK faces (needed for the first zh-CN case).
Metadata of both providers lists the files and digests; the React metadata also lists the faces Chromium really used.
`tool/parity fonts` verifies the pins.

## Reading the scores

For each capture both rasters are flattened on white and the smaller is padded with white (a size mismatch is reported and
is always a failure). Percentages are of pixels:

- **exact**: identical RGB. The strict number.
- **close**: every channel within 4/255. Colour rounding noise (for example a translucent fill that blends to 169 on one side and
  170 on the other) is invisible here but costs exact.
- **non-text** (geometry): exact plus the pixels classified as glyph anti-aliasing. Chromium and Skia rasterise glyphs differently,
  so text edges never match exactly; they are not worth iterating on.
- **buckets**: every mismatching pixel falls in the first bucket that explains it: `fill` (flat colour that differs by <= 4:
  blending/rounding), `hairline` (thin band on a long straight edge: border snapping), `corner` (where a horizontal and a
  vertical edge meet: radius arcs), `offset` (the neighbourhood matches after a whole-pixel shift: real geometry offsets),
  `text` (dense glyph ink no shift explains), `other` (wrong colour, missing or extra content).
- **regions**: named rectangles from the case plus the five worst 32 CSS px grid cells, scored with the same buckets.

Verdicts: `same` (exact 100%), `pass` (exact >= 96%), `geometry pass` (non-text >= 99.5%, the target for extension work),
`fail`. `not covered` means the React side renders it and Flutter has no mapped widget (`ParityGap` says why); a case that
exists is coverage, not a pass. The composite image shows React | Flutter | difference map (faded React with mismatches painted
in their bucket colour). `tool/parity-ext/analyze-diffs.py` ranks buckets by leverage (exact % if that bucket matched),
`tool/alignment-audit.py` reports vertical-edge and text-start offsets in CSS px (<= 0.75 aligned), and
`tool/parity-ext/inventory.py` lists every dsh surface with its computed coverage status.

## Plugging in screens (phase 1a and later)

Flutter side. A screen's widgets live in an app, feature or package. Give that package `test/parity/` with
`parity_capture_test.dart` (`void main() => runParityCapture(cases: parityCases, uncovered: parityUncovered);`), `case_map.dart`
(`export 'case_map.g.dart';`) and `cases/*.dart` declaring `final Map<String, ParityCase> ...` keyed by manifest `kind` (or
exact case id), with `dsh_parity` as a dev dependency. `tool/parity_case_map.py` (run by `tool/parity`, `tool/parity-ext/run` and
preflight) generates the git-ignored `case_map.g.dart`; `tool/parity` runs every package that has such an entry point and
merges the coverage maps. Use `ParityCase(framed: false)` and `capture.crop: "viewport"` for full screens; build them from
fixtures with fake controllers, the same fixtures the React host receives.

React side. A `screens.*` case needs the real dsh component tree: add a host file whose `kind` mounts the real ui-chat / ui-tool
components with fixture state (`tool/parity-web/host/cases/*.tsx`; the host already imports dsh sources through the `@dsh`
alias, and new dsh packages that need more npm dependencies add them to `tool/parity-web/package.json` + lockfile). The
React-side mocks for the host connection and store are not built yet: they are the first piece of work for the first screen
case.

## Provenance and licenses

- dsh (MIT, pinned in `docs/upstream-sync.json`) components are imported at run time from the checkout, never copied.
- The case manifest, provider output contract, metrics and report are a fresh implementation for this repository. They follow the
  public design of raft's visual-testing tool (case manifest, provider output contract, state variants, raw diff metrics,
  side-by-side composite, HTML report) and the structure of raft-flutter's parity setup, but no code was copied: raft's
  `packages/visual-testing` is licensed FSL-1.1-ALv2, which is not MIT, so it was used as a design reference only.
- Noto Sans: SIL OFL 1.1, see `tool/parity-fonts/OFL.txt` and `THIRD_PARTY_NOTICES.md`.
