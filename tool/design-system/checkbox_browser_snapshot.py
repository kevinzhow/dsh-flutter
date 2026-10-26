#!/usr/bin/env python3
"""Derive the pinned Chromium checkbox paint contract from source and captures.

This is an offline extraction step. The screenshots come from a separate
Chromium probe of unstyled native inputs, without the DSH disabled opacity.
"""
import argparse
import colorsys
import hashlib
import json
import re
from pathlib import Path

from PIL import Image


def one(pattern, text):
    matches = re.findall(pattern, text, re.S)
    if len(matches) != 1:
        raise ValueError('missing or ambiguous Chromium paint structure: ' + pattern)
    return float(matches[0])


def extract(source, directory):
    source_bytes = source.read_bytes()
    text = source_bytes.decode()
    radius = one(r'if \(part == kCheckbox \|\| part == kPushButton \|\| part == kTextField\) \{\s*return ([\d.]+)f;', text)
    border = one(r'kBorderWidth = ([\d.]+)f;', text)
    inset = one(r'skrect\.makeInset\(kBorderWidth \* ([\d.]+)f, kBorderWidth \* [\d.]+f\)', text)
    start = one(r'check\.moveTo\(skrect\.x\(\) \+ skrect\.width\(\) \* ([\d.]+)f, skrect\.centerY\(\)\)', text)
    step = one(r'check\.rLineTo\(skrect\.width\(\) \* ([\d.]+)f, skrect\.height\(\) \* \1f\)', text)
    end = one(r'check\.lineTo\(skrect\.right\(\) - skrect\.width\(\) \* ([\d.]+)f,\s*skrect\.y\(\) \+ skrect\.height\(\) \* \1f\)', text)
    stroke = one(r'flags\.setStrokeWidth\(skrect\.height\(\) \* ([\d.]+)f\)', text)
    lightness = one(r'kLightnessAdjust = ([\d.]+);', text)
    for required in ('skrect.makeInset(kBorderWidth / 2, kBorderWidth / 2)',
                     'canvas->drawRoundRect(skrect, radius, radius, flags)',
                     'hsl.l = std::clamp(hsl.l + l_adjust, 0.0, 1.0)'):
        if required not in text:
            raise ValueError('unrecognized Chromium checkbox drawing structure')

    rows = json.loads((directory / 'probe.json').read_text())
    if len(rows) != 48 or {row['browser'] for row in rows} != {'145.0.7632.6'}:
        raise ValueError('unexpected browser probe matrix/version')
    samples = {}
    for row in rows:
        key = (row['mode'], row['checked'], row['disabled'], row['state'])
        if row['styles']['appearance'] != 'auto' or row['styles']['colorScheme'] != row['mode']:
            raise ValueError('probe did not use the native checkbox')
        with Image.open(directory / (row['id'] + '.png')) as image:
            image = image.convert('RGB')
            center = image.getpixel((image.width // 2, image.height // 2))
            edge = image.getpixel((image.width // 2, round(row['density'] / 2)))
        colors = ['#%02x%02x%02x' % center, '#%02x%02x%02x' % edge]
        previous = samples.setdefault(key, [])
        previous.append((row['density'], colors))
    if len(samples) != 24 or any(len(v) != 2 or {x[0] for x in v} != {1, 2.625} or v[0][1] != v[1][1] for v in samples.values()):
        raise ValueError('native checkbox color samples disagree between densities')
    palette = {}
    for mode in ('light', 'dark'):
        palette[mode] = {}
        for state in ('normal', 'hover', 'pressed', 'disabled'):
            disabled = state == 'disabled'
            sample_state = 'normal' if disabled else state
            off = samples[(mode, False, disabled, sample_state)][0][1]
            on = samples[(mode, True, disabled, sample_state)][0][1]
            palette[mode][state] = {'offFill': off[0], 'offBorder': off[1],
                                    'onMark': on[0], 'onFillSample': on[1]}
        for checked in (False, True):
            expected = samples[(mode, checked, True, 'normal')][0][1]
            if any(samples[(mode, checked, True, state)][0][1] != expected for state in ('hover', 'pressed')):
                raise ValueError('disabled native state changed on pointer input')
        accent = next(row['accent'] for row in rows if row['mode'] == mode)
        rgb = [int(accent[i:i + 2], 16) / 255 for i in (1, 3, 5)]
        h, l, s = colorsys.rgb_to_hls(*rgb)
        for state, direction in [('hover', -1), ('pressed', 1)]:
            if mode == 'dark':
                direction = -direction
            adjusted = colorsys.hls_to_rgb(h, min(1, max(0, l + direction * lightness)), s)
            expected = '#%02x%02x%02x' % tuple(round(c * 255) for c in adjusted)
            if palette[mode][state]['onFillSample'] != expected:
                raise ValueError('native accent hover/pressed samples disagree with Chromium lightness rule')
    return {
        'schema': 'dsh-chromium-checkbox/1',
        'browser': '145.0.7632.6',
        'source': 'https://chromium.googlesource.com/chromium/src/+/refs/tags/145.0.7632.6/ui/native_theme/native_theme_base.cc',
        'sourceSha256': hashlib.sha256(source_bytes).hexdigest(),
        'probe': 'native Chromium input, 16 CSS px, light/dark, normal/hover/pressed/disabled, DPR 1 and 2.625',
        'geometry': {'radius': radius, 'borderWidth': border, 'backgroundInsetRatio': inset,
                     'checkStartX': start, 'checkStartY': 0.5, 'checkStepX': step, 'checkStepY': step,
                     'checkEndXFromRight': end, 'checkEndY': end, 'checkStrokeRatio': stroke,
                     'accentLightnessAdjust': lightness},
        'palette': palette,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--captures', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(extract(args.source, args.captures), indent=2) + '\n')
    print('Chromium checkbox geometry and two-density color samples agree')


if __name__ == '__main__':
    main()
