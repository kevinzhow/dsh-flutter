# Tooltip family: reference and native evidence

The shared tooltip and its keycaps use generated geometry, colours and placement from the published DSH primitives. It handles viewport fitting, anchor movement, delayed hover and keyboard focus, nested suppression, click pinning and dismissal, and exposes shortcut labels to accessibility. Message copy and branch actions use the shared component.

Sixteen comparisons use the real DSH message-action components and their Flutter counterparts at desktop and phone densities, English and Chinese, and both themes. All dimensions match; none meets the unchanged 99.5% non-text threshold, with mean 94.38%. The browser and Flutter images for all 24 prior command-menu cases remain pixel-identical to the preceding validated change. Fonts, classifier and threshold were not changed.

Full local preflight, four builds, two hardware-accelerated desktop replays and 13 Android touch/keyboard scenes passed. The final head changes only the desktop replay's initial pointer position after the build head. The first replay began with the cursor over a button, so its baseline was corrected before the successful run. `receipt.json` records provenance, build hashes, checks and limitations. Dynamic label resolvers and document-body portal behavior remain to be audited; overall visual parity is not claimed.
