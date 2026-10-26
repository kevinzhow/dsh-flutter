# Plugin manager layout and keyboard popovers

Implementation: ae29c2341c451b419d83fd2996d1a83a766fbb63. Reference: DSH 687f282e8625c6b8d11ff58211a90524be2e4317; ui-primitives and ui-plugin-manager package version 0.2.1-rc.2. Synthetic content only.

The manager uses the original single-column rows, Default SVG artwork, viewport page spacing, source heading metrics, equal-width segmented tabs and compound Add menu. Description line-clamping preserves word boundaries and full accessibility text. Anchored panels close on Escape for both pointer and keyboard opening and restore prior keyboard focus.

All 12 local preflight checks passed without skipped checks on the final implementation tree. Normal and synthetic-fixture Linux release and Android debug builds passed on the same implementation. Native Weston 14 / Intel LNL GPU replay passed four real-input assertions per desktop and phone: Add menu opens, Escape removes it, info popup opens and package details open. Corresponding images were manually inspected. Android API36 emulator replay passed 18 actual operation scenes; emulator rendering is SwiftShader, not a physical Android GPU.

The same 56 actual-source page comparisons average 97.248% non-text agreement, up from 95.529%; 10/56 meet 99.5%, up from 0/56. All dimensions agree. These static captures were made on 94a276e; the final commit only fixes pointer-opened panel focus and adds that regression test. No at-rest style changed. Overall visual acceptance remains incomplete.

Remaining families: plugin inventory and marketplace rows/empty states, phone text rendering, package-row hover extension, contributed actions, exact detail surfaces and segmented-tab transitions/focus appearance. The design-system-replication workflow is now installed; the next batch establishes generated recipes, dependency drift checks and a canonical component-family inventory before further migrations. Existing manual metrics are migration work, not a claim that recipe generation is finished.

Normal Android APK restored and stopped; owned emulator, app and Weston processes stopped. Shared ADB retained. No deployment, release or formal signing claim.

[Original / Whalee comparisons](components/README.md) · [Desktop Escape result](gpu/plugin-layout.desktop/menu-closed.png) · [Phone information popup](gpu/plugin-layout.phone/plugin-info.png) · [Android results](android/receipt.json) · [Exact provenance and build hashes](receipt.json)
