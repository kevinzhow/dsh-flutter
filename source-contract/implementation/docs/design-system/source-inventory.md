# Pinned source-input inventory

`tool/design-system/source_inventory.py` generates
`tool/design-system/source-inventory.generated.json` from the actual DSH source
checkout pinned by `tool/design-system/sources.lock.json`. This closes the gap
between the upstream package/style universe and the smaller set of retained
recipe inputs. It does **not** certify that a retained input is fully translated,
that a whole package is implemented, or that any visual acceptance target passed.

The tool enumerates the package globs declared in `pnpm-workspace.yaml`, including
extension packages such as `packages/extensions/ui-cordis`. It inventories every
public `@deepseek-ai/dsh-client-ui-*` manifest, all its `src/**/*.css` inputs and
their SHA-256 hashes. Public workspace packages with their own source CSS outside
that prefix are included separately as `support-styles`, including optional
surfaces outside the selected assembly. No source package/style count is encoded
as a success threshold. Counts in `summary` are computed from the actual entries.

At the current pin, `687f282e8625c6b8d11ff58211a90524be2e4317` / `0.2.1-rc.2`,
the UI prefix contributes 57 packages and 209 CSS inputs. Forty-eight packages
have CSS; nine use delegated controls/artwork, a native chooser, or structural
contracts. Thirteen UI packages have retained snapshot subsets: 36 source CSS
inputs bind to those subsets and 173 remain pending. Within primitives, 14 of
41 CSS inputs have retained inputs. These are **retention counts**, not coverage
percentages. Other public styling packages and dependency reachability remain
separate fields in the ledger: nine additional public packages contribute ten
CSS inputs, including the six optional experimental styling packages. The
selected roots reach 215 runtime workspace packages and 295 when build/dev
dependencies are included; those node counts are distinct from UI family counts.

## What each record means

- `sourceManifest` records the real manifest path and hash. `sourceDependencies`
  preserves all four declaration fields, including their `workspace:*`/`~`/`^`
  specifiers. `publication` freezes independently queried npm version metadata:
  package/version, immutable version endpoint, tarball URL, distribution integrity
  and dependency declarations after publication. Workspace specifiers must resolve
  to the corresponding source package's actual version. External semver ranges
  remain ranges; these records do not claim exact installed third-party versions.
- `dependencyScope` walks dependencies, optional dependencies and peers from the
  web-app, client-web and plugin-market-bundle manifests. It separately follows
  build/dev dependencies. This prevents primitives, dockkit and slots from
  disappearing because they are bundled during build rather than installed as
  separate runtime packages. Roots have their own path/version/hash records.
- `reachability` distinguishes `runtime`, `build-only` and
  `outside-selected-closure`. The last status retains optional source inputs
  explicitly; it does not claim that Whalee supports those features.
- `snapshot: null` means no retained package snapshot is recorded in the existing
  source lock. `retained-subset` records the actual locked file paths/hashes and
  publication identity. It never means the whole package is complete.
- CSS `retention: pending` means no retained stylesheet is bound to the source
  input. `retained-input` points to a real locked stylesheet. Some published CSS
  is minified, class-renamed or extracted from a bundle, so a binding does not
  imply equal raw source/snapshot bytes. The explicit AgentPresetSection →
  `styles.css` release alias is recorded by source path. Missing or ambiguous
  source bindings fail instead of guessing. The recipe generator's existing
  source-equivalence checks remain responsible for translated rules and states.
- `noCssClassification` classifies the nine CSS-free UI packages with exact source
  paths and hashes. For example, agent-loop and shell settings delegate
  SettingsForm/SettingsValueField; their lack of local CSS does not prove those
  inherited profiles exist. A newly discovered CSS-free UI package fails until
  its source behavior has an explicit reviewed classification.

There is no `done` or implemented-package status in this ledger. Inline styles,
SVG geometry, public/internal component exports, consumer migration, source
states and real-screen acceptance need their own component-family ownership
ledger. This inventory makes the file/package boundary exhaustive at the pinned
source; it must not replace those deeper checks.

## Generate and check with the real source

Set `DSH_SRC` to the pinned reference checkout, or pass `--src`. On k172, source
the existing absolute `scripts/pr16-env.sh` environment before running Python.
The source checkout must have exactly the locked HEAD and a clean working tree;
generation and full checks fail on another commit or edited inputs.

```sh
python3 -B tool/design-system/source_inventory.py --src "$DSH_SRC" --refresh-publications
python3 -B tool/design-system/source_inventory.py --src "$DSH_SRC" --check
python3 -B -m unittest discover -s tool/tests -p test_source_inventory.py
```

The explicit `--refresh-publications` operation reads public npm version metadata
for the discovered source packages, then validates source/published dependency
versions and retained package integrities before writing the ledger. It does not
install or execute packages. It does not copy source files into the snapshot set.
Review a new package, version or distribution identity before accepting the diff.
It never upgrades the source pin.

Ordinary generation and checks are offline and reuse the frozen publication
records already in the ledger. This keeps checks deterministic and avoids
registry requests during tests. A newly discovered package without a record
fails with a request to refresh explicitly. To incorporate a new retained profile
under the same pin, regenerate without refreshing publication metadata, then
review the changed input bindings:

```sh
python3 -B tool/design-system/source_inventory.py --src "$DSH_SRC"
python3 -B tool/design-system/source_inventory.py --src "$DSH_SRC" --check
```

A full check independently rediscovers source packages/CSS, validates manifest,
classification and CSS hashes, resolves dependency declarations, and compares
the resulting ledger. Removing a ledger entry or source sheet does not make the
scope smaller silently. It also checks the source lock and every retained file
hash. Retained/transformed CSS equivalence, CSS parsing and generated recipe
consumption remain separate checks; this tool does not claim to perform them.

## Environments without the reference checkout

Use the explicit limited mode:

```sh
python3 -B tool/design-system/source_inventory.py --check --snapshot-only
```

This verifies ledger structure, unique owned paths, coherent computed counts,
retained CSS bindings, the current source-lock digest and every retained file's
hash and manifest identity. It can run without the source checkout or network.
It prints **“source-universe completeness NOT independently verified”**. It
cannot discover a missing/unrecorded upstream package or stylesheet, rehash
unretained source inputs, or independently verify frozen npm metadata. It cannot
generate a ledger. Full checks never silently fall back to this mode.

## Failure behavior and verification

The focused suite uses a small isolated source workspace and real temporary git
commits. It checks package and CSS addition/removal/modification, unpublished
metadata omissions, source/published dependency drift, unsafe/duplicate paths,
duplicate JSON keys/package identities, missing workspace dependencies,
snapshot tampering/binding loss, source HEAD/dirty state and unknown CSS-free
packages. Source-content tests exercise drift independently of the git guard;
separate tests ensure production checks require the actual clean pinned commit.

The generated-file test also verifies the checked-in ledger against the real
retained snapshot set without requiring a reference checkout. This is useful
offline validation with the same deliberately limited meaning described above.
Integration into preflight/generator policy is owned by the encompassing
design-system contract; this file adds no page ports or product styling.
