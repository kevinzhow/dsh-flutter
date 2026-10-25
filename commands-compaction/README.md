# Commands and compaction verification

Source: `8934cc8e32621cbcc2a4de85c546b87ab2cf6a6b`, upstream DSH `687f282e8625c6b8d11ff58211a90524be2e4317`.
All conversation content is synthetic. Screenshots and portable JSON only; no app/host logs or credentials. Local paths are replaced with portable placeholders.

Local k172: all 12 full preflight checks passed (87 tool tests and all Dart/Flutter packages), 23 upstream replay snapshots, normal Linux and Android release builds passed. Preflight ran before committing: its headTree is the base tree, not the tested uncommitted worktree; source was committed unchanged after verification.

104 component pairs: commands 56 mean non-text 98.222%, 6 at least 99.5%; compaction 48 mean 97.430%, none at least 99.5%. All dimensions match. Strict total 6/104; broader geometryPass is not this strict count. Visual goal remains open.

Native Weston/Intel GL: desktop light EN and phone dark ZH, 7 scene assertions each. Initial/restored collapsed images are pixel identical. Phone manual expansion needed 9 capture attempts; this is functional evidence, not latency measurement. Android API36 dark ZH: actual taps, output expansion, manual summary, long-summary swipe, pinned-header collapse passed.

Regression: 72 prior React screenshots have identical dimensions and RGBA pixels after crop epsilon/font readiness changes. Browser-only regression, not a new joint 176-case matrix.

Limits: shared Markdown typography, tables and inner code-banner pinning remain incomplete. Compaction title pinning is implemented and verified. Chat renderers cover 14/19 kinds; ui-chat remains partial.
