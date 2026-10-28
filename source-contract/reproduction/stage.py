#!/usr/bin/env python3
"""Stage completed source-contract evidence; no network, Git mutation or publish."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT / 'scratch/whalee-design-system-contract'
DEST = ROOT / 'scratch/whalee-menu-sticky-evidence/source-contract'
BASE = 'ac8d066aa10802679e5e7c3c1d897c1bea613981'
CHECKS = {'check-deps', 'tool-tests', 'codegen', 'theme-pack', 'design-system', 'i18n',
          'icons', 'vector', 'parity', 'capability', 'format', 'analyze', 'tests'}
SENSITIVE = re.compile(r'-----BEGIN [^-\n]*PRIVATE KEY-----|\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-(?:proj-)?[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16})\b|\bBearer\s+[A-Za-z0-9._=-]{12,}', re.I)
HOME_PATH = re.compile(r'(?<![A-Za-z0-9_.])/(?:home|Users)/[^\s"\'<>]+|(?<![A-Za-z0-9_.])/root(?:/[^\s"\'<>]*)?(?=$|[\s"\'<>])')


def require(ok, message):
    if not ok:
        raise ValueError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(*args):
    return subprocess.check_output(['git', *args], cwd=REPO, text=True).strip()


def sanitize(text):
    require(not SENSITIVE.search(text), 'credential-shaped text in evidence')
    text = text.replace(str(ROOT), '[workspace]')
    text = HOME_PATH.sub('[home-path]', text)
    return re.sub(r'/run/user/\d+(?:/[^\s"\'<>]*)?', '[runtime-path]', text)


def source_paths(value):
    if isinstance(value, dict):
        if 'path' in value and 'sha256' in value and not value['path'].startswith('tool/'):
            yield value['path'], value['sha256']
        for child in value.values():
            yield from source_paths(child)
    elif isinstance(value, list):
        for child in value:
            yield from source_paths(child)


def main():
    require(not DEST.exists(), 'preserve existing evidence staging')
    require(not git('status', '--porcelain'), 'final source worktree must be clean')
    head, tree = git('rev-parse', 'HEAD'), git('rev-parse', 'HEAD^{tree}')
    require(not git('diff', '--name-only', BASE, head, '--', 'apps', 'features', 'packages'),
            'tool-only contract unexpectedly changes runtime sources')
    full = json.loads((REPO / '.local/source-contract-full.json').read_text())
    require(full['headTree'] == tree and full['fast'] is False
            and set(full['results']) == CHECKS
            and all(row['state'] == 'ok' for row in full['results'].values()),
            'exact final-tree all-thirteen checks must finish without skips')
    release = json.loads((REPO / '.local/preflight/release-inputs.json').read_text())
    ledger = json.loads((REPO / 'tool/design-system/source-inventory.generated.json').read_text())
    require(release['allPassed'] and release['verificationInputsUnchanged'], 'release reconstruction incomplete')
    for key, name in [('sourceLockSha256', 'sources.lock.json'), ('sourceInventorySha256', 'source-inventory.generated.json'),
                      ('verificationToolSha256', 'verify_release_inputs.py'), ('publishedVerifierSha256', 'published.py'),
                      ('inventoryVerifierSha256', 'source_inventory.py')]:
        require(release[key] == sha((REPO / 'tool/design-system' / name).read_bytes()), 'release receipt input mismatch')
    require(release['referenceCommit'] == ledger['referenceCommit'], 'source identities differ')
    source = Path(os.environ['DSH_SRC'])
    require(subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
            == ledger['referenceCommit'], 'reference checkout changed')
    inputs = dict(source_paths(ledger))
    spec = importlib.util.spec_from_file_location('source_contract_guard', REPO / 'tool/design-system/check.py')
    guard = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(guard)
    counts, failures = guard.inspect(REPO, json.loads((REPO / 'tool/design-system/families.json').read_text()))
    require(not failures, 'current source guard failed')
    manual = sum(rules.get('manual-metric', 0) for rules in counts.values())
    changed = git('diff', '--name-only', '--diff-filter=ACMRT', BASE, head).splitlines()
    with tempfile.TemporaryDirectory(prefix='.source-contract-', dir=DEST.parent) as temporary:
        stage = Path(temporary) / 'source-contract'
        stage.mkdir()

        def copy(path, target, exact=False, expected=None):
            require(path.is_file() and not path.is_symlink(), 'missing or linked evidence input')
            raw = path.read_bytes()
            if expected:
                require(sha(raw) == expected, 'input hash mismatch: ' + target)
            text = raw.decode()
            if exact:
                require(not SENSITIVE.search(text) and not HOME_PATH.search(text), 'unsafe exact source input')
            else:
                raw = sanitize(text).encode()
            destination = stage / target
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(raw)

        for name in changed:
            copy(REPO / name, 'implementation/' + name, exact=True)
        for name, expected in sorted(inputs.items()):
            relative = Path(name)
            require(not relative.is_absolute() and '..' not in relative.parts, 'unsafe source input path')
            copy(source / relative, 'reference-source/' + name, exact=True, expected=expected)
        copy(source / 'LICENSE', 'reference-source/LICENSE', exact=True)
        lock = json.loads((REPO / 'tool/design-system/sources.lock.json').read_text())
        for package in lock['packages']:
            for name, expected in package['files'].items():
                relative = 'tool/design-system/upstream/' + package['snapshotFolder'] + '/' + name
                copy(REPO / relative, 'released-inputs/' + package['snapshotFolder'] + '/' + name,
                     exact=True, expected=expected)
        for name in CHECKS:
            copy(REPO / '.local/preflight' / (name + '.txt'), 'checks/' + name + '.txt')
        for path, name in [(REPO / '.local/source-contract-full.json', 'preflight.json'),
                           (REPO / '.local/preflight/release-inputs.json', 'release-inputs.json')]:
            copy(path, name)
        for name in ['design-system-all-families-audit.md', 'design-system-guard-audit.md',
                     'design-system-style-literals-audit.md', 'design-system-contract-independent-review.md']:
            copy(ROOT / 'notes' / name, 'review/' + name)
        copy(ROOT / 'scripts/design-system-source-publish.py', 'reproduction/stage.py')
        report = ROOT / 'scratch/design-system-source-artifact'
        built = json.loads((report / 'build-receipt.json').read_text())
        require(built['head'] == head and built['tree'] == tree and built['previewPassed'],
                'final report is not bound to this validated tree')
        copy(ROOT / 'scripts/design-system-source-report.py', 'reproduction/report.py')
        for name in ['index.html', 'build-receipt.json', 'preview.json', 'preview.cjs']:
            copy(report / name, 'report/' + name, exact=True,
                 expected=built['htmlSha256'] if name == 'index.html' else None)
        cold = REPO / '.local/source-contract-cold-ci'
        cold_release = json.loads((cold / 'release-inputs.json').read_text())
        require(cold_release['allPassed'] and all(p['archiveOrigin'] == 'downloaded'
                for p in cold_release['packages']), 'cold archive/source-free verification incomplete')
        for name in ['release-inputs.json', 'design-system.txt']:
            copy(cold / name, 'checks/cold-source-free/' + name)
        patch = subprocess.check_output(['git', 'diff', '--binary', BASE, head], cwd=REPO, text=True)
        (stage / 'implementation.patch').write_text(sanitize(patch))
        receipt = {'head': head, 'tree': tree, 'base': BASE, 'runtimeSourcesUnchanged': True,
                   'referenceCommit': ledger['referenceCommit'], 'summary': ledger['summary'],
                   'checks': len(CHECKS), 'releasePackages': release['packageCount'],
                   'reconstructedFiles': release['verifiedSnapshotFiles'], 'referenceSourceFiles': len(inputs),
                   'implementationFiles': len(changed), 'remainingManualMetricMatches': manual,
                   'coldSourceFreeArchiveDownloads': len(cold_release['packages']),
                   'reportHtmlSha256': built['htmlSha256'],
                   'meaning': 'Source contracts and input retention; component migrations and visual acceptance remain unfinished.',
                   'releaseOrDeployment': False}
        (stage / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
        files = [{'path': str(p.relative_to(stage)), 'sha256': sha(p.read_bytes()), 'bytes': p.stat().st_size}
                 for p in sorted(stage.rglob('*')) if p.is_file()]
        (stage / 'files.json').write_text(json.dumps(files, indent=2) + '\n')
        require(git('rev-parse', 'HEAD') == head and not git('status', '--porcelain'), 'source changed during staging')
        stage.rename(DEST)
    print(json.dumps({'head': head, 'tree': tree, 'files': len(files) + 1,
                      'referenceSourceFiles': len(inputs), 'runtimeSourcesUnchanged': True}))


if __name__ == '__main__':
    main()
