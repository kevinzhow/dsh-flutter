# dsh-flutter

A cross-platform native client for DSH (DeepSeek Harness), built with Flutter. Working name: Whalee.

Status: step 5 (phone-first chat: pairing, session list, streamed conversation, tool-specific cards, to-do and plan surfaces, subagent transcripts, approvals and questions with their timed waits; attachments: pick, upload, gallery; workspace file browser and document preview; syntax highlighting; settings page, model and permission selection, local notifications; the sidebar terminal). Not affiliated with or endorsed by DeepSeek; an unofficial third-party client with no DeepSeek logo or brand asset.

## Layout

One package per layer of dsh's own web client (`docs/subsystems/web-client.md` upstream), one-way dependencies:

```
packages/dsh_client        pure Dart   pairing, certificate trust (pins), connection generations with backoff status, /api/remote.mux, unary /api calls (multipart binary results), streamed file upload, workspaceFiles client
packages/dsh_models        pure Dart   ClientSessions -> SessionManager -> Session (list, live updates, event window); terminal views over the duplex attach stream
packages/dsh_conversation  pure Dart   event registry + assembler (Contexts, Locations), the chat target, submitted plans and the todo history, ported from ui-conversation/ui-chat/ui-plan/ui-tool
packages/dsh_slots         pure Dart   typed slot registry, slot names are dsh's own
packages/dsh_theme         Flutter     theme contract engine, vocabulary = dsh --dsw-* tokens, official pack
packages/dsh_ui            Flutter     UI primitives that read only the theme contract (rows, terminal/diff/read/search/web blocks, icons from dsh's SVG paths)
packages/dsh_i18n          pure Dart   zh/en catalog generated from dsh's locale dictionaries
packages/dsh_highlight     pure Dart engine + Flutter assets   syntax highlighter: TextMate engine in Dart on shiki's grammars, scopes mapped to dsh's 9 --shiki-token-* classes
features/dsh_feature_approval          ui-approval: composer takeover for approval requests
features/dsh_feature_attachment        ui-attachment: composer attachment tray (pick, upload progress/cancel/retry), image tiles in messages
features/dsh_feature_chat              ui-chat: chat view, user/assistant/turn nodes, reasoning, markdown
features/dsh_feature_conversation      ui-conversation: session shell, header + model indicator, composer (send/stop), to-do dock
features/dsh_feature_documentpreview  ui-documentpreview: highlighted text, rendered/raw Markdown, image, open/save for other types
features/dsh_feature_files             ui-files: workspace file tree, live-watched
features/dsh_feature_plan              ui-plan: submitted-plan cards, plan sheet, plan-mode chip
features/dsh_feature_session           ui-session: the session list
features/dsh_feature_model_selection   ui-model-selection: model/effort seat in the composer tool row, model sheet
features/dsh_feature_permission_presets ui-permission-presets: new-session default row, composer permission seat
features/dsh_feature_settings          ui-settings: settings page (rail on wide windows, list then section on phones), General column
features/dsh_feature_theme             ui-theme: light/dark/system appearance, font families and sizes (shared with dsh web through the host)
features/dsh_feature_sidebar_right     ui-sidebar-right: tab strip, guide page, files/preview/terminal tabs (full-screen sheet on phones, inline column on wide windows)
features/dsh_feature_sidebar_terminal  ui-sidebar-terminal: interactive shell tabs on the xterm emulator, key bar for phones (docs/terminal.md)
features/dsh_feature_subagent          ui-subagent: header catalog, child transcripts (read-only)
features/dsh_feature_tool              ui-tool: tool rows and cards per tool kind (tool.call.toolview, generic fallback)
features/dsh_feature_user_questions    ui-user-questions: composer takeover for agent questions
                                       (one feature per dsh ui-* package; features never import each other)
apps/dsh_flutter                       composition root: pairing, navigation, platform manifests (Whalee)
tool/                                  generators, guards, preflight, live spike, visual parity tool (docs/parity.md)
tool/vendor/raft-visual-testing/       vendored Raft visual-testing CLI, FSL-1.1-ALv2 (not MIT), see License below
```

`tool/check_deps.py` enforces: client <- models <- conversation <- slots/features; features never import each other; ui and theme never import client; highlight is a leaf that only ui and apps may use.

## Pinned versions

- Flutter 3.47.6 / Dart 3.13.5 (`.fvmrc`). Use that SDK's `dart`, not the one on `PATH`.
- dsh `687f282e8` / npm `0.2.1-rc.2` (`docs/upstream-sync.json`). dsh has no stable API: a client pins an exact host version
  (`readHostVersion` in `dsh_client` reads it from `pluginManager/listBundles`).

## Working on it

