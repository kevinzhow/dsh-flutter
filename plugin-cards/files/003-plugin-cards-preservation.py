#!/usr/bin/env python3
"""Capture unchanged reference plans with an explicit clean PluginCard tree.

Run with the absolute pinned pr16 environment. References and comparison
semantics remain unchanged. This records equality and differences; neither is
inferred from an overall process exit code.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageChops


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'previous', 'out'):
        parser.add_argument('--' + name, type=Path, required=True)
    parser.add_argument('--expected-head', required=True)
    parser.add_argument('--expected-tree', required=True)
    args = parser.parse_args()
    repo, previous, out = (getattr(args, k).resolve() for k in ('repo', 'previous', 'out'))
    def identity():
        git = lambda *a: subprocess.check_output(['git', '-C', str(repo), *a], text=True).strip()
        if git('status', '--porcelain'):
            raise RuntimeError('Capture requires a clean committed tree')
        return {'head': git('rev-parse', 'HEAD'), 'tree': git('rev-parse', 'HEAD^{tree}')}
    before = identity()
    if before != {'head': args.expected_head, 'tree': args.expected_tree} or out.exists():
        raise RuntimeError('Explicit identity differs or output already exists')
    sys.path.insert(0, str(repo / 'tool'))
    from parity_lib import pipeline, vt, flutter
    import parity_case_map
    parity_case_map.generate()
    out.mkdir(parents=True)
    vt.setup(out / 'vt-setup.log')
    receipts = []
    for name, count in [('parity-header-shadows-final', 108), ('parity-header-shadows-regression', 96)]:
        old = previous / name
        current = out / name
        current.mkdir()
        results = current / 'visual-testing-results'
        shutil.copytree(old / 'visual-testing-results/react', results / 'react')
        (results / 'flutter').mkdir()
        plan_file = old / 'flutter-plan.json'
        plan = json.loads(plan_file.read_text())
        if len(plan['entries']) != count:
            raise RuntimeError('Retained reference plan count differs')
        plan.update(resultsDir=str(results), fontsManifest=str(repo / 'tool/parity-fonts/manifest.json'),
                    fixturesDirs=[str(repo / 'tool/parity-ext/fixtures')])
        plan['coverage'] = [{'id': e['key'], 'kind': e['case']['kind']} for e in plan['entries']]
        plan_path = current / 'flutter-plan.json'
        plan_path.write_text(json.dumps(plan, indent=2) + '\n')
        kinds = {e['case']['kind'] for e in plan['entries']}
        packages = set()
        for group in ('apps', 'features', 'packages', 'tool'):
            for case in (repo / group).glob('*/test/parity/cases/*.dart'):
                contents = case.read_text()
                if any(repr(kind) in contents or ('"' + kind + '"') in contents for kind in kinds):
                    packages.add(case.parent.parent.parent.parent)
        if not packages:
            raise RuntimeError('No actual case packages selected')
        for package in sorted(packages):
            print('capture', name, package.name, flush=True)
            env = dict(os.environ, PARITY_PLAN=str(plan_path), PARITY_PACKAGE=package.name)
            with (current / ('flutter-capture.' + package.name + '.log')).open('w') as log:
                subprocess.run(['nice', '-n', '15', 'flutter', 'test', 'test/parity/parity_capture_test.dart',
                                '--reporter', 'expanded', '-j', '2'], cwd=package, env=env,
                               stdout=log, stderr=subprocess.STDOUT, check=True)
        flutter.merge_coverage(results)
        images = list((results / 'flutter').glob('*.png'))
        if len(images) != count:
            raise RuntimeError('Actual Flutter output count differs')
        rows = pipeline.compare(plan['entries'], current, results, current / 'cli.log')
        summary = pipeline.summarize(rows, json.loads((results / 'flutter-case-map.json').read_text()),
                                     'parity-ext', 'PluginCard candidate; immutable original references retained.')
        (current / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        comparisons = []
        for provider in ('react', 'flutter'):
            for entry in plan['entries']:
                key = entry['key']
                a = old / 'visual-testing-results' / provider / (key + '.png')
                b = results / provider / (key + '.png')
                with Image.open(a) as old_image, Image.open(b) as new_image:
                    same_size = old_image.size == new_image.size
                    exact = same_size and not any(ImageChops.difference(
                        old_image.convert('RGBA'), new_image.convert('RGBA')).getextrema()[i][1]
                        for i in range(4))
                comparisons.append({'provider': provider, 'key': key, 'dimensionsEqual': same_size,
                                    'rgbaEqual': exact, 'oldSha256': sha(a), 'newSha256': sha(b)})
        receipt = {'name': name, 'captured': count, 'sourcePlanSha256': sha(plan_file),
                   'comparisons': comparisons, 'rgbaEqual': sum(r['rgbaEqual'] for r in comparisons)}
        (current / 'capture-identity.json').write_text(json.dumps({**before, **receipt}, indent=2) + '\n')
        receipts.append(receipt)
        print('completed', name, count, 'unchanged', receipt['rgbaEqual'], '/', len(comparisons), flush=True)
    if identity() != before:
        raise RuntimeError('Source identity changed during capture')
    receipt = {'schema': 'whalee-plugin-cards-preservation/1', **before,
               'scriptSha256': sha(Path(__file__)), 'plans': receipts}
    (out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')


if __name__ == '__main__':
    main()
