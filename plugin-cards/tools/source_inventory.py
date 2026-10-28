#!/usr/bin/env python3
"""Inventory pinned UI source inputs; retention is not recipe implementation.

Generation requires the real pinned source checkout. Checks are offline unless
--refresh-publications is explicitly requested. --snapshot-only can validate the
recorded ledger and retained inputs, but cannot re-establish source completeness.
"""
import argparse
import base64
import binascii
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
from urllib.parse import quote
from urllib.request import urlopen


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
SCHEMA = 'dsh-source-inventory/1'
UI_PREFIX = '@deepseek-ai/dsh-client-ui-'
MEANING = 'Source-input retention only. Recipe implementation, inline/SVG coverage and state acceptance are not assessed.'
DEPENDENCY_FIELDS = ('dependencies', 'optionalDependencies', 'peerDependencies', 'devDependencies')
RUNTIME_FIELDS = DEPENDENCY_FIELDS[:-1]
ROOT_MANIFESTS = (
    'packages/bundle/web-app/package.json',
    'packages/client/web/package.json',
    'packages/experimental/plugin-market-bundle/package.json',
)
# Classification is reviewed policy, not discovery. Unknown CSS-free UI packages
# must get a source-backed classification instead of silently becoming "done".
NO_CSS = {
    'brand-official': ('delegated-artwork', ['client/Brand.tsx'],
        'OfficialBrandMark/OfficialBrandName delegate FishLogo/BrandWordmark; Whalee identity is an explicit adapter.'),
    'directory-picker-native': ('renderless-native-adapter', ['client/flow.ts'],
        'NativeDirectoryFlow returns null and invokes the host directory chooser.'),
    'reference': ('delegated-controls', ['client/FileReference.tsx'],
        'FileReference/FolderReference use ReferenceChip; failure UI composes Modal and Button.'),
    'renderer': ('structural', ['client/app.tsx', 'client/bindings.tsx', 'client/scoped-slots.tsx'],
        'Slot/render assembly and bindings; classify contributed controls and error states separately.'),
    'session': ('structural', ['client/session-provider.tsx'],
        'renderSessionArea chooses the contributed session subtree or empty branch.'),
    'settings': ('model-and-slot-contracts', ['client/config-form.ts', 'client/schema.ts', 'client/settings-mirror.ts', 'client/contract/slots.ts'],
        'Settings models, schema, mirror and slots; field/form paint belongs to contributors and primitives.'),
    'settings-agent-loop': ('delegated-forms', ['client/AgentLoopCard.tsx'],
        'AgentLoopCard delegates SettingsForm and SettingsValueField; their profiles remain independently assessable.'),
    'settings-shell': ('delegated-forms', ['client/ShellCard.tsx'],
        'ShellCard delegates SettingsForm and SettingsValueField; their profiles remain independently assessable.'),
    'slots': ('structural', ['index.ts', 'renderer.ts', 'store.ts'],
        'Typed slot, renderer and store contracts; no independent painted control.'),
}
SNAPSHOT_ALIASES = {
    (UI_PREFIX + 'agent-preset', 'styles.css'): 'src/client/AgentPresetSection.module.css',
}


def fail(message):
    raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            fail('duplicate JSON key: ' + key)
        result[key] = value
    return result


def read_json(path):
    return json.loads(path.read_text(), object_pairs_hook=unique_object)


def encode(value):
    return json.dumps(value, ensure_ascii=False, indent=2) + '\n'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative_path(value):
    if (not isinstance(value, str) or not value or '\\' in value
            or PurePosixPath(value).is_absolute() or ':' in value
            or any(part in ('', '.', '..') for part in value.split('/'))):
        fail('unsafe inventory path: ' + repr(value))
    return value


def checked_file(root, name):
    relative_path(name)
    path = root / name
    if not path.is_file() or path.is_symlink() or not path.resolve().is_relative_to(root.resolve()):
        fail('missing/unsafe input file: ' + name)
    return path


def dependencies(manifest):
    result = {}
    for field in DEPENDENCY_FIELDS:
        entries = manifest.get(field, {})
        if not isinstance(entries, dict) or any(not isinstance(k, str) or not isinstance(v, str) for k, v in entries.items()):
            fail('invalid dependency declarations: ' + str(manifest.get('name')) + '/' + field)
        result[field] = dict(sorted(entries.items()))
    return result


