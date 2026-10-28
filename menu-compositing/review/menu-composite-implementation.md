# Menu composition implementation handoff — 2026-10-28

Clean isolated worktree `scratch/whalee-menu-compositing`, branch `codexalice/menu-compositing`, base80a1b160d15b7287789604cef69bc38a6a1fa1ad. Commit4feb2c38e63fc61f0e2a6dab125bd5709be7ccb2, “Composite menu rows over their declared opaque material”. No primary/popover worktree changes, native runs, full suites, builds, pushes or PR operations.

Exact tree: a32ed26154623c6ee9ced491712348f44330557f.

Only three committed files:

- `packages/dsh_ui/lib/src/dsh_menu_surface.dart`: standard and dock materials expose their already-computed opaque fill via existing DshSurface around content.
- `packages/dsh_ui/lib/src/dsh_menu_item.dart`: canonical row fills call existing DshSurface.paint only over a declared opaque ground. Unknown or nonopaque contexts retain the exact prior raw fill, including fractional alpha.
- `packages/dsh_ui/test/dsh_menu_compositing_test.dart`: eight focused tests covering actual raster pixels for light/dark model cells/options and check-only/focused/selected-fill/disabled states, semantic tap/selection and keyboard activation, dock ground declaration, unscoped/nonopaque custom-alpha preservation.

No generated tokens/colors/fonts/filter values changed. Product diff is9insertions/3deletions; no new paint algorithm. Variable backdrops are not represented as a fake uniform surface: the existing MenuSurface remains the same bounded opaque material, and unknown/nonopaque callers are left translucent. Future dynamic-filter work needs its own actual surface contract.

## Verification

All toolchains on k172 with absolute scripts/pr16-env.sh. Offline workspace pubget passed. Clean RED log `.local/menu-compositing-red-clean.log`: light modelCell/modelOption2PASS; dark2FAIL at actual rendered pixels, expected source(57,58,62), old actual(58,59,62). Initial RED log retained with an already-corrected test semantics-handle cleanup issue; use clean RED for evidence.

GREEN `.local/menu-compositing-green.log`:24PASS = new8 + existingmenu-family13 + popover-material3. This includes light/dark current selected/disabled/focus/action behavior. Three-file Dart analysis and design-system ratchet guard pass; logs `.local/menu-compositing-{analyze,guard}.log`. Format and gitdiffcheck pass.

## Actual source-capture proof

Four production model Effort fixtures captured only, directly through `features/dsh_feature_model_selection/test/parity/parity_capture_test.dart --no-pub` with four-entry PARITY_PLAN. Log `.local/menu-compositing-capture-model-only.log`,4PASS. Reused exact retained final source PNG+metadata, SHA and original paths in `build/parity-menu-compositing/retained-source-provenance.json`; source reference remains687f282/0.2.1-rc.2/Chromium145. No reference rerender or scorer/threshold change.

Detailed actual pixel comparison: `build/parity-menu-compositing/source-comparison-proof.json`. Both source and new Flutter PNGs/metadata live below `build/parity-menu-compositing/visual-testing-results/{react,flutter}`. All source enclosing pixel rects match and prior Flutter geometry is identical; phone raw logical rects differ from JS only at float noise, unchanged from prior.

| Effort card | source mismatched pixels before → after |
|---|---|
| dark desktop248×110 |8555→675|
| dark phone651×290 |57872→3318|
| light desktop248×110 |622→619|
| light phone651×290 |3057→3064|

Focused dark flat RGBA now matches source(57,58,62,255); plain dark base(41,42,46,255) is preserved. Light flat fill remains source-exact(238,240,241,255), plain base(251,252,252,255). Full light images are not byte-identical: precomposited color changes antialias-edge rounding at24desktop/83phone pixels, including a net7 more source-mismatched phone pixels. This bounded corner/AA residual is explicit; no theme special casing or fitted correction was added. Text/corner/shadow residuals and overall99.5 remain unfinished.

The generic capture wrapper initially probed unrelated unmapped package entrypoints (no tests ran there); it was stopped. The final proof used only four targeted model captures directly with --no-pub. No broad suite or native work followed.

See notes/menu-composite-audit.md for retained published CSS, exact alpha/rounding derivation and independent Chromium source-material/opaque-material experiments atDPR1/2.625. Parent owns integration, broad validation and final acceptance.
