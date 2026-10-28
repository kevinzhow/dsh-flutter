# All design-system families: source coverage audit

The current design-system contract is **not exhaustive**. Global theme tokens,
icons and 29 selected recipe classes are generated, but many existing canonical
widgets and most feature CSS bindings are still handwritten. A passing current
check means the recorded bypass/metric counts did not grow; it does not mean
all published components have source-derived recipes or real-reference acceptance.

This read-only audit is pinned to primary head `ac8d066aa10802679e5e7c3c1d897c1bea613981`,
tree `03c31b58f212046cb82e1d9bc79d67081ba78115`, and DSH
`687f282e8625c6b8d11ff58211a90524be2e4317` / published0.2.1-rc.2.
Only this note is an intentional audit output; no product/SDK source edits,
builds, native sessions or page ports were performed.

## Universe and provenance

All57 `@deepseek-ai/dsh-client-ui-*` packages were independently queried from
public npm version metadata on2026-10-28. Every name/version matched0.2.1-rc.2
and every response supplied a distribution integrity. Example immutable version
endpoint: https://registry.npmjs.org/@deepseek-ai%2Fdsh-client-ui-primitives/0.2.1-rc.2 .
The installed pinned CLI also contains54 of these UI package manifests; the
primitives/dockkit/slots packages are build-time dependencies rather than that
runtime subset. Existing published snapshots independently cover primitives
and dockkit. Source package versions alone were not used as proof of publication.

The dependency roots are `packages/bundle/web-app/package.json`
(`@deepseek-ai/dsh-web-app`), `packages/client/web/package.json`, and the already
used `packages/experimental/plugin-market-bundle/package.json`. Following
workspace dependencies/optional/peers gives215 workspace nodes and54 UI packages;
including their build/dev dependencies gives295 nodes and all57 UI packages.
A runtime-only inventory therefore drops exactly primitives, dockkit and slots.
Do not confuse these workspace closure counts with UI family counts.

| Audited unit | Count | Meaning |
| --- | ---: | --- |
| Published UI packages |57| All verified at the pinned release |
| UI packages with own CSS / without own CSS |48 /9| No-CSS packages may delegate styling or contain inline/SVG UI |
| UI source CSS files |209| File inventory, not209 completed logical families |
| Additional core published styling dependencies |3 packages /4 CSS files| locale, client-web, session-log-export |
| Optional experimental public styling packages |6 packages /6 CSS files| Enumerated separately below |
| Locked design-system package snapshots |13| Partial extraction does not cover an entire package |
| Retained physical CSS snapshot files |36| Some are renamed/combined; not a coverage percentage |
| Generated recipe classes / fields |29 /666| Several classes belong to one logical family |
| Current family labels / canonical references / unique canonical files |16 /29 /27| Coarse handwritten inventory |
| Shared non-generated Dart files / files referencing recipe classes |79 /22| Remaining57 include helpers; not57 inferred missing visual families |

The package/style inventory below is exhaustive for the pinned57 UI packages.
Public metadata was also verified for the additional3 core and6 experimental
packages. Private desktop renderer CSS and website CSS are explicitly separated.
This is an exhaustive source-file/package map, **not** a completed per-state
acceptance ledger. Inline styles, public component exports, SVG geometry and
source renderer behavior must be explicit ledger inputs as well as CSS files.


Current generated classes (all 29, as keys of `recipes.generated.json.metrics`):

`DshButtonRecipe`, `DshSegmentedTabRecipe`, `DshShortcutKeysRecipe`, `DshAddButtonRecipe`, `DshIconActionRecipe`, `DshMenuRecipe`, `DshMenuFooterRecipe`, `DshMenuGroupRecipe`, `DshMenuSurfaceRecipe`, `DshPluginAddMenuRecipe`, `DshDockMenuRecipe`, `DshTooltipRecipe`, `DshInputRecipe`, `DshSwitchRecipe`, `DshCheckboxNativeRecipe`, `DshCheckboxRecipe`, `DshPillRecipe`, `DshTagRecipe`, `DshModalRecipe`, `DshGuideReaderRecipe`, `DshScrollbarRecipe`, `DshRiskDialogRecipe`, `DshPlatformMaterialRecipe`, `DshSidebarRecipe`, `DshWorkspaceBrowserRecipe`, `DshSidebarLauncherRecipe`, `DshModelMenuRecipe`, `DshStatPanelRecipe`, `DshStatsPillRecipe`.

## The current guard's exact limits

`tool/design-system/check.py:34-50` scans six regex rule categories and checks
only that named canonical files exist. Empty canonical arrays pass (the banners
entry is currently empty). It does not enumerate upstream components, require a
source/package/selector for each family, verify recipe use by each class, or
validate the free-text migrationStatus. A recipe import elsewhere in a large
file is not coverage of every class in that file.

Current observed counts are11 platform-control,4 duplicate-button,899 manual-
metric, and zero recorded duplicate-input/tag/menu matches. The manual-metric
baseline permits905 and137 files have baseline entries. These counts are real
ratchet debt, not899 independently proven wrong styles. Native wrappers in
`dsh_text_field.dart` and all of `dsh_settings.dart` are allowlisted for the
platform-control rule.

The scanner produces zero matches for `EdgeInsets.all(17)`,
`EdgeInsets.symmetric(vertical: 17)`, `Duration(milliseconds: 650)`,
`const Color(0xff123456)` and `showModalBottomSheet(...)`. Its metric regex
only recognizes selected named arguments and BorderRadius.circular. Baseline
history checks do not independently reject wrapper-allowlist growth. These
are concrete gaps in enforcing the new no-handwritten-styling directive.

`theme_access.dart:26-46` explicitly defines a handwritten global DshSpace
rhythm, touch target and readable width. Naming a literal there is not
published component-recipe derivation. Likewise a valid generated theme color
token does not prove that a handwritten component chose the source's correct
role, dimensions, state or material composition.

## Current16-family contract

