# Long RiskConfirmation default-open scroll

Yes: the preferred checkbox's native autofocus automatically scrolls the actual
source content toward the acknowledgement. Once the pinned fonts are loaded
before source mount, it reaches the actual maximum scrollTop in all8 combinations
of density, locale and theme, with the checkbox fully visible. This is an initial
focus behavior; the64-case matrix's explicit top/bottom actions should stay as
controlled captures and do not prove default-open scrolling on Flutter.

Probe: `.local/headed-open-scroll.mjs`.
Raw proof: `.local/headed-open-scroll.json`, SHA256
`c50c39cd847663e2e717375c0a5df9e7889242add92a0201335a9a4fa75ae50c`.
The same actual RiskConfirmation, long warning dictionary,320px viewport, source
bundle, pinned font files, browser arguments and CSS are used. No set-scroll,
scrollTop assignment or scrollIntoView is applied by the probe. Product, harness,
manifest, capture cache and classifier files are unchanged.

Two timing conditions are tested in fresh contexts. Ordinary mount matches the
current harness. The diagnostic preloads the same400/500 primary/CJK font faces
by holding the source bundle's network response until those faces are loaded;
then the unchanged application mounts. Font families and metrics are unchanged.

| Viewport / locale | Ordinary settled initial scrollTop | Fonts-ready initial scrollTop = actual maximum | scrollHeight | clientHeight | Fonts-ready checkbox y→bottom |
| --- | ---: | ---: | ---: | ---: | --- |
| Desktop800@1 / EN | 414 | 482 | 674 | 192 | 197→213 |
| Desktop800@1 / ZH | 260 | 262 | 454 | 192 | 197→213 |
| Phone390@2.625 / EN | 590.095215 | 657.904785 | 850 | 192 | 175.095245→191.095245 |
| Phone390@2.625 / ZH | 392 | 393.904755 | 586 | 192 | 197.095245→213.095245 |

Light/dark values are identical. Content viewport is y24→216 in every condition.
Footer is outside content at y236→272 throughout.

In every initial state the active element is the source checkbox, marked
`data-dsh-automatic-focus`; computed outline is none/0px although focus-visible
matches. Ordinary cold mount focuses before font loading finishes. After fonts
settle its EN checkbox can fall below the content viewport (desktop y265→281;
phone y242.904770→258.904770) because text gains height after native focus already
scrolled. Moving keyboard focus away and back after fonts settle reaches the same
final bottom and reveals it. This is a source font-loading timing limitation,
not a reason to reproduce the early-font offset in Flutter.

Keyboard proof, all16 contexts: first Tab from the preferred checkbox reaches
Cancel, Shift+Tab returns to the checkbox, and another Shift+Tab reaches Close.
Focusing Close automatically scrolls content back to0. Header and body remain the
same scroll region; the fixed footer stays in place.

The earlier disabled proof still applies: disabled checkbox entry leaves BODY
focused in pinned source, then the first Tab enters Close. No Flutter focus-behind
modal behavior is requested to match that source limitation.

Validation:16/16 focus/traversal contracts PASS. All8 fonts-ready cases match the
actual measured maximum scrollTop and leave the checkbox fully visible. The
implicit`--hide-scrollbars` flag remains present. All probe-owned browser contexts,
browsers and HTTP server were closed. No native runtime was started.
