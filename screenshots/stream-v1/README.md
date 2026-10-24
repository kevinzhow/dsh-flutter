# Stream polish screenshots

Synthetic 320-turn session (generic text, written through dsh's own persistence, no model call), isolated `dsh web` on loopback.
`compare/` puts dsh web next to Whalee (light and dark). `whalee-phone/` are raw Android emulator captures (1080x2400, 411dp),
`whalee-desktop/` raw Linux-build captures at 1280x720, `dsh-web/` the dsh web side (headless Chromium; dsh web has no phone
layout, at 390px it keeps an icon rail).

| Element | File prefix in `compare/` | How it adapts dsh's design (raft-flutter pattern followed) |
|---|---|---|
| Message actions (clock + copy) | `phone_*_1_latest_end_actions` | dsh `MessageIconActions`; always visible on touch (dsh's `hover:none` rule; raft-flutter's `coarsePointer` turns hover chrome off), 44px touch target with the glyph flush to the row edge |
| Back-to-bottom button | `phone_*_2_back_to_bottom_button` | dsh `.toBottom` (34px round chevron, floating fill, l3 ring) at the trailing edge, 16px above the composer, in a 44px target; placed in the timeline stack like raft-flutter's `RaftTimelineBottomControls` |
| New-content count | `phone_*_4_new_content_count` | raft-flutter's "N new" in place of "Back to bottom", drawn as dsh's button widened to a pill (dsh has no count) |
| Scroll indicator | `phone_*_3_scroll_indicator` | thin 3dp non-interactive bar in dsh's scrollbar token, fades after scrolling (Kevin's request; raft-flutter shows nothing on touch) |
| Selection | `phone_*_5_selection` | long press selects a word with handles and the platform Copy / Select all toolbar, one region per message, a touch outside clears it (`RaftSelectionArea`, `message_body.dart`) |
| Skeleton, session opening | `phone_*_6_skeleton_session_open` | raft-flutter's `RaftSkeleton` pulse (2s, still under reduced motion), dsh hover-fill and bubble tokens, shaped like a stream; dsh shows the text "Loading history..." |
| Skeleton, older page | `phone_*_7_skeleton_older_page` | the same rows above the oldest message while a page is read; dsh's "Load earlier" button stays as the fallback |
| Desktop: latest end, back-to-bottom, hover actions, selection, scrollbar (visible, hover, drag), skeletons | `desktop_*` | replicated from dsh web: 5px always-visible thumb in `--dsw-alias-scrollbar-*`, hover-revealed actions on earlier rows, list-wide mouse selection with Ctrl+C |
