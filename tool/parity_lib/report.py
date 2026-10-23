"""summary.md and the self-contained HTML report (site/index.html) of a parity run."""
from __future__ import annotations

import html
import json
import pathlib
import shutil
from collections import OrderedDict

from .diffmetrics import BUCKETS, BUCKET_COLOURS, CLOSE_DELTA, GEOMETRY_PASS, PASS
from .manifest import surface_of

STATUS_LABEL = {
    'same': 'same', 'pass': 'pass', 'geometry-pass': 'geometry pass', 'fail': 'FAIL',
    'uncovered': 'not covered', 'missing-react': 'no React capture', 'missing-flutter': 'no Flutter capture',
}


def _area(case_id):
    return case_id.split('.')[1]


def _fmt(value):
    return '-' if value is None else '%.2f' % value


def summary_markdown(summary):
    c = summary['counts']
    lines = [
        '# dsh-flutter parity: %s' % summary['suite'], '',
        summary['notes'], '',
        'exact = identical pixels; close = within %d/255 per channel; non-text = exact plus glyph anti-aliasing pixels (geometry).' % CLOSE_DELTA,
        '',
        '%d captures: %d compared, %d same, %d pass (exact >= %g%%), %d geometry pass (non-text >= %g%%), %d fail, '
        '%d not covered, %d missing. Mean exact %s%%, mean non-text %s%%.' % (
            c['entries'], c['compared'], c['same'], c['pass'], PASS, c['geometryPass'], GEOMETRY_PASS, c['fail'],
            c['uncovered'], c['missing'], _fmt(summary['meanExactPct']), _fmt(summary['meanNonTextPct'])),
        '', '## Per case', '',
        '| case | theme | exact % | close % | non-text % | status | main bucket |', '|---|---|---:|---:|---:|---|---|',
    ]
    for r in summary['cases']:
        top = ''
        if 'buckets' in r and r['mismatched']:
            name, n = max(r['buckets'].items(), key=lambda kv: kv[1])
            top = '%s %d px' % (name, n)
        lines.append('| `%s` | %s | %s | %s | %s | %s | %s |' % (
            r['key'], r['theme'], _fmt(r.get('exactPct')), _fmt(r.get('closePct')), _fmt(r.get('nonTextPct')),
            STATUS_LABEL.get(r['status'], r['status']), top or (r.get('reason', '')[:60])))
    lines += ['', '## Per area', '', '| area | captures | compared | geometry pass | mean exact % | mean non-text % |', '|---|---:|---:|---:|---:|---:|']
    areas = OrderedDict()
    for r in summary['cases']:
        areas.setdefault(_area(r['caseId']), []).append(r)
    for area, rows in areas.items():
        done = [r for r in rows if 'exactPct' in r]
        mean = lambda f: _fmt(sum(r[f] for r in done) / len(done)) if done else '-'
        lines.append('| %s | %d | %d | %d | %s | %s |' % (
            area, len(rows), len(done), sum(r['status'] in ('same', 'pass', 'geometry-pass') for r in rows),
            mean('exactPct'), mean('nonTextPct')))
    return '\n'.join(lines) + '\n'


CSS = """
body{font:14px/1.45 system-ui,sans-serif;margin:0;background:#f4f4f6;color:#1b1b1f}
header{padding:18px 24px;background:#111;color:#fff}header h1{margin:0 0 4px;font-size:20px}
header p{margin:2px 0;color:#bbb}main{padding:16px 24px}
.stats{display:flex;gap:12px;flex-wrap:wrap;margin:8px 0 16px}
.stat{background:#fff;border-radius:8px;padding:10px 14px;box-shadow:0 1px 2px #0002}.stat b{display:block;font-size:20px}
table{border-collapse:collapse;background:#fff;width:100%;margin-bottom:20px}th,td{padding:6px 10px;border-bottom:1px solid #e6e6ea;text-align:left}
td.n,th.n{text-align:right;font-variant-numeric:tabular-nums}
.badge{border-radius:10px;padding:1px 8px;font-size:12px;color:#fff;white-space:nowrap}
.same,.pass{background:#1a8d3b}.geometry-pass{background:#5a9a1a}.fail{background:#c0392b}
.uncovered,.missing-react,.missing-flutter{background:#8a8a94}
.filters{margin:0 0 12px}.filters button{margin-right:6px;padding:4px 10px;border:1px solid #bbb;background:#fff;border-radius:6px;cursor:pointer}
.filters button.on{background:#111;color:#fff}
.card{background:#fff;border-radius:8px;box-shadow:0 1px 2px #0002;margin:0 0 14px;padding:12px 14px}
.card h3{margin:0 0 6px;font-size:14px;font-family:ui-monospace,monospace}.card img{max-width:100%;image-rendering:pixelated;border:1px solid #ddd}
.bar{display:flex;height:10px;border-radius:5px;overflow:hidden;background:#e6e6ea;margin:6px 0;max-width:420px}
.meta{color:#555;font-size:12px;margin:4px 0}details{margin-top:6px}code{font-size:12px}
"""