```sh
flutter pub get                       # workspace resolution, run from the repo root
tool/preflight --fast                 # guards: layering, codegen/theme/i18n staleness, format, analyze
tool/preflight                        # same plus every package's tests (not the `live` ones, which start real dsh hosts)
```

CI (`.github/workflows/ci.yml`) runs `tool/preflight` on every pull request and push to main, and builds an Android APK
(see "CI builds and release signing"). It has no dsh checkout, so it skips four checks on purpose and says so in the job
summary: `theme-pack`, `icons`, `vector` and `parity` (the parity selftest). Run the full `tool/preflight` locally before a PR.

Generators read the pinned dsh checkout: put it at `.local/dsh-src` (or set `DSH_SRC`). They are committed output
with a `--check` mode:

```sh
python3 tool/codegen/gen.py [--check]                      # Remote descriptors + event schema -> Dart
python3 tool/theme-adapters/build_official_pack.py [--check]   # dsh stylesheets -> official theme pack
python3 tool/i18n/gen_catalog.py [--check]                 # dsh locale dictionaries -> zh/en catalog
python3 tool/vectors/gen_expected.py --check <fixture>     # TS-produced expectations for the behaviour vectors
python3 tool/vectors/gen_settings_expected.py --check <fixture>   # the same for the settings vectors
```

## Connecting to a host

Whalee talks to a `dsh web` that you run yourself. Nothing goes through a server of ours.

1. On the computer that hosts your sessions, start it: `dsh web --no-open`. It prints one line, `dsh web: http://127.0.0.1:8686/?token=...`.
   That **launch link** is the key to the host: anyone who has it can use your agent, so treat it like a password. It stops
   working when the host restarts (the next `dsh web` prints a new one).
2. To reach it from a phone the host must listen on an address the phone can reach, not only on the loopback address:
   `dsh web --no-open --host <address of this computer>` (dsh refuses "all interfaces" on purpose). The printed link then
   carries that address. Behind a reverse proxy or a port forward, `--public-url <url>` makes it print the address the phone
   really uses, and `--trusted-host <host:port>` tells the host to accept it.
3. In Whalee, paste the link, or scan a QR code of it. dsh does not draw a QR code, so make one on the computer with a tool
   that works offline, for example `qrencode -t ansiutf8 '<launch link>'`, and scan it off the screen. Do not paste the link
   into a website that makes QR codes: it would see your key. Whalee only accepts a code that is a complete launch link and
   never shows or logs what the code contained.

### Plain http, and what Whalee does about it

A `http://` host sends everything (including your prompts and the launch link) unencrypted. Whalee therefore accepts plain
http only for the device itself and for private networks (loopback, `10.x`, `172.16-31.x`, `192.168.x`, link-local, the
`100.64.0.0/10` range that Tailscale uses, IPv6 unique-local; a host name counts when every address it resolves to is one of
those). Any other `http://` address is refused. An accepted http connection says **Not encrypted** next to the host address, and
the pairing form warns while you type it. Use it only on a network you trust.

### https with a certificate of your own (self-signed)

`dsh web` serves https when you give it a certificate and its key: `--tls-cert <file> --tls-key <file>` (PEM, key without
passphrase). A certificate you made yourself is not signed by anyone the phone knows, so Whalee does not trust it on its own.
Make one for the address you will connect to (here `<address>`, and a name if you have one):

```sh
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 365 \
  -keyout dsh-key.pem -out dsh-cert.pem -subj "/CN=dsh" \
  -addext "subjectAltName=IP:<address>,DNS:<name>"
chmod 600 dsh-key.pem
dsh web --no-open --host <address> --tls-cert dsh-cert.pem --tls-key dsh-key.pem
```

The first time Whalee connects it shows the certificate's **SHA-256 fingerprint** and sends nothing else: no request, no
launch link. Compare it with the fingerprint on the host:

```sh
openssl x509 -in dsh-cert.pem -noout -fingerprint -sha256
```

If they are the same, choose **Trust and connect**. Whalee remembers that one certificate for that host and port
(Settings, General, Host shows it and has **Forget certificate**) and from then on talks to exactly that certificate. If the host
later shows a different one, even one a public authority signed, Whalee refuses, sends nothing, and says the certificate
changed; you can look at the new fingerprint and trust it only after confirming that warning. There is no setting that accepts
every certificate. A certificate that a public authority signed (for example from Let's Encrypt) needs no confirmation.

### Tailscale

If the phone and the computer are on the same tailnet, the simplest setup is to let `dsh web` listen on the computer's
tailnet address and use the launch link with that address (Tailscale encrypts the path between the two devices, though to Whalee
it is still plain http and says so, because the app cannot see the tunnel). For an encrypted connection that needs no
confirmation, Tailscale can issue a real certificate for the computer's tailnet name (`tailscale cert <name>.<tailnet>.ts.net`,
after HTTPS is enabled for the tailnet); give those two files to `--tls-cert` and `--tls-key`, bind to the tailnet address, and
start `dsh web` with `--public-url https://<name>.<tailnet>.ts.net:<port>/` so the printed link carries that name.

