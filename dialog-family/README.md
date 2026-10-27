# Shared modal and retained guide reader evidence

This tranche sources the canonical Modal shell and agent-guide reader profile from the published DSH packages. The reader includes its source-specific prose, usage example headers/tags and quote styling. The reader is opened through its actual preset-row entry point. Source and application captures use the same synthetic content, two densities, two languages and both themes.

All 64 comparison captures are present: 64 have matching dimensions, 0 meet the fixed 99.5% non-text threshold, and mean non-text agreement is 97.103%. The whole reader, tab row, directly scrolled panel and retained panel groups are recorded separately in components/summary.json. Fonts and the classifier are unchanged.

The unchanged Playwright reference launch implicitly adds `--hide-scrollbars`. A separate source diagnostic with only that default argument omitted confirms a persistent thumb, five device pixels at DPR 1 and thirteen at DPR 2.625. The application keeps that source behavior. Diagnostic screenshots also expose outer-document scrollbars and shift layout, so they are evidence of paint behavior only and do not replace acceptance captures.

For each provider, all 16 direct-scroll panels are RGBA-identical to the corresponding panel after switching away and back. Separate browser DOM measurements verify positive independent offsets and preservation of the same source panel node across that switch; requested offsets can clamp to the actual scroll extent.

The 24-case legacy cohort contains eight unchanged risk dialogs and sixteen directory/workspace dialogs whose canonical frames intentionally changed. All eight risk captures in each provider are RGBA-identical to their preceding captures. The sixteen updated frames report paired image differences and measured before/after reference agreement without requiring RGBA equality. Across the entire cohort, 24 React and 8 Flutter images are RGBA-identical. Detailed group metrics are in regression/summary.json. These preservation checks cover the declared cohort and do not establish every caller’s route or focus behavior.

Four English browser cases in both themes and native densities record pointer-close/reopen, Escape-close/reopen and Control-only focus history. The source proofs and reproduction scripts are included. Those JSON proofs do not record a browser version; the renderer pin remains in the source lock. Reader, Markdown, focus-history and dialog-lifecycle test sources are included alongside the successful final-tree preflight.

Two native hardware GPU replays passed all recorded assertions and 22 Android scenes passed. The full 13-check preflight passed on the final tree. Runtime-source equivalence and all four build hashes are recorded explicitly; no raw process logs or credentials are copied.

Other modal and Markdown profiles remain pending in the family inventory. Remaining visual gaps are recorded in the receipt. No overall visual completion, deployment or release is claimed.
