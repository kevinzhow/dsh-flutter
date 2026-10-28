# Reported families independent review — 2026-10-28

Reviewed product and reference-fixture changes at
`ceab35228043f7a95e937081c8f79ce924c510a8` against
`c0fa5c671aa0001ea6192050413e4043b4bc236e`, read-only. No Flutter build,
test run, native device operation or repository mutation was performed.

No blocking correctness regression found in the three reported entry paths.
This is a source review, not a substitute for the parent's pending full checks,
paired reference captures or native replay.

## Native accessibility follow-up

Android then exposed a real omission missed by the initial source review:
statistics and model-trigger `Semantics(excludeSemantics:true)` suppressed the
child GestureDetector tap without re-exposing a native action. The focused
audit reproduced both with RED semantic-action assertions. Added the same
production callbacks directly to the enclosing Semantics; disabled/locked
model triggers expose no action. Actual semantic activation now opens/switches
both statistics cards and drives root→model/effort→remote selection. Whole
statistics13 and model-selection31 tests pass; RED and final GREEN logs are
retained under `.local/reported-*-a11y-{actual-red,red,green2}.log`.

The audit also identified the same pre-existing omission on the non-macOS
sidebar brand and SettingsDocumentAction; parent owns those separate files.
Shared menu rows already expose their `onTap`, and More/toggle/panel/rail-New,
search/edit, search-clear and retry keep child semantics without exclusion.
Native Android/GPU outputs from before these fixes must not stand in for the
final replacement runtime.

Reviewed:

- Shared root portal: live inherited theme/platform/frame propagation;
  bounded actual-anchor follower; grouped outside-pointer dismissal without
  an intercepting full-screen listener; static-stat focus retention;
  per-overlay sibling replacement; initial-KeyDown Escape; local-history and
  Back dismissal; owned listener/focus teardown.
- Sidebar: source macOS top-strip/logo overlap, scrollbar-side expansion,
  workspace header/list insets, source signed-out launcher geometry and
  canonical bounded More menu. The source and Flutter fixtures use the actual
  component composition with matching synthetic groups and session data.
- Model: compact root/model/effort panes, source clamp/gap, search and provider
  order, pending suppression, projection-backed selection, scroll reveal and
  nested Escape. A focused DshMenuItemButton handles Tab as activation before
  the enclosing pane's key handler; the latter's Tab focus-entry branch does
  not override row activation.
- Statistics: existing projection/formatting paths are preserved; open cards
  rebuild from current pills; source-derived bounded grid and unbacked
  filtered material replace the local card; source undefined separator ink
  falls back to inherited pill ink.
- Provenance: new package extraction decodes static CSS/class maps/behavior,
  validates archive integrity and bundle hashes, and retains manifest/license
  bytes. Family/compiler additions survive integration; no font/scoring
  classifier modification was found.

Known limits remain real and must stay visible in the delivery: textured
statistics backdrop sampling is not pixel-identical to Chromium; Linux
simulated macOS geometry cannot certify native window vibrancy; account
actions, composer-driven icon compaction and selection Toast remain unported.

One additional bounded source behavior to retain in the model inventory:
upstream ModelSelect's `onBlur` closes when focus leaves both the trigger and
card (`ModelSelect.tsx` around line 366). The Flutter anchored card currently
closes through outside pointer, Escape or Back, but has no equivalent
focus-out listener. Thus programmatic focus transfer by another application
shortcut can leave this card open. This does not affect the three reported
pointer/screenshot paths and is not a newly demonstrated app regression;
do not claim complete source keyboard/focus parity without covering it.

## Final combined fixed-head review

Independently reviewed clean/pushed
`a4b68e7ced8528bb7f5e71832e1cd77cf6d60aec`, tree
`88a00d89d8776423314579afaa7d836406aa9d9f`, against the prior runtime
`6de2b7073c5030b8bad9293e50db5acd03c74a66`. No blocking correctness issue
found in the combined final changes. No additional builds, test execution,
native run or product-source write was performed by this review.

