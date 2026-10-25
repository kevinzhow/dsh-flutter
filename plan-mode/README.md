# Interactive plan mode validation

Source head: c578208d8bb7d321f3b47f7c4c0b7a5be24bdd40, based on main 35851c8.
Pinned upstream: 687f282e8625c6b8d11ff58211a90524be2e4317.
All data is synthetic; no pairing links, app logs, credentials or user history are included.

- Actual upstream PlanChip, PlanReviewPanel, PlanReviewOpen and PlanPreview versus Flutter: 104 comparisons across desktop/phone, English/Chinese, light/dark. No missing comparisons. Mean non-text 93.772%; strict 99.5% goal **0/104**. Ten chip crops differ in dimensions; hover tooltips and font/paint differences remain tracked separately. The pipeline's `geometryPass` includes basic visual passes and is not a strict target count.
- Whole-app integration verifies generated /plan off routing, Host-projected state, logged exact-call sidebar resources, one shared title/body read, manual closure/reopen, temporary params-only review, original approval labels and cancellation by another client.
- Upstream behavior oracle covers ten address, eight review-narrowing and twelve Markdown-summary cases. Targeted tests cover pending cancellation, shared resource lifetime/cache reset and retry after refusal.
- Native Weston 14, Intel LNL GL: six actual click/scroll pixel assertions pass at each of desktop light and phone dark Chinese. Approval preserves Start building; refusal retries, Request changes returns to composer, and the document scrolls.
- Android API36 dark Chinese: eleven actual UI scenes pass, covering exit refusal/retry, manual opener, approval refusal/retry, original label, Request changes and document scrolling.
- Native callbacks use synthetic in-memory decisions. Real application service/sidebar routing is verified by plan_flow_test.dart, not claimed as a real model turn.
- Linux and Android release builds pass for both normal app and native fixture. Full local twelve-check preflight passes without skipped checks; final exact-head receipt is added after completion.
- Error feedback is capped at two lines with full-detail tooltip so narrow screens retain their controls. Overall visual parity remains incomplete.
- Normal APK restored/stopped; owned emulator/compositors/apps stopped, shared ADB retained. No release/deployment.
