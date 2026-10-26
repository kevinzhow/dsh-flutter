#!/usr/bin/env python3
"""Ratchet UI bypasses, duplicate component uses and hand-written metrics.

Baselines are per file and rule: moving a bypass or adding one in a new file
fails even when the repository-wide total falls. Reductions are allowed.
"""
from pathlib import Path
import json, os, re, subprocess, sys
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def code_only(text):
    # Preserve newlines so reports can point to the offending source location.
    pattern = r"//[^\n]*|/\*[\s\S]*?\*/|(?:r)?'''[\s\S]*?'''|(?:r)?\"\"\"[\s\S]*?\"\"\"|(?:r)?'(?:\\.|[^'\\])*'|(?:r)?\"(?:\\.|[^\"\\])*\""
    return re.sub(pattern, lambda m: '\n' * m[0].count('\n') + ' ', text)


def scan(source, patterns):
    code = code_only(source)
    return {name: len(list(re.finditer(pattern, code))) for name, pattern in patterns.items() if re.search(pattern, code)}


def sources(root):
    for group in ['apps', 'features', 'packages']:
        for package in sorted((root / group).iterdir()):
            folder = package / 'lib'
            if folder.is_dir():
                for file in sorted(folder.rglob('*.dart')):
                    if not file.name.endswith('.g.dart'):
                        yield file


def inspect(root, contract):
    counts, failures = {}, []
    for f in sources(root):
        name = f.relative_to(root).as_posix()
        observed = scan(f.read_text(), contract['patterns'])
        observed = {rule: count for rule, count in observed.items() if name not in contract['wrapperAllowlist'].get(rule, {})}
        if observed:
            counts[name] = observed
        for rule, count in observed.items():
            allowed = contract['baseline'].get(name, {}).get(rule, 0)
            if count > allowed:
                failures.append(f'{name}: {rule} grew {allowed} -> {count}; {contract["remediation"][rule]}')
    for family in contract['families']:
        for canonical in family['canonical']:
            if not (root / canonical).is_file():
                failures.append(f'{family["name"]}: missing canonical component {canonical}')
    return counts, failures


def baseline_growth(contract, previous, previous_source):
    failures = []
    for name, rules in contract['baseline'].items():
        for rule, count in rules.items():
            old = previous.get('baseline', {}).get(name, {}) if previous else {}
            if previous is not None and rule in previous['patterns']:
                limit = old.get(rule, 0)
            else:
                limit = scan(previous_source(name), {rule: contract['patterns'][rule]}).get(rule, 0)
            if count > limit:
                failures.append(f'{name}: ratchet baseline {rule} increased {limit} -> {count}; migrate the bypass instead')
    return failures


def check_baseline_history(contract):
    event_path = os.environ.get('GITHUB_EVENT_PATH')
    event = json.loads(Path(event_path).read_text()) if event_path else {}
    reference = event.get('pull_request', {}).get('base', {}).get('sha')
    if not reference:
        probe = subprocess.run(['git', 'rev-parse', '--verify', 'origin/main'], cwd=ROOT, capture_output=True, text=True)
        reference = probe.stdout.strip() if probe.returncode == 0 else 'HEAD'
    def contents(name):
        result = subprocess.run(['git', 'show', reference + ':' + name], cwd=ROOT, capture_output=True, text=True)
        return result.stdout if result.returncode == 0 else ''
    # Missing history is a failure; absence of an initial contract is allowed
    # only when the reference commit itself can actually be resolved.
    subprocess.run(['git', 'cat-file', '-e', reference + '^{commit}'], cwd=ROOT, check=True, capture_output=True)
    raw = contents('tool/design-system/families.json')
    previous = json.loads(raw) if raw else None
    return baseline_growth(contract, previous, contents)


def main():
    contract = json.loads((HERE / 'families.json').read_text())
    _, failures = inspect(ROOT, contract)
    failures.extend(check_baseline_history(contract))
    if failures:
        print('\n'.join(failures), file=sys.stderr)
        return 1
    print('design-system: family inventory and per-file bypass/duplicate/metric ratchets passed')
    return 0

if __name__ == '__main__':
    sys.exit(main())
