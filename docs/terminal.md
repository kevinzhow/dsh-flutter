# Sidebar terminal

Whalee's terminal is the port of dsh web's `ui-sidebar-terminal` (the tab, its guide card, the screen) over the Host's
`terminal` Remote namespace (`api-terminal-controller`). It lives in `features/dsh_feature_sidebar_terminal`; the models
(`TerminalView`, `ClientTerminals`) are pure Dart in `packages/dsh_models/lib/src/terminal`.

## Who may open one (visibility and permission)

dsh web has no setting, capability or permission gate on the terminal, and neither has Whalee:

- The tab type registers unconditionally and its card is always on the guide page. There is no settings row for it, no
  permission preset and no approval: `terminal.create` runs the shell directly through the Session's subprocess provider
  with the execution environment's system-user permissions, independent of the Agent's sandbox mode and approval policy
  (`.agents/notes/implemented/architecture/2026-09-16-user-terminal-permissions.md` upstream). The Host's own limits apply
  (8 terminals per Session, grid at most 500x200, 64 KiB per input command, a two-hour idle reclaim).
- Access is the pairing: whoever holds a paired connection to the Host can start a shell as the Host's user. That is the same
  as dsh web with the same launch token. Pair only hosts you trust, and prefer an encrypted address (the app already warns
  on plain http).
- A Host without the `terminal` namespace answers the first call with an error; the tab then shows dsh's own
  "Terminal error: ..." line, as web does. A Session that is gone shows "This terminal no longer exists".

## Emulator choice

Evaluated: [`xterm`](https://pub.dev/packages/xterm) 4.0.0 (MIT, TerminalStudio; 234k downloads in 30 days, 140 pub points,
Dart 3, all platforms) and `terminal_view` 0.5.0 (a very recent fork of it, one like, 900 downloads). `xterm` is the
established one and it works on the pinned Flutter 3.47.6 without changes. Its last release is February 2024 (the repository
has commits to June 2025), so it is pinned exactly (`xterm: 4.0.0`) and wrapped by our own widget so a replacement stays
local to `terminal_body.dart`/`terminal_theme.dart`. Licence and transitive dependencies are in `THIRD_PARTY_NOTICES.md`.

Known differences from xterm.js: no minimum-contrast adjustment (xterm.js lifts text to 4.5:1), no OSC colour overrides
(OSC 4/10/11/12 and their resets are ignored), no contrast-aware cursor, a hollow cursor while unfocused, and the grid is
sized from the viewport only (a read-only view does not scroll the Host's larger grid).

## Protocol (what is ported from dsh)

- `terminal/environment|shells|list|create|rename|close` are unary calls; `terminal/attach` is the duplex stream and
  `terminal/retain` the window hold. Types and descriptors are generated (`tool/codegen`, the extractor now understands
  `RemoteStream<Out, In>` and streams with several parameters).
- `DshConnection.openDuplex` is `openStream` with the uplink of the same logical stream. Nothing sent while a stream is not
  open is queued or replayed.
- `TerminalView` is dsh's `TerminalView` in Dart: create-or-find the terminal, hold it, attach after the hold is acknowledged
  on the current generation, order input and resize commands within the carrier's `inputWindow`, fail the attachment on a
  sequence gap, a stray snapshot or an out-of-order acknowledgement, never replay input after a reconnect.
- The close request is saved before the tab goes and retried at the next start (`TerminalPrefs`); a Session the Host no longer
  knows retires it.
- Not ported: persistence of the sidebar layout and of tab-to-terminal bindings (Whalee's sidebar is in memory, so a restarted
  app does not reattach; the Host reclaims an unheld idle terminal after two hours), the Host-terminal recovery list (commented out in
  the pinned dsh as well), the close-failure notice (not shown by the pinned dsh either), tab rename by double click
  (long press here), and drag/float/split docking.