def workspace_patterns(source):
    """Read the top-level pnpm packages string list, rejecting unknown syntax."""
    text = checked_file(source, 'pnpm-workspace.yaml').read_text()
    lines = text.splitlines()
    if lines.count('packages:') != 1:
        fail('workspace must have exactly one packages list')
    patterns = []
    for line in lines[lines.index('packages:') + 1:]:
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        if not line.startswith(' '):
            break
        match = re.fullmatch(r'  - ([^#]+?)(?:\s+#.*)?', line)
        if not match:
            fail('unsupported workspace package pattern: ' + line)
        pattern = match[1].strip()
        if pattern[:1] in ('\"', "'"):
            if pattern[-1:] != pattern[:1]:
                fail('unbalanced workspace package pattern')
            pattern = pattern[1:-1]
        relative_path(pattern)
        if not re.fullmatch(r'[\w./*?\[\]-]+', pattern):
            fail('unsupported workspace package pattern: ' + pattern)
        patterns.append(pattern)
    if not patterns or len(patterns) != len(set(patterns)):
        fail('empty/duplicate workspace package patterns')
    return patterns


def discover(source):
    manifests, paths = {}, set()
    for pattern in workspace_patterns(source):
        for folder in sorted(source.glob(pattern)):
            path = folder / 'package.json'
            if not path.is_file():
                continue
            name = path.relative_to(source).as_posix()
            checked_file(source, name)
            if name in paths:
                fail('duplicate workspace manifest path: ' + name)
            paths.add(name)
            data = read_json(path)
            identity = data.get('name')
            if not isinstance(identity, str) or not isinstance(data.get('version'), str):
                fail('workspace package has no name/version: ' + name)
            if identity in manifests:
                fail('duplicate workspace package: ' + identity)
            manifests[identity] = {'path': name, 'sha256': sha(path), 'manifest': data}
    if not manifests:
        fail('empty source workspace')
    # A workspace: dependency with a missing manifest must never be treated as
    # an external dependency, including when a source package was deleted.
    for name, record in manifests.items():
        for entries in dependencies(record['manifest']).values():
            for dependency, declared in entries.items():
                if declared.startswith('workspace:') and dependency not in manifests:
                    fail('missing workspace dependency package: ' + name + ' -> ' + dependency)
    return manifests


def verify_reference(source, commit):
    head = subprocess.run(['git', '-C', str(source), 'rev-parse', 'HEAD'], check=True, capture_output=True, text=True).stdout.strip()
    if head != commit:
        fail('source HEAD differs from pinned reference: ' + head + ' != ' + commit)
    dirty = subprocess.run(['git', '-C', str(source), 'status', '--porcelain', '--untracked-files=normal'], check=True, capture_output=True, text=True)
    if dirty.stdout.strip():
        fail('pinned source checkout is dirty; inventory requires its actual committed inputs')


def closure(workspace, roots, fields):
    visited, pending = set(), list(roots)
    while pending:
        name = pending.pop()
        if name in visited:
            continue
        visited.add(name)
        deps = dependencies(workspace[name]['manifest'])
        pending.extend(dep for field in fields for dep in deps[field] if dep in workspace)
    return visited


def registry_url(name, version):
    return 'https://registry.npmjs.org/' + quote(name, safe='@') + '/' + quote(version, safe='')


def publication_record(metadata):
    name, version = metadata['name'], metadata['version']
    distribution = metadata.get('dist', {})
    if not distribution.get('integrity') or not distribution.get('tarball'):
        fail('published package has no distribution integrity: ' + name)
    return {'name': name, 'version': version, 'registryVersionUrl': registry_url(name, version),
            'integrity': distribution['integrity'], 'tarball': distribution['tarball'],
            'dependencies': dependencies(metadata)}


