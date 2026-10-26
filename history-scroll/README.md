# Preserve the reader's history position

Implementation `0400a2ec076c63447e20a753cf5a82c7fd611cef`. All content in these captures is synthetic.

Previously, any changed row list with a pending row after the last durable message was classified as a new local send. A running-state update, older history page or remote steering echo could therefore call return-to-latest even after the reader had scrolled away. The two original desktop reproductions failed on the preceding main implementation: an existing pending echo plus a running-state update moved the offset by 380px; a remote next-step inbox update did the same.

Only newly observed local non-queued request IDs now trigger the local-send jump. Existing pending echoes and remote inbox updates preserve the reading position. New local sends measure the tail after their pending row lays out; a deferred jump is scoped to its original controller. Manual return-to-latest and following an already visible live tail retain their existing behavior.

Validation on the exact implementation tree:

- All13 local preflight checks passed, with no skipped checks. The chat/timeline suites pass33 tests. Four new regressions cover existing pending echoes, remote inbox changes, actual desktop wheel scrolling with an older page, and a new local send within one viewport of the tail.
- Normal and synthetic-fixture Linux release and Android debug builds passed.
- Native Weston14 / Intel LNL GPU replay passed five assertions per desktop light and phone dark: scroll away, retain the same reading pixels across running/remote/history updates, and return for an intentional new local send. Final reading and local-send captures were manually inspected. The new tail includes the remote steering item, local pending echoes and running indicator, confirming those updates actually landed.
- AndroidAPI36 emulator replay passed six real tap/touch-scroll scenes. The same synthetic question kept its bounds within one physical pixel through all three update types. A new local send reached the latest tail. The emulator uses SwiftShader; this does not claim physical Android GPU validation.

These are behavioral regression checks against the reproduced problem; they do not claim a new visual-alignment score. No fonts, design tokens, thresholds or pixel classifier changed. No real user messages, credentials or raw runtime logs are included. Normal APK restored/stopped; owned emulator/app/Weston processes stopped, shared ADB retained. No release or deployment.

[Exact validation and build hashes](receipt.json) · [Desktop reading](gpu/history.desktop/reading.png) · [Desktop after remote update](gpu/history.desktop/remote-update.png) · [Desktop after intentional send](gpu/history.desktop/local-send.png) · [Phone reading](gpu/history.phone/reading.png) · [Android reading anchor](android/reading-anchor.json)