### When the connection drops

Whalee keeps your sessions on screen and your unsent messages in place while it reconnects. It retries after 0.5 s, then 1, 2,
4, 8 and every 10 s at most, and shows what dsh web shows (Reconnecting, Disconnected, Connected) with the retry number and a
countdown; tapping it retries at once. After three failed retries it says the host cannot be reached. If the host restarted,
the launch link is no longer valid: Whalee says so and **Pair again** takes a new link (scan or paste) without leaving your
sessions.

## CI builds and release signing

The workflow `.github/workflows/ci.yml` (actions pinned by commit SHA, Flutter from `.fvmrc`) has two jobs:

- **preflight**: `tool/preflight --allow-skip theme-pack,icons,vector,parity`. The four named checks need the pinned dsh
  checkout (and, for `vector`, its node install), which CI does not have; they are skipped, listed in the job summary with the
  reason, and any other skipped check fails the job. Everything else runs: layering, tool tests, codegen and i18n staleness
  (offline mode), format, analyze and every package's tests.
- **android apk**: `flutter build apk --release`, uploaded as a workflow artifact (14 days). With no release keystore the APK
  is signed with the Android **debug** key and the job summary says so; such an APK installs for testing but is not the
  release identity (it cannot update a release-signed install, and the debug key is public knowledge).

To get release-signed APKs, add four repository secrets (GitHub: Settings, Secrets and variables, Actions, New repository
secret). The workflow signs with the release key only when all four are set; pull requests from forks never receive secrets.

| secret | value |
|---|---|
| `WHALEE_KEYSTORE_BASE64` | the keystore file, base64 on one line: `base64 -w0 whalee-release.jks` (macOS: `base64 -i whalee-release.jks`) |
| `WHALEE_KEYSTORE_PASSWORD` | the keystore password |
| `WHALEE_KEY_ALIAS` | the key alias inside the keystore |
| `WHALEE_KEY_PASSWORD` | the key password (the same as the keystore password for a PKCS12 keystore) |

With the GitHub CLI: `base64 -w0 whalee-release.jks | gh secret set WHALEE_KEYSTORE_BASE64`, then `gh secret set` for the other three.
Create the keystore yourself and keep it (and its passwords) somewhere safe outside the repository: a release identity that is lost cannot be
replaced for installed copies. For example `keytool -genkeypair -v -keystore whalee-release.jks -alias whalee -keyalg RSA -keysize 2048 -validity 10000`.

The step writes the keystore and an `apps/dsh_flutter/android/key.properties` (`storeFile`, `storePassword`, `keyAlias`,
`keyPassword`) on the runner for the build and deletes both afterwards. Both file names are git-ignored; the same
`key.properties` signs a local `flutter build apk --release` (without it the build uses the debug key). Treat anything that can edit
the workflow as able to read the secrets: do not give write access to people you would not give the key.

## Notifications

While the app is in the background and connected, a session that asks for an approval or a question becomes one local
notification; tapping it opens that session at the pending takeover. On Android the connection is kept alive by a
foreground service (type `specialUse`) that runs only while sessions are running, the app is in the background and
notifications are on; the Android 13+ permission is asked when the user turns notifications on. This is not push: once
the system kills the app nothing reaches the phone until a relay exists (out of scope). The switch is in Settings.

## Behaviour vectors

A vector is a trace (follow frames, pages, client actions) replayed through dsh's own TypeScript code to produce
expected snapshots, which the Dart port must reproduce exactly after every step: `expected` is the Session event
window (client model), `expectedChat` the chat snapshot of dsh's real conversation engine and chat Definitions
(`tool/vectors/ts/chat_glue.mjs`). Fixtures: `session_window_vector.json` (recorded, scrubbed),
`tool_turn_vector.json` (recorded live tool-call turn, scrubbed; tool argument keys kept), and
`conversation_edge_vector.json` (synthetic: reasoning and tool-call streaming, interruption, steering, failure,
max tokens, notice-woken turn, retry; `tool/vectors/synth_edge_trace.py`).

A second family, `dsh-settings-vector/1` (`tool/vectors/gen_settings_expected.py`, inputs from
`tool/vectors/synth_settings_trace.py`), covers the settings client: `settings_schema_vector.json` runs thousands of
values through dsh's real schemastery-backed schema service and compares verdict and failure text with the Dart port;
`settings_form_vector.json` replays scripted traces (reads, failures, writes, reconnects, disposal) through dsh's real
describe mirror and configuration forms; `settings_form_model_vector.json` does the same for the staged form model.

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