def verify_publication_shape(published, name, version):
    if (published.get('name'), published.get('version')) != (name, version):
        fail('publication identity/version mismatch: ' + name)
    if (published.get('registryVersionUrl') != registry_url(name, version)
            or not str(published.get('tarball', '')).startswith('https://registry.npmjs.org/')):
        fail('invalid published version provenance: ' + name)
    match = re.fullmatch(r'sha(256|384|512)-([A-Za-z0-9+/]+={0,2})', str(published.get('integrity', '')))
    try:
        valid_integrity = match is not None and len(base64.b64decode(match[2], validate=True)) == int(match[1]) // 8
    except binascii.Error:
        valid_integrity = False
    if not valid_integrity:
        fail('invalid published distribution integrity: ' + name)
    declared = published.get('dependencies')
    if not isinstance(declared, dict) or set(declared) != set(DEPENDENCY_FIELDS) or dependencies(declared) != declared:
        fail('invalid published dependency declarations: ' + name)


def fetch_publications(records):
    def fetch(record):
        manifest = record['manifest']
        with urlopen(registry_url(manifest['name'], manifest['version']), timeout=30) as response:
            data = json.loads(response.read(), object_pairs_hook=unique_object)
        if (data.get('name'), data.get('version')) != (manifest['name'], manifest['version']):
            fail('registry returned a different package/version: ' + manifest['name'])
        return manifest['name'], publication_record(data)
    with ThreadPoolExecutor(max_workers=6) as pool:
        return dict(pool.map(fetch, records))


def verify_publication(record, published, workspace):
    manifest = record['manifest']
    name = manifest['name']
    if published.get('name') != name or published.get('version') != manifest['version']:
        fail('published identity/version drift: ' + name)
    verify_publication_shape(published, name, manifest['version'])
    expected = dependencies(manifest)
    for entries in expected.values():
        for dependency, declared in entries.items():
            if declared.startswith('workspace:'):
                selector = declared.removeprefix('workspace:')
                version = workspace[dependency]['manifest']['version']
                if selector not in ('*', '~', '^'):
                    fail('unsupported published workspace dependency: ' + dependency + '/' + declared)
                entries[dependency] = ('' if selector == '*' else selector) + version
    if published.get('dependencies') != expected:
        fail('source/published dependency version drift: ' + name)


def snapshots(repo, lock):
    result, all_paths, folders = {}, set(), set()
    for package in lock['packages']:
        name, folder = package['name'], relative_path(package['snapshotFolder'])
        if name in result or folder in folders:
            fail('duplicate retained package/folder: ' + name)
        folders.add(folder)
        files = []
        for filename, digest in sorted(package['files'].items()):
            path = 'tool/design-system/upstream/' + folder + '/' + relative_path(filename)
            if path in all_paths:
                fail('duplicate retained input path: ' + path)
            all_paths.add(path)
            actual = checked_file(repo, path)
            if sha(actual) != digest:
                fail('retained input hash drift: ' + path)
            files.append({'path': path, 'sha256': digest})
        manifest = read_json(checked_file(repo, 'tool/design-system/upstream/' + folder + '/package.json'))
        if (manifest.get('name'), manifest.get('version')) != (name, package['version']):
            fail('retained manifest identity/version drift: ' + name)
        result[name] = {'status': 'retained-subset', 'sourceManifest': relative_path(package['sourcePackage']),
                        'version': package['version'], 'integrity': package['integrity'], 'files': files}
    return result


def source_css(source, record):
    folder = source / Path(record['path']).parent / 'src'
    sheets = []
    for path in sorted(folder.rglob('*.css')):
        name = path.relative_to(source).as_posix()
        sheets.append({'path': name, 'sha256': sha(checked_file(source, name))})
    return sheets


def bind_retained(name, css, snapshot):
    rows = [{**item, 'retention': 'pending', 'retainedInputs': []} for item in css]
    if snapshot:
        parent = str(Path(snapshot['sourceManifest']).parent)
        for retained in snapshot['files']:
            filename = Path(retained['path']).name
            if not filename.endswith('.css'):
                continue
            alias = SNAPSHOT_ALIASES.get((name, filename))
            matches = [row for row in rows if row['path'] == parent + '/' + alias] if alias else [
                row for row in rows if Path(row['path']).name == filename]
            if len(matches) != 1:
                fail('retained stylesheet has missing/ambiguous source binding: ' + retained['path'])
            matches[0]['retention'] = 'retained-input'
            matches[0]['retainedInputs'].append(retained['path'])
    return rows


