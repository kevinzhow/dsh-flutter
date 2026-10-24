# Stream polish: screenshots and measurements (dsh web first)

Synthetic 320-turn session (generic text, written through dsh's own persistence, no model call), an isolated `dsh web` on
loopback. Everything visible follows dsh web at the same width; raft-flutter's mechanics are invisible. Raft's skeleton and the
"N new" count are off behind one flag (`streamExtras`); their earlier screenshots are in `../stream-v1/`.

- `compare/`: dsh web (left) next to Whalee (right), light and dark, at 1280x720 and 390x844 (the Linux build with the desktop
  shell / phone drawer, same window size, density 1), and the 390 web window next to the Android emulator.
  `{light,dark}_{1280,390}_{latest_end,back_to_bottom,loading_history_hint,actions_hover,selection,load_earlier_loading}` and
  `{light,dark}_emulator_{latest_end,back_to_bottom,selection,loading_history_hint,load_earlier_loading}`.
  dsh web's 390px window keeps its 56px icon rail (no drawer), so the panes differ in width there; the column's right edge and
  the composer card's right edge are the same on both.
- `whalee-emulator/`: Android emulator (411dp, AMD iGPU, profile build), raw 1080x2400 (`*_2b_after_jump` is the state the
  selection starts from).
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
| Back to bottom | dsh's plain 34px chevron (`.toBottom`), at the message column's trailing edge, 16px above the composer; 44px touch area |
| Copy and clock under a message | shown on every row where nothing can hover, hidden-until-hover on earlier rows where a pointer hovers: dsh's `@media (hover: hover)` rule (`MessageIconActions.module.css`), keyed on the input device, not the width |
| Selection | one selection across messages (browser-like); on touch a long press with handles and the platform Copy / Select all toolbar, a touch outside the list clears it |
| Scrollbar | wide windows and pointer devices: dsh's 5px thumb in `--dsw-alias-scrollbar-*`, always visible, draggable; touch phones: none (raft-flutter) |

Message column (layout), as dsh web draws it (`ConversationRoot.module.css` `--dsh-chat-content-width`, `ChatView.module.css`
`.scroll` / `.column`, `InputBar.module.css` `.root` / `.card`): content width = `clamp(680px, 64% of the conversation column, 920px)`; the
message column is `min(content width, scroll width - 64px)`, the composer card `min(content width + 32px, scroll width - 32px)`, both
centred in the scroll body that is left of its 2px margin and the 5px scrollbar gutter (no gutter on a touch phone). Measured in dsh
web at 1280x720: column x 436.5..1116.5, card x 420.5..1132.5, to-bottom button right edge 1116.5; Whalee draws the same.
