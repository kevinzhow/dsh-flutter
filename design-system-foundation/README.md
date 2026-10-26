# Published design recipes: first family migration

Implementation `1180151ae3878405cdee48f1bd0e9f4db865b8e1`, tree `1ea3e217dd134c95519c168dc8236687d694c7b9`.

The pinned DSH plugin manager references ui-primitives via workspace:*, resolving package version 0.2.1-rc.2. Exact consumed CSS and its package manifest were obtained from that published npm archive; archive integrity, file hashes and the actual consumer declaration are recorded. Published Button and SegmentedTabs CSS match the pinned reference source bytes. Recipes are generated from those inputs. Unknown states/properties and untranslated conditional rules fail; the complete CSS rule audit is retained.

DshButton and DshSegmentedTabs use the generated base recipes. Existing user typography ladder overrides remain effective (including a 19px / 27px custom-pack regression). The family inventory explicitly marks the other family migrations pending. The new independent preflight check verifies published snapshots, live reference dependency/version/CSS where available, and per-file bypass/duplicate/manual-metric ratchets. CI checks its available snapshot without pretending to have a reference checkout. Baselines are compared with the PR base so they cannot be raised to hide a new violation. Five guard regressions cover future syntax/drift and bypass scenarios.

All 13 exact-tree local preflight checks passed, without skipped checks. Normal/fixture Linux release and Android debug builds passed. Weston14 / Intel LNL native GPU replay passed four real-input assertions per desktop and phone, including pointer-opened menu Escape dismissal, info and package details. AndroidAPI36 emulator passed18 actual interaction scenes; its renderer is SwiftShader, not physical Android GPU.

All56 production component-page captures and all10 native GPU scene captures are RGBA-identical to the preceding accepted implementation. This is preservation evidence only. Desired design is judged against the original DSH production components: those56 reference pairs still average97.248%, with10/56 meeting99.5% and all dimensions agreeing. Fonts, thresholds and pixel classifier are unchanged. The overall visual target is not complete.

Remaining: generated page-specific button variants, other component-family recipes and duplicate consolidation, existing bypasses, full semantic duplicate detection, additional conditional/animated recipes, and previously recorded inventory/marketplace/detail/phone text differences. The scanner covers named constructors and metric patterns, not arbitrary Dart expressions. Existing theme token generation still uses pinned source styles; expanding published-package provenance to every token/family is subsequent migration work. No automatic upstream polling schedule was created.

Normal Android APK restored/stopped, owned emulator/app/Weston processes stopped; shared ADB retained. No deployment or release.

[Original / implementation comparisons](components/README.md) · [Before/after regression](regression.json) · [Published source lock](published-source-lock.json) · [Family inventory](family-inventory.json) · [Guard regressions](guard-regressions.json) · [Device/build receipt](receipt.json)
