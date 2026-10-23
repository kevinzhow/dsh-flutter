"""Flutter provider driver: runs tool/parity_flutter's capture test with the run plan."""
from __future__ import annotations

import json
import subprocess
import sys

from . import env


def capture_packages():
    """Packages that host a capture entry point: the harness package itself plus any app, feature or package
    with `test/parity/parity_capture_test.dart` (screens plug in there, see docs/parity.md)."""
    found = [env.FLUTTER_PKG]
    for group in ('apps', 'features', 'packages'):
        found += sorted(p.parents[2] for p in (env.ROOT / group).glob('*/test/parity/parity_capture_test.dart'))
    return found


def merge_coverage(results):
    """results/flutter-case-map.json = union of the per-package maps; `mapped` wins over any gap."""
    merged = {}
    for path in sorted(results.glob('flutter-case-map.*.json')):
        for case_id, info in json.loads(path.read_text()).items():
            if case_id not in merged or (info.get('status') == 'mapped' and merged[case_id].get('status') != 'mapped'):
                merged[case_id] = info
    (results / 'flutter-case-map.json').write_text(json.dumps(merged, indent=2) + '\n')
    return merged


def capture(entries, coverage, out, results, fixtures_dirs, run_info):
    """Write results/flutter/* with every capture package; returns the worst exit code."""
    sys.path.insert(0, str(env.TOOL))
    import parity_case_map
    parity_case_map.generate()
    for stale in results.glob('flutter-case-map*.json'):
        stale.unlink()
    plan = {
        'resultsDir': str(results), 'fontsManifest': str(env.FONTS / 'manifest.json'),
        'fixturesDirs': [str(d) for d in fixtures_dirs], 'runInfo': run_info,
        'entries': entries, 'coverage': coverage,
    }
    plan_path = out / 'flutter-plan.json'
    plan_path.write_text(json.dumps(plan, indent=1))
    worst = 0
    for pkg in capture_packages():
        log = out / ('flutter-capture.%s.log' % pkg.name)
        cmd = ['nice', '-n', '15', 'flutter', 'test', 'test/parity/parity_capture_test.dart', '--reporter', 'compact', '-j', '2']
        e = env.flutter_env()
        e.update({'PARITY_PLAN': str(plan_path), 'PARITY_FONTS_MANIFEST': str(env.FONTS / 'manifest.json'),
                  'PARITY_PACKAGE': pkg.name})
        print('+', ' '.join(cmd), '(%s)' % pkg.relative_to(env.ROOT), flush=True)
        with open(log, 'w') as sink:
            r = subprocess.run(cmd, cwd=pkg, env=e, stdout=sink, stderr=subprocess.STDOUT)
        if r.returncode != 0:
            print('flutter capture in %s exited %d; see %s' % (pkg.name, r.returncode, log), file=sys.stderr)
        worst = max(worst, r.returncode)
    merge_coverage(results)
    return worst


def flutter_version():
    r = subprocess.run(['flutter', '--version', '--machine'], env=env.flutter_env(), capture_output=True, text=True)
    try:
        return json.loads(r.stdout).get('frameworkVersion')
    except ValueError:
        return None
