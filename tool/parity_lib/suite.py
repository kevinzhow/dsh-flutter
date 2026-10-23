"""The `run / summary / publish` commands shared by tool/parity (core suite) and tool/parity-ext/run."""
from __future__ import annotations

import argparse
import datetime
import json
import os
import pathlib
import shutil
import sys
import urllib.request

from . import env, fonts, flutter, manifest as mf, pipeline, react, report


class Suite:
    """Configuration of one suite."""

    def __init__(self, name, out_default, fixtures_dirs, host_dirs, load, publish_name):
        self.name = name
        self.out_default = out_default
        self.fixtures_dirs = fixtures_dirs   # directories with fixtures/*.json
        self.host_dirs = host_dirs           # extra host source directories (cache key)
        self.load = load                     # load(out) -> manifest dict (validated)
        self.publish_name = publish_name

    def out(self, env_var):
        return pathlib.Path(os.environ.get(env_var, str(self.out_default)))


def fixtures_hash(dirs):
    return env.tree_hash(*[d for d in dirs if pathlib.Path(d).exists()])


def add_run_arguments(ap):
    ap.add_argument('--cases', default='', help='comma list of capture keys / case ids / globs (`components.button.*`)')
    ap.add_argument('--refresh-react', action='store_true', help='ignore and overwrite the React cache')
    ap.add_argument('--skip-react', action='store_true', help='reuse results/react from an earlier run')
    ap.add_argument('--skip-flutter', action='store_true', help='reuse results/flutter from an earlier run')


def cmd_run(suite, args, out_env):
    out = suite.out(out_env)
    out.mkdir(parents=True, exist_ok=True)
    problems = fonts.check()
    if problems:
        sys.exit('parity fonts: ' + '; '.join(problems))
    man = suite.load(out)
    entries = mf.select(mf.entries(man), args.cases)
    if not entries:
        sys.exit('no capture matches --cases %r (manifest has %d)' % (args.cases, len(mf.entries(man))))
    results = out / 'visual-testing-results'
    for provider in mf.PROVIDERS:
        (results / provider).mkdir(parents=True, exist_ok=True)
    if not args.skip_flutter:  # stale files of the selected keys must not pass for fresh captures
        for e in entries:
            for ext in ('png', 'metadata.json'):
                (results / 'flutter' / ('%s.%s' % (e['key'], ext))).unlink(missing_ok=True)
    cache = env.default_cache()
    if not args.skip_react:
        status = react.capture(entries, out, results, suite.host_dirs, fixtures_hash(suite.fixtures_dirs), args.refresh_react, cache)
        print('react: %s' % json.dumps({s: sum(v == s for v in status.values()) for s in ('cache', 'captured', 'failed')}))
    coverage_all = [{'id': c['id'], 'kind': c['kind']} for c in man['cases'] if not mf.is_skipped(c)]
    if not args.skip_flutter:
        flutter.capture(entries, coverage_all, out, results, suite.fixtures_dirs,
                        {'suite': suite.name, 'dshCommit': env.dsh_commit()})
    coverage = pipeline.read_json(results / 'flutter-case-map.json', {})
    rows = [pipeline.compare_entry(e, results, out) for e in entries]
    summary = pipeline.summarize(rows, coverage, suite.name, notes_for(suite, man))
    summary.update({'dshCommit': env.dsh_commit(), 'flutterVersion': flutter.flutter_version(),
                    'generatedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds')})
    (out / 'summary.json').write_text(json.dumps(summary, indent=1) + '\n')
    (out / 'summary.md').write_text(report.summary_markdown(summary))
    site = report.write_site(summary, out, results)
    print(report.summary_markdown(summary))
    print('report: %s' % site)
    return 0


def notes_for(suite, man):
    from . import sampling
    base = 'Suite %s: %d cases in the manifest.' % (suite.name, len(man['cases']))
    return base + (' ' + sampling.sampled_themes_note() if suite.name == 'parity-ext' else '')


def cmd_summary(suite, args, out_env):
    path = suite.out(out_env) / 'summary.md'
    if not path.is_file():
        sys.exit('%s not found; run the suite first' % path)
    sys.stdout.write(path.read_text())
    return 0


def cmd_publish(suite, args, out_env):
    out = suite.out(out_env)
    site = out / 'site'
    root = os.environ.get('PARITY_REPORTS_ROOT')
    if not root:
        sys.exit('set PARITY_REPORTS_ROOT to the directory reports are published under')
    if not (site / 'index.html').is_file():
        sys.exit('%s has no index.html; run the suite first' % site)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    target = pathlib.Path(root) / suite.publish_name / stamp
    shutil.copytree(site, target)
    latest = target.parent / 'latest'
    if latest.is_symlink() or latest.exists():
        latest.unlink()
    latest.symlink_to(stamp)
    print('published %s' % target)
    base = os.environ.get('PARITY_BASE_URL')
    if base and not args.no_verify:
        url = '%s/%s/%s/index.html' % (base.rstrip('/'), suite.publish_name, stamp)
        with urllib.request.urlopen(url, timeout=15) as r:
            if r.status != 200:
                sys.exit('verify failed: %s -> %d' % (url, r.status))
        print('verified %s' % url)
    return 0
