"""Capture the current runtime against the retained exact DSH reference pairs.

Run after sourcing pr16-env.sh. Uses explicit current paths, fresh outputs,
the unchanged comparison pipeline and all requested capture providers.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT / 'scratch/whalee-source-shadows'
PREVIOUS = ROOT / 'scratch/whalee-menu-compositing/build'
sys.path.insert(0, str(REPO / 'tool'))
from parity_lib import pipeline, vt, flutter
import parity_case_map


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--visual-out', type=Path, default=REPO / 'build/parity-header-shadows-final')
    parser.add_argument('--regression-out', type=Path, default=REPO / 'build/parity-header-shadows-regression')
    args = parser.parse_args()
    parity_case_map.generate()
    vt.setup(REPO / '.local/header-shadows-vt-setup.log')
    for old_name, out, count in [
        ('parity-menu-compositing-final', args.visual_out.resolve(), 108),
        ('parity-menu-compositing-preservation', args.regression_out.resolve(), 96),
    ]:
        old = PREVIOUS / old_name
        new_name = out.name
        out.mkdir()
        results = out / 'visual-testing-results'
        shutil.copytree(old / 'visual-testing-results/react', results / 'react')
        (results / 'flutter').mkdir()
        plan = json.loads((old / 'flutter-plan.json').read_text())
        assert len(plan['entries']) == count
        plan.update(resultsDir=str(results), fontsManifest=str(REPO / 'tool/parity-fonts/manifest.json'),
                    fixturesDirs=[str(REPO / 'tool/parity-ext/fixtures')])
        plan['coverage'] = [{'id': e['key'], 'kind': e['case']['kind']} for e in plan['entries']]
        plan_path = out / 'flutter-plan.json'
        plan_path.write_text(json.dumps(plan, indent=2) + '\n')
        kinds = {e['case']['kind'] for e in plan['entries']}
        packages = set()
        for group in ('apps', 'features', 'packages', 'tool'):
            for case in (REPO / group).glob('*/test/parity/cases/*.dart'):
                contents = case.read_text()
                if any(repr(kind) in contents or ('"' + kind + '"') in contents for kind in kinds):
                    packages.add(case.parent.parent.parent.parent)
        assert packages
        for package in sorted(packages):
            print('capture', new_name, package.name, flush=True)
            env = dict(os.environ, PARITY_PLAN=str(plan_path), PARITY_PACKAGE=package.name)
            with (out / ('flutter-capture.' + package.name + '.log')).open('w') as log:
                subprocess.run(['nice', '-n', '15', 'flutter', 'test', 'test/parity/parity_capture_test.dart',
                                '--reporter', 'expanded', '-j', '2'], cwd=package, env=env,
                               stdout=log, stderr=subprocess.STDOUT, check=True)
        flutter.merge_coverage(results)
        assert len(list((results / 'flutter').glob('*.png'))) == count
        rows = pipeline.compare(plan['entries'], out, results, out / 'cli.log')
        summary = pipeline.summarize(rows, json.loads((results / 'flutter-case-map.json').read_text()),
                                     'parity-ext', 'Current source-shadow translation; original DSH references retained.')
        (out / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        identity = {
            'headAtCompletion': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=REPO, text=True).strip(),
            'shadowSourceSha256': sha(REPO / 'packages/dsh_ui/lib/src/dsh_shadow_box.dart'),
            'sourcePlanSha256': sha(old / 'flutter-plan.json'),
            'sourcePngSha256': {e['key']: sha(results / 'react' / (e['key'] + '.png')) for e in plan['entries']},
            'captured': count,
        }
        (out / 'capture-identity.json').write_text(json.dumps(identity, indent=2) + '\n')
        print('completed', new_name, count, flush=True)


if __name__ == '__main__':
    main()