The following lists recipe references actually found in each registered
canonical file. It is a consumption lead, not a full-state proof. In particular,
list rows share a file with generated switches/checkboxes while the row,
selector pill and stepper classes themselves remain handwritten.

| Family | Canonical source and observed recipe references | Coverage finding |
| --- | --- | --- |
| buttons | `packages/dsh_ui/lib/src/dsh_button.dart`: DshAddButtonRecipe, DshButtonRecipe, DshIconActionRecipe | Generated profiles exist; DshIconButton duplication/local adaptation remains. |
| menus | `packages/dsh_ui/lib/src/dsh_menu.dart`: DshMenuRecipe<br>`packages/dsh_ui/lib/src/dsh_menu_surface.dart`: DshDockMenuRecipe, DshMenuRecipe, DshMenuSurfaceRecipe<br>`packages/dsh_ui/lib/src/dsh_menu_item.dart`: DshDockMenuRecipe, DshMenuRecipe, DshModelMenuRecipe, DshPluginAddMenuRecipe, DshSidebarLauncherRecipe<br>`packages/dsh_ui/lib/src/dsh_menu_footer.dart`: DshMenuFooterRecipe<br>`packages/dsh_ui/lib/src/dsh_menu_follower.dart`: DshMenuRecipe<br>`packages/dsh_ui/lib/src/dsh_menu_group.dart`: DshMenuGroupRecipe | Generated profiles exist; submenus/arbitrary content/source-behavior gaps remain. |
| popovers | `packages/dsh_ui/lib/src/dsh_anchored_panel.dart`: DshMenuRecipe<br>`packages/dsh_ui/lib/src/dsh_popover_surface.dart`: DshMenuSurfaceRecipe, DshStatPanelRecipe<br>`packages/dsh_ui/lib/src/dsh_stat_panel.dart`: DshStatPanelRecipe | Stats material/placement only; context, turn and other popovers unprofiled; renderer graph research remains open. |
| tooltips | `packages/dsh_ui/lib/src/dsh_tooltip.dart`: DshMenuRecipe, DshShortcutKeysRecipe, DshTooltipRecipe | Generated base/keycaps; documented dynamic/document portal gaps. |
| dialogs | `packages/dsh_ui/lib/src/dsh_presentation.dart`: DshModalRecipe<br>`packages/dsh_ui/lib/src/dsh_dialog_reader.dart`: DshGuideReaderRecipe<br>`packages/dsh_ui/lib/src/dsh_reader_markdown.dart`: DshGuideReaderRecipe, DshTagRecipe<br>`packages/dsh_ui/lib/src/dsh_headed_dialog.dart`: DshModalRecipe, DshScrollbarRecipe<br>`packages/dsh_ui/lib/src/dsh_risk_dialog.dart`: DshCheckboxRecipe, DshRiskDialogRecipe | Generated Modal/guide/risk; settings/shortcuts and other callers still partial. |
| text-inputs | `packages/dsh_ui/lib/src/dsh_text_field.dart`: DshInputRecipe, DshModelMenuRecipe | DshInput generated; DshTextField major wrapper remains handwritten. |
| selection-and-checkbox | `packages/dsh_ui/lib/src/dsh_settings.dart`: DshCheckboxNativeRecipe, DshCheckboxRecipe, DshSwitchRecipe | Checkbox generated; broader selection controls are not covered. |
| switches | `packages/dsh_ui/lib/src/dsh_settings.dart`: DshCheckboxNativeRecipe, DshCheckboxRecipe, DshSwitchRecipe | Switch generated; does not cover other controls in the same file. |
| segmented-tabs | `packages/dsh_ui/lib/src/dsh_segmented_tabs.dart`: DshSegmentedTabRecipe | Tabs generated; source SegmentedControl is distinct and missing. |
| cards | `packages/dsh_ui/lib/src/dsh_card.dart`: **no recipe reference** | No generated Card profile; no universal Card stylesheet exists in the primitive package. |
| badges-and-pills | `packages/dsh_ui/lib/src/dsh_pill.dart`: DshPillRecipe<br>`packages/dsh_ui/lib/src/dsh_tag.dart`: DshTagRecipe | Pill/Tag generated; other status/progress/badge forms remain separate. |
| list-rows | `packages/dsh_ui/lib/src/dsh_settings.dart`: DshCheckboxNativeRecipe, DshCheckboxRecipe, DshSwitchRecipe | No row/selector/stepper recipe despite recipes used elsewhere in dsh_settings.dart. |
| empty-states | `packages/dsh_ui/lib/src/dsh_guide.dart`: **no recipe reference** | Guide artwork/card styles unprofiled. |
| toasts | `packages/dsh_ui/lib/src/dsh_toast.dart`: **no recipe reference** | Canonical Toast is manually styled; published Toast stylesheet unretained. |
| drawers-and-navigation | `features/dsh_feature_sidebar/lib/src/sidebar_root.dart`: DshSidebarRecipe<br>`features/dsh_feature_sidebar/lib/src/leading_controls.dart`: **no recipe reference**<br>`features/dsh_feature_session/lib/src/workspace/browser.dart`: DshSidebarRecipe, DshWorkspaceBrowserRecipe | Root/browser static profiles partially generated; leading controls still manual; dock/shell/drawer states incomplete. |
| banners | **empty canonical array** | No canonical source or recipe registered. |

## All41 primitive style inputs and their Flutter ownership

All source paths in this table are under
`packages/client/ui-primitives/src/`. Flutter filenames are under
`packages/dsh_ui/lib/src/` unless a feature is named. Fourteen source sheets
have locked generated inputs; 27 do not. A generated row below denotes an input
profile, not blanket visual/behavioral acceptance of every caller/state.

