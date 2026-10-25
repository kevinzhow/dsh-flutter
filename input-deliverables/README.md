# Input and delivered-file validation

Implementation: `30c64cff8a25e5f9f6f394095ba74b7d534377da`. All content is synthetic.

- Original-text evaluation and credential/reference rules: 255 actual upstream behavior checks.
- Deliverables, known-file resolution and Host DTO validation: 116 actual upstream checks.
- Local full preflight: all 12 checks passed. The final small accessibility change also passed focused regression tests and whole-workspace analysis; exact final-head CI is recorded in PR #33.
- Linux and Android normal/fixture release builds passed.
- Native Wayland on Weston 14 with Mesa Intel graphics: desktop and phone sizes, 9 actual interaction assertions each, all passed.
- Android API 36: 22 actual scenes passed, including independent reveal accessibility, raw-value exclusion while hidden, command launcher/pick, file association failure/retry, original file coordinates and Review navigation/layout controls.
- Visual matrix: 168 comparisons; **0 strict pixel matches**, mean non-text similarity 85.542%, 104/168 matching dimensions. Visual alignment remains open; long sent references still wrap as atomic WidgetSpans.

[Component comparison index](components/README.md) · [Native desktop](gpu/input.desktop/text.png) · [Native phone](gpu/input.phone/files.png) · [Android review](android/android-review-wrap.png) · [Validation receipt](receipt.json)

Owned native runtimes were stopped, the normal Android app restored and stopped, and shared ADB retained. Native fixture file actions are in memory; the production routing is tested by `apps/dsh_flutter/test/deliverables_flow_test.dart`.
