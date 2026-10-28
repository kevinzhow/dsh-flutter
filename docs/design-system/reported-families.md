# Reported sidebar, statistics and model menu

The three screenshots in task19 identify production entry points: the desktop
workspace sidebar and its More launcher, session statistics, and model/effort
selection. The reference is DSH commit
`687f282e8625c6b8d11ff58211a90524be2e4317`, consuming the published
`0.2.1-rc.2` packages recorded in `tool/design-system/sources.lock.json`.

The source comparison mounts the real upstream `SidebarRoot`,
`WorkspaceBrowser`, `SettingsRoot`, `AccountMenu`, `StatsPills` and `ModelSelect`.
The data is synthetic and shared with Flutter. The 108 cases cover both themes,
English/Chinese, desktop/phone geometry, and macOS sidebar/material profiles.
`build/parity-reported-final/summary.json` records the actual comparison;
passing checks or matching dimensions does not establish the 99.5% target.

| Family | Generated profile | Canonical implementation |
|---|---|---|
| Sidebar/workspaces/More | `sidebar_recipes.py` | `SidebarRoot`, `WorkspaceBrowser`, `SettingsLauncherRow` |
| Statistics | `stats_recipes.py`, `platform_material_recipes.py` | `StatPillView`, `DshStatPanel`, `DshPopoverSurface` |
| Model/effort/search | `model_menu_recipes.py` | `ModelSeat`, `DshMenuSurface`, `DshMenuItemButton`, `DshTextField` |
| Placement/dismissal | published menu portal values | `DshAnchoredPanel`, `DshMenuFollower` |

The shared root overlay carries the initiating theme, platform and frame
insets, and refreshes when those dependencies or live data change. It measures
the panel itself, follows the actual trigger and passes outside pointer events
through so another control works on the first click. Interactive menus own
foreground focus. Static statistics panels retain trigger focus and replace
their sibling panel on pointer or keyboard activation. Escape handles the
initial key-down only, so backing out of a model submenu does not also close
the root when the key is released.

Model selection uses the compact anchored root/model/effort menu at every
width. It has no modal viewport mask or bottom-sheet header. Statistics use
the source blur, saturation, scoped macOS fill, clamping and content metrics.
The sidebar restores the source top-strip overlap, brand and browser insets;
More opens above its bottom launcher. New Session, the interactive brand,
statistics and model triggers expose their activation callbacks to assistive
technology; a locked model trigger exposes no activation action.

ModelSelect's published CSS uses a content box: its minimum/maximum widths and
height cap apply before the generated padding. The outer minimum is therefore
248px, while the short root/effort cards retain their natural heights. Model
and statistics placement use the source DOM measurement contract: integer
`offsetWidth`/`offsetHeight` and JavaScript viewport dimensions determine the
coordinates; the actual card and CSS viewport constraints retain fractional
layout dimensions. Other followers keep their existing geometry behavior.
The model search placeholder paints over the editable line instead of sizing
it. This preserves the native input box when a fallback glyph is taller.
MenuSurface reads its own generated `--dsw-menu-surface-fill` token; statistics
retain the separate scoped `--dsw-specific-menu` material. They intentionally
resolve different fills on macOS, as the released stylesheets require.

Native replay uses these production entries with synthetic services. Its scene
toolbar is painted after the sidebar's nested route so Android can expose its
semantics; a hidden measured placeholder preserves the same visual layout.
Replay receipts identify their runtime commit, inputs, assertions and cleanup.
These fixtures do not certify a paired host, the complete application drawer
gesture, or real macOS vibrancy.

Remaining differences are explicit:

- Textured statistics backdrops retain small RGB differences in the composed
  Skia readback path. The source values are blur40/saturate150; adding the source
  mirror tile mode produced identical Flutter images in all three smoke cases.
  Those probes are retained and no improvement is attributed to that change.
- Text rasterization can still differ between Chromium and Flutter. No font or
  glyph-metric override is used to hide those measured differences.
- Actual macOS window vibrancy requires macOS acceptance. Linux rendering with
  macOS geometry cannot establish it.
- The sidebar has unported account operations and remaining pointer-scrollbar,
  keyboard-control and collapse-animation profiles; see `reported-sidebar.md`.
- Model composer icon compaction and selection Toast presentation remain
  unported. Programmatic focus transfer outside the trigger/card does not yet
  reproduce the source blur-to-close behavior. Pointer, Escape and system Back
  dismissal are separate tested paths.
- Other component families and the overall 99.5% goal remain unfinished.
  Fonts, the pixel classifier and acceptance thresholds are unchanged.
