# Design system replication

The reference is DSH commit `687f282e8625c6b8d11ff58211a90524be2e4317`. Its plugin manager declares `@deepseek-ai/dsh-client-ui-primitives` as `workspace:*`; the actual referenced package version is `0.2.1-rc.2`. `tool/design-system/sources.lock.json` records that dependency, published npm tarball integrity and the hashes of the consumed published files. The checked-in CSS files are extracted from that release and checked against the pinned reference checkout.

`tool/design-system/generate.py` produces component recipes and a complete CSS rule audit for the published sources recorded in the lock. Components consume the generated recipes; colours and radii resolve through the current theme. Typography resolves to the corresponding generated theme ladder rung so user theme overrides remain effective. Unsupported states, properties or conditional rules fail generation. Reduced-motion rules are retained. The family inventory records which variants and families still need migration.

Run the pinned environment and `python tool/design-system/generate.py --check` to check the actual reference consumer dependency, package version, source CSS and generated output. CI without a reference checkout uses `--snapshot-only` to verify the published snapshot and generated output; it cannot independently check an upstream checkout it does not have. No network request is needed during validation. Updating the pin requires obtaining the newly referenced published package, verifying the archive, replacing its snapshot and lock, and reviewing the generated recipe diff. A repository tag alone is insufficient.

`tool/design-system/families.json` records the canonical components, known duplicate implementations and migration status. Families without audited recipes are explicitly marked pending. `check.py` rejects increases in direct platform controls, references to known duplicate button/input implementations and detected manual numeric metrics. Limits are per file and rule: moving a bypass fails even if the repository total declines. The checker also compares the baseline with the actual PR base commit, so increasing the baseline cannot hide a new bypass. The initial baseline cannot exceed violations already in that base. The two native text-editing wrapper exceptions state their reasons. The scanner covers named metrics and control constructors, not all possible Dart expressions; semantic duplicate detection still requires review.

`tool/preflight` runs recipe verification and the family ratchet as a separate check, including CI when other upstream-dependent checks skip. Regenerate recipes with `python tool/design-system/generate.py`, then run the check and full preflight. Do not increase the baseline to make a new violation pass. Retire duplicates by migrating their callers to the family recipe, then lower the baseline.

Acceptance uses real reference components with matching data, viewport, locale, density and theme. Previous Whalee images are only regression evidence, never the source of the desired design. Keep fonts, thresholds and pixel classification fixed. Each subsequent family migration must include reference comparisons, explicit remaining differences and regression evidence for preserved appearances. No automated upstream polling schedule is created by this work; run the checks during every planned upstream synchronization.

## Button family profiles

The add, icon action and info action profiles are generated from the **published** `@deepseek-ai/dsh-client-ui-plugin-manager@0.2.1-rc.2` CSS, layered over the primitive recipe. The actual web-app dependency and package version are locked too. Its release embeds CSS and a static class map in `lib/client.js`; `published.py` decodes the JSON literals without executing JavaScript. To reproduce the snapshot from the downloaded release, run:

```sh
python tool/design-system/published.py --archive /path/to/dsh-client-ui-plugin-manager-0.2.1-rc.2.tgz
```

This verifies the npm archive SHA512, bundle SHA256, exact decoded CSS bytes, class map and metadata. Ordinary checks verify the checked-in snapshot hashes. The generator compares affected button rules against the actual reference source after only the observed minifier transformations (class hashes, comma whitespace, decimal zero omission, transparent background spelling). Unknown affected selectors, properties, conditional rules and untranslated structural values fail. Other plugin-manager rules remain an **audit**, not a claim that their families are translated.

`DshButton` owns all primitive/add/icon/info states. The icon action is the source's raw button (28×28, disabled opacity .5, explicit focus outline); the info action is a small primitive override (20×20, disabled opacity .4, primitive focus rules). They deliberately differ. `DshSplitButton` composes two canonical buttons. Each owns its independent superellipse corners, opacity and outline, including the source's left divider on the method-picker half. There is no page-level outer clip or manually assembled divider. A single pending-install action retains all corners.

