# Canonical icon-action adoption

This bounded button-family change retires `DshIconButton` and moves three
Whalee-only connection controls to the existing published `DshButton`
`iconAction` profile: pairing Settings, repair Back, and scanner Close. The
source action is 28×28 with the generated 16px icon seat; the old 44px outer
seat, 36px circle and 18px glyph are removed. No replacement wrapper or hit padding
preserves those handwritten dimensions. Existing Charcoal glyphs remain the
native-only icon adapter defined by `tool/icons/gen_charcoal_icons.py`.

`packages/dsh_ui/pubspec.yaml` and the workspace both declare
`publish_to: none`; the package resolves inside the Dart workspace. A complete
current-tree search found three production calls, one constructor declaration,
and one export; no other wrapper import, test caller or declared external
package consumer was found. This does not establish that an unknown external
Git consumer cannot exist. The obsolete class and export are removed together.

The per-file guard now observes 892 metric matches and 0 duplicate-button
matches, down from 895 and 4. The duplicate total represented **three calls plus
the constructor**, not four controls. The metric reduction is exactly the
wrapper's width36, height36 and icon18 expressions. Pattern coverage and
wrapper allowances remain unchanged; platform-control matches remain 11.
Count reductions are not a claim of complete visual parity.

The source is DSH 0.2.1-rc.2, pinned reference commit
`687f282e8625c6b8d11ff58211a90524be2e4317`. Existing generated
`DshIconActionRecipe` reads published PluginManager `.iconButton` CSS:
radius-sm, caption idle/secondary hover, transparent idle, hover-fill token,
disabled group opacity .5, and explicit solid focus width/color/offset 1.
`DshButtonRecipe.iconSize` comes from published primitive Button `.icon`.
There are no new product style numbers or colors in this change.

Before changing the shared control, `tool/design-system/capture-icon-actions.mjs`
rendered the actual published PluginManagerPage and HeaderLeadingControls.
Their integrity-verified `package/lib/client.js` factories are evaluated with
one measurement hook immediately before the final return, exposing the private
component binding. **No component body or CSS is rewritten.** The manager
bundle's SHA256 remains
`b4efaa441258a547a0d7b3cab559fe073c69e69fe2bbb617c710ded134e7c4f9`.
Supporting primitives are the actual pinned upstream modules; store snapshots,
callbacks and labels are fixture data. Published theme sheets, source Web mount
defaults, and the existing parity font manifest define the surrounding context.
This fixture is a source behavior/profile proof, not production connection-page
pixel acceptance.

The final source proof is `build/icon-actions-source-final2/source-trace.json`
with `provenance.json`, 144 screenshots, pointer/touch/keyboard events and
computed styles. It covers light/dark, DPR 1/2.625, mouse at desktop width 640 and
touch at phone width 390. All 16 profile/state checks pass. The original 120 PNGs
and the intermediate 144 PNGs remain in `build/icon-actions-source` and
`build/icon-actions-source-final`; those preliminary hosts lacked the final
Web font/mount setup and are retained investigation evidence, not the final
visual reference.

The actual source establishes these state distinctions:

- Mouse hover changes icon-action fill and foreground; a held pointer uses the
  same hover styling. Moving one pixel beyond the control clears it while
  `:active` remains true, and returning restores it.
- Touch-down has no hover fill or hover foreground. Current Flutter previously
  synthesized these from `_pressed`. Only iconAction's predicate now follows
  `_enabled && _hovered`. Primitive, add, info and Header predicates, focus,
  callbacks and opacity code are unchanged.
- Home/keyboard focus gives the source icon action its solid token outline;
  disabled source actions retain idle color/fill and do not activate.
- Chromium synthesizes sticky `:hover` after touch-up, persisting after its
  transient `:active` state ends, until an outside touch. Header exhibits the
  same browser behavior. **This post-touch-up behavior remains UNMATCHED and
  PENDING in Flutter. It is not an approved platform exception or completed
  parity.** No synthetic-hover timeout, fitted state/color, or Header rewrite
  is introduced here. Existing Header native auto-outline paint limitations
  also remain open.

Meaningful pre-change results are retained in
`.local/icon-actions-profile-red2.log` (four state failures, one passing
keyboard/semantics/disabled case) and `.local/icon-actions-routes-red2.log`
(18 failures on the old 44px route geometry). Earlier `*-red.log` files also
retain an initial test-only semantics-handle cleanup failure; those results
must not be counted as five product failures.

The bounded implementation passes 30 canonical/profile tests, including all
existing primitive/add/info/Header profile tests, and 18 real-route cases for
the three controls. Pointer, keyboard and semantics activation open Settings
or pop the appropriate repair/scanner route; no connection is created by those
actions. Cases cover desktop/phone, light/dark across the matrix, and phone
DPR 2.625. Canonical tests prove callback counts and disabled blocking. The
route fixtures establish the navigation outcome, rather than independently
instrumenting the application's callback invocation count. Focused analysis
and the unchanged guard pass. Logs and a hash-bound receipt are retained in
`.local/icon-actions-*.log` and `build/icon-actions-receipt.json`.

Reproduce from this worktree on k172:

```sh
source /home/kevinzhow/.raft/agents/c337cede-cf80-47b0-8830-fde6dd880664/scripts/pr16-env.sh
node tool/design-system/capture-icon-actions.mjs --archives <verified-archive-directory> --out <new-output-directory>
```

The three native connection pages have no exact pinned Web route counterpart.
Their published-profile adoption and route behavior are checked separately
from the actual Web manager and the source-measured profile regions.

`apps/dsh_flutter/test/parity/icon_actions_main.dart` mounts the real routes
with offline services, passive effect counters and an injected camera preview.
F6/F7 only prepare routes. F8 returns to pairing and clears remembered focus
before ordinary Tab traversal. Pointer and keyboard activation still use the
production buttons. The literal native manifest has four GPU cases with 76
image assertions and 76 screenshots; its Android section specifies twelve
captures, 20 inputs sent once each and 27 checks, including a unique focused
descendant within each labeled action's own bounds. Five forward Tabs reach
Back from the Android route's first editable field. An injected Shift+Tab
advanced focus in the observed API36 run; reverse injection remains pending.
The earlier native focus failure and separate traversal diagnostics are
retained as failed/history evidence.

`icon_actions_source_raster_test.dart` replays all 144 actual source states
(80 IconAction, 64 Header), retaining full native frames and source-defined
control crops. Callback counts agree in preparation; 36 pointer-focus ownership
differences, post-touch synthetic hover and Header UA outline paint remain
unmatched. Raw RGBA differences have no equality or fitted acceptance gate.
The actual PluginManager refresh toolbar also has sixteen paired idle/hover
screens. These comparisons establish neither full-family completion nor Web
pairing, production-camera or network parity.