- Shared DOM geometry now mirrors the actual source APIs. Only the coordinate
  equations use integer window dimensions and integer offset dimensions;
  anchor rectangles, child layout and CSS viewport constraints remain
  fractional. Both statistics and ModelSeat opt in. Defaultfalse preserves
  other follower clients, and the relayout predicate includes the new flag.
- ModelSelect's `.menu` has no border-box declaration or applicable global
  reset. Its240/420 width and360 height limits constrain content, with4px
  padding outside each side. The final width and height constraint composition
  preserves that relationship; it does not resize the34px rows or76/110px
  root/effort cards. Source CSS viewport caps correctly retain fractional
 100vw/100vh even while JS coordinate clamping uses integers.
- The material correction is source-backed: actual MenuSurface.module.css
  `.material` paints `--dsw-menu-surface-fill`, and the generated
  DshMenuSurfaceRecipe.fillToken has exactly that value. macOS overrides only
  the separate `--dsw-specific-menu` used by statistics; routing that94% token
  into generic MenuSurface was incorrect. The final implementation restores
  the released MenuSurface token while DshPopoverSurface keeps its correct
  scoped statistics fill. Remaining arbitrary-content/native-vibrancy limits
  are still applicable; the sampled flat-ground match does not certify them.
- The DshInput placeholder is now positioned inside the box determined by
  EditableText. It cannot increase intrinsic layout height with a fallback
  Chinese or emoji glyph. Direct actual-source probes found both English and
  Chinese desktop model inputs at17px, wrapper27px, font12px/normal line height.
  The paint-only change fixes placeholder-dependent growth; it does not prove
  matching browser normal-line height. It retains IgnorePointer and leaves
  native editing/actions, padding, font settings and controller behavior in
  place. Standard inputs keep their existing outer height. The remaining
  input/menu height difference is recorded below.
- The added tests validate the source geometry, unchanged default placement,
  long-card content-box caps, placeholder independence and source-ground
  light/dark material pixels. No font, classifier, threshold or capture-rule
  edit is present in the reviewed revision.

Final108-pair captures,96-case preservation, exact-tree full checks and new
GPU/Android runs remain the parent's acceptance responsibility. Earlier6de
native receipts must remain prior-runtime evidence. Overall99.5 is still
unfinished, and the source focus-out/Toast/composer-icon limits above remain.

## Final PNG residual: natural input line height

Latest actual paired metadata confirms the model directory still has a small
height discrepancy in both EN and ZH, after the source-derived placement,
content-box and placeholder corrections:

| Density/context | Actual source directory | Flutter directory | Positions |
|---|---|---|---|
|Desktop1×, EN and ZH|248×291|248×290|source(828,449), Flutter(828,450)|
|Phone2.625×, EN and ZH|248×290.38098|248×290|both(118.095238,450)|

The phone PNGs are source651×763 versus Flutter651×762 physical pixels. This
is one logical pixel at1× and one physical pixel (0.380952 logical) at2.625×;
it must not be described as one logical pixel at every density.

Fresh read-only inspection of the same actual pinned source host and fonts
confirms English and Chinese placeholders do not change the browser input's
normal line box. Desktop input height is17px with27px padded wrapper. Native
2.625× input height is16.380952835px with26.380952835px wrapper; its offsetHeight
is16, and the menu offsetHeight is290 despite a290.380951px DOMRect. This is
consistent with the remaining difference from Flutter's16px natural editable
line box and the resulting290px card. The source DOM input measurements and
the full card metadata are direct observations; the localization of all the
remaining height difference to the editable line is an inference from those
observations and the matching surrounding recipe geometry.

The paint-only placeholder correction therefore removes an invalid source of
layout growth without completing input normal-line pixel parity. No invented
17px CSS-normal recipe constant, font override, scorer change or acceptance
crop adjustment was applied. This residual remains part of the unfinished
overall visual target and must stay visible in the final evidence/PR limits.

