#!/usr/bin/env python3
"""Ratchet UI bypasses, duplicate component uses and hand-written metrics.

Baselines are per file and rule: moving a bypass or adding one in a new file
fails even when the repository-wide total falls. Reductions are allowed.
"""
from pathlib import Path, PurePosixPath
import json, os, re, subprocess, sys
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent


def read_contract(text):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('invalid design-system contract: duplicate key ' + key)
            result[key] = value
        return result
    return json.loads(text, object_pairs_hook=unique)


def validate_contract(contract):
    """Validate the policy itself before its patterns can exempt any source."""
    def require(condition, reason):
        if not condition:
            raise ValueError('invalid design-system contract: ' + reason)

    def text(value):
        return isinstance(value, str) and bool(value.strip())

    def production_path(value):
        if not text(value) or '\\' in value:
            return False
        path = PurePosixPath(value)
        return (not path.is_absolute() and '..' not in path.parts
                and str(path) == value and len(path.parts) >= 4
                and path.parts[0] in ('apps', 'features', 'packages')
                and path.parts[2] == 'lib' and path.suffix == '.dart')

    require(isinstance(contract, dict), 'expected an object')
    require(set(contract) == {'schema', 'families', 'patterns', 'remediation',
                              'wrapperAllowlist', 'baseline'}, 'unknown or missing policy fields')
    require(contract['schema'] == 'dsh-design-families/1', 'unknown schema')
    patterns = contract['patterns']
    require(isinstance(patterns, dict) and bool(patterns), 'patterns must be a nonempty object')
    for name, pattern in patterns.items():
        require(text(name) and re.fullmatch(r'[a-z][a-z0-9-]*', name), 'invalid pattern name')
        require(text(pattern), 'empty pattern ' + name)
        try:
            compiled = re.compile(pattern)
        except re.error as error:
            require(False, 'invalid pattern ' + name + ': ' + str(error))
        require(compiled.search('') is None, 'pattern matches empty text: ' + name)
    remediation = contract['remediation']
    require(isinstance(remediation, dict) and set(remediation) == set(patterns)
            and all(text(value) for value in remediation.values()), 'remediation must cover every rule')
    families = contract['families']
    require(isinstance(families, list) and bool(families), 'families must be a nonempty list')
    names = set()
    for family in families:
        required = {'name', 'canonical', 'migrationStatus', 'pendingDuplicates'}
        require(isinstance(family, dict) and required <= set(family)
                and set(family) <= required | {'status'}, 'unknown or missing family fields')
        name = family['name']
        require(text(name) and re.fullmatch(r'[a-z][a-z0-9-]*', name)
                and name not in names, 'invalid or duplicate family name')
        names.add(name)
        canonical = family['canonical']
        require(isinstance(canonical, list) and all(production_path(p) for p in canonical)
                and len(set(canonical)) == len(canonical), 'malformed canonical paths: ' + name)
        require('status' not in family or family['status'] in ('active', 'pending'),
                'unknown family status: ' + name)
        require(bool(canonical) or family.get('status') == 'pending',
                'empty canonical requires pending status: ' + name)
        require(text(family['migrationStatus']), 'missing migration status: ' + name)
        require(isinstance(family['pendingDuplicates'], list)
                and all(text(p) for p in family['pendingDuplicates']), 'malformed pending duplicates: ' + name)
    allowances = contract['wrapperAllowlist']
    require(isinstance(allowances, dict) and set(allowances) <= set(patterns), 'unknown wrapper rule')
    for rule, files in allowances.items():
        require(isinstance(files, dict) and all(production_path(p) and text(reason)
                                               for p, reason in files.items()),
                'malformed wrapper allowance: ' + rule)
    baseline = contract['baseline']
    require(isinstance(baseline, dict), 'baseline must be an object')
    for path, rules in baseline.items():
        require(production_path(path) and isinstance(rules, dict) and bool(rules)
                and set(rules) <= set(patterns)
                and all(type(count) is int and count >= 0 for count in rules.values()),
                'malformed baseline entry: ' + str(path))


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


def policy_changes(contract, previous, previous_source, current_source):
    """New rules may tighten coverage; existing rules and coverage cannot shrink."""
    failures = []
    if previous is not None:
        for rule, pattern in previous['patterns'].items():
            if rule not in contract['patterns']:
                failures.append(f'pattern {rule} removed; retain existing coverage and add stricter rules')
            elif contract['patterns'][rule] != pattern:
                failures.append(f'pattern {rule} changed; retain it and add a stricter rule instead')
        families = {family['name']: family for family in contract['families']}
        for family in previous['families']:
            name = family['name']
            if name not in families:
                failures.append(f'family {name} removed; migrate its registered coverage instead')
            elif not set(family['canonical']) <= set(families[name]['canonical']):
                failures.append(f'{name}: canonical coverage removed; retain the registered source owners')
    for rule, files in contract['wrapperAllowlist'].items():
        old_files = previous.get('wrapperAllowlist', {}).get(rule, {}) if previous else {}
        for name in files:
            if previous is not None and name not in old_files:
                failures.append(f'{name}: {rule} wrapper allowance added; register source-backed coverage instead')
                continue
            pattern = previous['patterns'][rule] if previous is not None else contract['patterns'][rule]
            before = scan(previous_source(name), {rule: pattern}).get(rule, 0)
            after = scan(current_source(name), {rule: pattern}).get(rule, 0)
            if after > before:
                failures.append(f'{name}: {rule} wrapper occurrences grew {before} -> {after}; '
                                'the existing wrapper exemption is bounded to its base occurrences')
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
    previous = read_contract(raw) if raw else None
    def current(name):
        path = ROOT / name
        return path.read_text() if path.is_file() else ''
    return (baseline_growth(contract, previous, contents)
            + policy_changes(contract, previous, contents, current))


def main():
    try:
        contract = read_contract((HERE / 'families.json').read_text())
        validate_contract(contract)
        _, failures = inspect(ROOT, contract)
        failures.extend(check_baseline_history(contract))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print('design-system: ' + str(error), file=sys.stderr)
        return 1
    if failures:
        print('\n'.join(failures), file=sys.stderr)
        return 1
    print('design-system: family inventory and per-file bypass/duplicate/metric ratchets passed')
    return 0

if __name__ == '__main__':
    sys.exit(main())
