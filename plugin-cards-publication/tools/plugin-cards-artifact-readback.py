#!/usr/bin/env python3
"""Download every published Card report file through the official Raft CLI."""
import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('report', 'fresh-read', 'out'):
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ('artifact', 'version'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    assert not args.out.exists()
    report = json.loads((args.report / 'build-receipt.json').read_text())
    read = json.loads(args.fresh_read.read_text())
    assert read['ok'] is True and read['data']['status'] == 200
    value = read['data']['result']
    assert value['artifact']['id'] == args.artifact
    assert value['version']['id'] == args.version
    expected = {r['path']: {'sha256': r['sha256'], 'size': r['bytes']} for r in report['files']}
    actual = {r['path']: {'sha256': r['sha256'], 'size': r['size']} for r in value['version']['files']}
    assert len(expected) == len(report['files']) == len(actual) == 225
    assert actual == expected and value['version']['size'] == report['rawVersionBytes']
    for name, row in expected.items():
        assert not Path(name).is_absolute() and '..' not in Path(name).parts
        assert sha(args.report / name) == row['sha256']
    args.out.mkdir(parents=True)

    def download(item):
        name, row = item
        target = args.out / name
        target.parent.mkdir(parents=True, exist_ok=True)
        payload = json.dumps({'artifact': args.artifact, 'version': args.version, 'path': name})
        command = ['raft', 'integration', 'invoke', '--service', 'artifact-share', '--action',
                   'download_artifact_file', '--data-json', payload, '--output', str(target), '--json']
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=120)
        if result.returncode:
            raise RuntimeError('Official download failed for ' + name + ': exit ' + str(result.returncode))
        response = json.loads(result.stdout)
        assert response['ok'] is True and response['data']['status'] == 200
        assert target.is_file() and not target.is_symlink()
        assert target.stat().st_size == row['size'] and sha(target) == row['sha256'], name
        return {'path': name, **row, 'downloadedSha256': sha(target), 'status': 200, 'exactBytes': True}

    rows = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        futures = [pool.submit(download, item) for item in expected.items()]
        for future in concurrent.futures.as_completed(futures):
            rows.append(future.result())
            if len(rows) % 16 == 0:
                print(json.dumps({'downloaded': len(rows), 'total': 225}), flush=True)
    assert len(rows) == 225 and all(sha(args.out / r['path']) == r['sha256'] for r in rows)
    receipt = {'schema': 'whalee-plugin-cards-server-readback/1', 'artifact': args.artifact,
               'version': args.version, 'head': report['head'], 'tree': report['tree'],
               'reportBuildReceiptSha256': sha(args.report / 'build-receipt.json'),
               'freshReadReceiptSha256': sha(args.fresh_read), 'files': sorted(rows, key=lambda r: r['path']),
               'all225DownloadedThroughRaftCLI': True, 'exactBytes': True,
               'totalBytes': sum(r['size'] for r in rows), 'scriptSha256': sha(Path(__file__))}
    (args.out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'downloaded': len(rows), 'bytes': receipt['totalBytes'], 'exactBytes': True}), flush=True)


if __name__ == '__main__':
    main()