The base button's previous appearance is regression-checked separately from reference acceptance. The 32-case primitive matrix includes all four variants, two sizes, both brightnesses, default/hover and disabled labels. Real `PluginManagerPage` captures cover the custom profiles at desktop/phone densities, both locales and brightnesses. Fonts, threshold and classifier stay fixed. Remaining family work is explicit: three local round icon-control callers still use the older platform adaptation and must be given an appropriate source-backed or explicitly specified adaptation before consolidation. Their current custom shape is not falsely attributed to the published icon-action recipe. Menus and tooltip styles are also separate pending families; their page-specific numbers are not covered by this button migration.

## Published theme inputs and conditional scope

The theme adapter now generates from the eight global CSS literals in the published `@deepseek-ai/dsh-client-ui-theme@0.2.1-rc.2` bundle. The terminal font fallback comes from the separately published `ui-sidebar-terminal@0.2.1-rc.2` bundle. Their actual web-app dependencies, archive integrity, bundle hashes, decoded input hashes and reference source/import-order hashes are locked. Extraction decodes static JSON strings without executing JavaScript. Run `published.py --archive ... --package @deepseek-ai/dsh-client-ui-theme` (or `...ui-sidebar-terminal`) to reproduce the corresponding snapshot verification.

`build_official_pack.py --check` verifies the published snapshots, actual reference dependency and source drift before generation. `--snapshot-only --check` works without an upstream checkout or network. CI's theme check uses this mode instead of skipping when upstream sources are unavailable. Generated JSON and Dart include the package names, release versions and exact input provenance. No source stylesheet supplies runtime token values anymore.

The shared strict CSS reader retains every condition and declaration in `tool/design-system/theme.generated.json`. Unknown conditions, new token scopes, malformed/duplicate declarations, lost corner capability guards and unresolved token references fail generation. Only the existing corner-shape capability is explicitly modeled, because Flutter implements that curve, and the exact browser scrollbar fallback is classified as a CSS-engine fallback. Neither condition is silently flattened into unrelated global tokens.

Four existing scoped token overrides stay explicit in the audit: keyboard-only focus handling, the dark menu material stroke and the macOS light/dark menu material. The macOS material overrides remain pending; the dark stroke is consumed by the menu recipe, and these scoped values are not treated as global colours or claimed as complete platform behavior. A newly introduced scope fails until deliberately classified or implemented.

Published minification represents several alpha values as 8-bit hex colours. The adapter preserves those values exactly, including hex alpha, instead of reconstructing an authored percentage from the source checkout. The rendered colour bytes, typography, dimensions and real-reference captures are checked separately; string spelling alone is not visual equivalence. This is a source-provenance correction within the same pinned release, not a font, threshold or classifier change. Other component-family migrations remain unfinished.


## Shared menu recipes (first migration tranche)

`Menu.module.css`, `MenuSurface.module.css` and `MenuGroup.module.css` are exact published primitive files. The generator owns the normal/dense/compact row geometry, heading/separator rules, check/fill selection, disabled/danger/focus tokens and surface radii/stroke/elevation. The plugin manager's add row and viewport width come from its decoded release CSS. All source selectors and properties have an explicit contract; consumed values generate fields and every other structural value must match its audited value. Unknown states, conditions, duplicate rules, nonsquare icons and changed untranslated structures fail generation.

`DshMenuCard` and contributed rows use the same `DshMenuSurface` and `DshMenuItemButton`. Arrow keys wrap enabled rows, Home/End select endpoints, Tab enters the list and activates a focused row, and Escape/Shift+Tab dismiss and restore focus. The plugin page supplies content/actions and a generated width rather than assembling its own row style. Dark material uses the source l3 stroke; ordinary material uses l1. The existing rounded `DshShadowBox` behavior is preserved unless a caller explicitly supplies the theme's superellipse shape.

