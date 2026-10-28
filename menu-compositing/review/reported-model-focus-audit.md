# Model pane programmatic focus

Source: DSH `687f282e8625c6b8d11ff58211a90524be2e4317`, published model
selection0.2.1-rc.2. This follow-up corrects the earlier hover-only explanation
of the effort-card difference. The source's focused effort cue is real and
must survive moving the pointer out of the menu.

## Actual source probe

An independent fresh Playwright/Chromium instance served the existing actual
pinned-source static host on an ephemeral port, with the original capture
arguments, verified pinned-font hashes and exact desktop EN dark case. It ran
click chip → click root Effort → hover synthetic result label, without changing
the source, capture engine or the concurrently running capture pipeline.

The active element was the Max BUTTON (`effort-option-effort:max`). Before
pointer settlement, after settlement and after200ms, Max had hover=false,
focus=true and focus-visible=true. Its computed background was
`rgba(255,255,255,0.08)`; Low and High were transparent and unfocused. Source
row rectangles were x832,width240,height34, with y634/668/702 respectively.
There were no page errors. The temporary server and browser were closed in
`finally`; no native fixture or desktop compositor was started.

The relevant published rules are `ModelSelect.tsx:176-201`, which programmatically
focuses the checked row after pane entry, and `ModelSelect.module.css:239-248`,
which gives `:focus-visible` the generated hover token while `.selected` remains
transparent/check-only. Moving the pointer is useful capture hygiene, but
does not clear this actual source focus cue.

## Implementation scope

Changed only four shared-main product/test files, without a commit:

- `packages/dsh_ui/lib/src/dsh_menu_item.dart`: optional controlled
  `focusVisible` intent. The canonical row applies it only while its actual
  node has primary focus and the row is enabled. Null preserves existing
  modality-based presentation and all paints still use existing generated
  tokens. No selection-fill default changed.
- `features/dsh_feature_model_selection/lib/src/model_select.dart`: assign
  this intent to the node the source would programmatically focus on pane
  entry. Clear it on blur, a new pane or return to root. Search entry retains
  its existing input focus. Keyboard focus movement uses the normal cue after
  the programmatic entry node blurs.
- The two corresponding existing test files contain the behavioral regressions.

No global FocusManager strategy, font, scorer, classifier, capture engine,
reference, metric or manually chosen style value changed.

## RED / GREEN

The new feature test reproduced the missing cue before the fix. After pointer
entry and moving the pointer away, the effective Max row already had primary
focus and selected/check-only state, but its decoration fill was null instead
of the canonical generated hover token. RED log:
`notes/reported-model-focus-red.log`.

After the fix,35 model-selection tests and13 canonical menu-family tests passed.
They cover pointer-settled focused entry, blur to another row, check-only
selection after blur, keyboard arrows and Escape return, disabled rows, pending
selection suppression and unchanged default touch presentation for callers
without an explicit focus intent. Logs:
`notes/reported-model-focus-green.log` and
`notes/reported-menu-focus-green.log`.

Targeted four-file analysis found no issues; `check_deps` passed all45 packages;
four-file formatter and `git diff --check` passed. Analysis log:
`notes/reported-model-focus-analyze.log`.

Old native receipts remain evidence for their exact previous runtime. Main
owns fresh paired captures, full preflight, final builds and native84/Android15
replay on the new runtime. This focused GREEN result does not certify those
future runs or the overall99.5% visual target.
