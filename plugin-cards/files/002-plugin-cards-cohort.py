#!/usr/bin/env python3
"""Capture one explicit real-source cohort and bind its complete output set."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'out'):
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ('cases', 'head', 'tree'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--count', type=int, required=True)
    args = parser.parse_args()
    repo, out = args.repo.resolve(), args.out.resolve()
    def identity():
        git = lambda *a: subprocess.check_output(['git', '-C', str(repo), *a], text=True).strip()
        if git('status', '--porcelain'):
            raise RuntimeError('Cohort capture requires a clean committed tree')
        return {'head': git('rev-parse', 'HEAD'), 'tree': git('rev-parse', 'HEAD^{tree}')}
    before = identity()
    if before != {'head': args.head, 'tree': args.tree} or out.exists():
        raise RuntimeError('Explicit identity differs or output exists')
    out.mkdir(parents=True)
    (out / 'identity-before.json').write_text(json.dumps(before, indent=2) + '\n')
    env = dict(os.environ, PARITY_EXT_ALL_THEMES='1', PARITY_EXT_OUT=str(out))
    with (out / 'run.log').open('w') as log:
        result = subprocess.run([sys.executable, 'tool/parity-ext/run', 'run', '--cases', args.cases,
                                 '--refresh-react', '--reference', 'native'], cwd=repo, env=env,
                                stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError('Capture failed; complete partial output retained')
    summary = json.loads((out / 'summary.json').read_text())
    plan = json.loads((out / 'flutter-plan.json').read_text())
    keys = {e['key'] for e in plan['entries']}
    if len(plan['entries']) != len(keys) or len(keys) != args.count or {r['key'] for r in summary['cases']} != keys:
        raise RuntimeError('Plan and actual complete cohort differ')
    hashes, meta_hashes = {}, {}
    pin = json.loads((repo / 'tool/design-system/sources.lock.json').read_text())['referenceCommit']
    for provider in ('react', 'flutter'):
        folder = out / 'visual-testing-results' / provider
        if {p.stem for p in folder.glob('*.png')} != keys:
            raise RuntimeError('Provider PNG set differs')
        hashes[provider], meta_hashes[provider] = {}, {}
        for key in sorted(keys):
            file = folder / (key + '.png')
            meta = folder / (key + '.metadata.json')
            data = json.loads(meta.read_text())
            if data.get('provider') != provider or data.get('captureKey') != key:
                raise RuntimeError('Provider metadata differs')
            if provider == 'react' and data.get('react', {}).get('dshCommit') != pin:
                raise RuntimeError('Reference pin differs')
            hashes[provider][key], meta_hashes[provider][key] = sha(file), sha(meta)
    after = identity()
    if before != after:
        raise RuntimeError('Tree changed during capture')
    receipt = {**before, 'captured': args.count, 'identityBefore': before, 'identityAfter': after,
               'cases': args.cases, 'sourcePngSha256': hashes['react'], 'flutterPngSha256': hashes['flutter'],
               'metadataSha256': meta_hashes, 'summarySha256': sha(out / 'summary.json'),
               'planSha256': sha(out / 'flutter-plan.json'), 'scriptSha256': sha(Path(__file__))}
    (out / 'capture-identity.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'head': args.head, 'tree': args.tree, 'captured': args.count}))


if __name__ == '__main__':
    main()