| Source stylesheet | Existing Flutter ownership/counterpart | Generated provenance/status |
| --- | --- | --- |
| `Button.module.css` | dsh_button.dart | DshButtonRecipe; add/icon/info variants have separate generated profiles |
| `Checkbox.module.css` | dsh_settings.dart / DshCheckbox | DshCheckboxRecipe + DshCheckboxNativeRecipe; browser profile is separately pinned |
| `CodeCard.module.css` | dsh_code_block.dart + dsh_code_toolbar.dart | NO generated profile |
| `CommandText.module.css` | terminal/tool command presentation; no named canonical CommandText | NO generated profile |
| `ConfigField.module.css` | dsh_settings_form.dart / fields | NO generated profile |
| `ConnectionIndicator.module.css` | dsh_connection_indicator.dart | NO generated profile; manually copied CSS values |
| `DiffBlock.module.css` | dsh_diff_block.dart | NO generated profile |
| `DisclosureRow.module.css` | dsh_disclosure_row.dart + dsh_disclosure.dart | NO generated profile |
| `FileTypeIcon.module.css` | dsh_file_types.dart | glyph data generated separately; CSS geometry/palette profile absent |
| `HoverCard.module.css` | no dedicated HoverCard/HoverCardGroup canonical implementation | NO generated profile; Tooltip is a different source family |
| `ImageLightbox.module.css` | dsh_lightbox.dart | NO generated profile |
| `ImagePreview.module.css` | dsh_attachment.dart image/frame/group widgets | NO generated profile |
| `InlineEditor.module.css` | local rename/edit implementations; no dedicated InlineEditor canonical | NO generated profile |
| `Input.module.css` | dsh_text_field.dart / DshInput | DshInputRecipe; DshTextField major variant remains manual |
| `JsonTree.module.css` | dsh_json_block.dart / local tree rendering | NO generated JsonTree profile |
| `Menu.module.css` | dsh_menu.dart + dsh_menu_item.dart + dsh_menu_follower.dart | DshMenuRecipe; still bounded migration/state coverage |
| `MenuGroup.module.css` | dsh_menu_group.dart | DshMenuGroupRecipe |
| `MenuSurface.module.css` | dsh_menu_surface.dart; popover material consumes common fields | DshMenuSurfaceRecipe; render graph/platform acceptance remains separate |
| `Modal.module.css` | dsh_presentation.dart + headed/reader dialogs | DshModalRecipe; caller-specific pages remain partial |
| `PathLabel.module.css` | HeadTailCap is a helper; path rows are feature/content-specific | NO generated PathLabel profile |
| `Pill.module.css` | dsh_pill.dart | DshPillRecipe |
| `ReadBlock.module.css` | dsh_read_block.dart | NO generated profile |
| `RiskConfirmation.module.css` | dsh_risk_dialog.dart | DshRiskDialogRecipe plus checkbox profile |
| `SearchBlock.module.css` | dsh_search_block.dart | NO generated profile |
| `SegmentedControl.module.css` | no dedicated source SegmentedControl canonical; selector pill is separate | NO generated profile; SegmentedTabs does not cover this sheet |
| `SegmentedTabs.module.css` | dsh_segmented_tabs.dart | DshSegmentedTabRecipe |
| `ShortcutKeys.module.css` | dsh_tooltip.dart / DshShortcutKeys | DshShortcutKeysRecipe |
| `StateDot.module.css` | dsh_state_dot.dart and dsh_status_dot.dart | NO generated profile; distinguish state vocabulary before consolidating |
| `Switch.module.css` | dsh_settings.dart / DshSwitch | DshSwitchRecipe |
| `Tag.module.css` | dsh_tag.dart | DshTagRecipe |
| `TerminalBlock.module.css` | dsh_terminal_block.dart | NO generated block profile; generated font stack is not its CSS recipe |
| `TextShimmer.module.css` | dsh_shimmer.dart | NO generated profile |
| `Toast.module.css` | dsh_toast.dart | NO generated profile |
| `Tooltip.module.css` | dsh_tooltip.dart | DshTooltipRecipe; remaining dynamic/document portal cases documented |
| `WebBlock.module.css` | dsh_web_block.dart | NO generated profile |
| `markdown/CodeBlock.module.css` | dsh_code_block.dart / markdown | NO generated profile |
| `markdown/JsonBlock.module.css` | dsh_json_block.dart | NO generated profile |
| `markdown/MarkdownText.module.css` | dsh_markdown.dart | NO generated profile |
| `settings-form/SettingsForm.module.css` | dsh_settings_form.dart | NO generated profile |
| `settings-form/fields.module.css` | dsh_settings_form.dart + dsh_settings_form_model.dart | NO generated field/secret/select profile |
| `user-text.module.css` | dsh_reference_chip.dart + conversation user text | NO generated profile |

Additional primitive exports in `src/index.ts` include icon/permission/reference/
link SVGs, FishLogo/BrandWordmark, plugin/guide artwork and nonvisual helpers.
`tool/icons/gen_icons.py`, `gen_shell_icons.py`, `gen_file_types.py` and related
adapters are separate generated-asset evidence; they do not supply the missing
CSS profiles above. Whalee identity and approved phone adaptations should be
explicit deviations with owners/recipes, not counted as published DSH designs.
Pure data/clipboard/ranking/composition helpers are not missing paint families.

## Primitive public exports beyond CSS filenames

`packages/client/ui-primitives/src/index.ts` has **97 explicitly named runtime
exports from 62 source modules**, plus the `icons/index.tsx` wildcard. This count
includes constants/helpers and is not a count of 97 visual component families.
Type-only exports are excluded. The complete module-to-value map below exposes
style-free/delegated entry points that a CSS-only inventory would miss. All paths
are relative to that same primitive `src/` directory. The 41-sheet mapping above
provides the current visual ownership; unprofiled visual exports are not silently
certified by being in the same package as a generated Button.

