# Capture corrections — k172, 2026-10-25

Source PR #26, head a6fa4fca4c2f24fee4bf1bd01e267fade8f58e60; based on main 9920f7a. These are synthetic fixtures and contain no host credentials or model requests.

## Fractional device boundaries

All 72 retry/prompt cases were recaptured with unchanged cases, pinned fonts, browser flags, thresholds and classifiers. React now copies the enclosing device rectangle from its full viewport PNG, matching Flutter. All 72 image pairs have equal dimensions. Compared with integrated-chat/react, exactly six images gained the missing last row (223→224 or 454→455); all overlapping RGBA pixels in all 72 captures are identical. See capture-boundary-comparison.json. No resampling, filling or excluded failed regions.

Retry: mean non-text 97.531%, 0/32 at least 99.5%. System prompt: mean 98.735%, 4/40 at least 99.5%. Combined strict geometry count: 4/72. The broader summary status counts include official basic-pass results and must not be mistaken for this strict count. The overall visual goal remains open in task #6.

## Native cursor

The native fixture is the preserved accepted Linux standalone system-prompt build, under Weston14 with Intel Lunar Lake hardware GL; both app and compositor render-device guards passed. Desktop-light and phone-dark-Chinese click/expand/scroll replay passed; recorded app/Weston processes were verified gone afterward.

The pointer was not moved. Its compositor sprite alone was hidden during each screenshot and restored afterward. On the desktop card, exactly 198 pixels changed inside the 13×23 rectangle [77,1,90,24] in card coordinates; every pixel outside that cursor region stayed identical. The same browser/native card comparison changed from 99.281% to 99.511%. This is one matching native sample, not a 72-case native pass. The application pixels beneath the pointer were rendered normally; no screenshot masking or painting was used.

## Font diagnostic (not a policy change)

Five captures of the same two-line card vary only Chromium font-render-hinting. The fixed baseline remains `none`. Native-card non-text results: none 99.511%, default 99.380%, slight 99.564%, medium 99.373%, full 99.380%. These are separate diagnostics, not replacements for the published baseline. No product typography or reference font settings changed.

## Validation

All 11 fast preflight checks passed, including 84 tool tests, parity selftest, formatting and workspace analysis. New tests cover fractional edges/origins, float noise, viewport clipping, unchanged RGBA channels, invalid geometry, private screenshot permissions and cursor restoration after capture timeout. Product build jobs are also run by PR CI. Full product tests/builds were not repeated locally for this tooling-only change; the 72 Flutter captures compiled and executed the modified harness.