JS = """
const buttons=[...document.querySelectorAll('.filters button')];
function apply(f){buttons.forEach(b=>b.classList.toggle('on',b.dataset.f===f));
document.querySelectorAll('.card').forEach(c=>{c.style.display=(f==='all'||c.dataset.status===f||(f==='bad'&&['fail','missing-react','missing-flutter'].includes(c.dataset.status))||c.dataset.theme===f)?'':'none'})}
buttons.forEach(b=>b.onclick=()=>apply(b.dataset.f));apply('all');
"""


def _probe_table(react_meta, flutter_meta, field, columns):
    r, f = (react_meta or {}).get(field, []), (flutter_meta or {}).get(field, [])
    if not r and not f:
        return ''
    rows = []
    for i in range(max(len(r), len(f))):
        a, b = (r[i] if i < len(r) else {}), (f[i] if i < len(f) else {})
        cells = ''.join('<td>%s</td><td>%s</td>' % (html.escape(str(a.get(c, ''))[:48]), html.escape(str(b.get(c, ''))[:48])) for c in columns)
        rows.append('<tr>%s</tr>' % cells)
    head = ''.join('<th>%s React</th><th>%s Flutter</th>' % (c, c) for c in columns)
    return '<details><summary>%s</summary><table><tr>%s</tr>%s</table></details>' % (field, head, ''.join(rows))