| Source module | Explicitly exported runtime values |
| --- | --- |
| `StateDot.tsx` | `StateDot` |
| `DisclosureRow.tsx` | `DisclosureRow` |
| `TextShimmer.tsx` | `TextShimmer` |
| `Button.tsx` | `Button` |
| `Pill.tsx` | `Pill` |
| `SegmentedTabs.tsx` | `SegmentedTabs` |
| `Tag.tsx` | `Tag` |
| `PathLabel.tsx` | `PathLabel` |
| `Switch.tsx` | `Switch` |
| `SegmentedControl.tsx` | `SegmentedControl` |
| `Checkbox.tsx` | `Checkbox` |
| `Input.tsx` | `Input` |
| `InlineEditor.tsx` | `InlineEditor` |
| `Menu.tsx` | `Menu`, `MenuItemButton` |
| `MenuSurface.tsx` | `MenuSurface` |
| `MenuGroup.tsx` | `MenuGroup`, `observeStickyMenuGroups` |
| `useAnchoredMaxHeight.ts` | `useAnchoredMaxHeight` |
| `useAnchoredPosition.ts` | `useAnchoredPosition` |
| `useDismissOnOutsidePointer.ts` | `useDismissOnOutsidePointer` |
| `HoverCard.tsx` | `HoverCard` |
| `HoverCardGroup.tsx` | `HoverCardGroup` |
| `ShortcutKeys.tsx` | `ShortcutKeys` |
| `keyboard-composition.ts` | `observeComposition` |
| `focus.ts` | `focusWithoutRing` |
| `useModalLayer.ts` | `closeTopModal`, `isBehindModal`, `modalSelector`, `useModalLayer` |
| `Modal.tsx` | `Modal` |
| `RiskConfirmation.tsx` | `RiskConfirmation` |
| `ConnectionIndicator.tsx` | `ConnectionIndicator` |
| `FishLogo.tsx` | `FishLogo`, `FISH_LOGO_PATH`, `FISH_LOGO_VIEWBOX` |
| `BrandWordmark.tsx` | `BrandWordmark` |
| `PermissionIcon.tsx` | `PermissionIconAutoReviewMedium`, `PermissionIconAutoReviewRegular`, `PermissionIconFullAccessMedium`, `PermissionIconFullAccessRegular`, `PermissionIconReadOnlyMedium`, `PermissionIconReadOnlyRegular`, `PermissionIconWorkspaceWriteMedium`, `PermissionIconWorkspaceWriteRegular` |
| `ReferenceIcon.tsx` | `ReferenceIconMedium`, `ReferenceIconRegular` |
| `LinkIcon.tsx` | `LinkIconMedium`, `LinkIconRegular`, `classifyLinkPath` |
| `FileTypeIcon.tsx` | `FileTypeIcon`, `classifyFileType`, `fileExtension` |
| `user-text.tsx` | `UserTextRun`, `ReferenceChip` |
| `Tooltip.tsx` | `Tooltip` |
| `input-modality.ts` | `pointerModality` |
| `Toast.tsx` | `Toast` |
| `file-size.ts` | `fileSizeText` |
| `clipboard.ts` | `writeClipboard` |
| `settings-form/SettingsForm.tsx` | `SettingsForm` |
| `settings-form/fields.tsx` | `SettingsSecretField`, `SettingsValueField` |
| `settings-form/form-model.ts` | `SettingsFormModel`, `settingsNumberField`, `settingsTextField` |
| `code-highlighting.ts` | `CODE_HIGHLIGHT_EXTENSIONS`, `languageForPath`, `useCodeHighlighter` |
| `relative-time.ts` | `relativeTime` |
| `rank-by-name.ts` | `rankByName` |
| `darwin-desktop.ts` | `isDarwinDesktop` |
| `JsonTree.tsx` | `JsonTree` |
| `TerminalBlock.tsx` | `TerminalBlock`, `DEFAULT_TERMINAL_MAX_LINES` |
| `CommandText.tsx` | `CommandText` |
| `ReadBlock.tsx` | `ReadBlock`, `DEFAULT_READ_MAX_LINES` |
| `DiffBlock.tsx` | `DiffBlock`, `DEFAULT_DIFF_MAX_LINES`, `diffTotals` |
| `SearchBlock.tsx` | `SearchBlock`, `DEFAULT_SEARCH_MAX_LINES` |
| `WebBlock.tsx` | `WebBlock` |
| `markdown/CodeBlock.tsx` | `CodeBlock` |
| `markdown/JsonBlock.tsx` | `JsonBlock` |
| `markdown/MarkdownDelegate.tsx` | `MarkdownDelegateProvider` |
| `markdown/MarkdownText.tsx` | `MarkdownText` |
| `markdown/plain-text.ts` | `extractMarkdownPlainText` |
| `plugin-artwork.tsx` | `PluginArtworkTerminal`, `PluginArtworkLoop`, `PluginArtworkSubagent`, `PluginArtworkSearch`, `PluginArtworkDefault` |
| `guide-artwork.tsx` | `GuideArtworkBrowser`, `GuideArtworkFiles` |
| `ImageLightbox.tsx` | `ImageLightbox` |
| `icons/index.tsx` | wildcard icon exports; audited separately by generated icon assets |

`CodeToolbar.tsx`, `ConfigField.tsx` and `ImagePreview.tsx` are
also source components consumed internally/by exposed `./src/*` paths even when
the root entry does not export their values. For example ConfigField emits a
native `select`, `textarea` or password input, validation text and reset action;
it is not covered by the single-line Input recipe. CodeToolbar renders its own
copy/wrap actions using CodeCard CSS. An export-only ledger would therefore also
be insufficient; source-internal components and caller-visible states need owners.

The nine UI packages with no own CSS classify as follows; no CSS does not mean
no UI and does not mean a new recipe is always needed:

| Package | Concrete source under `packages/client/<package>/src/` | Classification / inherited visual ownership |
| --- | --- | --- |
| `ui-brand-official` | `client/Brand.tsx` | OfficialBrandMark delegates FishLogo; OfficialBrandName delegates BrandWordmark. Whalee branding is an approved adapter, not an inferred DSH recipe. |
| `ui-directory-picker-native` | `client/flow.ts` | NativeDirectoryFlow returns null and invokes the host picker. Platform-adapter behavior; no React paint to profile. |
| `ui-reference` | `client/FileReference.tsx` | FileReference/FolderReference delegate ReferenceChip; file failure UI composes Modal/Button. Needs those profiles and failure-state behavior coverage. |
| `ui-renderer` | `client/app.tsx`, `client/bindings.tsx`, `client/scoped-slots.tsx` | Render/slot assembly and binding infrastructure. Classify structural/error handling independently from visual component profiles. |
| `ui-session` | `client/session-provider.tsx` | renderSessionArea chooses children/empty scope. Structural; visual empty branch belongs to its contributor. |
| `ui-settings` | `client/config-form.ts`, `client/schema.ts`, `client/settings-mirror.ts`, `client/contract/slots.ts` | Settings model/service/slot contracts; actual fields/forms belong to primitives and feature contributors. |
| `ui-settings-agent-loop` | `client/AgentLoopCard.tsx` | Delegates SettingsForm/SettingsValueField; inherits the currently missing form/field profiles. |
| `ui-settings-shell` | `client/ShellCard.tsx` | Delegates SettingsForm/SettingsValueField; inherits the same form/field profiles. |
| `ui-slots` | `index.ts`, `renderer.ts`, `store.ts` | Registry and typed store/renderer contracts; no independent painted control. |

## Complete57-package/style-file map

Package identifiers below all expand to `@deepseek-ai/dsh-client-<identifier>`;
source package roots are `packages/client/<identifier>`, except `ui-cordis`,
whose root is `packages/extensions/ui-cordis`. CSS paths are relative
to each package's `src/`. The Flutter column names the current ownership area;
for unprofiled families it is **not** a claim of complete equivalence. Snapshot
presence is only retention/provenance: the generator may consume a small subset
of a retained file, and many files in that package remain unretained.