This is **partial menu-family coverage**. Submenus, shortcuts, pinned footers, sticky groups, the dock-specific row profile and transparent macOS backing are pending. The renderer retains the existing uniform page-ground material composition: a direct Flutter backdrop blur samples beyond the menu bounds and pulls in the trigger, unlike the observed Chromium result. Arbitrary content backdrops need a bounded sampling implementation; no claim of general backdrop-filter equivalence is made. `MenuGroup` is audited for drift, not rendered yet.

Acceptance includes the real plugin page with its add menu open and the real workspace session menu, with the source primitive matrix used only to check its three sizing profiles. The parity theme self-test checks the full frame corner: a crop of a menu may correctly start with its shadow/fill and is not a background-theme sentinel. Thresholds, fonts and classification are unchanged.

## Dock profile and footer geometry

The web kernel actually depends on `@deepseek-ai/dsh-client-ui-dockkit@0.2.1-rc.2`. Its published `lib/components/dockkit.module.css` is copied byte for byte and checked against the reference source. The lock also covers the actual TabMenu and web reset sources, because inherited font and box-model rules matter. `published.py --archive ... --package @deepseek-ai/dsh-client-ui-dockkit` reproduces the archive verification without executing JavaScript.

Dock menus use the shared material with their own content-box minimum width, padding and border, without the primitive menu's elevation. Their rows use the source secondary-size expression and natural line height, rather than a fixed primitive row height. The private dock renderers are removed. Pointer context menus remain available, and a touch long press opens the same menu. Dock Tab traversal retains ordinary button behavior; Enter and Space activate the row.

Explicit CSS `normal` line boxes derive spacing and baseline from the actual font/text at the current density. Their fractional CSS height is retained even when Flutter rounds its paragraph height in logical pixels. This path only handles an explicitly requested natural line height; existing fixed ladder styles keep their previous path. Font files, selected families, classifier and thresholds remain fixed.

`DshMenuFooter` owns the published margin, padding and border. Its border occupies layout space, so the workspace picker's bottom row reaches the source position. Menu separators retain their CSS logical height; border snapping is used for borders rather than to shrink a filled separator's layout. Primitive profile fixtures now use matching block-layout anchors in both providers instead of an unrelated anonymous inline line box.

Acceptance includes the actual upstream DockSurface with its context menu open, plus the TabMenu row-state matrix (English/Chinese, pointer/keyboard states and both densities), alongside real plugin/workspace menu contexts. The browser fixture opens the real dock chip context-menu handler; native checks exercise actual pointer and touch input. The native fixture exercises the actual DockLayout and workspace picker. Generic scrolling-footer integration, submenus, shortcuts, sticky groups, transparent macOS backing and arbitrary-content bounded blur remain follow-up work.

Each shared menu row owns a separate semantics node. This keeps a grouped menu from absorbing its footer action and reporting the entire popup as that action’s bounds. A regression test checks the actual semantic row rectangle, and Android verifies physical clicks from those accessibility bounds.

Full-viewport captures round physical dimensions to the nearest pixel, following measured Chromium native/emulated screenshot output. Fractional element crops use enclosing bounds. This prevents a partial display column from being truncated in phone viewport comparisons.

### Shared menu viewport and linked placement

`DshMenu`/`DshMenuCard` own both scrolling items and fixed footer entries. The
published Menu CSS generates the viewport height expression and anchor gap;
`menu-portal.json` records the exact placement block extracted from the released
primitive bundle, including its hash. The generator rejects unknown placement
expressions instead of assuming the CSS height margin is also the portal margin.
`DshMenuFollower` measures the composited anchor, keeps the initially unplaced
card hidden, and fits its visible card inside the overlay. Movement and ancestor
transforms update placement without scheduling idle frames. A caller can pass the
frame's computed top reserve through `frameOverlayTop`.

The workspace picker uses the same card and keyboard walk, including its footer,
rather than a private layout, width calculation and 520px cap. Focus reveals only
clipped rows; an already visible row and the fixed footer stay still. Actual
WorkspacePickFlow long-list comparisons cover English/Chinese, light/dark and
menus with/without the footer. Submenus, shortcut displays, sticky groups,
arbitrary-content backdrop filtering, macOS backing and full app-frame reserve
integration remain separate work.

