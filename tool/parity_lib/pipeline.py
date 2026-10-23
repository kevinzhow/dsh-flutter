"""Diff stage shared by tool/parity and tool/parity-ext/run: the vendored CLI's diff plus dsh's own supplement.

The pixel-perfect %, RGB similarity and status of every capture are the vendored CLI's (vt.diff). The supplement
(diffmetrics: non-text %, buckets, regions) is computed from the same two PNGs and only adds what the CLI lacks.
"""
from __future__ import annotations

import json
import pathlib

from . import diffmetrics as dm, vt

OFFICIAL_PASSING = ('same', 'pass', 'basic-pass')
PASSING = OFFICIAL_PASSING + ('geometry-pass',)


def read_json(path, default=None):
    try:
        return json.loads(pathlib.Path(path).read_text())
    except (OSError, ValueError):
        return default


def status_of(official, non_text_pct, size_mismatch):
    """dsh status of a compared capture from the CLI's status.

    same | pass (> 99% pixel-perfect) | basic-pass (> 96%) are the CLI's; `geometry-pass` is dsh's own target
    (non-text >= 99.5%); a different raster size is always a failure, whatever the padded comparison says."""
    if size_mismatch:
        return 'fail'
    if official in OFFICIAL_PASSING:
        return official
    return 'geometry-pass' if non_text_pct >= dm.GEOMETRY_PASS else 'fail'


def compare(entries, out, results, log=None):
    """Official diff of every entry, then the supplement; returns the result rows (summary.json 'cases')."""
    official = vt.diff(entries, out, log)
    rows = []
    for e in entries:
        key, case = e['key'], e['case']
        row = {'key': key, 'caseId': case['id'], 'variantId': e['variant']['id'], 'theme': case['theme'],
               'kind': case['kind'], 'title': case['title'], 'variantName': e['variant']['name']}
        o = official[key]
        react_png = results / vt.BASELINE / ('%s.png' % key)
        flutter_png = results / vt.CURRENT / ('%s.png' % key)
        if not react_png.is_file():
            row['status'] = 'missing-react'
        elif not flutter_png.is_file():
            row['status'] = 'missing-flutter'
        else:
            m = o['metrics']
            row.update(officialStatus=o['status'], pixelPerfectPct=round(100.0 * m['pixelPerfectSimilarity'], 3),
                       rgbPct=round(100.0 * m['rgbSimilarity'], 3),
                       sizeReact=[m['baselineWidth'], m['baselineHeight']], sizeFlutter=[m['currentWidth'], m['currentHeight']],
                       sideBySide=o.get('sideBySideImage'))
            row['sizeMismatch'] = row['sizeReact'] != row['sizeFlutter']
            res = dm.compare_files(react_png, flutter_png, case['viewport']['density'], case.get('regions', []))[0]
            for field in ('exactPct', 'closePct', 'nonTextPct', 'mismatched', 'pixels', 'buckets', 'regions', 'worstCells'):
                row[field] = res[field]
            row['status'] = status_of(o['status'], res['nonTextPct'], row['sizeMismatch'])
        rows.append(row)
    return rows


def summarize(rows, coverage, suite, notes, extra=None):
    """Build summary.json content from comparison rows and the Flutter coverage map."""
    for r in rows:
        cov = coverage.get(r['caseId'], {})
        r['coverage'] = cov.get('status', 'unknown')
        if r['status'] == 'missing-flutter' and cov.get('status') not in (None, 'mapped'):
            r['status'] = 'uncovered'
            r['reason'] = cov.get('reason', '')
    compared = [r for r in rows if 'pixelPerfectPct' in r]
    counts = {
        'entries': len(rows),
        'compared': len(compared),
        'same': sum(r['status'] == 'same' for r in rows),
        'strict': sum(r['status'] in ('same', 'pass') for r in rows),
        'pass': sum(r['status'] in OFFICIAL_PASSING for r in rows),
        'geometryPass': sum(r['status'] in PASSING for r in rows),
        'fail': sum(r['status'] == 'fail' for r in rows),
        'uncovered': sum(r['status'] == 'uncovered' for r in rows),
        'missing': sum(r['status'] in ('missing-react', 'missing-flutter') for r in rows),
    }
    mean = lambda field: round(sum(r[field] for r in compared) / len(compared), 3) if compared else None
    return {
        'schema': 'dsh-parity-summary/2', 'suite': suite, 'notes': notes, 'counts': counts,
        'meanPixelPerfectPct': mean('pixelPerfectPct'), 'meanRgbPct': mean('rgbPct'), 'meanNonTextPct': mean('nonTextPct'),
        'thresholds': {'official': 'vendored CLI: pass > 99% pixel-perfect, basic-pass > 96%', 'geometry': dm.GEOMETRY_PASS},
        'cases': rows,
        **(extra or {}),
    }