| UI package | Own CSS inputs (all) | Locked snapshot | Flutter ownership / coverage |
| --- | --- | --- | --- |
| `ui-agent-preset` | 5: `client/AgentPresetLabel.module.css`, `client/AgentPresetSeat.module.css`, `client/AgentPresetSection.module.css`, `client/CreatePluginMenuItem.module.css`, `client/PresetGuideDialog.module.css` | `ui-agent-preset`: `PresetGuideDialog.module.css`, `styles.css` | features/dsh_feature_agent_management; shared guide/dialog/tag components |
| `ui-approval` | 1: `client/ApprovalPanel.module.css` | none | features/dsh_feature_approval |
| `ui-attachment` | 5: `AttachmentRail.module.css`, `DropOverlay.module.css`, `FileCard.module.css`, `MessageImage.module.css`, `client/ComposerAttachments.module.css` | none | features/dsh_feature_attachment; packages/dsh_ui/lib/src/dsh_attachment.dart |
| `ui-brand-official` | 0; delegate/inline/structural source still needs ownership classification | none | sidebar branding / dsh_whale_mark.dart (approved Whalee identity deviation) |
| `ui-chat` | 18: `client/chat/AssistantMarkdown.module.css`, `client/chat/ChatGroupSeat.module.css`, `client/chat/ChatView.module.css`, `client/chat/ContextBody.module.css`, `client/chat/ContextInjectionRow.module.css`, `client/chat/GenericCommandCard.module.css`, `client/chat/MessageIconActions.module.css`, `client/chat/MessageItem.module.css`, `client/chat/ReasoningRow.module.css`, `client/chat/StatsPills.module.css`, `client/chat/TurnNavigator.module.css`, `client/chat/TurnProcessNodeView.module.css`, `client/chat/TurnTailNodeView.module.css`, `client/chat/TurnTriggerNodeView.module.css`, `client/chat/TurnUsagePanel.module.css`, `client/chat/accessibility.module.css`, `client/chat/stat-dialog.module.css`, `client/settings/PreferenceRow.module.css` | `ui-chat`: `StatsPills.module.css`, `stat-dialog.module.css` | features/dsh_feature_chat; shared content/attachment/stat controls |
| `ui-commands` | 1: `client/PopupSelectView.module.css` | none | features/dsh_feature_commands |
| `ui-conversation` | 10: `client/input/editor/ReferenceChip.module.css`, `client/input/editor/composer-editor.module.css`, `client/queue/QueueDock.module.css`, `client/settings/EnterBehaviorRow.module.css`, `client/skeleton/ContextMeter.module.css`, `client/skeleton/ConversationRoot.module.css`, `client/skeleton/HeroShell.module.css`, `client/skeleton/InputBar.module.css`, `client/skeleton/TodoPanel.module.css`, `client/user-text/UserText.module.css` | none | features/dsh_feature_conversation; dsh_chat_axis.dart |
| `ui-cordis` | 3: `client/CordisDefineRow.module.css`, `client/CordisPanel.module.css`, `client/CordisRunRow.module.css` | none | no dedicated canonical family; loader/plugin views require explicit mapping |
| `ui-deepseek-model-label-1017` | 1: `client/DeepSeekModelLabel.module.css` | none | model-selection label seat; no dedicated generated label profile |
| `ui-deliverables` | 5: `client/ChangedFiles.module.css`, `client/Deliverables.module.css`, `client/FileDiff.module.css`, `client/PresentRow.module.css`, `client/ReviewTab.module.css` | none | features/dsh_feature_deliverables |
| `ui-directory-picker-browse` | 1: `client/DirectoryBrowser.module.css` | none | features/dsh_feature_directory_picker_browse |
| `ui-directory-picker-native` | 0; delegate/inline/structural source still needs ownership classification | none | features/dsh_feature_directory_picker_native (native adapter) |
| `ui-dockkit` | 1: `components/dockkit.module.css` | `ui-dockkit`: `dockkit.module.css` | app frame / dsh_rightbar_host.dart / dock menu profile; full dock family incomplete |
| `ui-goal` | 2: `client/GoalBar.module.css`, `client/GoalCommandInputView.module.css` | none | features/dsh_feature_agent_management; conversation contributions |
| `ui-input-trigger` | 1: `client/MenuView.module.css` | none | features/dsh_feature_input_trigger |
| `ui-jobs` | 1: `client/JobListAction.module.css` | none | features/dsh_feature_agent_management |
| `ui-layout` | 1: `client/AppFrame.module.css` | none | features/dsh_feature_layout; app frame |
| `ui-message-feedback` | 2: `client/FeedbackDialog.module.css`, `client/MessageFeedbackActions.module.css` | none | conversation/chat contributions; no generated feedback profile |
| `ui-model-selection` | 1: `client/ModelSelect.module.css` | `ui-model-selection`: `ModelSelect.module.css` | features/dsh_feature_model_selection; canonical model menu rows |
| `ui-open-in-app` | 1: `client/OpenTargetButton.module.css` | none | features/dsh_feature_open_in_app |
| `ui-permission-presets` | 2: `client/PermissionRow.module.css`, `client/PermissionSelect.module.css` | none | features/dsh_feature_permission_presets |
| `ui-plan` | 2: `client/PlanModeControl.module.css`, `client/PlanPreview.module.css` | none | features/dsh_feature_plan |
| `ui-plugin-manager` | 1: `client/PluginManagerPage.module.css` | `ui-plugin-manager`: `PluginManagerPage.module.css` | features/dsh_feature_plugins; canonical add-button/menu profiles only |
| `ui-plugin-market` | 1: `client/DiscoverSection.module.css` | `ui-plugin-market`: `DiscoverSection.module.css` | features/dsh_feature_plugins; Pill categories only |
| `ui-primitives` | 41: `Button.module.css`, `Checkbox.module.css`, `CodeCard.module.css`, `CommandText.module.css`, `ConfigField.module.css`, `ConnectionIndicator.module.css`, `DiffBlock.module.css`, `DisclosureRow.module.css`, `FileTypeIcon.module.css`, `HoverCard.module.css`, `ImageLightbox.module.css`, `ImagePreview.module.css`, `InlineEditor.module.css`, `Input.module.css`, `JsonTree.module.css`, `Menu.module.css`, `MenuGroup.module.css`, `MenuSurface.module.css`, `Modal.module.css`, `PathLabel.module.css`, `Pill.module.css`, `ReadBlock.module.css`, `RiskConfirmation.module.css`, `SearchBlock.module.css`, `SegmentedControl.module.css`, `SegmentedTabs.module.css`, `ShortcutKeys.module.css`, `StateDot.module.css`, `Switch.module.css`, `Tag.module.css`, `TerminalBlock.module.css`, `TextShimmer.module.css`, `Toast.module.css`, `Tooltip.module.css`, `WebBlock.module.css`, `markdown/CodeBlock.module.css`, `markdown/JsonBlock.module.css`, `markdown/MarkdownText.module.css`, `settings-form/SettingsForm.module.css`, `settings-form/fields.module.css`, `user-text.module.css` | `ui-primitives`: `Button.module.css`, `SegmentedTabs.module.css`, `Pill.module.css`, `Menu.module.css`, `MenuSurface.module.css`, `MenuGroup.module.css`, `ShortcutKeys.module.css`, `Tooltip.module.css`, `Input.module.css`, `Switch.module.css`, `Checkbox.module.css`, `RiskConfirmation.module.css`, `Tag.module.css`, `Modal.module.css` | canonical packages/dsh_ui; detailed mapping below |
| `ui-reference` | 0; delegate/inline/structural source still needs ownership classification | none | features/dsh_feature_reference; dsh_reference_chip.dart |
| `ui-renderer` | 0; delegate/inline/structural source still needs ownership classification | none | app composition / module and slot infrastructure; not a paint recipe |
| `ui-schedule` | 9: `client/ClockPicker.module.css`, `client/DatePicker.module.css`, `client/PickerPopover.module.css`, `client/ScheduleCatalogAction.module.css`, `client/ScheduleCreateCard.module.css`, `client/ScheduleTurnCard.module.css`, `client/SessionScheduleMark.module.css`, `client/TaskManagerPage.module.css`, `client/TaskMenu.module.css` | none | features/dsh_feature_agent_management |
| `ui-secret-mask` | 1: `client/SecretText.module.css` | none | features/dsh_feature_secret_mask |
| `ui-session` | 0; delegate/inline/structural source still needs ownership classification | none | features/dsh_feature_session; structural/session ownership |
| `ui-settings` | 0; delegate/inline/structural source still needs ownership classification | none | features/dsh_feature_settings; settings slot host |
| `ui-settings-account` | 8: `client/AccountAvatar.module.css`, `client/AccountMenu.module.css`, `client/AccountNotice.module.css`, `client/AccountSection.module.css`, `client/DesktopOnboarding.module.css`, `client/OnboardingSurface.module.css`, `client/PlatformOverlay.module.css`, `client/SignInDialog.module.css` | `ui-settings-account`: `AccountMenu.module.css` | features/dsh_feature_settings; sidebar signed-out menu profile only |
| `ui-settings-agent-loop` | 0; delegate/inline/structural source still needs ownership classification | none | settings forms / plugin settings composition |
| `ui-settings-general` | 8: `client/CurrentVersionRow.module.css`, `client/DesktopUpdateIndicator.module.css`, `client/DeveloperToolsRow.module.css`, `client/GeneralSection.module.css`, `client/HostReleasePrompt.module.css`, `client/SettingsDocumentAction.module.css`, `client/SettingsRoot.module.css`, `client/chrome.module.css` | `ui-settings-general`: `SettingsRoot.module.css` | features/dsh_feature_settings; only launcher-specific CSS is profiled |
| `ui-settings-models` | 4: `client/DeepSeekOnboardingDialog.module.css`, `client/ModelsSection.module.css`, `client/OnboardingModal.module.css`, `client/WelcomeNotice.module.css` | none | features/dsh_feature_model_settings |
| `ui-settings-plugin-inventory` | 1: `client/PluginInventorySettingsTab.module.css` | none | features/dsh_feature_plugins; shared Tag only |
| `ui-settings-plugins` | 1: `client/PluginsSettingsSection.module.css` | none | features/dsh_feature_plugins / settings |
| `ui-settings-session-log` | 1: `client/UploadRow.module.css` | none | features/dsh_feature_settings / session export settings |
| `ui-settings-shell` | 0; delegate/inline/structural source still needs ownership classification | none | settings forms / plugin settings composition |
| `ui-settings-subagent` | 3: `client/SubagentCard.module.css`, `client/SubagentLimitsFields.module.css`, `client/SubagentModelSelectionFields.module.css` | none | features/dsh_feature_settings / subagent settings |
| `ui-settings-web-search` | 1: `client/WebSearchCard.module.css` | none | features/dsh_feature_settings / plugin settings forms |
| `ui-shortcuts` | 1: `client/Reference.module.css` | none | features/dsh_feature_shortcuts; shared ShortcutKeys |
| `ui-sidebar` | 2: `client/HeaderLeadingControls.module.css`, `client/SidebarRoot.module.css` | `ui-sidebar`: `HeaderLeadingControls.module.css`, `SidebarRoot.module.css` | features/dsh_feature_sidebar; generated root plus unprofiled leading controls |
| `ui-sidebar-browser` | 1: `client/view/Browser.module.css` | none | sidebar-right / platform browser integration; explicit family mapping needed |
| `ui-sidebar-documentpreview` | 13: `client/LoadingIndicator.module.css`, `client/TextPreview.module.css`, `client/code/CodeBody.module.css`, `client/excel/ExcelBody.module.css`, `client/html/HtmlBody.module.css`, `client/image/ImageBody.module.css`, `client/markdown/MarkdownBody.module.css`, `client/markdown/frontmatter-fields.module.css`, `client/office/FontNotice.module.css`, `client/office/OfficeBody.module.css`, `client/pdf/PdfBody.module.css`, `client/zoom/ZoomControls.module.css`, `client/zoom/ZoomViewport.module.css` | none | features/dsh_feature_documentpreview |
| `ui-sidebar-files` | 1: `client/FilesBody.module.css` | none | features/dsh_feature_files |
| `ui-sidebar-right` | 3: `client/shell/ExpandButton.module.css`, `client/shell/SidebarRight.module.css`, `client/tabs/guide/GuideBody.module.css` | none | features/dsh_feature_sidebar_right; dsh_rightbar_host.dart |
| `ui-sidebar-terminal` | 4: `client/TerminalCleanup.module.css`, `client/TerminalGuide.module.css`, `client/TerminalTitle.module.css`, `client/terminal.module.css` | `ui-sidebar-terminal`: metadata/behavior/font only | features/dsh_feature_sidebar_terminal; terminal font generated, pane CSS not |
| `ui-skill` | 1: `client/SkillRow.module.css` | none | features/dsh_feature_agent_management / tool presentations |
| `ui-slots` | 0; delegate/inline/structural source still needs ownership classification | none | packages/dsh_slots; style-free slot contract |
| `ui-subagent` | 3: `client/SubagentHeaderLineage.module.css`, `client/SubagentReadOnlyComposer.module.css`, `client/sidebar-chat/SidebarChat.module.css` | none | features/dsh_feature_subagent |
| `ui-theme` | 13: `client/AppearanceRow.module.css`, `client/FontFamilyRow.module.css`, `client/FontSettingsGroup.module.css`, `client/FontSizeRow.module.css`, `styles/base.css`, `styles/brand-font.css`, `styles/corner-shape.css`, `styles/design-platform.css`, `styles/focus.css`, `styles/gradient-shadow-text.css`, `styles/onboarding.css`, `styles/scrollbar.css`, `styles/shiki.css` | `ui-theme`: `base.css`, `corner-shape.css`, `design-platform.css`, `focus.css`, `gradient-shadow-text.css`, `onboarding.css`, `scrollbar.css`, `shiki.css` | packages/dsh_theme global token pack; features/dsh_feature_theme; editor CSS unprofiled |
| `ui-tool` | 7: `client/tool/ToolCallTree.module.css`, `client/tool/components/AskQuestionCard.module.css`, `client/tool/components/ExitCodeBadge.module.css`, `client/tool/components/QuestionToolRow.module.css`, `client/tool/components/ToolDetails.module.css`, `client/tool/components/ToolRow.module.css`, `client/tool/toolviews/bash-sample.module.css` | none | features/dsh_feature_tool; shared code/read/diff/search/web blocks |
| `ui-trajectory` | 8: `client/TrajectoryCell.module.css`, `client/TrajectoryGroupHeader.module.css`, `client/TrajectoryTable.module.css`, `client/TrajectoryTimeline.module.css`, `client/TrajectoryToolbar.module.css`, `client/TrajectoryTurn.module.css`, `client/TrajectoryTurnHeader.module.css`, `client/views.module.css` | none | conversation/chat/tool trajectory renderers; no generated trajectory profile |
| `ui-user-questions` | 3: `client/PlanReviewPanel.module.css`, `client/QuestionComposer.module.css`, `client/QuestionReplyView.module.css` | none | features/dsh_feature_user_questions |
| `ui-workflow-run` | 1: `client/WorkflowRunPanel.module.css` | none | features/dsh_feature_workflow_run |
| `ui-workspace` | 4: `client/WorkspacePicker.module.css`, `client/rows/AnimatedRows.module.css`, `client/rows/Rows.module.css`, `client/rows/WorkspaceBrowser.module.css` | `ui-workspace`: `Rows.module.css`, `WorkspaceBrowser.module.css` | features/dsh_feature_workspace; feature_session workspace browser |

