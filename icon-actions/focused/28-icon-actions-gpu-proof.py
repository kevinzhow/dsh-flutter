"""Run the canonical icon-action route fixture with explicit artifact proof.

Source the pinned workspace environment before invocation. This wrapper has no
implicit product/build/output paths and never invokes the reported-family
wrapper. Existing output and application homes are preserved.
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


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True, type=Path)
    parser.add_argument('--builds', required=True, type=Path)
    parser.add_argument('--manifest', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--app-home', required=True, type=Path)
    parser.add_argument('--expected-head', required=True)
    parser.add_argument('--expected-tree', required=True)
    parser.add_argument('--expected-assertions', required=True, type=int)
    parser.add_argument('--manifest-sha256', required=True)
    args = parser.parse_args()
    repo, builds, manifest_path, out, app_home = (
        path.resolve() for path in
        (args.repo, args.builds, args.manifest, args.out, args.app_home))
    if out.exists() or app_home.exists():
        raise SystemExit('GPU output and application home must both be fresh')
    if not (builds / 'linux-fixture.ready').is_file():
        raise SystemExit('Current fixture ready marker missing')
    app = builds / 'linux-fixture/dsh_flutter'
    library = builds / 'linux-fixture/lib/libapp.so'
    capture = repo / 'tool/parity-desktop/gpu_capture.py'
    manifest = json.loads(manifest_path.read_text())
    if sum('expect' in step for case in manifest['cases']
           for step in case['app']) != args.expected_assertions:
        raise SystemExit('The explicitly supplied assertion count differs')

    def identity():
        return {
            'runtimeHead': (builds / 'runtime-head.txt').read_text().strip(),
            'runtimeTree': (builds / 'runtime-tree.txt').read_text().strip(),
            'executableSha256': sha(app),
            'applicationLibrarySha256': sha(library),
            'manifestSha256': sha(manifest_path),
        }

    before = identity()
    if (before['runtimeHead'] != args.expected_head or
            before['runtimeTree'] != args.expected_tree):
        raise SystemExit('Build identity differs from the explicitly ready runtime')
    repo_head = subprocess.check_output(
        ['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
    repo_tree = subprocess.check_output(
        ['git', '-C', str(repo), 'rev-parse', 'HEAD^{tree}'], text=True).strip()
    if repo_head != args.expected_head or repo_tree != args.expected_tree:
        raise SystemExit('Repository differs from the explicitly ready runtime')
    if before['manifestSha256'] != args.manifest_sha256:
        raise SystemExit('Authorized input/assertion manifest changed')

    out.mkdir(parents=True)
    (out / 'runtime-before.json').write_text(
        json.dumps({'capturedAt': now(), **before}, indent=2) + '\n')
    (out / 'cases.json').write_bytes(manifest_path.read_bytes())
    env = dict(os.environ)
    env.pop('PARITY_DESKTOP_HOST_LOG', None)
    env.update(
        XDG_RUNTIME_DIR=f'/run/user/{os.getuid()}',
        PARITY_DESKTOP_APP=str(app),
        PARITY_DESKTOP_HOME=str(app_home),
        PYTHONUNBUFFERED='1',
    )
    started = now()
    completed = subprocess.run(
        [sys.executable, str(capture), str(out), str(manifest_path)],
        cwd=repo, env=env)
    finished = now()
    after = identity()
    cases = []
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
        cases.append({
            'id': case['id'], 'size': [case['width'], case['height']],
            'theme': case['theme'], 'locale': case['locale'],
            'backend': environment.get('backend'), 'renderer': environment.get('renderer'),
            'appRenderDevices': environment.get('appRenderDevices', []),
            'appRenderer': environment.get('appRenderer', []),
            'inputCounts': dict(inputs), 'inputCount': sum(inputs.values()),
            'activationKeyInputCount': sum(v for k, v in inputs.items() if k != 'move'),
            'assertionCount': len(expected),
            'passedAssertions': sum(a.get('passed') is True for a in actual),
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
        for c in cases)
    receipt = {
        'schema': 'whalee-icon-actions-gpu-runtime/1',
        'status': 'passed' if passed else 'failed',
        'startedAt': started, 'finishedAt': finished, 'exitCode': completed.returncode,
        **before, 'binaryBefore': before, 'binaryAfter': after,
        'binaryUnchanged': before == after, 'cases': cases,
        'proofWrapperSha256': sha(Path(__file__)),
        'totalAssertions': sum(c['assertionCount'] for c in cases),
        'totalPassedAssertions': sum(c['passedAssertions'] for c in cases),
        'totalScreenshots': sum(c['screenshotCount'] for c in cases),
        'ownedFixturePidsRemaining': leftover,
        'ownedPidsAbsent': not leftover and all(c['ownedPidsAbsent'] for c in cases),
    }
    (out / 'runtime.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({key: receipt[key] for key in (
        'status', 'runtimeHead', 'runtimeTree', 'executableSha256', 'applicationLibrarySha256',
        'binaryUnchanged', 'totalAssertions', 'totalPassedAssertions', 'totalScreenshots', 'ownedPidsAbsent')}))
    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())
