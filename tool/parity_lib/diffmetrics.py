"""Raw image diff metrics for provider captures (numpy + Pillow).

Both providers write a PNG of the same element; this module compares the two rasters pixel by
pixel and explains where they differ. Nothing here knows about dsh, React or Flutter.

Scores (percent of pixels, after flattening both images on white and padding the smaller one
with white to the larger size):

  exact      pixels whose RGB is identical                         ("exact %")
  close      pixels whose largest channel delta is <= CLOSE_DELTA  (colour rounding noise)
  nonText    exact + pixels classified as glyph anti-aliasing      ("non-text %": geometry)

Every mismatching pixel is assigned to the FIRST bucket that explains it:

  fill      both images are locally flat (3x3 constant) and differ by <= FILL_DELTA/255:
            blending / colour rounding over a uniform fill
  hairline  on, or one pixel next to, a long straight horizontal/vertical edge of either image
            and the mismatch band is thin (<= HAIRLINE_BAND px): border / divider snapping
  corner    next to the junction of a horizontal and a vertical edge: rounded-corner arcs
  offset    a patch around the pixel matches (mean delta <= OFFSET_MEAN) once the second image
            is shifted by a whole CSS px (<= OFFSET_MAX_CSS) or one device px: real geometry offsets
  text      dense ink neighbourhood (5x5 luminance range >= INK_RANGE) that no shift explains:
            glyph rasterisation and sub-pixel glyph placement (Chromium vs Skia anti-aliasing)
  other     everything else: wrong colours, missing or extra content

A case reaches the *geometry pass* when nonText >= GEOMETRY_PASS; text anti-aliasing is
deliberately not something to iterate on. Regions (named rectangles from the case, plus the
worst cells of a regular grid) are scored with the same buckets.

The bucket definitions follow the documented approach of raft-flutter's parity-ext analysis;
the code is a fresh implementation (no source copied).
"""
from __future__ import annotations

import numpy as np
from PIL import Image

BUCKETS = ('fill', 'hairline', 'corner', 'offset', 'text', 'other')
BUCKET_COLOURS = {  # visualisation only
    'fill': (0, 160, 255), 'hairline': (255, 0, 0), 'corner': (255, 0, 255),
    'offset': (255, 160, 0), 'text': (0, 170, 0), 'other': (0, 0, 0),
}
PASS = 96.0
STRICT_PASS = 99.0
GEOMETRY_PASS = 99.5
CLOSE_DELTA = 4
FILL_DELTA = 4
HAIRLINE_BAND = 3
EDGE_MIN_LEN = 8
OFFSET_MEAN = 2.0
OFFSET_MAX_CSS = 3
INK_RANGE = 48
GRID_CSS = 32


def load_rgb(path):
    """PNG -> int16 HxWx3, alpha flattened on white."""
    a = np.asarray(Image.open(path).convert('RGBA')).astype(np.float32)
    alpha = a[..., 3:] / 255.0
    return np.rint(a[..., :3] * alpha + 255.0 * (1 - alpha)).astype(np.int16)


def pad_to(img, h, w):
    out = np.full((h, w, 3), 255, np.int16)
    out[:img.shape[0], :img.shape[1]] = img
    return out


def shift(a, dy, dx, fill):
    """Content moved by (dy, dx); uncovered cells get `fill`."""
    out = np.full_like(a, fill)
    h, w = a.shape[:2]
    ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    if ys.stop - ys.start > 0 and xs.stop - xs.start > 0:
        out[yd, xd] = a[ys, xs]
    return out


