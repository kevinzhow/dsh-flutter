# Work-details verification

Validated source: `4e6d0cb1fd676b2060c64ac466dfa33d1fc42673` (tree `a6a799d234a67af57ffb5b1d5079ecf9191e4dbc`). Upstream DSH: `687f282e8625c6b8d11ff58211a90524be2e4317`.
All chat content is synthetic. This folder contains only screenshots and portable JSON, without app/host logs, credentials or local workspace paths.

All 12 complete local preflight checks passed on k172 with no skips, including all Dart/Flutter suites and upstream replay (17 snapshots in the new turn-process fixture). Normal Linux and Android release builds passed. Component/native builds used `eec1182a6abd598fed3b305560a42d8a9e3f6793`; the only subsequent product edit simplifies repeated theme-style reads to the same resolved baseStyle properties. The other edit fixes a source-guard false positive for copying style properties. Neither changes font values or rendering. Full preflight ran after this final commit and records its exact tree.

136 component pairs were captured and compared:

| Component | Pairs | Mean non-text | At least 99.5% | Size mismatches |
| --- | ---: | ---: | ---: | ---: |
| Turn process | 64 | 97.361% | 2 | 0 |
| Display settings | 32 | 98.116% | 0 | 0 |
| Process group | 40 | 92.595% | 0 | 10 |

Strict total: 2/136. Broader geometryPass counts are not this strict count. The visual goal remains open. Ten Chinese phone group captures are one physical pixel shorter in Flutter; typography and Markdown also remain imperfect. Fonts, classification and thresholds are unchanged.

Native Weston/Intel LNL GL: desktop 1280×720 light EN and phone-size 390×844 dark ZH each passed 7 scene assertions. All assertions succeeded on the first capture attempt. Actual clicks cover process/group/reasoning disclosures and all four modes. After collapsing, the entire chat region below y=210 restores pixel exactly; settings above that crop intentionally change. Recorded app/compositor processes are gone. These assertions establish scene changes, not animation latency.

Android API36 dark ZH: 15 real tap/swipe scenes passed, including nested reasoning, a long process, return/collapse, all four modes and independent next-input timing. Normal product APK was restored, the app stopped and the owned emulator shut down; shared ADB was retained.

Limits: coordinated whole-turn fold animation and compensation across complex uncapped nested pagination remain partial, alongside shared typography/Markdown fidelity. All Chat modes continue hiding system prompts and ordinary context per upstream; raw request inspection belongs to later Trajectory work. Chat renderers now cover 15/19 kinds; ui-chat settings are still partial.
