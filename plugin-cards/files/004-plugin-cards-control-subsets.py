#!/usr/bin/env python3
"""Split completed Tag/Switch captures without rerendering or altering originals."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--parent', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    parent, out = args.parent.resolve(), args.out.absolute()
    assert not out.exists()
    identity = json.loads((parent / 'capture-identity.json').read_text())
    plan = json.loads((parent / 'flutter-plan.json').read_text())
    summary = json.loads((parent / 'summary.json').read_text())
    assert identity['captured'] == len(plan['entries']) == len(summary['cases']) == 104
    assert identity['summarySha256'] == sha(parent / 'summary.json')
    assert identity['planSha256'] == sha(parent / 'flutter-plan.json')
    all_keys = set()
    for name, count in [('tag', 56), ('switch', 48)]:
        entries = [e for e in plan['entries'] if e['key'].startswith('components.' + name + '-family.')]
        keys = {e['key'] for e in entries}
        rows = [r for r in summary['cases'] if r['key'] in keys]
        assert len(keys) == len(entries) == len(rows) == count and not (all_keys & keys)
        all_keys |= keys
        target = out / name
        target.mkdir(parents=True)
        subset_plan = {**plan, 'entries': entries}
        subset_summary = {**summary, 'cases': rows, 'notes': 'Unmodified subset of the parent capture; see capture-identity.json.'}
        # These aggregate fields are derived from retained rows; the metric rows
        # and every source/Flutter PNG and metadata file remain byte-identical.
        subset_summary['counts'] = {**summary['counts'], 'entries': count, 'compared': count,
                                   'same': sum(r['status'] == 'same' for r in rows),
                                   'strict': sum(r['status'] in ('same', 'pass') for r in rows),
                                   'pass': sum(r['status'] in ('same', 'pass', 'basic-pass') for r in rows),
                                   'geometryPass': sum(r['status'] in ('same', 'pass', 'basic-pass', 'geometry-pass') for r in rows),
                                   'fail': sum(r['status'] == 'fail' for r in rows), 'missing': 0, 'uncovered': 0}
        for field in ('PixelPerfectPct', 'RgbPct', 'NonTextPct'):
            subset_summary['mean' + field] = round(sum(r[field[0].lower() + field[1:]] for r in rows) / count, 3)
        for file, value in [('flutter-plan.json', subset_plan), ('summary.json', subset_summary)]:
            (target / file).write_text(json.dumps(value, indent=2) + '\n')
        png_hashes, metadata_hashes = {}, {}
        for provider, identity_field in [('react', 'sourcePngSha256'), ('flutter', 'flutterPngSha256')]:
            png_hashes[provider], metadata_hashes[provider] = {}, {}
            for key in sorted(keys):
                for suffix in ('.png', '.metadata.json'):
                    relative = Path('visual-testing-results') / provider / (key + suffix)
                    source, dest = parent / relative, target / relative
                    expected = identity[identity_field][key] if suffix == '.png' else identity['metadataSha256'][provider][key]
                    assert sha(source) == expected
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(source, dest)
                    assert sha(source) == sha(dest)
                    (png_hashes if suffix == '.png' else metadata_hashes)[provider][key] = expected
        receipt = {key: identity[key] for key in ('head', 'tree', 'identityBefore', 'identityAfter')}
        receipt.update(captured=count, derivedFrom=str(parent), parentCaptureHashes={
            name: sha(parent / name) for name in ('summary.json', 'flutter-plan.json', 'capture-identity.json')},
            sourcePngSha256=png_hashes['react'], flutterPngSha256=png_hashes['flutter'],
            metadataSha256=metadata_hashes, summarySha256=sha(target / 'summary.json'),
            planSha256=sha(target / 'flutter-plan.json'), scriptSha256=sha(Path(__file__)), rerendered=False)
        (target / 'capture-identity.json').write_text(json.dumps(receipt, indent=2) + '\n')
    assert all_keys == {e['key'] for e in plan['entries']}
    print(json.dumps({'parent': str(parent), 'out': str(out), 'tag': 56, 'switch': 48, 'originalBytesIdentical': True}))


if __name__ == '__main__':
    main()
