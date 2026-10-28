# Source statistics DOM measurements — 2026-10-28

The first complete 108-pair comparison at runtime6de2b707 found eight statistics
dimension mismatches: phone right-edge × activity/usage × EN/ZH × light/dark.
Every card already had the same logical width300 and matching logical height.
This was placement, not a grid-width or typography discrepancy.

Pinned source is DSH687f282e8625c6b8d11ff58211a90524be2e4317, published
DSH0.2.1-rc.2, Chromium145.0.7632.6. `ui-chat/stat-dialog.ts` delegates to the
actual primitive `ui-primitives/src/useAnchoredPosition.ts`. That function reads
the trigger's fractional getBoundingClientRect, the panel's integer
offsetWidth/offsetHeight, and integer window.innerWidth/innerHeight. It uses
the offset measurements to place and clamp; it does not resize the card.

Direct DOM inspection used the already built real source host and its pinned
fonts with the exact phone activity/right-edge/light synthetic entry. The
probe made no source/style changes and saved no alternate acceptance capture.

| Reading | Source observation |
|---|---:|
| documentElement DOMRect width |390.0952453613281|
| window.innerWidth |390|
| window.innerHeight |400|
| trigger DOMRect top/height |362 /22|
| activity panel DOMRect width/height |300 /158.38095092773438|
| panel offsetWidth/offsetHeight |300 /158|
| source inline left/top |78 /196|

Thus the source computes x=`390−300−12=78` and y=`362−8−158=196`.
The previous Flutter follower used its fractional viewport390.095238 and card
height158.380952 for those coordinate equations, giving x78.095238 and
y195.619048. The card's layout size itself was correct. At2.625× the source
x78 makes the enclosing raster [204,993),789 columns; the former Flutter x
makes [205,993),788 columns. Usage has the same issue with height182.38095 and
source top172 versus Flutter171.61905. EN/ZH and both themes repeat these
same geometry readings.

A second minimal native Chromium probe verified the DOM integer rule away
from this one case: CSS width100.5 reports offsetWidth101. At1.25×, a389×421
request lays out a389.600006×421.600006 viewport but innerWidth/Height are
390/422. At2.625×, CSS viewport389.333344×421.333344 gives inner389/421.
Positive Dart roundToDouble reproduces these DOM readings.

The shared correction is an opt-in `domOffsetGeometry` flag on
DshAnchoredPanel/DshMenuFollower, defaultfalse. Only coordinate calculation
rounds the card's measured dimensions and the viewport dimensions. Anchor
DOMRect-equivalent geometry and actual child layout stay fractional. Stats
opts in; ModelSeat is owned by its lane. Existing other clients keep the
prior fractional coordinate contract. CSS width/height constraints continue
using fractional viewport sizes because CSS100vw/100vh differs from the JS
window readings; DshStatPanel's bounds are deliberately unchanged.

Tests capture the source requirement independently of visual scoring:

- A300×158.380952 card in the390.095238×400 native2.625 viewport places at
  x78/y196 and encloses789 physical columns when opted in, without changing
  its actual width/height. The defaultfalse branch keeps x78.095238/y195.619048
  and788 columns, proving existing clients retain their geometry.
- The actual StatPillView/DshStatPanel production path has the same source
  placement and dimensions with four synthetic rows. The small label strings
  keep unit-test Ahem from overriding the source's300px minimum; typography
  values themselves are unchanged.
- Both opted-in tests reproduced RED at x78expected versus78.095238actual
  before the coordinate logic. Logs:
  `.local/reported-dom-geometry-{ui,stats}-actual-red.log`.

No crop/scoring/classification/font rule, arbitrary pixel translation or card
size was adjusted. The actual source reference captures remain authoritative;
parent owns new paired captures and replacement native runtime acceptance.
