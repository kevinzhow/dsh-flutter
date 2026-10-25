# System prompt validation on k172

Source b29cf2a, based on main7fd655d. Pinned DSH687f282e8, Flutter3.47.6.

The implementation materializes historical system prompts and request-series cards and registers their disclosure renderer. Upstream normal-chat visibility is preserved: these cards are not ordinary transcript rows; the work-details view mode remains a separate A1 item.

## Component comparison

All40 cases compare the real upstream SystemPromptRow against Flutter: English/Chinese, light/dark,480logical pixels at1x and240at2.625x, closed/open/update/long/empty states. Open cases explicitly hover then click in both providers. Mean non-text agreement is **98.724%**, **4/40 reach99.5%**. The report's broader geometryPass counter also accepts official CLI statuses; it must not be read as the strict99.5% count. No visual-pass claim or scoring/threshold change.

Four long phone captures have matching173px logical height but browser454 versus Flutter455 device rows, due to the existing capture rounding difference. Captures and metadata are retained, with no exclusion.

## Native validation

The standalone test entry uses the real widget and synthetic-only text, without a host/model connection. Weston14/Intel LNL hardware rendering was checked at1280x720light and390x844Chinese dark. Both cards expand, and the long body scrolls fromline0 to92–99. Saved app/Weston processes were verified gone. Pixel checks confirm the native frame background matches the React theme. This is native Linux at a phone-sized window, not Android.

API36 Android emulator: installed the standalone test APK, tapped both headers and swiped inside the second body. Before/after screenshot checks show the first card remains fixed while the long body changes. Images were visually inspected. This checks the actual Android widget, not pairing or a DSH session. Normal Linux release/Android debug product builds were also restored and passed.

## Shared tracking correction

Theme styles previously inherited ambient Material letter/word spacing. A regression test now covers every font role with explicit ambient tracking, and defaults are reset to CSS normal spacing. The same native single-card sample improves from94.167 to95.606% exact agreement, and99.138 to99.281% non-text agreement. It still falls short of99.5%; this one sample does not replace the40-case matrix. Both native crops and the browser reference are included.

## Checks

Full12-check preflight passed with no skipped checks; receipt matches finaltreed9230fabceaca6f332ffd2806d60bdd353fd12ae. Nine prompt-state tests and20 upstream TypeScript snapshots cover replacements, historical updates, initial duplication, series starts and tools-only changes. Widget/integration tests cover literal text, truncation, selection, keyboard, localization and scrolling.

All content is synthetic. Native validation uses the dedicated test entry, not a new product screen.
