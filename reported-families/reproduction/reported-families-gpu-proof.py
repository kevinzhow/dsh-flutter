"""Bind a real GPU replay to before/after build hashes and cleanup receipts.

Invoke only after sourcing the pinned env and receiving the main owner's
explicit ready signal. Output and app homes must be fresh; failed and previous
rounds are preserved rather than reused. This is a workspace evidence wrapper,
not product code.
"""
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys

ROOT = Path('[workspace]')
REPO = ROOT / 'scratch/whalee-reported-families'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expected-head', required=True)
    parser.add_argument('--expected-tree', required=True)
    parser.add_argument('--out', type=Path, default=REPO / 'build/native-reported-gpu-final')
    parser.add_argument('--home', type=Path, default=REPO / '.local/reported-native-home-final')
    args = parser.parse_args()
    out, home = args.out.resolve(), args.home.resolve()
    if out.exists() and any(out.iterdir()):
        raise SystemExit('Refusing to overwrite existing GPU evidence: ' + str(out))
    if home.exists():
        raise SystemExit('Refusing to overwrite an existing GPU app home: ' + str(home))
    build = REPO / '.local/reported-builds'
    if not (build / 'linux-fixture.ready').is_file():
        raise SystemExit('Fixture ready marker missing')
    app = build / 'linux-fixture/dsh_flutter'
    library = build / 'linux-fixture/lib/libapp.so'
    manifest_path = REPO / 'tool/parity-desktop/reported-families-cases.json'
    manifest = json.loads(manifest_path.read_text())

    def identity():
        return {
            'runtimeHead': (build / 'runtime-head.txt').read_text().strip(),
            'runtimeTree': (build / 'runtime-tree.txt').read_text().strip(),
            'executableSha256': sha(app),
            'applicationLibrarySha256': sha(library),
            'manifestSha256': sha(manifest_path),
        }

    before = identity()
    if before['runtimeHead'] != args.expected_head or before['runtimeTree'] != args.expected_tree:
        raise SystemExit('Fixture source differs from the explicitly signalled build')
    out.mkdir(parents=True, exist_ok=True)
    (out / 'runtime-before.json').write_text(json.dumps({'capturedAt': now(), **before}, indent=2) + '\n')
    (out / 'cases.json').write_bytes(manifest_path.read_bytes())
    env = dict(os.environ, REPORTED_GPU_OUT=str(out), REPORTED_GPU_HOME=str(home))
    started = now()
    completed = subprocess.run(['bash', str(ROOT / 'scripts/reported-families-gpu.sh')], env=env)
    finished = now()
    after = identity()
    receipts = []
    for case in manifest['cases']:
        folder = out / case['id']
        environment_file, pids_file = folder / 'environment.json', folder / 'pids.json'
        environment = json.loads(environment_file.read_text()) if environment_file.is_file() else {}
        pids = json.loads(pids_file.read_text()) if pids_file.is_file() else {}
        absence = {name: not Path('/proc', str(pid)).exists() for name, pid in pids.items()}
        inputs = Counter(k for step in case['app'] for k in step
                         if k in ('move', 'click', 'secondaryClick', 'drag', 'scroll', 'keys', 'text'))
        expected = [step['expect'] for step in case['app'] if 'expect' in step]
        actual = environment.get('captureAssertions', [])
        named = [step['capture'] for step in case['app'] if 'capture' in step]
        screenshots = [str((folder / (label + '.png')).relative_to(out)) for label in named]
        screenshots.append(case['id'] + '.png')
        receipts.append({
            'id': case['id'], 'size': [case['width'], case['height']],
            'theme': case['theme'], 'locale': case['locale'],
            'backend': environment.get('backend'), 'renderer': environment.get('renderer'),
            'appRenderDevices': environment.get('appRenderDevices', []),
            'appRenderer': environment.get('appRenderer', []),
            'inputCounts': dict(inputs), 'inputCount': sum(inputs.values()),
            'activationKeyInputCount': sum(v for k, v in inputs.items() if k != 'move'),
            'assertionCount': len(expected), 'passedAssertions': sum(a.get('passed') is True for a in actual),
            'assertionsMatchManifest': len(actual) == len(expected) and all(
                {k: a.get(k) for k in spec} == spec and a.get('passed') is True
                for a, spec in zip(actual, expected)),
            'namedCaptureCount': len(named), 'screenshotCount': len(screenshots),
            'screenshots': screenshots,
            'allScreenshotsExist': all((out / name).is_file() for name in screenshots),
            'recordedPids': pids, 'recordedPidAbsence': absence,
            'ownedPidsAbsent': bool(pids) and all(absence.values()),
        })
    leftover = []
    for process in Path('/proc').iterdir():
        if not process.name.isdigit():
            continue
        try:
            if (process / 'exe').resolve() == app.resolve():
                leftover.append(int(process.name))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    passed = completed.returncode == 0 and before == after and not leftover and all(
        c['assertionsMatchManifest'] and c['allScreenshotsExist'] and c['ownedPidsAbsent']
        and c['backend'] == 'native-wayland' and '/dev/dri/renderD128' in c['appRenderDevices']
        for c in receipts)
    receipt = {
        'schema': 'whalee-reported-gpu-runtime/1', 'status': 'passed' if passed else 'failed',
        'startedAt': started, 'finishedAt': finished, 'exitCode': completed.returncode, **before,
        'binaryBefore': before, 'binaryAfter': after, 'binaryUnchanged': before == after,
        'cases': receipts,
        'totalAssertions': sum(c['assertionCount'] for c in receipts),
        'totalPassedAssertions': sum(c['passedAssertions'] for c in receipts),
        'totalScreenshots': sum(c['screenshotCount'] for c in receipts),
        'ownedFixturePidsRemaining': leftover,
        'ownedPidsAbsent': not leftover and all(c['ownedPidsAbsent'] for c in receipts),
    }
    (out / 'runtime.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({key: receipt[key] for key in (
        'status', 'runtimeHead', 'runtimeTree', 'executableSha256', 'applicationLibrarySha256',
        'binaryUnchanged', 'totalAssertions', 'totalPassedAssertions', 'totalScreenshots', 'ownedPidsAbsent')}))
    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())
