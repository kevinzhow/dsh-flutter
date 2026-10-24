# Model retry on k172

Implementation: 19ebf9f, based on PR16 e0bc26e. Pinned DSH: 687f282e8; Flutter 3.47.6.

32 component comparisons cover English/Chinese, light/dark, 480 logical pixels at 1x and 240 at 2.625x; real upstream RetryNodeView versus Flutter. Each covers scheduled, started, expanded started, or expanded cancelled. Mean non-text agreement 97.508%; **0/32 reach the 99.5% acceptance threshold**. No visual-pass claim. Font and style probes accompany every image. The narrow English cancelled case has matching logical element height 85px but browser capture is 223px versus Flutter 224px at 2.625x. The capture tool and thresholds are unchanged.

Native screenshot: real isolated DSH JSONL events for started/cancelled chains, opened by pointer replay under Weston 14 / Intel LNL GPU, with both disclosures expanded. Environment proof is included.

Android screenshot: API36 emulator, installed debug APK, paired to the same synthetic-only host. UI hierarchy verified both states and two delay/failure disclosures after taps. This checks actual Android behavior; component comparisons are Flutter widget captures, not Android screenshots.

All data is synthetic. Active countdown is tested with a controlled client clock; the persisted native fixture uses completed turns, not a real transient provider failure.
