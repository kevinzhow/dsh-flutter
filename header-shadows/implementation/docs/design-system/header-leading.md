# HeaderLeadingControls source migration

This batch replaces the sidebar leading seat's private gesture/hover-painted
button with the canonical `DshButtonProfile.headerAction`. It is based on
`2a4e85c659b51fee5e1e3115f1c1a9bbe5b5b374`, with no package upgrade.

The published `@deepseek-ai/dsh-client-ui-sidebar` 0.2.1-rc.2 CSS provides the
28×28 control, radius token, secondary glyph token, hover fill and 8px group
gap. Its published `HeaderLeadingControls.js` region provides both 16px glyphs
and both 500ms tooltip delays. `header_leading_recipes.py` translates those
inputs into `DshHeaderLeadingRecipe`; the feature uses its fields without
handwritten layout metrics or a second button implementation.

The entire three-rule Header stylesheet is classified, including structural
declarations. New states, declarations, conditions, unsupported structural
values and unknown required tokens fail generation. The release behavior's
exact released text is fingerprinted after substituting only the supported
numeric delay/icon fields: changed actions, labels, shortcut IDs, native button
type, icon identity or ambiguous repeated fields also fail. This is an explicit
closed set, not a JavaScript evaluator.
Whitespace, comments and literal contents remain in the fingerprints. A
previous normalization removed whitespace inside strings and incorrectly
accepted changed shortcut/key names such as `session. new` and `Page Down`.
Four negative cases reproduced that gap before the exact-text check; the
numeric propagation tests still pass and the generated recipes are unchanged.

## Retained provenance

Reference checkout: `687f282e8625c6b8d11ff58211a90524be2e4317`.
The existing package integrities and all existing CSS/class/source hashes stay
unchanged. New inputs come from the same integrity-verified archives:

| Input | SHA256 |
| --- | --- |
| ui-sidebar `package/lib/client.js` | `4d4535b9ac9160e13067b1f8a8510d158da2aaf6a15191b418a5956261ff9b3e` |
| Actual `HeaderLeadingControls.js` region | `c37d454753de03040012910c34c36db4a4b1a5c463f6c1670ec33a2d2021b22c` |
| `HeaderLeadingControls-behavior.json` | `36dd043a238d1ef6d9b85bcd9d84ff09129a0a3c0e130789dae69f65d6bb1a2d` |
| `ui-primitives/input-modality.json` | `fee36d3bd30d2fbfb404bb2230de1ecaa7ccc905a5b3b7a10fdd4955dc14ee86` |
| Raw source `ui-primitives/src/input-modality.ts` | `91268be3f5ddb7b9a1defb13628d96082477e8771cdaa5df37d6d8b16bbbf2ba` |

`published.py` extracts and verifies the named behavior regions without
executing JavaScript. `generate.py --src` additionally verifies the pinned
source hashes and normalizes the actual Header CSS against the published CSS.

## Interaction and focus contract

Header keeps the secondary glyph color while idle, hovered or pressed. It has
only a `:hover` fill; touch press or keyboard activation does not synthesize a
ghost active fill. Canonical button semantics, pointer activation, Enter and
Space dispatch the feature actions once. The Header profile owns its geometry
and rejects caller metric overrides. Its absent disabled opacity rule is not
replaced with the primitive button's dimming rule.

Header has no local focus rule or outline offset. The generated profile reads
the locked global `focus.css` width and color tokens. The shared
`DshFocusPresentation` now separately exposes the published input modality's
pointer ownership of outline suppression. Only Header consumes that new flag
and the shared focus-visible history. Existing button profiles retain their
prior paint conditions and interaction paths.

A pointer press takes Header focus and suppresses the outline. Enter alone
does not remove suppression. Navigation keys remove it; a non-navigation key
also removes it after focus moves to another control. Four actual consumer
raster assertions first failed when Header still used Flutter's highlight
callback after mouse focus, and passed after Header switched to the existing
shared focus-visible history. Tests also retain the original profiles' behavior.

## Focused validation and evidence

Local evidence is retained under `build/header-leading/` in the isolated
`scratch/whalee-header-leading` worktree. It includes the verified package
archives, source checks, targeted logs and all failed attempts.

- Six Python tests cover actual released values, mutation propagation to every
  Header field without changing other recipes, unknown style/state/condition
  rejection, ambiguous behavior rejection, extraction and global focus drift.
- Six Header profile tests and seven consumer tests cover light/dark states,
  touch/mouse press, native semantics, keyboard callbacks, pointer/navigation
  focus ownership, focus transfer, disabled semantics, live shortcut updates,
  the 499/500ms tooltip boundary and existing Windows visibility/placement.
- Thirty existing button/profile/sidebar tests pass unchanged.
- The five touched Dart source/test files pass focused analysis. Recipe/source
  drift and the existing per-file family guard pass. The feature's actual
  manual metric count decreases from four to zero; only that debt is removed.

The reference fixture in `tool/parity-ext/host/header-leading.tsx` imports the
actual locked `HeaderLeadingControls.tsx`, actual Tooltip/icons and actual
input-modality implementation. The wrapper supplies only callback/shortcut
fixture data and a fixed capture frame. `capture-header-leading.mjs` captures
idle, hover, pressed and keyboard focus in both themes at DPR1 and DPR2, and
asserts actual DOM metrics, color inheritance, state behavior and callbacks.
Flutter's consumer test exports the matching 16 images when
`HEADER_LEADING_RASTER_OUT` is set.

`raster/source-receipt.json`, `raster/comparison.json` and `receipt.json` retain
the source observations and uncensored image comparison. Non-focus captures
have only small glyph/edge raster differences (maximum 1–3 channel levels).
No scorer, acceptance threshold, font, token, alpha or color was tuned to them.

## Remaining boundaries

Native Chromium `outline-style:auto` is still a renderer difference: despite
the computed CSS primary outline color, Chromium paints a UA ring (notably a
white ring in dark mode) with native geometry. Canonical `DshButton` paints
its existing theme-colored stroke. This batch fixes the Header visibility
state and uses the source tokens; it does **not** certify those focus rasters
as matching, invent UA color constants or claim full visual completion.

The source AppFrame mounts this seat only on Darwin with a collapsed sidebar;
the Header component itself renders both controls unconditionally. Flutter's
existing host additionally supports Windows caption controls, hiding New
Session while expanded and changing tooltip side/label. This batch preserves
that host behavior. AppFrame/index source files are not newly locked here, so
full platform mounting, traffic-light placement and caption behavior are not
certified by this component profile.

Header focus tests cover ordinary hardware keys, pointer focus and focus
transfer. Cross-window blur and composition originating in a separate editor
are not certified here. The feature still projects shortcut keycaps rather
than the Web's `aria-keyshortcuts` attribute into Flutter semantics. Native
applications, full suites, release builds and deployment remain the integrating
owner's next validation steps.
