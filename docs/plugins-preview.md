# Plugins and document preview

The Plugins panel manages the connected Host's current profile. Its bundle cards keep official identity, installation, availability, selection, removability and live row state independent. A Host without profile management still provides its read-only Settings inventory. Built-in native configuration pages remain feature-owned `plugins.item` occupants; the Settings shell follows `settings.plugins.tab`.

Installation first inspects the exact package spec. Generic third-party installs remain disabled until explicitly enabled. Official on-demand targets preserve the Host's exact spec, version and requested selection. Registry choices distinguish an omitted option from an explicit pnpm-default null. Discover-provided choices are transient; manual choices are remembered on the device.

A request ID owns progress, output, cancellation and recovery. Lost responses do not establish success or cancellation. An absent `waitForInstall` result becomes unknown. Applying cannot reopen a cancellation window. Pending script names require an explicit confirmation, and a stale confirmation cannot approve a later installation. Uninstall also requires confirmation. Restart-required, overridden and failed outcomes remain distinct.

Discover retains prior results during failed reads. Later pages pin the first page's `fetchedAt`; a changed index restarts from the first page once and fails if replaced again. Source edits await the Host and preserve its confirmed list on refusal. Installation uses the exact Host-provided version target after displaying its origin.

PDFium receives complete authorized bytes, with zoom controls and no Host URL or cookie. Office conversion checks the original Session's read permission, source metadata and renderer generation before reusing a bounded cache. Concurrent readers share conversions; retiring the last reader aborts its HTTP request. Missing-font notices retain the converter's reported families.

HTML is static by default. Developer tools enable an interactive opaque iframe, without `allow-same-origin` or application callbacks. Static previews remove active tags and event attributes and install a restrictive CSP. Interactive previews pack at most 64 declared classic `.js` and `.css` files, limited to 4 MiB per asset and 32 MiB total, through the original Session and base-file authorization. Modules, dynamic requests and CSS dependency traversal do not gain a Host file bridge. File/mode changes retire the browsing context.

Linux embeds WebKitGTK 4.1 in the native Wayland window. Its context is ephemeral; file access, permissions, downloads and new windows are refused. Individual child bounds preserve Flutter input elsewhere. An active Flutter modal hides the native child and closing it restores the same browsing context. The background currently loses its HTML content while that modal is visible, so this is not full visual parity. Other native platforms use InAppWebView without registered application JavaScript handlers. The Android implementation is pinned with the licensed Gradle compatibility patch documented under `third_party/flutter_inappwebview_android`.

Linux builders need `libwebkit2gtk-4.1-dev`; deployed Linux installations need the matching WebKitGTK runtime. CI installs the development package. PDFium is bundled through Dart native assets. No DSH service deployment or application release is performed by this feature.

Dedicated spreadsheet rendering, arbitrary browser-plugin UI modules, exact manager/Discover detail artwork and strict pixel alignment remain incomplete. Behavioral tests and native interaction evidence must be assessed independently of the visual-parity task.

Reproduce the real Office conversion without calling a model, with `dsh` on PATH and an isolated writable `DSH_HOME`:

```sh
python3 tool/live_spike/make_office_fixture.py .local/office-live/workspace
# Run from tool/live_spike with an absolute DSH_HOME, workspace and output directory.
DSH_HOME=/absolute/isolated/dsh-home dart run bin/plugins_preview.dart /absolute/office-live/workspace /absolute/office-live/results
```

The check owns and stops its child Host, pairs in memory, creates a synthetic Session and verifies PDF conversion plus authorization before cache reuse. Its portable receipt excludes launch credentials and runtime logs. Native fixture `test/parity/plugins_preview_main.dart` separately covers production plugin controls, PDFium and opaque HTML interaction. The component comparison uses pinned upstream `PluginManagerPage`, `DiscoverSection` and `PluginInventorySettingsTab` directly, without substituting their primitives or artwork.
