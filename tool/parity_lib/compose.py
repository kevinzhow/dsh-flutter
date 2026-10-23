"""Side-by-side composite of one comparison: React | Flutter | difference map.

The difference map is the React raster faded to a quarter with every mismatching pixel painted in the colour
of its bucket (diffmetrics.BUCKET_COLOURS). Labels use the pinned parity font so the output is
reproducible. Small captures are upscaled with nearest-neighbour so single pixels stay visible.
"""
from __future__ import annotations

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from . import env
from .diffmetrics import BUCKETS, BUCKET_COLOURS

GAP = 12
LABEL_H = 22
BACKGROUND = (232, 232, 236)


def _font(size):
    try:
        return ImageFont.truetype(str(env.FONTS / 'files' / 'NotoSans-Regular.ttf'), size)
    except OSError:
        return ImageFont.load_default()


def _panel_scale(width):
    return max(1, min(6, int(round(280 / max(1, width)))))


def side_by_side(react_rgb, flutter_rgb, diff_rgb, caption):
    """Arrays (HxWx3 uint8) -> PIL image."""
    panels = [('React (dsh web)', react_rgb), ('Flutter (dsh_flutter)', flutter_rgb), ('Difference by bucket', diff_rgb)]
    scale = _panel_scale(max(p.shape[1] for _, p in panels))
    images = []
    for label, arr in panels:
        im = Image.fromarray(np.asarray(arr, dtype=np.uint8))
        images.append((label, im.resize((im.width * scale, im.height * scale), Image.NEAREST)))
    legend_h = 22
    width = GAP + sum(im.width + GAP for _, im in images)
    width = max(width, 520)
    height = LABEL_H * 2 + max(im.height for _, im in images) + GAP + legend_h
    canvas = Image.new('RGB', (width, height), BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    font, small = _font(13), _font(11)
    draw.text((GAP, 4), caption, fill=(30, 30, 34), font=font)
    x = GAP
    for label, im in images:
        draw.text((x, LABEL_H + 4), label, fill=(60, 60, 66), font=small)
        canvas.paste(im, (x, LABEL_H * 2))
        x += im.width + GAP
    # legend
    lx, ly = GAP, height - legend_h + 4
    for name in BUCKETS:
        draw.rectangle([lx, ly + 2, lx + 9, ly + 11], fill=BUCKET_COLOURS[name])
        draw.text((lx + 13, ly), name, fill=(60, 60, 66), font=small)
        lx += 13 + int(draw.textlength(name, font=small)) + 14
    return canvas
