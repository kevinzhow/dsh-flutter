# Native Toast callback observation

This changes only the synthetic native fixture and its recorded comparison rectangles. Production Toast timers, source paint timing, shadow rendering, tokens, fonts, classifier and visual acceptance thresholds are unchanged.

## Why the original probe failed

The retained `build/toast-gpu-final2` diagnostic was produced from commit `699801259ede778bfbd5dcf49e2a009220f753bf`, tree `e018bd02a859da1657bc61a7502c9f256ba2e639`, manifest SHA-256 `8f77b54a24ba1a5755fe2758039c7c64c368e482ee5f4d80d4ef1f89e1f358fa`. Its first dark case passed 22 assertions; the light case failed the pending callback comparison. It remains failed evidence, and none of its images was replaced or edited.

The actual callback status in both light `changed-update.png` and `changed-pending.png` is `lifecycle; done: 0; clicks: 2`. The original full-width status rectangle `[8,110,1272,130]` includes empty background under the Toast's shadow. Between those frames, 2,065 pixels change there by at most 3 RGB channel values, exclusively within `[538,110,743,121]`; the status text remains unchanged. The same dark rectangle happens to quantize identically. Raw original file hashes and measured differences are retained in `.local/toast-callback-probe-diagnosis.json`.

The pinned published `Toast.module.css` uses a delayed fade, and the element owns `--dsw-shadow-lv3`, including `0 12px 32px 0 #00000014`. Its complete published behavior body reschedules `holdMs + FADE_MS` from an actual hold update. Changing the CSS custom-property delay retains the original animation timeline. The canonical implementation deliberately preserves this distinction.

The fixture changes hold from the generated 3,000ms default to default+fade=4,000ms. Therefore the intended pending observation crosses the original 4,000ms completion boundary while the source paint can already be fading. Shortening its 3,800ms wait would weaken the deadline test. Allowing a pixel tolerance would conflate the callback observation with shadow rendering.

## Dedicated actual counter

The fixture now paints `Lifecycle callback count: N` in a separate footer seat using its existing fixture spacing. It reads the same actual `done` state incremented by the canonical Toast's completion callback. It has one explicit, uniquely named semantics owner. The unchanged upper `Toast fixture: ...` label remains the Android driver's unique status target; there is no duplicate label and no added Android operation.

The pinned native widget tests measure the entire actual counter Text rectangle. No glyph selection, pixel search, fitted crop, color masking, image resizing or score change is used.

| Viewport | DPR | Themes | Measured counter rectangle `[left,top,right,bottom]` | Measured long Toast bottom | Source shadow band bottom |
| --- | --- | --- | --- | --- | --- |
| 1280×720 | 1 and 2.625 | light and dark | `[8,692,1272,712]` | 174 | 234 |
| 390×844 | 1 and 2.625 | light and dark | `[8,816,382,836]` | 262 | 322 |

The collision guard reads every shadow layer from the actual generated `DshShadowBox` and adds `offsetY + spread + 3 × (CSS blurRadius / 2)` to the measured long Toast bottom. It is fixture separation proof, not a production shadow change or a comparison tolerance. All eight viewport/DPR/theme combinations put the counter well below that band.

The eight behavioral raster tests capture the complete app boundary and compare the full counter rectangle. Its raw RGBA remains exactly equal after the original deadline while the Toast is fading and the actual callback count is still 0. It then changes only after the real completion callback makes the count 1. The callback is never invoked manually by a test.

## Preserved driver contract

Only three comparison rectangles per GPU case move to the measured footer: same-hold expired, changed-hold pending, and changed-hold expired. Their references and true/false conditions stay intact. All waits, input order, screenshots and assertions remain:

- four GPU cases, 88 assertions, 100 full PNGs and 136 literal input instructions;
- Android's entire literal object remains unchanged: 19 scenes, 35 checks and 28 inputs;
- original control/status/owner geometry remains unchanged;
- no application build, emulator, GPU replay, process termination, push or publication ran in this preparation lane.

Preparation data, fixture/test hashes and the pinned geometry-log hash are refreshed in `toast-cases.json`. `.local/toast-callback-probe-preparation.json` binds the logs and confirms the restricted literal delta.

## Verification

Eight focused tests fail on the original fixture because the dedicated observation does not exist. With the fixture correction, all 23 native fixture tests pass, including eight exact-RGBA callback probes and eight measured geometry/semantics/input cases. Focused analysis is clean. Logs remain in `.local/toast-callback-probe-red.log`, `.local/toast-callback-probe-green-final.log` and `.local/toast-callback-probe-analyze.log`.

This is preparation evidence. The integrating owner must rebuild and rerun the native proof on the new exact clean head before accepting it. The previous failed native run does not become accepted through this correction.
