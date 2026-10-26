# Single-line input family: reference and native evidence

The font-settings input uses a shared component and recipe generated from the published DSH primitive. It supports focus styling, controlled and committed values, an optional icon, disabled input and browser-style length limits. A real Chromium probe checks partial insertion and whole emoji at the length boundary.

Twenty-four comparisons crop the real DSH font-settings input and the Flutter counterpart at desktop and phone sizes, English and Chinese, both themes, and placeholder, value and focused states. Desktop dimensions match in all 12 cases; the phone field remains wider because the existing settings row stacks it below the label. None reaches the unchanged 99.5% non-text threshold. The ten previous expanded font-settings comparisons are pixel-identical for both providers. Fonts, classifier and threshold were not changed.

Full local preflight, four builds, two hardware-accelerated desktop input replays, and eight Android touch, typing and commit scenes passed. The final head adds only the desktop replay manifest after the build head. `receipt.json` records provenance, build hashes, checks and limitations. Feature-specific input overrides and overall visual parity remain open.