Native linked menus keep the source portal margins inside the Flutter view's OS
safe bounds. The insets come from FlutterView rather than potentially consumed
SafeArea padding, and metric updates reach both placement and menu height without
resetting row focus or scroll state. This prevents a tall Android menu from
putting its first row underneath the status bar; zero-inset desktop/Web fixture
geometry is preserved.

### Menu shortcut presentation

`ShortcutKeys.module.css` is verified byte-for-byte against the pinned published
primitive archive and the reference source. Its plain key spacing and typography,
and the menu's caption color and 11px/16px override, generate shared recipe
fields. Unknown shortcut states, properties and untranslated tooltip structures
fail the generator. `DshShortcutKeys` remains the single keycap renderer; the
menu variant supplies its source styling, and `DshMenuShortcut` carries the
caller-provided effective key labels and accessible shortcut description.

Session action contributions can receive a current effective-binding lookup;
the application has not yet wired its shortcut catalog to this lookup and does
not yet register the rename, fork or archive commands. The real DSH workspace
session-action menu and the same Flutter workspace screen are compared with
matching synthetic effective bindings in normal and archived states. Existing
unbound menus remain regression cases. Tooltip keycaps, submenus,
arbitrary-content backdrop filtering and macOS material backing remain separate
work; this change does not claim whole-family or overall visual parity.


### Scrollable menu groups

`DshMenuGroup` compiles its heading padding, font, color, stuck fill, radius and
adjacent-group gap from the locked published `MenuGroup.module.css`. A pinned
header stays within its group and is pushed away by the next group; its fill
appears only after the group's start passes the viewport. It names the group
for accessibility, supports wrapped and scaled headings, and retains row
contexts for keyboard selection. The command popup preserves ungrouped rows
without inserting an adjacent-group gap. It waits for a usable viewport before
revealing the active row and leaves already visible rows in place, including
when a pinned heading would otherwise cover them. The model sheet uses the same
group.

The reference cases mount the real DSH command popup and model selector over
synthetic data. A deterministic scroll-position step prepares initial, pinned
and transition views in both capture providers; native touch and keyboard tests
are reported separately. The model selector still uses a bottom sheet in this
client, with wider and taller rows than the reference desktop menu; the current
comparisons do not establish visual parity. Fonts and the 99.5% classifier
remain unchanged.

### Tooltips and their keycaps

The pinned primitive archive supplies `Tooltip.module.css`, the shortcut-key
stylesheet and the placement logic snapshot. The generator checks their
structure and emits the bubble, keycap, animation and placement values;
untranslated states and conditions fail the source audit. The tooltip width cap
applies to content before padding, as in the published CSS. `DshTooltip` uses
the shared overlay, tracks its anchor, fits the viewport, flips above or below,
and supports hover and keyboard focus delays, nested suppression, click
pinning and dismissal. Pointer-driven refocus does not reopen a keyboard hint.
The shortcut-only variant exposes its key labels to accessibility.

The message copy and branch controls provide real source and Flutter comparison
cases in both themes and languages at desktop and phone densities. These are
evidence of the current differences, not a claim of visual parity. Dynamic label
resolver callbacks and the source's optional document-body portal need further
audit; the Flutter implementation accepts a string and uses its nearest overlay.

### Single-line input atom

`Input.module.css` and the reference component are locked to the published
primitive package. The generator rejects unknown input states and emits the
wrapper, icon, typography, border and focus tokens. `DshInput` is the shared
single-line atom for controlled values and for settings that commit on blur or
Enter; it preserves the Chromium input's measured inline inset. It supports an
optional icon, disabled semantics and input length limits. Length limits retain
the part of an insertion that fits and avoid splitting a surrogate pair, as in
the reference browser.

