# Shared menu viewport, safe bounds, and focus evidence

The shared menu family now owns scrolling rows and a pinned footer. Linked menus follow their actual anchor and remain within native safe insets. The workspace picker uses the shared implementation. Menu rows expose their actual input focus to accessibility, and Android requests native view focus at startup so its first hardware key reaches Flutter.

The 180 real DSH reference comparisons include the workspace picker long-list screens in both themes, languages, and viewport sizes. 172 pairs have equal dimensions and 18 meet the unchanged 99.5% non-text target; the wider visual goal is unfinished. All 180 prior React and Flutter captures are pixel-identical after the focus work. The reference is DSH; old Whalee images are used only to establish regression stability.

All 13 local checks passed on the final tree. Linux desktop and phone GPU replays passed 11 assertions each, and the final Android fixture passed 41 interaction scenes. Three independent cold starts verified native focus and the first End/Up/Enter sequence; a separate actual text-entry check passed. Receipt.json records exact source, build, and capture provenance, artifact hashes, diagnosis and remaining gaps. No deployment or release.
