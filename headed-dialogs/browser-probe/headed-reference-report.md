# Headed / risk source reference handoff

Base: main942090b4c2eded5991a92209a101fd20de787c99, treef25b01542a822f759c6e7bde9fc1813b8e8964dd.
Isolated worktree: `scratch/whalee-headed-reference`, branch`codexalice/headed-reference`.
No product edits, commits, pushes, ADB, GPU, emulator or native process runs.

## Three scoped files

| File | SHA256 |
| --- | --- |
| tool/parity-ext/build-headed-dialogs.py | 16416b8747a82d24851894c21dc0ffbe32f2cc55a4e52974a81748e0e6d0a387 |
| tool/parity-ext/host/headed-dialogs.tsx | 840e576fe5372f674114a43444f7191264cb07063d7afe176efff67343400fc7 |
| apps/dsh_flutter/test/parity/cases/headed_dialogs.dart | c5e9fff996bb6b02b45fd0eafc0198e3dfecf382c13760665fa59f06bf0d26dd |

New kind`headed-dialogs.risk`, prefix`components.headed-dialogs.`. Source renders
actual RiskConfirmation without restyling. Copy comes from the real current-session
permission.access dictionaries(accessEn/accessZh), matching Flutter's locale seat.
The existing risk cohort's different host/dictionary and the reader64 cohort are
untouched and remain separate preservation work.

The Flutter fixture uses the agreed controlled DshRiskDialog API: acknowledged,
onAcknowledgedChange, disabled, onCancel and onConfirm. It uses a StatefulWidget
for the source-controlled checkbox and closes its local fixture on either action.
It is parsed/formatted, but cannot compile at the untouched942090b base until the
parent integrates that new public API. Public case-map discovery automatically
finds the new map; no shared import file is edited here.

## Matrix and source results

64 captures: 32 whole cards covering unchecked/checked × enabled/disabled;
16 long-content cards at explicit top/bottom scroll positions; 16 fixed-footer
crops at those same positions. Every group spans EN/ZH, light/dark,
desktop800@1 and phone390@2.625. Normal viewport height900; long height320.
Long warning copy repeats the real localized string six times separated by spaces.

Vendored CLI validates2244 total manifest cases, with64 newly added by this builder.
Actual React capture:64 fresh,0 failed. No Flutter comparison is claimed.
Artifacts: `build/parity-headed-reference/visual-testing-results/react/`.
SHA256 and PNG dimensions for all64 are in`.local/headed-reference-receipt.json`.
Capture log:`.local/headed-source-captures.log`.

48 real-source DOM contexts(32 normal +16 long) pass controlled checked/disabled,
confirm-gating, focus and DOM ownership assertions. Raw browser proof:
`.local/headed-source-measurements.json`; reproducible probe:
`.local/headed-source-measure.mjs`.

| Normal card | EN size CSS px | ZH size CSS px |
| --- | --- | --- |
| Desktop | 440×314 | 440×270 |
| Phone DPR2.625 | 342.095245×358 | 342.095245×292 |

At height320 all long cards are272 high, from actual support for
`max-height:calc(100dvh - 48px)`. Content is192 high; footer is36 high, separated
by20 with bottom padding24. The full header62px and body scroll together.
Footer remains outside content and its full rectangle is unchanged at top/bottom
in16/16 long contexts. All8 top/bottom footer PNG pairs are exactly RGBA-equal;
proof:`.local/headed-footer-retention.json`.

At short viewport source content extents are desktop EN482/ZH262 and phone
EN657.904785/ZH393.904755 CSS px(actual maximum scrollTop; rounded DOM scrollHeight
produces658/394 on phone). Explicit case offsets avoid relying on focus scrolling:
source automatic checkbox focus initially scrolls the long content towards its end.

Source body margin-top20 is measured after the header; warning typography14/22,
icon18 with gap10; acknowledgement margin-top20, native checkbox16 with top3.
Footer actions are36px high. ZH outer widths hit the source minimums72/136;
EN labels expand naturally(desktop73.59375/145.4375; phone72.345238/145.434525).

## Focus findings and capture limit

Enabled entry focuses the source checkbox in32/32 contexts, with
`data-dsh-automatic-focus` present and computed outline none/0px even though
`:focus-visible` matches. Existing Flutter DshCheckbox already has private
`_automaticFocusSuppressed` state and navigation-key release; the audit's broader
claim that no checkbox suppression exists is incorrect.

Disabled entry leaves focus on BODY in16/16 contexts. The pinned useModalLayer
selects the disabled`[data-modal-autofocus]` input before its fallback query, and
native focus fails. First unmodified Tab enters Close(proved for both disabled
checked states). This is a source limitation; it does not justify intentionally
moving Flutter focus behind its foreground modal.

Reference capture arguments remain unchanged, including Playwright's implicit
`--hide-scrollbars`. Risk content has no stable gutter and in these captures its
client width equals the card's whole width(including the long overflow cases).
No visible-thumb acceptance claim is made; PR55's separate diagnostic already
established the implicit flag's effect. Fonts, classifier and thresholds remain
unchanged. Every probe-owned browser/context/HTTP server is closed.