def box_mean(x, r):
    """Mean over a (2r+1)^2 window (edge padded)."""
    p = np.pad(x.astype(np.float64), r, mode='edge')
    c = np.pad(p.cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    k = 2 * r + 1
    return (c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)


def dilate(mask, r):
    out = mask.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            if dy or dx:
                out |= shift(mask, dy, dx, False)
    return out


def run_length(mask, axis):
    """Per-cell length of the contiguous True run along `axis` (1 = horizontal, 0 = vertical)."""
    m = mask if axis == 1 else mask.T
    out = np.zeros(m.shape, np.int32)
    for i in range(m.shape[0]):
        row = m[i]
        if not row.any():
            continue
        d = np.diff(np.concatenate(([0], row.view(np.int8), [0])))
        for s, e in zip(np.flatnonzero(d == 1), np.flatnonzero(d == -1)):
            out[i, s:e] = e - s
    return out if axis == 1 else out.T


def _flat(img):
    eq = np.ones(img.shape[:2], bool)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy or dx:
                eq &= (shift(img, dy, dx, -1) == img).all(-1)
    return eq


def _edges(img, min_len):
    """(horizontal, vertical) masks of pixels on a long straight colour edge."""
    up, down = shift(img, 1, 0, -1), shift(img, -1, 0, -1)
    left, right = shift(img, 0, 1, -1), shift(img, 0, -1, -1)
    eh = (img != up).any(-1) | (img != down).any(-1)
    ev = (img != left).any(-1) | (img != right).any(-1)
    hs = eh & ((img == left).all(-1) | (img == right).all(-1))
    vs = ev & ((img == up).all(-1) | (img == down).all(-1))
    return run_length(hs, 1) >= min_len, run_length(vs, 0) >= min_len


def luminance(img):
    return (img[..., 0] * 0.299 + img[..., 1] * 0.587 + img[..., 2] * 0.114)


def _range5(lum):
    p = np.pad(lum, 2, mode='edge')
    h, w = lum.shape
    stack = np.stack([p[dy:dy + h, dx:dx + w] for dy in range(5) for dx in range(5)])
    return stack.max(0) - stack.min(0)


def classify(r, f, density):
    """-> (mismatch mask, label array: -1 matching, else index into BUCKETS)."""
    mism = (r != f).any(-1)
    label = np.full(mism.shape, -1, np.int8)
    if not mism.any():
        return mism, label
    delta = np.abs(r - f).max(-1)
    todo = mism.copy()

    def assign(mask, name):
        nonlocal todo
        hit = todo & mask
        label[hit] = BUCKETS.index(name)
        todo = todo & ~hit

    assign(_flat(r) & _flat(f) & (delta <= FILL_DELTA), 'fill')

    min_len = max(EDGE_MIN_LEN, int(round(EDGE_MIN_LEN * density / 2)))
    rh, rv = _edges(r, min_len)
    fh, fv = _edges(f, min_len)
    eh, ev = rh | fh, rv | fv
    band = max(HAIRLINE_BAND, int(np.ceil(HAIRLINE_BAND * density / 2)))
    thin_v = run_length(mism, 0) <= band    # thickness across a horizontal edge
    thin_h = run_length(mism, 1) <= band    # thickness across a vertical edge
    corner_zone = dilate(eh, 2) & dilate(ev, 2)
    assign(corner_zone, 'corner')
    near_h, near_v = dilate(eh, 1), dilate(ev, 1)
    assign((near_h & thin_v) | (near_v & thin_h), 'hairline')

    # whole-pixel offsets
    radius = max(2, int(round(2 * density)))
    css = [int(round(s * density)) for s in range(-OFFSET_MAX_CSS, OFFSET_MAX_CSS + 1)]
    shifts = {(a, b) for a in css for b in css} | {(a, b) for a in (-1, 0, 1) for b in (-1, 0, 1)}
    shifts.discard((0, 0))
    best = np.full(mism.shape, np.inf)
    if todo.any():
        for dy, dx in sorted(shifts):
            d = np.abs(r - shift(f, dy, dx, 255)).mean(-1)
            best = np.minimum(best, box_mean(d, radius))
        assign(best <= OFFSET_MEAN, 'offset')

    ink = (_range5(luminance(r)) >= INK_RANGE) | (_range5(luminance(f)) >= INK_RANGE)
    assign(ink, 'text')
    assign(np.ones_like(todo), 'other')
    return mism, label


def _pct(part, total):
    return 100.0 * part / total if total else 100.0


def _score(mism, label, delta, window=None):
    """Counts and percentages over a window (y0, y1, x0, x1) of the padded raster."""
    if window is not None:
        y0, y1, x0, x1 = window
        mism, label, delta = mism[y0:y1, x0:x1], label[y0:y1, x0:x1], delta[y0:y1, x0:x1]
    total = int(mism.size)
    mismatched = int(mism.sum())
    text = int((label == BUCKETS.index('text')).sum())
    buckets = {b: int((label == i).sum()) for i, b in enumerate(BUCKETS)}
    return {
        'pixels': total,
        'mismatched': mismatched,
        'exactPct': round(_pct(total - mismatched, total), 3),
        'closePct': round(_pct(total - int((mism & (delta > CLOSE_DELTA)).sum()), total), 3),
        'nonTextPct': round(_pct(total - mismatched + text, total), 3),
        'buckets': buckets,
    }


def verdict(exact_pct, non_text_pct):
    """same | pass | geometry-pass | fail (a geometry pass is a pass of the non-text score only)."""
    if exact_pct >= 100.0:
        return 'same'
    if exact_pct >= PASS:
        return 'pass'
    if non_text_pct >= GEOMETRY_PASS:
        return 'geometry-pass'
    return 'fail'


def compare_arrays(r, f, density=1.0, regions=()):
    """Compare two flattened rasters. Returns (result dict, label array, padded react, padded flutter)."""
    size_react, size_flutter = (r.shape[1], r.shape[0]), (f.shape[1], f.shape[0])
    h, w = max(r.shape[0], f.shape[0]), max(r.shape[1], f.shape[1])
    rp, fp = pad_to(r, h, w), pad_to(f, h, w)
    mism, label = classify(rp, fp, density)
    delta = np.abs(rp - fp).max(-1)
    result = _score(mism, label, delta)
    result.update({
        'sizeReact': list(size_react), 'sizeFlutter': list(size_flutter),
        'sizeMismatch': size_react != size_flutter,
        'meanAbsDelta': round(float(np.abs(rp - fp).mean()), 4),
        'verdict': verdict(result['exactPct'], result['nonTextPct']),
    })
    # A different raster size can never be a geometry pass: the padded white hides the extra area.
    if result['sizeMismatch']:
        result['verdict'] = 'fail'
    named = []
    for reg in regions:
        y0 = max(0, int(round(reg['y'] * density)))
        x0 = max(0, int(round(reg['x'] * density)))
        y1 = min(h, int(round((reg['y'] + reg['height']) * density)))
        x1 = min(w, int(round((reg['x'] + reg['width']) * density)))
        if y1 <= y0 or x1 <= x0:
            named.append({'name': reg['name'], 'error': 'region outside the capture'})
            continue
        s = _score(mism, label, delta, (y0, y1, x0, x1))
        named.append({'name': reg['name'], 'rect': [x0, y0, x1 - x0, y1 - y0], **s})
    result['regions'] = named
    cell = max(8, int(round(GRID_CSS * density)))
    cells = []
    for y0 in range(0, h, cell):
        for x0 in range(0, w, cell):
            win = (y0, min(h, y0 + cell), x0, min(w, x0 + cell))
            s = _score(mism, label, delta, win)
            if s['mismatched']:
                cells.append({'rect': [x0, y0, win[3] - x0, win[1] - y0], **s})
    cells.sort(key=lambda c: -(c['mismatched'] - c['buckets']['text']))
    result['worstCells'] = cells[:5]
    return result, label, rp, fp


def compare_files(react_png, flutter_png, density=1.0, regions=()):
    r, f = load_rgb(react_png), load_rgb(flutter_png)
    return compare_arrays(r, f, density, regions)


def diff_visual(rp, label):
    """Faded first image with mismatching pixels painted in their bucket colour (RGB uint8)."""
    out = (255 - (255 - rp) // 4).astype(np.int16)
    for i, name in enumerate(BUCKETS):
        out[label == i] = BUCKET_COLOURS[name]
    return out.astype(np.uint8)