## Matched-hover capture contract

Read-only inspection of495fb691aae64bd2c7c193d9b4f945e4051888dc/tree
559e3de1d09e902a12dceaa639dc3b3499deffba confirms its only changes are the
reported-model case builder's final existing hover action and the associated
documentation. The actual source browser click retains a mouse over the
page; Flutter's test touch click does not establish a matching mouse position.
Explicitly settling both pointers removes that possible state difference.
The earlier hypothesis that the Max cue was merely a leftover row hover was
not supported by the subsequent source DOM probe: Max remained hover=false
and focus-visible=true. The component focus correction below is required in
addition to this capture hygiene.

Both providers now perform `hover reported-model-result` after opening/drilling
the menu. This is the existing shared synthetic result label, outside the menu;
it gives both providers the same final pointer location. No component style,
product behavior, renderer, font, classifier, crop or numerical threshold is
changed by this correction.

Earlier report/stage prototypes and their metrics are superseded, unpublished
before-pointer evidence. Their observed input-line geometry residual remains
documented above, but final results must come from the refreshed108 paired
captures and matching final-tree full checks. Native runtimea4b68e7 and its
build/GPU/Android evidence are now prior-runtime evidence, superseded by the
programmatic-focus revision below. The earlier192 provider preservation
comparison concerns unaffected cases.
The report builder now derives all visual counts/means and directory dimension
prose from the newly staged records and requires the matched-hover manifest.

## Programmatic-focus fixed-head review

Independently reviewed clean/pushed
`37fbe33ad7edc2fc818d2666b812b13eae1040e4`, tree
`7ee075f6de59f2f84954d630403926521d975bf0`, against495fb691. The diff changes
two production files, their two bounded test files and documentation. No
blocking correctness issue found in the new focus-presentation path. This
review ran no builds/tests/native applications and made no product edits.

The actual source contract is clear: ModelSelect programmatically focuses the
checked enabled option after a drilled pane mounts, while its CSS uses the
canonical hover token for `:focus-visible`. Its `.selected` rule stays
transparent, with selection represented by the trailing check. The fresh DOM
probe in `reported-model-focus-audit.md` found Max hover=false/focus=true/
focus-visible=true before and after pointer settlement. Clearing hover alone
cannot remove or reproduce this source cue.

The final canonical DshMenuItemButton adds optional focusVisible intent,
defaultnull. Explicit intent paints only when the row has actual primary
focus; the existing enabled gate suppresses disabled-row cues. Null leaves
other clients' modality-based behavior intact. Both the normal row paint and
the dock ring use the same resolved intent, and all colors remain generated
tokens. The selectionFill default and trailing check behavior are unchanged.

ModelSheet records the actual FocusNode it requests after drilling. It clears
the intent for a new pane, on that node's blur and when returning to the root;
the search-input branch retains its existing focus path. Consequently the
cue follows real focus rather than the stored selected value, and keyboard
movement resumes ordinary focus presentation after the entry node blurs.
No global focus modality, arbitrary style metric, font, palette, classifier,
capture engine or score threshold was changed.

Read-only visual inspection of the final3 desktop/light and phone/dark
`model-efforts.png` screenshots shows the Max row's focus fill and check, with
Low and High unfilled. The GPU lane separately records the unchanged84
assertions against this exact runtime. Parent owns the fresh final108/96,
full13, four builds, Androidfinal5 receipts and final staging acceptance.

The demonstrated resolved-model pane-entry cue is now fixed. It must not be
listed as a remaining screenshot difference or confused with the separate
source onBlur behavior: programmatic focus transfer outside the trigger/card
still does not close the Flutter menu. Natural input line-height sampling,
statistics composed blur, macOS vibrancy acceptance and the other explicitly
bounded model/sidebar gaps remain unfinished. No new visual count or mean is
claimed by this code review; the report reads the refreshed completed stage
using explicit runtime37fbe33/tree7ee075f6 arguments.
