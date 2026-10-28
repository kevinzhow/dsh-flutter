# Published Toast and three existing owners

This bounded UI change consumes `DshToastRecipe` from the companion published
source contract, reference DSH `687f282e8625c6b8d11ff58211a90524be2e4317` and
ui-primitives0.2.1-rc.2. It migrates the canonical Toast and exactly three existing
Flutter owners: open-in-app launch failure, file open/reveal failure and Settings
upload notice. Fourteen other source owners remain pending; this is not a
whole-family or overall visual-completion claim.

The owner-mounted API is resolved text, optional icon widget, optional `DshToastTone.success`,
optional hold duration and completion callback. No icon is the default. Success
overrides a supplied icon with the actual generated
`IconCheckCircleOutlineRegular`, whose two filled paths are read by the existing
icon generator. Caller-provided glyphs keep their own artwork size. Failure
owners explicitly supply the existing real warning icon; upload saved uses
success and upload failed supplies no icon. Actions and anchor inputs are not
implemented and remain frozen/pending in the companion source contract.

`DshToast` is the owner-mounted API for arbitrary custom icon widgets. Its real
`OverlayPortal` retains the owner's live inherited providers, including values
other than themes. The imperative `DshToasts.show` / `showOn` adapter accepts only
resolved `DshIconData`, optional tone, hold and text: the entry it inserts has no
relationship to the initiating widget's provider subtree. It deliberately does
not accept a generic Widget or claim to capture that context. The existing two
warning callers pass `DshIcons.warning`; Settings mounts `DshToast` itself.

The imperative `show(context)` inserts its occurrence in the nearest logical
Overlay, normally Navigator's, while that occurrence's own portal paints in
the outer Toast host. This keeps launch/file notices and direct Settings
notices on the same outer entry, so their show order matches the source's
equal-z body portals. Inserting an imperative occurrence directly into the
outer host would otherwise keep it above a later direct notice. The explicit
`showOn(navigator.overlay)` fallback already has the required logical placement.
The actual workspace/file failure followed by accepted upload is covered by a
painted-icon comparison to the upload notice alone; counting both widgets is
not proof of their visible order.

## Source layout and placement

The max-width constraint applies to content before adding horizontal padding:
the long source content cap is640 plus32 outer padding on desktop, and viewport
minus48 content plus32 padding on phone. The reference's800px viewport therefore
allows672px outside, and390 allows374px. Text has no artificial line-count cap
or fixed banner height. Canonical theme contour and `DshShadowBox` paint the
surface using the generated radius/material/shadow slots. There is no local
alpha, blur, font or threshold fitting.

`DshToastHost` mounts a real outer `Overlay.wrap` around the Navigator in
`MaterialApp.builder`. Each occurrence remains logically in its owner subtree
and targets that outer Overlay using `OverlayPortal`; the host does not reparent
widget specs into a root map. Navigator/lightbox entries stay inside the ordinary
entry below those portal children, preserving the source Toast1100/lightbox1000
relation in either show order. This also escapes transformed feature ancestors,
keeps coordinates relative to the window and lets pointer input reach the
Navigator underneath. No focus is requested. Independent owners remain
independent; this is not a global queue.

An isolated consumer without the app host uses the framework's root-overlay
portal so it still escapes feature transforms. Plain Overlay paint order cannot
promise priority over a subsequently inserted route; production's host is the
mount that supplies that ordering. Broader priorities involving menus, tooltips,
other overlays or nested app roots remain outside this batch.

The banner sets the actual source `SemanticsRole.alert`, with icon semantics
excluded and the text retained through entry opacity. The pinned Flutter API
forbids combining that role with its polite live-region flag, so the old
`liveRegion:true` flag is deliberately removed. Widget role evidence does not
certify actual native announcement timing or delivery.

## Lifetime and motion

Entry and delayed fade use the generated CSS curve keywords, durations and
offset. The mapping uses Flutter's corresponding standard CSS cubic curves;
unsupported generated keywords throw. Reduced motion removes entry movement and
entry opacity while preserving the delayed fade. Fractional milliseconds are
converted through microseconds, and zero hold/entry/fade values are handled
without division by zero.

