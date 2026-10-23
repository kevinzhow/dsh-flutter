"""Diff, composite and summary stage shared by tool/parity and tool/parity-ext/run."""
from __future__ import annotations

import json
import pathlib

from . import diffmetrics as dm
from .compose import side_by_side
from .manifest import PROVIDERS


def read_json(path, default=None):
    try:
        return json.loads(pathlib.Path(path).read_text())
    except (OSError, ValueError):
        return default


def compare_entry(entry, results, out):
    """Diff one capture key. Returns the result row (also written to <out>/diff/<key>.json)."""
    key, case = entry['key'], entry['case']
    react_png = results / 'react' / ('%s.png' % key)
    flutter_png = results / 'flutter' / ('%s.png' % key)
    row = {'key': key, 'caseId': case['id'], 'variantId': entry['variant']['id'], 'theme': case['theme'],
           'kind': case['kind'], 'title': case['title'], 'variantName': entry['variant']['name']}
    if not react_png.is_file():
        row.update(status='missing-react')
    elif not flutter_png.is_file():
        row.update(status='missing-flutter')
    else:
        density = case['viewport']['density']
        res, label, rp, fp = dm.compare_files(react_png, flutter_png, density, case.get('regions', []))
        row.update(res)
        row['status'] = res['verdict']
        comp_dir = out / 'composites'
        comp_dir.mkdir(parents=True, exist_ok=True)
        caption = '%s   exact %.2f%%   non-text %.2f%%   %s' % (key, res['exactPct'], res['nonTextPct'], res['verdict'])
        side_by_side(rp.astype('uint8'), fp.astype('uint8'), dm.diff_visual(rp, label), caption).save(comp_dir / ('%s.png' % key))
    (out / 'diff').mkdir(parents=True, exist_ok=True)
    (out / 'diff' / ('%s.json' % key)).write_text(json.dumps(row, indent=1) + '\n')
    return row


PASSING = ('same', 'pass', 'geometry-pass')


def summarize(rows, coverage, suite, notes, extra=None):
    """Build summary.json content from comparison rows and the Flutter coverage map."""
    cases = {}
    for r in rows:
        cov = coverage.get(r['caseId'], {})
        r['coverage'] = cov.get('status', 'unknown')
        if r['status'] == 'missing-flutter' and cov.get('status') not in (None, 'mapped'):
            r['status'] = 'uncovered'
            r['reason'] = cov.get('reason', '')
        cases[r['key']] = r
    ordered = list(cases.values())
    compared = [r for r in ordered if 'exactPct' in r]
    counts = {
        'entries': len(ordered),
        'compared': len(compared),
        'same': sum(r['status'] == 'same' for r in ordered),
        'pass': sum(r['status'] in ('same', 'pass') for r in ordered),
        'geometryPass': sum(r['status'] in PASSING for r in ordered),
        'fail': sum(r['status'] == 'fail' for r in ordered),
        'uncovered': sum(r['status'] == 'uncovered' for r in ordered),
        'missing': sum(r['status'] in ('missing-react', 'missing-flutter') for r in ordered),
    }
    mean = lambda field: round(sum(r[field] for r in compared) / len(compared), 3) if compared else None
    summary = {
        'schema': 'dsh-parity-summary/1', 'suite': suite, 'notes': notes, 'counts': counts,
        'meanExactPct': mean('exactPct'), 'meanNonTextPct': mean('nonTextPct'),
        'thresholds': {'pass': dm.PASS, 'strict': dm.STRICT_PASS, 'geometry': dm.GEOMETRY_PASS},
        'cases': ordered,
        **(extra or {}),
    }
    return summary
