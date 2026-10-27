# Risk tiny-height and conditional-scrollbar source proof

The actual source keeps its20px content/footer gap even when the card is too
short to contain the footer. Its normal classic scrollbar reserves space only
when the risk content overflows; this profile does not use a stable gutter.

Read-only probe: `.local/headed-tiny-gutter.mjs`, SHA256
`eee4590e73fb1546753257db16f54952234201b259407898584fad2a2f1354cb`.
Raw18-context proof: `measurements.json`, SHA256
`f0d3ff346c475f1da127355bc12c41d48bf9e40f04185056411dc216ee1af03a`.
Full PNGs are retained for all18 contexts, with four no-hide overflow gutter PNGs.

Actual RiskConfirmation and current EN permission.access copy are unchanged.
Pinned fonts load before the unchanged source bundle mounts, avoiding the known
cold-font autofocus offset. Tests cover both native reference densities; ordinary
and no-hide scrollbar probes cover both themes. The only browser argument
change in diagnostic-visible is ignoring Playwright's implicit --hide-scrollbars.
No product, source host, manifest, capture settings, classifier or cache was edited.

## Viewport80 / max-height32

Both densities produce these exact CSS coordinates:

| Region | y | height | bottom |
| --- | ---: | ---: | ---: |
| Card | 24 | 32 | 56 |
| Scroll content | 24 | 0 | 24 |
| Gap before footer | 24 | 20 | 44 |
| Footer | 44 | 36 | 80 |

Card CSS max-height is32px, padding-bottom24px, gap20px, overflow hidden.
The footer retains its natural36px height. Its vertical intersection with the
card is12px; the remainder overflows and is clipped by the real card. Rounded
corners can further clip pixels near the horizontal edges. The source does not
reduce the20px gap or shrink the footer to fit this extreme viewport.

Natural short EN geometry, measured separately at height900, is314px card /
234px content on desktop and358px card /278px content on phone. The tiny card's
content scrollHeight retains234 /278 while its clientHeight collapses to0.
Autofocus changes its internal scrollTop but not these frame/footer positions.

## Conditional gutter and inherited palette

| Mode / content | Desktop CSS gutter / physical px | Phone CSS gutter / physical px |
| --- | --- | --- |
| Ordinary capture, short | 0 /0 | 0 /0 |
| Ordinary capture, long | 0 /0 | 0 /0 |
| No-hide diagnostic, short | 0 /0 | 0 /0 |
| No-hide diagnostic, long | 5 /5 | 4.952381 /13 |

Both themes agree. The actual overflow gutter is measured as the difference
between the content outer rect and its first header child's content width.
DOM offsetWidth-clientWidth reports5 CSS px in both overflowing no-hide cases,
while native DPR2.625 raster/layout width is13physical px. Short cases have
clientWidth=offsetWidth. Computed scrollbar-gutter is auto throughout; WebKit
scrollbar CSS width is5px, thumb border0px, track margins0px and transparent track.
Exact thumb-colour rows fill all5 /13 device columns in every long diagnostic.

Risk inherits the body l1 thumb variable. Its light thumb is rgb(229,229,229).
Its dark thumb is rgb(60,60,61), whereas the reader's explicitly elevated l2
thumb would be rgb(84,85,87). This profile does not rebind to l2.

At viewport320 long cards remain272px high, content192px, gap20px, footer36px
and bottom padding24px. The no-hide gutter changes only scroll content width:
desktop client440→435; phone client342→337(outer width342.095245 unchanged).
Phone long EN scrollHeight grows850→872(one additional22px line), and final
autofocus scrollTop grows657.904785→680. Footer geometry is identical.

This isolated RiskConfirmation host does not expose additional outer-document
scrollbars when the hidden flag is removed, so its root/card geometry stays the
same. Earlier guide diagnostics had outer-document overflow and shifted geometry;
that caveat remains relevant to those hosts. The no-hide screenshots here are
still diagnostic and were not substituted into the reference capture cache.

All18 source contexts pass assertions; both tiny cases retain the20px gap and
show the12px vertical footer intersection; all four no-hide long cases reserve
and paint the expected5 /13 physical columns with the inherited l1 colour.
All probe-owned contexts, browsers and HTTP server were closed. No native runtime.
