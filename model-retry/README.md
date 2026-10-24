# Model retry on k172

Implementation: 3338ba4, based on PR16 e0bc26e. Pinned DSH: 687f282e8; Flutter 3.47.6.

32 component comparisons cover English/Chinese, light/dark, 480 logical pixels at 1x and 240 at 2.625x; real upstream RetryNodeView versus Flutter. Each covers scheduled, started, expanded started, or expanded cancelled. Mean non-text agreement 97.517%; **0/32 reach the 99.5% acceptance threshold**. No visual-pass claim. Font and style probes accompany every image. The narrow English cancelled case has matching logical element height 85px but browser capture is 223px versus Flutter 224px at 2.625x. The capture tool and thresholds are unchanged.

Native screenshot: real isolated DSH JSONL events for started/cancelled chains, opened by pointer replay under Weston 14 / Intel LNL GPU, with both disclosures expanded. Environment proof is included.

Android screenshot: API36 emulator, installed debug APK, paired to the same synthetic-only host. UI hierarchy verified both states and two delay/failure disclosures after taps. This checks actual Android behavior; component comparisons are Flutter widget captures, not Android screenshots.

All data is synthetic. Active countdown is tested with a controlled client clock; the persisted native fixture uses completed turns, not a real transient provider failure.

## Follow-up spacing correction

3338ba4 reproduces the automatic numeric/ideographic gap in the Chinese duration while preserving spoken and selected text. In the pinned native-density browser, changing only `text-autospace` from normal to no-autospace moves the Chinese unit by exactly 1.625 logical pixels; see autospace-browser-proof.json. This corresponds to [CSS Text Level 4 inter-script spacing](https://www.w3.org/TR/css-text-4/#text-autospace-property). The expanded Chinese phone delay ink now spans x38..356 in both images (previously Flutter ended at351).

The new Chinese native GPU screenshot and final12check receipt cover3338ba4. The English native screenshot and Android screenshot retain the earlier19ebf9f run; Linux and Android builds were repeated successfully after the spacing change, and selection/semantics regression coverage passed.

Remaining visual investigation: in the English started/closed desktop sample, all107 pixels classified as non-text mismatches lie in text columns; none lie in the chevron or remaining background. On the phone,1466/1473 lie in text columns and7 in the chevron area. The classifier assigns straight glyph edges to its hairline bucket; bounding/outline differences still need investigation. This is a localization of the remaining difference, **not proof of acceptance**. No scoring rule or threshold was changed;0/32 still reach99.5%.
