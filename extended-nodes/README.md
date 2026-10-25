# Remaining chat node verification

Source: `9389dedba57d1a0404d59aa8a707c2f8caa0f05d`. Upstream DSH: `687f282e8625c6b8d11ff58211a90524be2e4317`.
All content is synthetic. This folder contains only screenshots and portable JSON, with no app/host logs, credentials or local workspace paths.

All 12 complete local checks passed on k172 with no skips at code commit `6d69f83bd1242949d1582f44395199b0ede1f02f`, tree `a0f87c63f5e331c3f6992d92e0bbef8ffef81b88`. The final follow-up changes only the replay's pointer/focus steps and pixel regions; product Dart code and build inputs are identical. Normal Linux and Android release builds passed. The real upstream replay covers 30 snapshots of goal commands, exclusive late replies, context forms and workflow lifecycle; all earlier vectors also pass.

216 component pairs compared:

| Component | Pairs | Mean non-text | At least 99.5% | Size mismatches |
| --- | ---: | ---: | ---: | ---: |
| Goal command input | 24 | 98.492% | 0 | 0 |
| Question reply | 32 | 98.708% | 0 | 6 |
| Context injection | 104 | 98.351% | 17 | 0 |
| Workflow run | 56 | 97.537% | 0 | 0 |

Strict total: 17/216. Broader geometryPass counts are not this strict count. The visual goal remains open; fonts, thresholds and classification are unchanged. The six expanded question-reply captures differ by 1 physical pixel on desktop ZH and phone ZH, and 3 pixels on phone EN. Shared typography/baseline fidelity remains partial.

Native Weston/Intel LNL GL: desktop 1280×720 light EN and phone-size 390×844 dark ZH each passed 10 pixel assertions through actual clicks and wheel input. They cover late-reply expansion/collapse, bounded context scrolling, member activation, clean completion/restart and abnormal disclosure. Reply/context crops restore pixel exactly. Workflow failed content restores pixel exactly after focus returns to the status control; restart verifies that the member content reappears rather than requiring the initial focus decoration. Polling establishes scene changes, not animation latency. All recorded app/compositor PIDs are gone.

Android API36 dark ZH: 15 real tap/swipe scenes passed. Testing discovered a member button's accessible bounds merging its following settled row; isolated semantic containers and a regression test fix that issue. The normal APK was restored, the app stopped and the owned emulator shut down; shared ADB was retained.

The native workflow member action is a standalone fixture caption. Actual direct-child navigation is separately verified in `apps/dsh_flutter/test/extended_nodes_flow_test.dart`, through the real composition root, Session model and keyed slots: exact parent/child/mode follow address, normal-context hiding and disabled navigation after the child stops. No live model or real workflow service is involved in these component fixtures.

All 19 Chat node kinds now have keyed renderers. Overall feature parity remains partial, including shared typography/Markdown, turn navigation, feedback, secret masking and other items recorded in the capability inventory. System prompts and ordinary context remain hidden in normal Chat modes under upstream visibility rules; tool changes retain their visible rows.
