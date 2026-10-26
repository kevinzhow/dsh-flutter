# Model providers and common settings validation

Implementation: `68dfa7a6bb768e638169d218339b5f5a474e45fe`. All content is synthetic.

- Actual upstream production behavior vectors cover provider directory joins, key/capacity/model/reasoning validation, minimal path operations, search-provider transactions and subagent model authorization.
- Local full preflight: all 12 checks passed on the exact implementation tree, without skipped checks. Generated transport, controller, widget and normal-app integration tests run in that suite.
- Linux and Android normal/fixture release builds passed. Final subsequent changes only reorder an import and clean up test API usage.
- Native Wayland on Weston 14 with Mesa Intel graphics: desktop and phone sizes, 7 actual interaction assertions each, all passed. Synthetic welcome, model editor and key reveal/edit/remask interactions use generated Remote/ConfigForms calls.
- Android API 36: 31 actual scenes passed. Native password input has an API-key hint label and editable/password state; reveal exposes checked state and editing remasks. Key refusal/retry, discovery/adoption/save, accepted toggles, numeric validation, shared Subagent Save and search configuration are exercised. Preference toast persistence across settings closure is verified in widget/integration tests; UIAutomator's idle wait can outlast its display duration.
- Visual matrix: 96 comparisons; **0 strict pixel matches**, mean non-text similarity 83.149%, 4/96 matching dimensions. Visual alignment remains incomplete. Fonts, thresholds and classification are unchanged.

[Component comparison index](components/README.md) · [Native desktop](gpu/models.desktop/remasked.png) · [Native phone](gpu/models.phone/general.png) · [Android validation](android/receipt.json) · [Validation receipt](receipt.json)

Owned native runtimes were stopped, the normal Android app restored and stopped, and shared ADB retained. Native fixture actions are synthetic; normal production app routing is tested by `apps/dsh_flutter/test/model_settings_flow_test.dart`. Native account login and platform-specific behavior remain in the following platform task.
