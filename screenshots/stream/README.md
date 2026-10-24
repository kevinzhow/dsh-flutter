# Stream polish: screenshots and measurements (dsh web first)

Synthetic 320-turn session (generic text, written through dsh's own persistence, no model call), an isolated `dsh web` on
loopback. Everything visible follows dsh web at the same width; raft-flutter's mechanics are invisible. Raft's skeleton and the
"N new" count are off behind one flag (`streamExtras`); their earlier screenshots are in `../stream-v1/`.

- `compare/`: dsh web (left) next to Whalee (right), light and dark, at 1280x720 and 390x844 (the Linux build, same window size,
  density 1), plus emulator-only sheets for the phone.
  `{light,dark}_{1280,390}_{latest_end,back_to_bottom,loading_history_hint,actions_hover,load_earlier_loading}`.
- `whalee-emulator/`: Android emulator (411dp, AMD iGPU, profile build), raw 1080x2400.
- `whalee-linux/`, `dsh-web/`: the raw captures behind `compare/` (`dsh-web/elements/` are the element crops).
- `measurements/frame-timing.txt`: frame build / raster times from `FrameTiming` (`apps/dsh_flutter/lib/perf_main.dart`).
- `measurements/parity-ext-chat-stream-summary.md`: element-level parity against dsh's real `ChatView.module.css` rules and
  `MessageIconActions` (`tool/parity-ext/run run --cases 'components.chat-stream.*'`, native density reference);
  `measurements/parity-ext-pairs/`: side by side of a few.

What a phone shows, and why (dsh web's own rules, not raft-flutter's touch rules):

| Element | At the phone width |
|---|---|
| Opening a session | the hint "Loading history…" (dsh `.hint`), nothing else |
| Older history | dsh's "Load earlier" control (disabled "Loading…" while a page is read); pages are also read when the reader nears the top |
| Back to bottom | dsh's plain 34px chevron (`.toBottom`), trailing edge, 16px above the composer; 44px touch area |
| Copy and clock under a message | shown on every row where nothing can hover, hidden-until-hover on earlier rows where a pointer hovers: dsh's `@media (hover: hover)` rule (`MessageIconActions.module.css`), keyed on the input device, not the width |
| Selection | one selection across messages (browser-like); on touch a long press with handles and the platform Copy / Select all toolbar, a touch outside the list clears it |
| Scrollbar | wide windows and pointer devices: dsh's 5px thumb in `--dsw-alias-scrollbar-*`, always visible, draggable; touch phones: none (raft-flutter) |
