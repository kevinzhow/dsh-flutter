# Toast announcements above clipped owners and modal routes

The canonical `DshToastHost` keeps one root alert per live Toast occurrence.
The painter still belongs to its original `OverlayPortal`, so custom icon
widgets retain arbitrary live owner providers. The host receives only the raw
text, owner text direction and measured transformed card rectangle. It does
not reparent artwork, resolve themes, own timers or choose another layout.

## Why the separate semantics seat is necessary

On Android API36, exact source `88ba0431e0fe5a76c546ae3a6030fcd1a801a96d`
(tree `3170455231c54797de8db492096afc7d5290dca6`) visibly painted the actual
`SettingsUploadNotice` success Toast but omitted it from Android UI automation.
The real offline upload request was accepted. Its first UIA dump ran from
170.7ms to2360.8ms after the tap and contained no `Preference saved` node; a
screenshot at2639.3ms still showed the Toast. Its ordinary4000ms completion
therefore does not explain that missing node.

A widget control of the actual Settings/native fixture, at fake200ms, found
one raw alert node and visible painter, but zero matching nodes in **both**
platform-exported semantic orders. Flutter3.47.6's `OverlayPortal` documentation
(`widgets/overlay.dart`, around1830) explicitly describes this logical-owner
semantics limitation: the overlay may still paint when its semantics anchor
inside a scrolling owner is no longer exposed. A later modal similarly must
not hide an announcement painted above it.

The retained proof folder is
`scratch/whalee-toast-announcement/build/toast-upload-diagnostic` under the
agent workspace. `diagnostic.json`, raw PNG/XML, `widget-observation.json` and
`cleanup.json` retain the exact before-fix runtime and observations. They are
diagnostic evidence, not a successful replay of the repaired binary.

## Actual published accessibility lifetime

The source is DSH `687f282e8625c6b8d11ff58211a90524be2e4317`, actual
ui-primitives0.2.1-rc.2. `Toast.tsx` uses a body portal and role`alert`; the
retained published factory and CSS are unchanged. `source-ax.json` records
Chromium's full AX tree and the alert's partial AX tree from that actual host:

- At animation time0, CSS opacity0 / visibility`visible` still exports the
  alert. The control pauses the real CSS animations and changes their
  `currentTime`; it rewrites no CSS declaration or component body.
- Changing the actual hold prop after the original fade duration produces
  visibility`hidden`. Chromium ignores/removes the alert **before** the later,
  rescheduled completion callback. An opacity-only visibility rule would be
  incorrect.
- Clearing the owner removes the DOM alert and AX alert. The callback uses
  the latest actual callback prop.

The published bundle SHA256 is
`333ea89e7518ec1f1d33111bb9c65d382454bcc3638ebac7116253c92fe5d566`;
archive SHA256 is
`576dc4a46ed55db70ae45b4b956e0d886a5700da32aeaed5bafb478f043f59ff`.
The JSON also binds the producer, complete source provenance and browser
version. The source producer is retained beside the receipt.

This repair retains the existing source-derived paint/hidden boundary and
`alwaysIncludeSemantics` at initial opacity0. Registration exists only while
that actual painter seat is mounted. It adds no timer or inferred pixel rule.

## Ownership, bounds and fallback

The host's announcement layer is logically outside Navigator, after the outer
paint Overlay. Every painter state has its own identity, including occurrences
with equal text. Keyed root nodes keep their semantic identity while raw text,
direction or actual bounds change. Post-frame measurements use the real
render transform to the host, including entry translation; no synthetic1px
rectangle, fitted inset, threshold or alternate style is used.

Once the root accepts an occurrence, the local painter semantics are excluded
to avoid duplicate alerts. Measurement callbacks verify attachment/mounting;
removal queues a null record and fences stale reports. No pointer action or
focus request is introduced. Ordinary replacement, clear, original expiry and
changed-hold completion continue to belong to the existing Toast owner.

Without `DshToastHost`, the original local portal alert/context/lifetime path
is preserved. This fallback does **not** certify platform traversal through
clipped logical anchors or modal routes; consumers requiring root
announcements must mount the canonical host around Navigator. The imperative
adapter remains data-only and does not gain arbitrary initiating context.

## Validation and remaining authority

The new exported-traversal regressions fail on the unmodified27fd parent:
four meaningful assertion failures, four passing boundary controls, no
compilation failure (`.local/toast-announcement-red2.log`). The repaired
candidate's98 focused pinned-font Toast tests pass, covering actual Settings
upload, actual lightbox in both orders, clipped providers, full raw text,
direction updates, stable node identity, equal-text independent owners,
replacement/clear/unmount, initial-opacity0, changed-hold fade-before-callback,
and the existing timer/paint/pointer/context tests. The earlier unpinned run
is retained; Ahem cannot establish the callback digit raster comparisons.

The native diagnostic restored/read back the exact normal88 APK
`faddd2bbc00391b5afff78b0f633f2912c9c71dc6b50685124ca11bb81daef09`,
force-stopped the app and stopped only the owned `whalee-api36` emulator. The
shared ADB process was retained; no root or display override was used.

An exact integrated native replay must still prove actual UIA reachability of
the repaired binary, including the ordinary upload and modal cases. Widget
role/traversal evidence does not certify screen-reader spoken delivery,
announcement urgency or every platform's accessibility behavior. Existing
source-owner/other-family and renderer limits remain unchanged.
