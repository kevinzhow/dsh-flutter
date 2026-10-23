# dsh-flutter

A cross-platform native client for DSH (DeepSeek Harness), built with Flutter.

Status: phase 0 (protocol spike and project skeleton). Not affiliated with or endorsed by DeepSeek.

## Layout

One package per layer of dsh's own web client (`docs/subsystems/web-client.md` upstream), one-way dependencies:

```
packages/dsh_client        pure Dart   pairing, connection generations, /api/remote.mux, unary /api calls
packages/dsh_models        pure Dart   ClientSessions -> SessionManager -> Session (list, live updates, event window)
packages/dsh_conversation  pure Dart   event definitions per target, chat target skeleton
packages/dsh_slots         pure Dart   typed slot registry, slot names are dsh's own
packages/dsh_theme         Flutter     theme contract engine, vocabulary = dsh --dsw-* tokens, official pack
packages/dsh_ui            Flutter     UI primitives that read only the theme contract
packages/dsh_i18n          pure Dart   zh/en catalog generated from dsh's locale dictionaries
features/dsh_feature_approval          one feature per dsh ui-* package; features never import each other
apps/dsh_flutter                       composition root plus the phase-0 debug screen
tool/                                  generators, guards, preflight, live spike
```

`tool/check_deps.py` enforces: client <- models <- conversation <- slots/features; features never import each other; ui and theme never import client.

## Pinned versions

- Flutter 3.47.6 / Dart 3.13.5 (`.fvmrc`). Use that SDK's `dart`, not the one on `PATH`.
- dsh `687f282e8` / npm `0.2.1-rc.2` (`docs/upstream-sync.json`). dsh has no stable API: a client pins an exact host version
  (`readHostVersion` in `dsh_client` reads it from `pluginManager/listBundles`).

## Working on it

```sh
flutter pub get                       # workspace resolution, run from the repo root
tool/preflight --fast                 # guards: layering, codegen/theme/i18n staleness, format, analyze
tool/preflight                        # same plus every package's tests
```

Generators read the pinned dsh checkout: put it at `.local/dsh-src` (or set `DSH_SRC`). They are committed output
with a `--check` mode:

```sh
python3 tool/codegen/gen.py [--check]                      # Remote descriptors + event schema -> Dart
python3 tool/theme-adapters/build_official_pack.py [--check]   # dsh stylesheets -> official theme pack
python3 tool/i18n/gen_catalog.py [--check]                 # dsh locale dictionaries -> zh/en catalog
python3 tool/vectors/gen_expected.py --check <fixture>     # TS-produced expectations for the behaviour vector
```

`tool/live_spike` starts its own `dsh web` on `127.0.0.1`, drives the Dart client against it (pairing, streaming,
cancel, approvals, restart and re-pair) and records timings; see the phase-0 PR for results.
