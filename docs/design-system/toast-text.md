# Bounded source-normal Toast text correction

This change consumes the existing published Toast contract without changing its
recipe, font, colour, capture inputs or comparison rules. The actual
ui-primitives0.2.1-rc.2 Toast at DSH
`687f282e8625c6b8d11ff58211a90524be2e4317` inherits
`white-space: normal`, `overflow-wrap: normal` and `word-break: normal`.
Its `.text` span only supplies `min-width: 0`; the whole Toast retains the
published content-box cap, padding and line height.

The canonical painter previously passed raw tabs, newlines and repeated spaces
to a native paragraph. It also let the paragraph emergency-wrap a sole oversized
word into several rows. Both differ from the actual published component.

## Source proof and implementation boundary

All 64 existing whitespace/unbroken-word inputs were measured on the untouched
published component with per-character DOM Ranges and rendered `innerText`.
Normal and reduced motion, both themes/locales, desktop/phone and DPR1/2.625
agree on the relevant behavior. The English whitespace input becomes
`Synthetic spaces and line breaks with a non-breaking space.`; the Chinese
input becomes `合成 空格 与 换行以及 不换行空格。`. NBSP remains NBSP. The
oversized Latin token stays one 22px line and paints beyond its constrained text
seat instead of adding rows.

Eight additional unchanged-source controls distinguish empty/collapsed ASCII
whitespace from NBSP/em-space, verify that NBSP joins two oversized words, and
verify ordinary Chinese line breaks. Empty and ASCII-whitespace-only spans have
zero width and height; NBSP still has a line box. These are actual source props,
not changes to the retained seven scenario inputs or component body/styles.

The private canonical `_ToastText` collapses only ASCII CSS whitespace and
trims collapsed edge spaces in its visual string. It retains the full original
value in `DshToast.text` and `DshChromeText.semanticsLabel`. The existing native
intrinsic measurement, compared with an otherwise-identical grapheme/WJ clone,
identifies a sole unbreakable run. That clone and its terminal measurement space
never paint or replace the raw announcement. Such a run disables emergency
wrapping and uses visible overflow; ordinary paragraphs retain the native
breaker's real break opportunities. A wholly collapsed span has no line box,
while its owner retains source padding and any separate icon seat.

This is a bounded correction for the retained inputs and the stated controls.
Mixed paragraphs containing an oversized unbreakable run still need a fuller
CSS line-break implementation; this change does not claim all Unicode,
bidirectional, language-sensitive segment-break or font-engine behavior is
equivalent. No source overflow is clipped or rewritten to improve a score.

## Retained preparation evidence

In the isolated `scratch/whalee-toast-text` worktree:

- `.local/toast-text-source-proof.json` and its `.mjs` producer contain the64
  actual source measurements, original source provenance and all character
  ranges. Chromium145.0.7632.6, published source body/styles unchanged.
- `.local/toast-text-source-controls.json` and
  `.local/toast-text-source-break-controls.json` contain the eight additional
  controls and their separate unchanged-source producers.
- `build/toast-text-provider64-final` is a fresh source-only run through the
  normal parity CLI and actual-published provider. Its64 original PNGs decode
  and compare RGBA-identical to the corresponding retained source224 originals;
  `.local/toast-text-provider64-verification.json` records every comparison.
- `.local/toast-text-red.log` preserves the original implementation's27 failed
  checks. Focused canonical/owner checks and analysis/guard receipts are retained
  separately; their exact hashes are in `.local/toast-text-handoff.json`.

The first normal-provider attempt used a relative output directory, which the
vendored CLI resolved from its output cwd; it failed before capture. That log
and output remain. The successful retry used an absolute output directory.
An additional-control summary initially failed after measurements were written;
its producer, log and output remain separate from the successful control run.

These are source and focused-widget preparation proofs. The integrator owns
fresh combined-tree paired captures, native replay and overall visual acceptance.
Geometry can continue finding the single `DshChromeText` outer line box; its
`data` is now the actual displayed string, while the original semantic value
must be labeled separately from source DOM `textContent`. No capture producer,
scenario, native fixture, generated recipe or family policy is changed here.