def write_site(summary, out, results):
    """<out>/site/index.html + the images it links (copied, so the directory can be published alone)."""
    out, results = pathlib.Path(out), pathlib.Path(results)
    site = out / 'site'
    img = site / 'img'
    img.mkdir(parents=True, exist_ok=True)
    cards = []
    for r in summary['cases']:
        key = r['key']
        for name, src in (('composite', out / 'composites' / ('%s.png' % key)),
                          ('react', results / 'react' / ('%s.png' % key)),
                          ('flutter', results / 'flutter' / ('%s.png' % key))):
            if src.is_file():
                shutil.copy(src, img / ('%s.%s.png' % (key, name)))
        react_meta = _load(results / 'react' / ('%s.metadata.json' % key))
        flutter_meta = _load(results / 'flutter' / ('%s.metadata.json' % key))
        picture = ''
        if (img / ('%s.composite.png' % key)).is_file():
            picture = '<img src="img/%s.composite.png" alt="%s">' % (html.escape(key), html.escape(key))
        elif (img / ('%s.react.png' % key)).is_file():
            picture = '<img src="img/%s.react.png" alt="React capture">' % html.escape(key)
        bar = ''
        if r.get('mismatched'):
            total = r['mismatched']
            bar = '<div class="bar">%s</div><div class="meta">%s</div>' % (
                ''.join('<span style="width:%.2f%%;background:rgb%s"></span>' % (100.0 * r['buckets'][b] / total, BUCKET_COLOURS[b])
                        for b in BUCKETS if r['buckets'][b]),
                ' &middot; '.join('%s %d' % (b, r['buckets'][b]) for b in BUCKETS if r['buckets'][b]))
        regions = ''
        if r.get('regions'):
            regions = '<table><tr><th>region</th><th class="n">exact %</th><th class="n">non-text %</th></tr>%s</table>' % ''.join(
                '<tr><td>%s</td><td class="n">%s</td><td class="n">%s</td></tr>' % (html.escape(g['name']), _fmt(g.get('exactPct')), _fmt(g.get('nonTextPct')))
                for g in r['regions'])
        worst = ''
        if r.get('worstCells'):
            worst = '<details><summary>worst regions (grid cells, device px)</summary><ul>%s</ul></details>' % ''.join(
                '<li>x %d y %d %dx%d: %d px, non-text %.1f%%</li>' % (*c['rect'], c['mismatched'], c['nonTextPct']) for c in r['worstCells'])
        fonts = ''
        if react_meta and flutter_meta:
            fonts = '<details><summary>fonts</summary><div class="meta">React drew with: %s<br>Flutter registered: %s</div></details>' % (
                html.escape(json.dumps(react_meta.get('fonts', {}).get('platformFonts', {}))),
                html.escape(', '.join('%s %s' % (f['family'], f['weight']) for f in flutter_meta.get('fonts', {}).get('faces', []))))
        probes = (_probe_table(react_meta, flutter_meta, 'typography', ['text', 'fontSize', 'fontWeight', 'color'])
                  + _probe_table(react_meta, flutter_meta, 'styleTokens', ['size', 'backgroundColor']))
        size = ''
        if r.get('sizeMismatch'):
            size = '<div class="meta"><b>size mismatch</b>: React %s, Flutter %s</div>' % (r['sizeReact'], r['sizeFlutter'])
        cards.append(
            '<section class="card" data-status="%s" data-theme="%s" id="%s"><h3>%s <span class="badge %s">%s</span></h3>'
            '<div class="meta">%s &middot; %s</div>%s<div class="meta">exact <b>%s%%</b> &middot; non-text <b>%s%%</b> &middot; close <b>%s%%</b></div>%s%s%s%s%s%s%s</section>' % (
                r['status'], r['theme'], html.escape(key), html.escape(key), r['status'], STATUS_LABEL.get(r['status'], r['status']),
                html.escape(r['title']), html.escape(r['variantName']), size, _fmt(r.get('exactPct')), _fmt(r.get('nonTextPct')),
                _fmt(r.get('closePct')), picture, bar, regions, worst, fonts, probes,
                '<div class="meta">%s</div>' % html.escape(r.get('reason', '')) if r.get('reason') else ''))
    c = summary['counts']
    rows = ''.join('<tr><td><a href="#%s">%s</a></td><td>%s</td><td class="n">%s</td><td class="n">%s</td><td><span class="badge %s">%s</span></td></tr>' % (
        html.escape(r['key']), html.escape(r['key']), r['theme'], _fmt(r.get('exactPct')), _fmt(r.get('nonTextPct')), r['status'],
        STATUS_LABEL.get(r['status'], r['status'])) for r in summary['cases'])
    page = '<!doctype html><meta charset="utf-8"><title>dsh-flutter parity: %s</title><style>%s</style>' % (html.escape(summary['suite']), CSS)
    page += '<header><h1>dsh-flutter parity: %s</h1><p>%s</p><p>dsh %s &middot; Flutter %s</p></header><main>' % (
        html.escape(summary['suite']), html.escape(summary['notes']), html.escape(str(summary.get('dshCommit', ''))[:9]), html.escape(str(summary.get('flutterVersion', ''))))
    page += '<div class="stats">%s</div>' % ''.join('<div class="stat"><b>%s</b>%s</div>' % kv for kv in [
        (c['entries'], 'captures'), (c['same'], 'same'), (c['pass'], 'pass (exact >= %g%%)' % PASS),
        (c['geometryPass'], 'geometry pass (non-text >= %g%%)' % GEOMETRY_PASS), (c['fail'], 'fail'), (c['uncovered'], 'not covered'),
        (_fmt(summary['meanExactPct']) + '%', 'mean exact'), (_fmt(summary['meanNonTextPct']) + '%', 'mean non-text')])
    page += '<table><tr><th>case</th><th>theme</th><th class="n">exact %</th><th class="n">non-text %</th><th>status</th></tr>' + rows + '</table>'
    page += '<div class="filters">%s</div>' % ''.join('<button data-f="%s">%s</button>' % kv for kv in [
        ('all', 'all'), ('bad', 'problems'), ('fail', 'fail'), ('geometry-pass', 'geometry pass'), ('uncovered', 'not covered'), ('light', 'light'), ('dark', 'dark')])
    page += ''.join(cards) + '</main><script>%s</script>' % JS
    (site / 'index.html').write_text(page)
    return site / 'index.html'


def _load(path):
    try:
        return json.loads(pathlib.Path(path).read_text())
    except (OSError, ValueError):
        return None
