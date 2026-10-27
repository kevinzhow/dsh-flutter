# Real source scrollbar paint diagnostic

The missing source thumb in parity captures is caused by Playwright's implicit
`--hide-scrollbars` launch argument. It is a reference-capture limit, not a
source rule that hides the thumb at rest. No product, capture-harness, classifier,
font or threshold files were changed.

Probe: `.local/dialog-scrollbar-paint.mjs`, using the existing real-source
`build/parity-dialog-reference/react-plan.json`, actual Standard mode guide and
pinned fonts. Chromium headless shell 145.0.7632.6 / Playwright 1.58.2.

Two launch modes differ only by `ignoreDefaultArgs: ['--hide-scrollbars']` in the
diagnostic mode. `Browser.getBrowserCommandLine` confirms the flag exists in the
normal parity launch and is absent from the diagnostic launch. The explicit
`chromiumArgs` in capture metadata do not include Playwright's implicit defaults.

| Real source case | DPR | Scroll extent, default / diagnostic | Default exact thumb pixels, all five states | Diagnostic idle exact thumb pixels | Diagnostic mid-thumb width | Painted right gap |
| --- | ---: | ---: | ---: | ---: | --- | ---: |
| panel-scrolled-desktop-en-usage.dark | 1 | 218 / 223 CSS px | 0 | 369 | 5 device px / 5 CSS px | 0 device px |
| reader-phone-en-usage.dark | 2.625 | 209 / 209 CSS px | 0 | 7,823 | 13 device px / 4.952381 CSS px | 0 device px |

The five states are idle, pointer over panel, pointer over scrollbar gutter,
after a real wheel scroll, and after moving out and waiting 1.5 seconds.
Real wheel scrolling moved the source panel from zero to 180 CSS px at DPR 1,
and to 180.190475 CSS px at DPR 2.625. In the normal launch all five gutter
rasters are RGBA-identical, with zero pixels of the actual thumb colour.

In the diagnostic launch the thumb is visible immediately at idle and remains
visible after 1.5 seconds. Hovering the gutter changes its fill from
rgb(84,85,87) to rgb(101,103,107). A real wheel scroll moves the painted thumb.
The current published skin has width 5px, border 0px and track margin 0px;
measurement shows the paint fills all five / thirteen reserved device columns
at the thumb's middle, with no extra side inset.

Exact normal-colour core bounds at diagnostic idle (rounded caps omit some
edge rows): desktop x713,y217,width5,height75 device px; phone
x935,y935,width13,height605 device px. After wheel these move to y296 and y1235.
See `paint-bounds.json` for all states and raw `measurements.json` for DOM and
CSS values. Full-page and gutter PNGs are retained for every state.

The no-hide diagnostic also reveals outer-document scrollbars: the usable
viewport and modal layout shift (desktop panel x80→77.5 and height180→175;
phone panel width342.095→337.143 CSS px). Thus these diagnostic screenshots are
not replacements for current reference captures and were not put into the
parity cache. Their purpose is to establish source paint/visibility behavior.
All probe-owned browser contexts, browsers and HTTP server were closed.
