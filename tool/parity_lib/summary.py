"""summary.md of a parity run: the table that goes into a PR. The HTML report is the vendored CLI's (site/)."""
from __future__ import annotations

from collections import OrderedDict

from .diffmetrics import CLOSE_DELTA, GEOMETRY_PASS

STATUS_LABEL = {
    'same': 'same', 'pass': 'pass', 'basic-pass': 'basic pass', 'geometry-pass': 'geometry pass', 'fail': 'FAIL',
    'uncovered': 'not covered', 'missing-react': 'no React capture', 'missing-flutter': 'no Flutter capture',
}


def _fmt(value):
    return '-' if value is None else '%.2f' % value


def markdown(summary):
    c = summary['counts']
    lines = [
        '# dsh-flutter parity: %s' % summary['suite'], '',
        summary['notes'], '',
        'pixel-perfect and RGB similarity are the vendored visual-testing CLI\'s (status: pass > 99%%, basic pass > 96%% pixel-perfect); '
        'non-text = identical pixels plus glyph anti-aliasing pixels (dsh geometry target, >= %g%%); close = within %d/255 per channel.'
        % (GEOMETRY_PASS, CLOSE_DELTA), '',
        '%d captures: %d compared, %d same, %d pass (official, > 96%% pixel-perfect), %d geometry pass (incl. those), %d fail, '
        '%d not covered, %d missing. Mean pixel-perfect %s%%, mean non-text %s%%.' % (
            c['entries'], c['compared'], c['same'], c['pass'], c['geometryPass'], c['fail'], c['uncovered'], c['missing'],
            _fmt(summary['meanPixelPerfectPct']), _fmt(summary['meanNonTextPct'])),
        '', '## Per case', '',
        '| case | theme | pixel-perfect % | RGB % | close % | non-text % | status | main bucket |',
        '|---|---|---:|---:|---:|---:|---|---|',
    ]
    for r in summary['cases']:
        top = ''
        if 'buckets' in r and r['mismatched']:
            name, n = max(r['buckets'].items(), key=lambda kv: kv[1])
            top = '%s %d px' % (name, n)
        lines.append('| `%s` | %s | %s | %s | %s | %s | %s | %s |' % (
            r['key'], r['theme'], _fmt(r.get('pixelPerfectPct')), _fmt(r.get('rgbPct')), _fmt(r.get('closePct')),
            _fmt(r.get('nonTextPct')), STATUS_LABEL.get(r['status'], r['status']), top or (r.get('reason', '')[:60])))
    lines += ['', '## Per area', '',
              '| area | captures | compared | geometry pass | mean pixel-perfect % | mean non-text % |', '|---|---:|---:|---:|---:|---:|']
    areas = OrderedDict()
    for r in summary['cases']:
        areas.setdefault(r['caseId'].split('.')[1], []).append(r)
    for area, rows in areas.items():
        done = [r for r in rows if 'pixelPerfectPct' in r]
        mean = lambda f: _fmt(sum(r[f] for r in done) / len(done)) if done else '-'
        lines.append('| %s | %d | %d | %d | %s | %s |' % (
            area, len(rows), len(done), sum(r['status'] in ('same', 'pass', 'basic-pass', 'geometry-pass') for r in rows),
            mean('pixelPerfectPct'), mean('nonTextPct')))
    return '\n'.join(lines) + '\n'
