# Integrated chat validation

PR25 merged as e0d60bb; PR24 rebased as eda1676. Both node registries, both upstream behavior fixtures, and the11/19 capability inventory are preserved. Complete12-check preflight passes on treea88f3108265997bb53ee9bb44093ebfa54412c03. Linux release and Android debug builds pass.

All72 component comparisons are recaptured from the integrated source:32 model-retry plus40 system-prompt cases, both locales/themes and desktop/phone density. Mean non-text agreement98.188%; strict4/72 reach99.5%. No capture exclusions or scoring changes; visual work continues separately.

The normal Linux app was rebuilt at this source and paired to the isolated synthetic retry fixture under Weston/Intel LNL GPU. Both started/cancelled disclosures opened with the correct delay/failure details. Screenshot was inspected; no real conversation or provider call was used. Android was rebuilt at the integrated head; actual Android fixture interaction provenance remains in model-retry/ and system-prompt/.

All owned capture app/compositor processes and the fixture host were stopped after validation.

The functional scope is now merged: PR25 as e0d60bb, PR24 as 9920f7a. Final main tree is identical to the locally validated integrated tree recorded in preflight.json. Visual discrepancies continue as follow-up work; no visual acceptance is claimed.