The13 package locks omit44 UI package identities. Even among the13:
plugin-manager extracts add/icon/info/menu profiles, plugin-market categories,
agent-preset the guide plus audited roster CSS, settings-general/account the
sidebar launcher portions, dockkit menu-related fields, and chat two statistics
sheets out of18. Terminal contributes font provenance rather than all four
terminal-pane sheets. HeaderLeadingControls is retained but its existing
canonical `_Control` still uses literal28/16/8 and500ms. `ui-theme` token input
coverage does not generate its ThemeEditor/preview control geometry.

## Styling dependencies outside the UI prefix

The following public pinned packages were also verified at0.2.1-rc.2. They have
no dedicated generated component profiles in the current recipe inventory.
The first three belong to core client/application styling; the last six are
experimental plugin surfaces and must be recorded if supported, rather than
silently inheriting an all-components-complete claim.

| Source package | Name | Own CSS inputs | Flutter scope |
| --- | --- | --- | --- |
| `packages/client/locale` | `@deepseek-ai/dsh-client-locale` | `src/client/LanguageRow.module.css` | core settings/shell/session actions |
| `packages/client/web` | `@deepseek-ai/dsh-client-web` | `src/base.css`, `src/boot-page.module.css` | core settings/shell/session actions |
| `packages/session-query/session-log-export` | `@deepseek-ai/dsh-session-log-export` | `src/client/HeaderAction.module.css` | core settings/shell/session actions |
| `packages/experimental/client-ui-agent-team` | `@deepseek-ai/dsh-experimental-client-ui-agent-team` | `src/client/TeamAction.module.css` | optional experimental feature; no generated family ownership established |
| `packages/experimental/client-ui-claude-code-mods` | `@deepseek-ai/dsh-experimental-client-ui-claude-code-mods` | `src/client/Band.module.css` | optional experimental feature; no generated family ownership established |
| `packages/experimental/client-ui-cot-translation` | `@deepseek-ai/dsh-experimental-client-ui-cot-translation` | `src/client/Translation.module.css` | optional experimental feature; no generated family ownership established |
| `packages/experimental/client-ui-voice-input` | `@deepseek-ai/dsh-experimental-client-ui-voice-input` | `src/client/VoiceInput.module.css` | optional experimental feature; no generated family ownership established |
| `packages/experimental/inspector` | `@deepseek-ai/dsh-experimental-inspector` | `src/client/bottom/page.module.css` | optional experimental feature; no generated family ownership established |
| `packages/experimental/session-inspector` | `@deepseek-ai/dsh-experimental-session-inspector` | `src/client/views/inspector.module.css` | optional experimental feature; no generated family ownership established |