The completion Timer is independent of animation ticks. Same-hold text/callback,
theme and overlay rebuilds retain the deadline and call the latest completion
once. A changed hold synchronously cancels/reschedules that Timer, even before
the portal child rebuilds. The CSS paint timeline stays anchored to the
original mount; changing a delay can therefore hide paint earlier than the
newly restarted completion Timer. Unmount cancels the Timer. The fully faded
surface has no visible/semantic content if an owner delays removal.

Each imperative show allocates its display identity outside the overlay builder.
A rebuild cannot accidentally manufacture a new occurrence. Re-showing identical
copy still creates a new identity, and old completion cannot remove its
replacement. Settings upload also fences completion by the actual notice
sequence. The portal keeps these occurrence identities stable. The painter owns
and disposes a scheduler `Ticker` directly, so a route's `TickerMode` does not
pause source portal animations when a later route covers its logical owner.
Completion still uses the independent Timer; removing the owner tears down the
portal, timer and ticker together.

## Verification and explicit limits

Four source regressions were run against the unchanged base and failed for the
existing icon, desktop/phone content-box and timer/frame defects. Additional RED
evidence reproduces a deadline cancelled one frame late during a hold update.
The independent review reproduced a further RED failure: the original host map
made an arbitrary inherited-context icon see the root instead of its owner.
The repair tests require the live owner provider and preserve the original
deadline through provider changes, cancellation on owner removal and source
entry/fade timing while a later opaque route disables the owner's TickerMode.
Both actual lightbox show orders compare real painted Toast-core RGBA to the
same Toast alone, rather than assuming logical element order equals paint order.

Focused tests cover source sizing, real artwork override, custom icon size,
CSS curves, reduced entry, zero-hold composition, latest callback, hold changes,
unmount, root placement, pointer pass-through, existing focus, alert role,
replacement identity, independent owners and both actual lightbox show orders.
Real feature tests invoke failed open/file actions and accepted/refused setting
writes, checking warning/success/absent-icon mapping and stale-notice fencing.

The zero-hold overlap was also checked with the retained unchanged source build
and actual Chromium animations paused at0/80/160/500/1000ms. It confirms combined
entry/fade opacity, rather than replacing entry opacity when fade starts. This
small source-only probe is retained in `.local/toast-zero-source-proof.json`;
it is not a new native/paired acceptance capture or an upstream source mutation.

The family scanner reports877 manual-metric matches, down from880 by removing
the three existing Toast matches; duplicate-button0 and platform-control11 are
unchanged. These counts do not prove component coverage.

The integrated text correction implements source-proven CSS ASCII whitespace
collapse, preserves raw semantics/NBSP, removes empty collapsed line boxes and
keeps a sole unbreakable run on one overflowing line. See `toast-text.md` for
the actual-source controls and the pending mixed-paragraph/Unicode boundary.
The shared shadow now takes an explicit authored-owner opacity flag. Only the
direct Toast background token enables its one-internal-paint-pixel exclusion inset (1/native DPR in logical units);
computed opaque menu materials keep their prior source-owner classification.
No global post-transform snapping is added: actual browser controls preserve
fractional translations, and Chromium's pre-transform coordinates and
retained-origin inner superellipse contour remain separate pending work.
Still unproven: general mixed oversized-word paragraph breaking, complex
Unicode/bidi, source animation and shadow raster equivalence, native
announcement/contour delivery, the fourteen other owners and actions/anchor.
The native launch warning remains registration-owned rather than keyed to each
source OpenTargetButton/path. Control unmount/path changes, independent source
controls and the source command path's different failure policy are separate
pending owner migrations; this context repair does not change them.
Final actual-source/Flutter pairs, both locales/themes/DPRs and native replay
belong to the integrator after the clean combined tree. This branch runs no
application builds, GPU/Android inputs, publication or release.