def no_css_classification(source, record):
    suffix = record['manifest']['name'].removeprefix(UI_PREFIX)
    if suffix not in NO_CSS:
        fail('unclassified CSS-free UI package: ' + record['manifest']['name'])
    kind, evidence, explanation = NO_CSS[suffix]
    parent = str(Path(record['path']).parent)
    return {'kind': kind, 'explanation': explanation, 'sourceEvidence': [
        {'path': parent + '/src/' + path, 'sha256': sha(checked_file(source, parent + '/src/' + path))}
        for path in evidence]}


def summary(packages):
    ui = [p for p in packages if p['scope'] == 'ui-package']
    support = [p for p in packages if p['scope'] == 'support-styles']
    css = [item for p in ui for item in p['css']]
    return {'uiPackages': len(ui), 'uiPackagesWithCss': sum(bool(p['css']) for p in ui),
            'uiPackagesWithoutCss': sum(not p['css'] for p in ui), 'uiCssInputs': len(css),
            'uiPackagesWithRetainedSnapshots': sum(p['snapshot'] is not None for p in ui),
            'uiCssRetainedInputs': sum(item['retention'] == 'retained-input' for item in css),
            'uiCssPendingInputs': sum(item['retention'] == 'pending' for item in css),
            'supportStylePackages': len(support), 'supportCssInputs': sum(len(p['css']) for p in support)}


def collect(source, repo, publications):
    lock_path = repo / 'tool/design-system/sources.lock.json'
    lock = read_json(lock_path)
    verify_reference(source, lock['referenceCommit'])
    workspace = discover(source)
    by_path = {v['path']: k for k, v in workspace.items()}
    for path in ROOT_MANIFESTS:
        if path not in by_path:
            fail('missing dependency root manifest: ' + path)
    roots = [by_path[path] for path in ROOT_MANIFESTS]
    runtime, build = closure(workspace, roots, RUNTIME_FIELDS), closure(workspace, roots, DEPENDENCY_FIELDS)
    retained = snapshots(repo, lock)
    packages = []
    for name, record in sorted(workspace.items()):
        manifest = record['manifest']
        ui = name.startswith(UI_PREFIX)
        public = not manifest.get('private') and manifest.get('publishConfig', {}).get('access') == 'public'
        css = source_css(source, record) if ui or public else []
        if not ui and (not css or not public):
            continue
        if manifest.get('private') or manifest.get('publishConfig', {}).get('access') != 'public':
            fail('UI package is not explicitly public: ' + name)
        if name not in publications:
            fail('missing published metadata; use --refresh-publications: ' + name)
        published = publications[name]
        verify_publication(record, published, workspace)
        snapshot = retained.get(name)
        if snapshot and (snapshot['sourceManifest'] != record['path'] or snapshot['version'] != manifest['version']
                         or snapshot['integrity'] != published['integrity']):
            fail('retained package/source publication drift: ' + name)
        packages.append({'name': name, 'version': manifest['version'],
                         'scope': 'ui-package' if ui else 'support-styles',
                         'reachability': 'runtime' if name in runtime else 'build-only' if name in build else 'outside-selected-closure',
                         'sourceManifest': {'path': record['path'], 'sha256': record['sha256']},
                         'sourceDependencies': dependencies(manifest), 'publication': published,
                         'snapshot': snapshot, 'css': bind_retained(name, css, snapshot),
                         'noCssClassification': no_css_classification(source, record) if ui and not css else None})
    missing = set(retained) - {p['name'] for p in packages}
    if missing:
        fail('retained package absent from source inventory: ' + ', '.join(sorted(missing)))
    result = {'schema': SCHEMA, 'referenceCommit': lock['referenceCommit'],
              'workspaceManifest': {'path': 'pnpm-workspace.yaml', 'sha256': sha(source / 'pnpm-workspace.yaml')},
              'snapshotLockSha256': sha(lock_path),
              'meaning': MEANING,
              'dependencyScope': {
                  'roots': [{'name': name, 'path': workspace[name]['path'], 'version': workspace[name]['manifest']['version'],
                             'sha256': workspace[name]['sha256']} for name in roots],
                  'runtimeFields': list(RUNTIME_FIELDS), 'buildFields': list(DEPENDENCY_FIELDS),
                  'workspacePackages': len(workspace), 'runtimeWorkspacePackages': len(runtime), 'buildWorkspacePackages': len(build),
                  'runtimeUiPackages': sorted(name for name in runtime if name.startswith(UI_PREFIX)),
                  'buildUiPackages': sorted(name for name in build if name.startswith(UI_PREFIX))},
              'summary': summary(packages), 'packages': packages}
    validate_ledger(result)
    return result


