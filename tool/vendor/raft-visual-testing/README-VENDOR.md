# Vendored: raft visual-testing

This directory is a verbatim copy of Raft's cross-provider visual-testing CLI. It is **not** part of the MIT-licensed
dsh-flutter code: every file here, except this note, is under the Functional Source License, Version 1.1, ALv2 Future
License (FSL-1.1-ALv2), Copyright 2026 Botiverse, Inc. The full text is in [`LICENSE`](LICENSE).

## Origin

| | |
|---|---|
| Repository | https://github.com/botiverse/raft-source |
| Tag | `v1.21.23-source.1` |
| Commit | `db5e399f017d584e49597e3a28757645d6807893` |
| Path | `packages/visual-testing` |
| License file | `LICENSE` at the repository root of that commit, copied here byte for byte |

The 36 files of `packages/visual-testing` at that commit are copied without any change (`node_modules` and build
outputs are not part of the source tree and are excluded). The only files added by dsh-flutter are `LICENSE` and this
note. No copyright notice was removed; the source files carry none of their own, the notice is the one in `LICENSE`.

## License: FSL-1.1-ALv2, not MIT

- The code may be used, copied, modified and redistributed for any Permitted Purpose. A Permitted Purpose is any
  purpose other than a Competing Use, and "internal use and access" is named as one.
- A Competing Use is making the software available to others in a commercial product or service that substitutes for it,
  for another Botiverse product or service that uses it, or that offers the same or substantially similar
  functionality. The terms apply to every copy, modification and derivative: keep `LICENSE` with any copy, and do not
  remove copyright notices.
- Each version converts to the Apache License 2.0 on the second anniversary of the date Botiverse made it available
  (the grant is in `LICENSE`); the conversion does not change anything before that date.
- The rest of dsh-flutter stays MIT (`../../../LICENSE`). See `../../../THIRD_PARTY_NOTICES.md`.

### Why this is a Permitted Purpose

dsh-flutter uses the CLI only as an internal development and test tool: it validates the visual case manifest, scores
and composes the screenshots of the dsh web client against the Flutter client, and renders the comparison report that
developers read. It is not part of the shipped app, and dsh-flutter does not offer it, or anything with the same
functionality, to anyone as a commercial product or service. The maintainer approved this use. If dsh-flutter ever
did start offering visual testing to others, this directory would have to go.

dsh-flutter code that talks to the CLI lives **outside** this directory (`tool/parity_lib/vt.py`, `tool/parity`,
`tool/parity-ext/run`, `tool/parity-vt/`) and is MIT. It only runs the CLI as a separate process.

## How dsh-flutter uses it

`tool/parity` and `tool/parity-ext/run` write the providers' captures in the CLI's provider output contract
(`visual-testing-results/{react,flutter}/<case>.png` and `.metadata.json`), then run the CLI's `validate`, `diff
--pairs react__flutter` and `site` with `SLOCK_VISUAL_REPO_ROOT` pointing at the run's output directory. The CLI's only
runtime dependency here is `sharp` (pinned in `tool/parity-vt/package.json` and `pnpm-lock.yaml`, installed outside
the repository by `tool/parity setup`). Details: `docs/parity.md`.

## Updating

1. Pick the new raft-source tag and note its commit.
2. Replace the files, without editing them:
   ```sh
   git clone --depth 1 --branch <tag> https://github.com/botiverse/raft-source "$TMPDIR/raft-source"
   rsync -a --delete --exclude node_modules --exclude LICENSE --exclude README-VENDOR.md \
       "$TMPDIR/raft-source/packages/visual-testing/" tool/vendor/raft-visual-testing/
   cp "$TMPDIR/raft-source/LICENSE" tool/vendor/raft-visual-testing/LICENSE
   ```
3. Update the tag and commit in this file, in `THIRD_PARTY_NOTICES.md` and in `docs/parity.md`. If the license text
   changed, re-check the Permitted Purpose reasoning above.
4. If `package.json` there changed its `sharp` range, update `tool/parity-vt/package.json` and run
   `corepack pnpm install` in a copy of that directory to refresh `pnpm-lock.yaml`.
5. Run `tool/parity selftest`, then both suites, and compare the scores with the previous run before opening the PR.
   Fix incompatibilities in the glue (`tool/parity_lib/vt.py`), never in this directory.
