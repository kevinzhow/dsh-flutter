# Reported sidebar gap — task19, 2026-10-28

The first user screenshot is the expanded desktop sidebar at approximately2×
scale, not the approved phone drawer. Its More card appears near the traffic
lights even though the launcher is at the foot. The source of truth is
DSH687f282e8625c6b8d11ff58211a90524be2e4317 and published0.2.1-rc.2.

## Source and implementation

| Part | Real source entry | Canonical Flutter entry |
|---|---|---|
| Sidebar shell/brand/New Session/panels | ui-sidebar/src/client/SidebarRoot.tsx | dsh_feature_sidebar SidebarRoot |
| Workspace groups and Session list | ui-workspace/src/client/rows/WorkspaceBrowser.tsx, Rows.tsx | dsh_feature_session WorkspaceBrowser |
| Foot margins and signed-out More | ui-settings-general SettingsRoot.tsx, ui-settings-account AccountMenu.tsx | SettingsLauncherRow |
| Floating More card | published Menu portal, MenuSurface and signed-out AccountMenu profile | DshAnchoredPanel + DshMenuSurface + DshMenuItemButton(sidebarLauncher) |

The four package archives are integrity-verified and decoded without executing
JavaScript. Their stylesheet class maps, manifest/license bytes, source hashes,
consumer dependency versions and full parsed CSS are retained by sources.lock,
upstream snapshots and recipes.generated.json. DshSidebarRecipe,
DshWorkspaceBrowserRecipe and DshSidebarLauncherRecipe read this data. New
states, declaration names or conditions in translated profiles fail generation.

Concrete corrections:

- The source52px macOS strip cancels the root6px top inset, then the60px
  logo row overlaps its last12px. The old Flutter stack applied the inset and
  shortened the logo instead: all content below it sat12px too low. The source
  puts New Session at y104 and the28px toggle center at y25.
- Source brand typography is18px/24px, weight600 and0.04em tracking. The old
  fallback used16px; the generated profile now owns it. Whalee retains its
  explicitly approved whale/name branding.
- The browser restores the12px row inset while its scroll seat reaches the
  sidebar edge; the header extends4px farther right. The old composition kept
  the entire browser inset and clipped the action cluster early. macOS no
  longer paints the opaque bottom gradient over the translucent column.
- The signed-out More launcher is32px, not42px. The source settings wrapper
  gives it4px vertical margins and2px inline expansion. Its Settings menu row
  is40px with a16px icon.
- The old CompositedTransformFollower contained a full-size Align: its bottom
  anchor used the viewport height and lifted the card to the titlebar. More
  now uses the shared bounded menu follower above the actual launcher, with
  canonical surface, row, divider, keyboard dismissal and viewport fitting.

The manual-style ratchets fell sidebar13→7, browser78→73, settings shell9→4.
This is partial migration: untouched states still remain in the inventory.

## Evidence contract and verification

`tool/parity-ext/build-reported-sidebar.py` selects12 comparisons:
macOS desktop, ordinary desktop and390px phone viewport, each in both themes
and EN/ZH. Every case mounts the *real* source SidebarRoot, WorkspaceBrowser,
SettingsRoot and AccountMenu with synthetic injected stores. The Flutter case
mounts the actual application composition through
`ReportedSidebarFixture({required i18n, platform=darwin, collapsed=false,
width=280, onAction})`. That helper has no test/parity imports and is reusable
by the native fixture target. Its two Chinese Session titles, two Workspaces
and panel labels are synthetic and identical between providers.

Focused local results:39 sidebar/settings/browser widget tests pass;35
recipe/tool tests pass; all four archives verify; source/generator and metric
ratchets pass; scoped analysis and Vite host build pass. Main owns the actual
paired captures and native GPU/Android run. This note makes no visual-score
claim before those captures run.

## Remaining differences

- The actual macOS window vibrancy/backdrop remains a platform acceptance
  requirement; a Linux fixture with macOS geometry cannot certify macOS pixels.
- The reference keeps its real account menu entries (Contact us and Sign in).
  Whalee's existing footer exposes its implemented Settings/host-security
  operations. No placeholder account/network actions were added by this fix.
  Closed-root comparisons do not certify those unported account operations.
- Sidebar pointer-linger scrollbars, rail entry/collapse choreography, keyboard
  focus on all legacy sidebar controls, New Session's hover label mask and the
  Windows caption micro-transforms remain separate static-profile gaps.
- Phone capture covers the approved drawer's real SidebarRoot content at the
  same width. AppFrame's drawer open/close/edge gesture is a native acceptance
  path; it is not claimed by this component capture alone.