def validate_ledger(ledger):
    if (ledger.get('schema') != SCHEMA or ledger.get('meaning') != MEANING
            or not re.fullmatch(r'[0-9a-f]{40}', ledger.get('referenceCommit', ''))):
        fail('invalid source inventory schema/reference')
    packages = ledger.get('packages')
    if not isinstance(packages, list) or not packages:
        fail('empty source package inventory')
    if (ledger['workspaceManifest']['path'] != 'pnpm-workspace.yaml'
            or not re.fullmatch(r'[0-9a-f]{64}', ledger['workspaceManifest']['sha256'])
            or not re.fullmatch(r'[0-9a-f]{64}', ledger['snapshotLockSha256'])):
        fail('invalid workspace/lock provenance')
    names, paths, retained_paths = set(), set(), set()
    for package in packages:
        name = package['name']
        if name in names:
            fail('duplicate inventory package: ' + name)
        names.add(name)
        if package['scope'] not in ('ui-package', 'support-styles') or (package['scope'] == 'ui-package') != name.startswith(UI_PREFIX):
            fail('invalid package scope: ' + name)
        parent = str(PurePosixPath(package['sourceManifest']['path']).parent)
        source_inputs = [package['sourceManifest'], *package['css']]
        classification = package['noCssClassification']
        if not package['css'] and package['scope'] == 'ui-package':
            if not classification or not classification.get('sourceEvidence'):
                fail('missing CSS-free package classification: ' + name)
            source_inputs.extend(classification['sourceEvidence'])
        elif classification is not None:
            fail('unexpected CSS-free classification: ' + name)
        for item in source_inputs:
            path = relative_path(item['path'])
            if path in paths:
                fail('duplicate source input path: ' + path)
            paths.add(path)
            if not path.startswith(parent + '/') or not re.fullmatch(r'[0-9a-f]{64}', item['sha256']):
                fail('source input owner/hash mismatch: ' + path)
        snapshot = package['snapshot']
        snapshot_css = set()
        if snapshot:
            if snapshot['sourceManifest'] != package['sourceManifest']['path'] or snapshot['version'] != package['version']:
                fail('snapshot owner/version mismatch: ' + name)
            for item in snapshot['files']:
                path = relative_path(item['path'])
                if path in retained_paths:
                    fail('duplicate retained input path: ' + path)
                retained_paths.add(path)
                if path.endswith('.css'):
                    snapshot_css.add(path)
        bound = []
        for item in package['css']:
            if not item['path'].startswith(parent + '/src/') or not item['path'].endswith('.css'):
                fail('invalid CSS input owner/path: ' + item['path'])
            if item['retention'] != ('retained-input' if item['retainedInputs'] else 'pending'):
                fail('retention status contradicts retained inputs: ' + item['path'])
            bound.extend(item['retainedInputs'])
        if len(bound) != len(set(bound)) or set(bound) != snapshot_css:
            fail('missing/duplicate/foreign retained CSS binding: ' + name)
        published = package['publication']
        verify_publication_shape(published, name, package['version'])
    scope = ledger['dependencyScope']
    if (scope['runtimeFields'] != list(RUNTIME_FIELDS) or scope['buildFields'] != list(DEPENDENCY_FIELDS)
            or [r['path'] for r in scope['roots']] != list(ROOT_MANIFESTS)
            or len({r['name'] for r in scope['roots']}) != len(scope['roots'])):
        fail('invalid source dependency roots/fields')
    for root in scope['roots']:
        if not root['version'] or not re.fullmatch(r'[0-9a-f]{64}', root['sha256']):
            fail('invalid source dependency root version/hash')
    runtime, build = scope['runtimeUiPackages'], scope['buildUiPackages']
    ui_names = {p['name'] for p in packages if p['scope'] == 'ui-package'}
    if (runtime != sorted(set(runtime)) or build != sorted(set(build))
            or not set(runtime) <= set(build) <= ui_names):
        fail('dependency closure contains duplicate/unknown UI packages')
    for package in packages:
        if package['reachability'] not in ('runtime', 'build-only', 'outside-selected-closure'):
            fail('invalid source reachability: ' + package['name'])
        if package['scope'] == 'ui-package':
            expected = 'runtime' if package['name'] in runtime else 'build-only' if package['name'] in build else 'outside-selected-closure'
            if package['reachability'] != expected:
                fail('source reachability contradicts dependency closure: ' + package['name'])
    if ledger.get('summary') != summary(packages):
        fail('source inventory summary disagrees with its inputs')