The real font-settings family row uses this atom. Its previous desktop captures
remain pixel-identical, and focused, populated and placeholder fields are
compared separately against the actual DSH component. The phone settings row
currently uses a wider stacked field than the web reference, so those crops do
not have matching widths. The major text field and feature-specific variants
remain a separate audit; in particular, the model selector overrides the source
input's padding, border and type rather than using the base atom unchanged.

### Switches

`Switch.module.css` and the component source are locked to the published
primitive. The generated recipe supplies the track and thumb geometry, colors,
disabled opacity, focus outline and transition. `DshSwitch` remains controlled
by its caller and supports pointer, Space/Enter and accessibility activation;
disabled switches refuse input. The thumb respects reduced motion. Focus rings
follow the source's pointer and keyboard modality rules. A parent `DshButton`
only draws its own ring when it has primary focus, so a nested switch does not
also highlight its surrounding card.

Acceptance uses the actual plugin manager bundle switch at both sizes, themes
and languages, including on, off, disabled and keyboard-focused states. The
color and antialiasing differences seen in the small switch crops remain
measured against the unchanged 99.5% target; the whole-page focused captures
also include surrounding content and are reported separately.

### Checkboxes and risk acknowledgement

The published `Checkbox.module.css` and `RiskConfirmation.module.css` use
different label layouts and accent tokens. They produce separate profiles of
the shared controlled `DshCheckbox`; the risk dialog gives the acknowledgement
initial focus without an outline until navigation, as the reference modal does.
Space, pointer and accessibility activation work on enabled controls, while
Enter alone does not toggle a native checkbox.

The source uses a browser-native input rather than defining the square and
checkmark in CSS. `checkbox-native.json` records the shape and lightness rule
from Chromium 145.0.7632.6's `ui/native_theme/native_theme_base.cc`, plus the
browser's light/dark system colors sampled at DPR 1 and 2.625. The snapshot is
locked separately from the DSH CSS; it is a reference-renderer adaptation,
not a DSH theme token. `probe_chromium_checkbox.mjs` and
`checkbox_browser_snapshot.py` reproduce its samples and structural checks.
The Chromium Authors' license is retained alongside the snapshot. Other
browsers and platform-native paint conventions may differ.

Reference cases use the actual risk confirmation and model input-type source
components. The Flutter risk dialog is real; the model checkbox context is a
fixture because the model editor has not yet been wired to the shared atom.
The comparison reports isolated controls and whole-dialog focus separately.

### Pills

The published primitive defines a static capsule and an interactive button,
with independent active, hover and focus behavior. The market package supplies
the category-group spacing. Their source locks and generated recipes drive
`DshPill` and the actual market category filter. An empty category declaration
shows no group. The terminal status retains its source height and color
overrides. Keyboard and accessibility activation, pressed state, disabled
behavior and pointer-controlled focus follow the source; the pinned Chromium
probe records the browser's focus outline and disabled-hover behavior.
Native accessibility exposes the pressed category as a selected button, since
Flutter's toggled flag maps to a switch on Android.

The segmented-tab source uses Pill as an underlying button but overrides its
geometry, focus decoration and keyboard model; it remains the separate
`DshSegmentedTabs` profile. Schedule-specific overrides and the
market's locale-aware category ordering remain to be audited. The real market
and terminal screenshots measure the remaining visual differences; focused
whole-page captures are reported separately from the cropped controls.

### Read-only tags

The published Tag stylesheet generates the capsule's content-box geometry,
typography and eight tones, including the source's `color-mix` percentages.
`DshTag` is the shared non-interactive component. Settings override labels,
agent-preset selection labels and plugin inventory warning, disabled and
failure states now use it. The first two replace separate private tags. The
inventory page still has a different row layout and retains its enabled-state
text; other source Tag consumers remain to be migrated. The family ratchet
prevents the retired private components from returning.

The settings field also exposes accessibility activation for its reset and
help buttons; disabled reset remains unavailable.

Reference captures use the actual DSH shell settings, agent-preset section and
plugin inventory components. Crop dimensions can differ when the surrounding
page positions a tag at a different fraction of a device pixel; the reference
comparison retains those differences and the unchanged 99.5% target.
