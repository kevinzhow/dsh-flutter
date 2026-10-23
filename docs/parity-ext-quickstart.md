# Parity extension: agent quickstart

One page for adding or fixing a surface in the extension suite (`tool/parity-ext/run`; background in
[parity.md](parity.md)).

## Add a surface

1. **React host** `tool/parity-ext/host/<area>.tsx`: export `kinds: Record<string, KindRenderer>` (see
   `host/atoms.tsx`). Import dsh components with `@dsh/<package>/src/<File>.tsx` (`@dsh` is `packages/client` of the pinned
   checkout), lay items out with `Stack` from `tool/parity-web/host/layout.tsx`, and put `data-parity-id` on every element an
   interaction targets. Files are discovered by glob; nothing shared is edited. A kind may only be registered once.
2. **Builder** `tool/parity-ext/build-<area>.py`: use `base_case`, `themed` and `replace_cases` from `builders_api.py` (copy
   `build-button-matrix.py`). Ids are `components.<area>.<surface>.<name>.<theme>`; the first case of a surface is its default
   variant (it is the one the dark theme keeps). Optional top-level `ORDER = n` (default 1000) only if the builder must run
   before or after another. The manifest (`build/parity-ext/cases.json`) is generated on every run and never committed.
3. **Flutter** `tool/parity_flutter/test/parity/cases/<area>.dart` (or the owning package's own `test/parity/cases/`): a public
   top-level `final Map<String, ParityCase> <area>Cases = {'<kind>': ParityCase(widgets: [...], build: (ctx) => ...)}`.
   That is the whole registration: `tool/parity_case_map.py` merges every such map into the git-ignored `case_map.g.dart`.
   Read the renderer input from `ctx.props` (the same JSON the React host gets), lay items out with `ParityStack(layout: ctx.layout)`,
   wrap interaction targets with `parityItem(id, widget)`. For a kind with no Flutter widget yet, add it to a
   `Map<String, ParityUncovered>` (see `cases/uncovered.dart`): the case is still captured on the React side and reported as `not covered`.

Rules: the Flutter builder must render through the real product widget (`DshButton`, ...), not a look-alike; props and layout
are the only shared input; do not special-case a theme (the widget reads the theme contract).

## Run only your cases

```sh
tool/parity-ext/run list --cases 'components.<area>.*'     # which captures exist after sampling
tool/parity-ext/run run --cases 'components.<area>.*'      # comma list / globs; --refresh-react to recapture
tool/parity-ext/run summary
```

Results: `build/parity-ext/summary.md` (per case and per area) and `site/index.html`. Use `PARITY_EXT_OUT` for a private output
directory, `PARITY_CACHE` to share captures.

## Done criterion

**Geometry pass** for every case of your area: the `non-text` column of `summary.md` >= 99.5% (similarity after counting the
pixels classified as glyph anti-aliasing as matching). `tool/parity-ext/analyze-diffs.py --out build/parity-ext --cases <glob> --viz DIR`
shows where the rest is (fill, hairline, corner, offset, text, other) ranked by leverage; `tool/alignment-audit.py run --root
build/parity-ext --cases <glob>` gives edge and text-start offsets in CSS px. The strict pixel-perfect number is reported next to it and
is not the target. Never iterate on the `text` bucket: fix layout, colour, spacing, borders, radii and glyph positions that move
by whole pixels.

## Theme sampling

`light` runs every case. `dark` runs 1-2 cases per surface (`components.<area>.<surface>`): the first case in builder order plus one
dense case (a name with a density word such as `long`, `many`, `mixed`, `all`, `full`, else the last case of the surface); rule and
word list in `tool/parity_lib/sampling.py`. `--cases` only sees the sampled set; `PARITY_EXT_ALL_THEMES=1` runs everything.

## Page inventory

`python3 tool/parity-ext/inventory.py --write build/parity-ext/inventory.md` lists every dsh surface with a computed status
(`ok`, `web-only`, `untested`, `MISSING`, `excluded`) from the case ids that exist and the Flutter coverage map of the last runs.
Rows hold web metadata only; a branch that adds cases edits nothing. `--check` validates the rows, `--check --discover`
lists dsh ui-primitives files without a row.

## Rules

- No full-suite runs per task: run your cases once per change and read the output once. No polling loops.
- Do not publish from a task branch; do not commit `build/` or generated images; evidence goes in the PR description.
- `tool/preflight` runs `tool/parity selftest` (manifests validate, builders produce a valid sampled manifest, font pins hold,
  metrics behave) and the Flutter harness self-test (`flutter test` in `tool/parity_flutter`).
