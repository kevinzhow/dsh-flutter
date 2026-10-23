# dsh-flutter

A cross-platform native client for DSH (DeepSeek Harness), built with Flutter. Working name: Whalee.

Status: phase 1b-1 (phone-first chat: pairing, session list, streamed conversation, tool-specific cards, to-do and plan surfaces, subagent transcripts, approvals and questions). Not affiliated with or endorsed by DeepSeek; an unofficial third-party client with no DeepSeek logo or brand asset.

## Layout

One package per layer of dsh's own web client (`docs/subsystems/web-client.md` upstream), one-way dependencies:

```
packages/dsh_client        pure Dart   pairing, connection generations, /api/remote.mux, unary /api calls
packages/dsh_models        pure Dart   ClientSessions -> SessionManager -> Session (list, live updates, event window)
packages/dsh_conversation  pure Dart   event registry + assembler (Contexts, Locations), the chat target, submitted plans and the todo history, ported from ui-conversation/ui-chat/ui-plan/ui-tool
packages/dsh_slots         pure Dart   typed slot registry, slot names are dsh's own
packages/dsh_theme         Flutter     theme contract engine, vocabulary = dsh --dsw-* tokens, official pack
packages/dsh_ui            Flutter     UI primitives that read only the theme contract (rows, terminal/diff/read/search/web blocks, icons from dsh's SVG paths)
packages/dsh_i18n          pure Dart   zh/en catalog generated from dsh's locale dictionaries
features/dsh_feature_approval          ui-approval: composer takeover for approval requests
features/dsh_feature_chat              ui-chat: chat view, user/assistant/turn nodes, reasoning, markdown
features/dsh_feature_conversation      ui-conversation: session shell, header + model indicator, composer (send/stop), to-do dock
features/dsh_feature_plan              ui-plan: submitted-plan cards, plan sheet, plan-mode chip
features/dsh_feature_session           ui-session: the session list
features/dsh_feature_subagent          ui-subagent: header catalog, child transcripts (read-only)
features/dsh_feature_tool              ui-tool: tool rows and cards per tool kind (tool.call.toolview, generic fallback)
features/dsh_feature_user_questions    ui-user-questions: composer takeover for agent questions
                                       (one feature per dsh ui-* package; features never import each other)
apps/dsh_flutter                       composition root: pairing, navigation, platform manifests (Whalee)
tool/                                  generators, guards, preflight, live spike, visual parity tool (docs/parity.md)
tool/vendor/raft-visual-testing/       vendored Raft visual-testing CLI, FSL-1.1-ALv2 (not MIT), see License below
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
python3 tool/vectors/gen_expected.py --check <fixture>     # TS-produced expectations for the behaviour vectors
```

## Behaviour vectors

A vector is a trace (follow frames, pages, client actions) replayed through dsh's own TypeScript code to produce
expected snapshots, which the Dart port must reproduce exactly after every step: `expected` is the Session event
window (client model), `expectedChat` the chat snapshot of dsh's real conversation engine and chat Definitions
(`tool/vectors/ts/chat_glue.mjs`). Fixtures: `session_window_vector.json` (recorded, scrubbed),
`tool_turn_vector.json` (recorded live tool-call turn, scrubbed; tool argument keys kept), and
`conversation_edge_vector.json` (synthetic: reasoning and tool-call streaming, interruption, steering, failure,
max tokens, notice-woken turn, retry; `tool/vectors/synth_edge_trace.py`).

## Product name

The display name and application id live in `apps/dsh_flutter/lib/src/app_identity.dart` and are repeated in the
platform manifests (Android, iOS, Linux); `test/app_identity_test.dart` fails when they drift.

## Live tests

`tool/live_spike/bin/live_app.dart` starts its own `dsh web` on 127.0.0.1 and runs the app-layer live test
(`apps/dsh_flutter/test/live`, tag `live`) against it; `tool/live_spike/bin/live_spike.dart` is the phase-0 protocol spike.

`tool/live_spike` starts its own `dsh web` on `127.0.0.1`, drives the Dart client against it (pairing, streaming,
cancel, approvals, restart and re-pair) and records timings; see the phase-0 PR for results.

## License

dsh-flutter is MIT licensed (`LICENSE`). Exceptions, each under its own license and listed in `THIRD_PARTY_NOTICES.md`:

- `tool/vendor/raft-visual-testing/` is Raft's visual-testing CLI, vendored unchanged and licensed
  [FSL-1.1-ALv2](tool/vendor/raft-visual-testing/LICENSE) (Copyright 2026 Botiverse, Inc.), **not MIT**. It is used only as an
  internal development and test tool for the visual parity tool (`docs/parity.md`); see its
  [`README-VENDOR.md`](tool/vendor/raft-visual-testing/README-VENDOR.md) for the origin, the Permitted Purpose and how to update it.
- The pinned parity fonts (`tool/parity-fonts/`) are SIL OFL 1.1.
- Data and types generated from DeepSeek Harness (MIT) are covered by its notice.
