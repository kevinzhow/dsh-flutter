#!/usr/bin/env python3
"""Capture sixteen actual PluginManager screens on one explicit clean tree."""
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
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--expected-head', required=True)
    parser.add_argument('--expected-tree', required=True)
    args = parser.parse_args()
    repo, out = args.repo.resolve(), args.out.resolve()
    def identity():
        git = lambda *a: subprocess.check_output(['git', '-C', str(repo), *a], text=True).strip()
        if git('status', '--porcelain'):
            raise RuntimeError('Manager capture requires a clean committed tree')
        return {'head': git('rev-parse', 'HEAD'), 'tree': git('rev-parse', 'HEAD^{tree}')}
    before = identity()
    if before != {'head': args.expected_head, 'tree': args.expected_tree} or out.exists():
        raise RuntimeError('Capture identity differs or output exists')
    out.mkdir(parents=True)
    (out / 'identity-before.json').write_text(json.dumps(before, indent=2) + '\n')
    env = dict(os.environ, PARITY_EXT_ALL_THEMES='1', PARITY_EXT_OUT=str(out))
    with (out / 'run.log').open('w') as log:
        result = subprocess.run([sys.executable, 'tool/parity-ext/run', 'run', '--cases',
                                 'components.icon-actions.manager-refresh-*', '--refresh-react',
                                 '--reference', 'native'], cwd=repo, env=env,
                                stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError('Manager capture failed; logs and partial results preserved')
    expected = {f'components.icon-actions.manager-refresh-{state}-{device}-{locale}.{theme}'
                for state in ('idle', 'hover') for device in ('desktop', 'phone')
                for locale in ('en', 'zh') for theme in ('light', 'dark')}
    summary = json.loads((out / 'summary.json').read_text())
    if len(summary['cases']) != 16 or {r['key'] for r in summary['cases']} != expected:
        raise RuntimeError('Requested sixteen real-screen cases differ')
    pngs, metadata = {}, {}
    for provider in ('react', 'flutter'):
        folder = out / 'visual-testing-results' / provider
        if {p.stem for p in folder.glob('*.png')} != expected:
            raise RuntimeError('Provider output set differs from the real-screen plan')
        pngs[provider], metadata[provider] = {}, {}
        for key in sorted(expected):
            pngs[provider][key] = sha(folder / (key + '.png'))
            meta = folder / (key + '.metadata.json')
            data = json.loads(meta.read_text())
            if data.get('provider') != provider or data.get('captureKey') != key:
                raise RuntimeError('Provider metadata differs')
            if provider == 'react' and data.get('react', {}).get('dshCommit') != '687f282e8625c6b8d11ff58211a90524be2e4317':
                raise RuntimeError('Actual source reference pin differs')
            metadata[provider][key] = sha(meta)
    after = identity()
    if after != before:
        raise RuntimeError('Tree changed during capture')
    receipt = {**before, 'captured': 16, 'identityBefore': before, 'identityAfter': after,
               'sourcePngSha256': pngs['react'], 'flutterPngSha256': pngs['flutter'],
               'metadataSha256': metadata, 'scriptSha256': sha(Path(__file__)),
               'summarySha256': sha(out / 'summary.json')}
    (out / 'capture-identity.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'head': before['head'], 'tree': before['tree'], 'captured': 16}))


if __name__ == '__main__':
    main()