This gives60 core public packages with213 source CSS files, or66 public packages in this style audit / 219 CSS files when these six optional surfaces are included. These
are source inventories, not counts of independent canonical controls.

`apps/desktop` is a **private** package, not another npm-published UI package;
its four renderer styles are `renderer/update-dialog.css`, `renderer/welcome.css`,
`renderer/mandatory-update.css`, and `renderer/assets/window-material.css`.
They are relevant platform/reference surfaces if ported and need an explicit
adapter ledger. The website's three VitePress CSS files are documentation UI,
not part of the app dependency/style acceptance universe.

## Generated-field consumption and unsupported coverage claims

A direct reference scan finds55 of666 generated fields unused by runtime code.
Several are deliberately redundant font-size/line-height audit metadata whose
fontToken already carries the effect, so55 is **not** an implementation-gap
count. However sidebar/workspace scrollbar fields and row/header/group gaps
are concrete review candidates: emitting them without connecting source-owned
paint/layout leaves handwritten counterparts in place. Class/field consumption
needs explicit `runtime`, `derived` or `audit-only` classification.

The global token generator is substantial and verified. That does not generate
connection/status/disclosure/toast/content/form recipes. Existing visual cases
may establish a bounded real-reference comparison, but fixture count, generated
token count, preserved legacy RGBA pixels and generic tool passes cannot be
used to claim all source families/states are covered. Popover backend sampling,
macOS vibrancy and documented state/caller gaps remain explicit limitations.

## First foundational fixes, before more page ports

1. **Make the universe machine derived.** Add the57-package plus3 core-dependency
   closure, every CSS/inline/SVG source and public component export to a generated
   catalog from pinned published archives. Give each component profile source
   package/version/integrity, original selector/state, canonical owner and
   generated/partial/unmapped/deviation status. Keep optional surfaces explicit.
   A missing source file, new export, unsupported state or empty owner must
   produce a visible inventory failure/change, not disappear behind16 labels.
2. **Connect profiles already retained.** Finish HeaderLeadingControls and
   consume the existing workspace/row/scrollbar metrics where intended. Split
   the row, selector and stepper ownership from the generated switch/checkbox
   classes in dsh_settings.dart. DshInput and handwritten major DshTextField are
   distinct profiles. Resolve duplicate icon actions through source profiles.
3. **Compile common forms and selection next.** Extract ConfigField, SettingsForm,
   fields/secret/select controls, SegmentedControl, settings rows/stepper/pills
   from their published CSS and behavior. These are shared foundations for
   account/model/plugin/preset/settings consumers, not separate page fixes.
4. **Compile common feedback/navigation atoms.** StateDot/spinner versus StatusDot
   vocabulary, ConnectionIndicator, DisclosureRow, TextShimmer and Toast need
   actual profiles and state coverage. HoverCard/InlineEditor/PathLabel need
   explicit ownership instead of being assumed covered by Tooltip/Input/helpers.
5. **Compile content/media families.** CodeCard/toolbar, code/markdown/JSON,
   terminal/read/diff/search/web, user text/reference chips, image preview/
   lightbox and file-type CSS must consume source profiles. Generic DshCard's
   handwritten layer2/border-l4/radius/padding is not a universal source Card
   family; select real source profiles rather than generating an invented Card
   recipe. Shell/dock/composer/trajectory families follow the same ownership rule.
6. **Enforce the actual contract.** Extend static checks to all paint/layout/
   typography/state/timing inputs and component-level source provenance; track
   legitimate platform/algorithmic constants separately. Ratchet allowlist changes
   as well as counts. Add source-mutation/unknown-state checks and meaningful
   controlled pointer/keyboard/accessibility plus real reference state captures.
   Moving a literal into a handwritten helper or retaining a CSS file must not
   be reported as completing a component profile.

The current16 statuses already admit many partial migrations. Retain that
honesty while replacing the coarse inventory with the source-derived catalog.
This audit identifies the complete package/style scope and foundational debt;
it is not a claim that the above migrations or99.5% visual acceptance are done.