def check_snapshots(ledger, repo):
    validate_ledger(ledger)
    lock_path = repo / 'tool/design-system/sources.lock.json'
    lock = read_json(lock_path)
    if ledger['referenceCommit'] != lock['referenceCommit'] or ledger['snapshotLockSha256'] != sha(lock_path):
        fail('source inventory snapshot lock/reference drift; regenerate with the actual pinned source')
    expected = snapshots(repo, lock)
    recorded = {p['name']: p['snapshot'] for p in ledger['packages'] if p['snapshot']}
    if recorded != expected:
        fail('source inventory retained snapshots differ from the lock')


def check_source(ledger, source, repo):
    check_snapshots(ledger, repo)
    publications = {p['name']: p['publication'] for p in ledger['packages']}
    actual = collect(source, repo, publications)
    if actual != ledger:
        old_names, new_names = {p['name'] for p in ledger['packages']}, {p['name'] for p in actual['packages']}
        old_css = {i['path']: i['sha256'] for p in ledger['packages'] for i in p['css']}
        new_css = {i['path']: i['sha256'] for p in actual['packages'] for i in p['css']}
        changes = ['packages removed=' + str(sorted(old_names - new_names)), 'added=' + str(sorted(new_names - old_names)),
                   'CSS removed=' + str(sorted(old_css.keys() - new_css.keys())), 'added=' + str(sorted(new_css.keys() - old_css.keys())),
                   'changed=' + str(sorted(k for k in old_css.keys() & new_css.keys() if old_css[k] != new_css[k]))]
        fail('source inventory drift (including manifest/dependency/classification inputs); ' + '; '.join(changes))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--src', type=Path, default=Path(os.environ.get('DSH_SRC', ROOT / '.local/dsh-src')))
    parser.add_argument('--check', action='store_true', help='check the ledger against the actual pinned source')
    parser.add_argument('--snapshot-only', action='store_true', help='validate recorded/retained inputs only; source completeness remains unverified')
    parser.add_argument('--refresh-publications', action='store_true', help='explicitly query pinned public registry version metadata')
    args = parser.parse_args(argv)
    if args.snapshot_only and (args.refresh_publications or not args.check):
        parser.error('--snapshot-only requires --check and cannot refresh publication metadata')
    if args.check and args.refresh_publications:
        parser.error('refresh publication metadata during generation, then check offline')
    path = HERE / 'source-inventory.generated.json'
    try:
        previous = read_json(path) if path.exists() else None
        if args.snapshot_only:
            if previous is None:
                fail('missing source inventory; snapshot-only cannot generate it')
            check_snapshots(previous, ROOT)
            print('source-inventory: snapshot-only PASS; source-universe completeness NOT independently verified')
        elif args.check:
            if previous is None:
                fail('missing source inventory; generate with the actual pinned source')
            check_source(previous, args.src, ROOT)
            print('source-inventory: pinned-source package/CSS/dependency/retention check PASS; implementation acceptance not assessed')
        else:
            publications = {p['name']: p['publication'] for p in previous['packages']} if previous else {}
            if args.refresh_publications:
                lock = read_json(HERE / 'sources.lock.json')
                verify_reference(args.src, lock['referenceCommit'])
                workspace = discover(args.src)
                candidates = [record for name, record in sorted(workspace.items()) if name.startswith(UI_PREFIX) or (
                    not record['manifest'].get('private')
                    and record['manifest'].get('publishConfig', {}).get('access') == 'public' and source_css(args.src, record))]
                publications = fetch_publications(candidates)
            ledger = collect(args.src, ROOT, publications)
            path.write_text(encode(ledger))
            print('source-inventory: generated source-input ledger; ' + json.dumps(ledger['summary'], sort_keys=True))
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError) as error:
        print('source-inventory: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
