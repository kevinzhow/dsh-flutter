"""Failure-oriented tests of the source universe, not fixture-count acceptance."""
import copy
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('source_inventory', ROOT / 'tool/design-system/source_inventory.py')
inventory = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(inventory)
PREFIX = inventory.UI_PREFIX


class SourceInventoryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.source, self.repo = self.base / 'reference', self.base / 'flutter'
        self.source.mkdir()
        self.repo.mkdir()
        self.write(self.source, 'pnpm-workspace.yaml', 'packages:\n  - packages/*/*\n')
        self.manifest('packages/bundle/web-app', '@deepseek-ai/dsh-web-app', dependencies={PREFIX + 'widget': 'workspace:*'})
        self.manifest('packages/client/web', '@deepseek-ai/dsh-client-web', dependencies={PREFIX + 'widget': 'workspace:*'})
        self.manifest('packages/experimental/plugin-market-bundle', '@deepseek-ai/dsh-experimental-plugin-market-bundle')
        self.manifest('packages/client/ui-widget', PREFIX + 'widget', dependencies={PREFIX + 'slots': 'workspace:*'},
                      devDependencies={PREFIX + 'primitives': 'workspace:*'})
        self.manifest('packages/client/ui-primitives', PREFIX + 'primitives')
        self.manifest('packages/client/ui-slots', PREFIX + 'slots')
        self.write(self.source, 'packages/client/ui-primitives/src/Button.module.css', '.button { height: 36px; }\n')
        self.write(self.source, 'packages/client/ui-widget/src/Widget.module.css', '.widget { display: flex; }\n')
        for filename in ('index.ts', 'renderer.ts', 'store.ts'):
            self.write(self.source, 'packages/client/ui-slots/src/' + filename, 'export {}\n')
        subprocess.run(['git', 'init', '-q', str(self.source)], check=True, capture_output=True)
        self.commit_source()
        self.lock_snapshot()
        self.publications = self.published_metadata()
        self.ledger = inventory.collect(self.source, self.repo, self.publications)

    @staticmethod
    def write(root, path, contents):
        result = root / path
        result.parent.mkdir(parents=True, exist_ok=True)
        result.write_text(contents)
        return result

    def manifest(self, folder, name, **kwargs):
        return self.write(self.source, folder + '/package.json', inventory.encode({
            'name': name, 'version': '0.2.1-rc.2', 'publishConfig': {'access': 'public'}, **kwargs}))

    def commit_source(self):
        subprocess.run(['git', '-C', str(self.source), 'add', '.'], check=True, capture_output=True)
        subprocess.run(['git', '-C', str(self.source), '-c', 'user.name=Inventory Test',
                        '-c', 'user.email=inventory@example.invalid', 'commit', '-qm', 'fixture'], check=True, capture_output=True)
        self.commit = subprocess.run(['git', '-C', str(self.source), 'rev-parse', 'HEAD'], check=True, capture_output=True, text=True).stdout.strip()

    def lock_snapshot(self):
        source = self.source / 'packages/client/ui-primitives'
        path = 'tool/design-system/upstream/ui-primitives/'
        manifest = self.write(self.repo, path + 'package.json', (source / 'package.json').read_text())
        css = self.write(self.repo, path + 'Button.module.css', (source / 'src/Button.module.css').read_text())
        self.lock = {'referenceCommit': self.commit, 'packages': [{
            'name': PREFIX + 'primitives', 'version': '0.2.1-rc.2',
            'integrity': self.integrity(PREFIX + 'primitives'), 'snapshotFolder': 'ui-primitives',
            'sourcePackage': 'packages/client/ui-primitives/package.json',
            'files': {'package.json': inventory.sha(manifest), 'Button.module.css': inventory.sha(css)}}]}
        self.write(self.repo, 'tool/design-system/sources.lock.json', inventory.encode(self.lock))

    def published_metadata(self):
        result = {}
        workspace = inventory.discover(self.source)
        for name, record in workspace.items():
            if not name.startswith(PREFIX):
                continue
            manifest = copy.deepcopy(record['manifest'])
            for field, entries in inventory.dependencies(manifest).items():
                manifest[field] = {key: '0.2.1-rc.2' if value == 'workspace:*' else value for key, value in entries.items()}
            manifest['dist'] = {'integrity': self.integrity(name),
                                'tarball': 'https://registry.npmjs.org/test.tgz'}
            result[name] = inventory.publication_record(manifest)
        return result

    @staticmethod
    def integrity(name):
        return 'sha512-' + base64.b64encode(hashlib.sha512(name.encode()).digest()).decode()

    def package(self, suffix, ledger=None):
        return next(p for p in (ledger or self.ledger)['packages'] if p['name'] == PREFIX + suffix)

    def check_changed_source(self, pattern):
        # Source-content faults are independently checked in addition to the
        # real production HEAD/cleanliness guard tested below.
        with patch.object(inventory, 'verify_reference'), self.assertRaisesRegex(ValueError, pattern):
            inventory.check_source(self.ledger, self.source, self.repo)

    def test_dependency_closure_keeps_build_only_primitives_and_classifies_slots(self):
        inventory.check_source(self.ledger, self.source, self.repo)
        self.assertEqual(self.package('primitives')['reachability'], 'build-only')
        self.assertEqual(self.package('slots')['reachability'], 'runtime')
        self.assertEqual(self.package('slots')['noCssClassification']['kind'], 'structural')
        self.assertEqual(self.package('widget')['sourceDependencies']['devDependencies'][PREFIX + 'primitives'], 'workspace:*')
        self.assertEqual(self.package('widget')['publication']['dependencies']['devDependencies'][PREFIX + 'primitives'], '0.2.1-rc.2')
        self.assertNotIn(PREFIX + 'primitives', self.ledger['dependencyScope']['runtimeUiPackages'])
        self.assertIn(PREFIX + 'primitives', self.ledger['dependencyScope']['buildUiPackages'])

    def test_retained_and_pending_are_input_states_not_implementation_states(self):
        self.assertEqual(self.package('primitives')['snapshot']['status'], 'retained-subset')
        self.assertEqual(self.package('primitives')['css'][0]['retention'], 'retained-input')
        self.assertEqual(self.package('widget')['css'][0]['retention'], 'pending')
        self.assertIsNone(self.package('widget')['snapshot'])
        self.assertEqual(self.ledger['summary']['uiCssPendingInputs'], 1)
        self.assertNotIn('implemented', json.dumps(self.ledger))

    def test_source_sheet_removed_added_and_modified_each_fail(self):
        sheet = self.source / 'packages/client/ui-widget/src/Widget.module.css'
        original = sheet.read_text()
        sheet.unlink()
        self.check_changed_source('unclassified CSS-free UI package')
        sheet.write_text(original + '.new { color: red; }\n')
        self.check_changed_source('source inventory drift.*changed=')
        sheet.write_text(original)
        self.write(self.source, 'packages/client/ui-widget/src/Extra.module.css', '.extra {}\n')
        self.check_changed_source('source inventory drift.*CSS.*added=')

    def test_source_package_removed_is_not_reinterpreted_as_external(self):
        (self.source / 'packages/client/ui-slots/package.json').unlink()
        self.check_changed_source('missing workspace dependency package')

    def test_new_published_ui_package_requires_metadata_and_inventory_review(self):
        self.manifest('packages/client/ui-extra', PREFIX + 'extra')
        self.write(self.source, 'packages/client/ui-extra/src/Extra.css', '.extra {}\n')
        self.check_changed_source('missing published metadata')

    def test_removed_package_or_sheet_in_recorded_ledger_cannot_pass_full_check(self):
        missing_package = copy.deepcopy(self.ledger)
        missing_package['packages'].remove(self.package('widget', missing_package))
        missing_package['summary'] = inventory.summary(missing_package['packages'])
        with self.assertRaisesRegex(ValueError, 'unknown UI packages'):
            inventory.check_source(missing_package, self.source, self.repo)
        missing_sheet = copy.deepcopy(self.ledger)
        self.package('widget', missing_sheet)['css'] = []
        self.package('widget', missing_sheet)['noCssClassification'] = {'kind': 'claimed-structural', 'sourceEvidence': [
            {'path': 'packages/client/ui-widget/src/index.ts', 'sha256': '0' * 64}]}
        missing_sheet['summary'] = inventory.summary(missing_sheet['packages'])
        with self.assertRaisesRegex(ValueError, 'source inventory drift'):
            inventory.check_source(missing_sheet, self.source, self.repo)

    def test_duplicate_package_source_path_retained_binding_and_json_keys_fail(self):
        cases = []
        duplicate_package = copy.deepcopy(self.ledger)
        duplicate_package['packages'].append(copy.deepcopy(duplicate_package['packages'][0]))
        cases.append((duplicate_package, 'duplicate inventory package'))
        duplicate_path = copy.deepcopy(self.ledger)
        self.package('widget', duplicate_path)['css'].append(copy.deepcopy(self.package('widget', duplicate_path)['css'][0]))
        cases.append((duplicate_path, 'duplicate source input path'))
        duplicate_binding = copy.deepcopy(self.ledger)
        refs = self.package('primitives', duplicate_binding)['css'][0]['retainedInputs']
        refs.append(refs[0])
        cases.append((duplicate_binding, 'duplicate.*retained CSS binding'))
        for ledger, pattern in cases:
            with self.subTest(pattern=pattern), self.assertRaisesRegex(ValueError, pattern):
                inventory.validate_ledger(ledger)
        duplicate_json = self.write(self.repo, 'duplicate.json', '{"path": "one", "path": "two"}')
        with self.assertRaisesRegex(ValueError, 'duplicate JSON key'):
            inventory.read_json(duplicate_json)

    def test_duplicate_source_package_identity_and_overlapping_workspace_patterns_fail(self):
        self.manifest('packages/duplicate/ui-widget', PREFIX + 'widget')
        with self.assertRaisesRegex(ValueError, 'duplicate workspace package'):
            inventory.discover(self.source)
        (self.source / 'packages/duplicate/ui-widget/package.json').unlink()
        self.write(self.source, 'pnpm-workspace.yaml', 'packages:\n  - packages/*/*\n  - packages/client/*\n')
        with self.assertRaisesRegex(ValueError, 'duplicate workspace manifest path'):
            inventory.discover(self.source)

    def test_unsafe_and_foreign_source_paths_fail(self):
        for path in ('../Widget.css', '/Widget.css', 'packages//Widget.css', 'packages/./Widget.css', 'C:/Widget.css', 'packages\\Widget.css'):
            with self.subTest(path=path), self.assertRaisesRegex(ValueError, 'unsafe inventory path'):
                inventory.relative_path(path)
        changed = copy.deepcopy(self.ledger)
        self.package('widget', changed)['css'][0]['path'] = 'packages/client/ui-primitives/src/Foreign.css'
        with self.assertRaisesRegex(ValueError, 'source input owner/hash mismatch'):
            inventory.validate_ledger(changed)

    def test_published_version_and_dependency_drift_fail(self):
        for mutate, pattern in ((lambda p: p.update(version='0.2.2'), 'identity/version drift'),
                                (lambda p: p['dependencies']['devDependencies'].update({PREFIX + 'primitives': '0.2.0'}), 'dependency version drift')):
            publications = copy.deepcopy(self.publications)
            mutate(publications[PREFIX + 'widget'])
            with self.subTest(pattern=pattern), self.assertRaisesRegex(ValueError, pattern):
                inventory.collect(self.source, self.repo, publications)

    def test_snapshot_hash_lock_and_binding_drift_fail(self):
        sheet = self.repo / 'tool/design-system/upstream/ui-primitives/Button.module.css'
        sheet.write_text('.wrong {}\n')
        with self.assertRaisesRegex(ValueError, 'retained input hash drift'):
            inventory.check_snapshots(self.ledger, self.repo)
        sheet.write_text((self.source / 'packages/client/ui-primitives/src/Button.module.css').read_text())
        changed = copy.deepcopy(self.ledger)
        self.package('primitives', changed)['css'][0]['retainedInputs'] = []
        self.package('primitives', changed)['css'][0]['retention'] = 'pending'
        changed['summary'] = inventory.summary(changed['packages'])
        with self.assertRaisesRegex(ValueError, 'retained CSS binding'):
            inventory.check_snapshots(changed, self.repo)
        self.lock['referenceCommit'] = '0' * 40
        self.write(self.repo, 'tool/design-system/sources.lock.json', inventory.encode(self.lock))
        with self.assertRaisesRegex(ValueError, 'snapshot lock/reference drift'):
            inventory.check_snapshots(self.ledger, self.repo)

    def test_snapshot_only_deliberately_does_not_claim_source_completeness(self):
        # No reference checkout exists, yet the explicitly limited offline
        # operation can still verify committed records and retained artifacts.
        moved = self.base / 'away'
        self.source.rename(moved)
        inventory.check_snapshots(self.ledger, self.repo)
        with patch.object(inventory, 'ROOT', self.repo), patch.object(inventory, 'HERE', self.repo / 'tool/design-system'):
            self.write(self.repo, 'tool/design-system/source-inventory.generated.json', inventory.encode(self.ledger))
            with patch('builtins.print') as output:
                self.assertEqual(inventory.main(['--check', '--snapshot-only']), 0)
            self.assertIn('completeness NOT independently verified', output.call_args[0][0])

    def test_full_check_never_falls_back_when_reference_source_is_missing(self):
        self.source.rename(self.base / 'away')
        with patch.object(inventory, 'ROOT', self.repo), patch.object(inventory, 'HERE', self.repo / 'tool/design-system'):
            self.write(self.repo, 'tool/design-system/source-inventory.generated.json', inventory.encode(self.ledger))
            with patch('builtins.print') as output:
                self.assertEqual(inventory.main(['--check', '--src', str(self.source)]), 1)
            self.assertNotIn('PASS', str(output.call_args))

    def test_unreachable_public_styling_package_is_recorded_as_optional_source(self):
        self.manifest('packages/experimental/example', '@deepseek-ai/dsh-experimental-example')
        self.write(self.source, 'packages/experimental/example/src/Optional.css', '.optional {}\n')
        manifest = inventory.read_json(self.source / 'packages/experimental/example/package.json')
        manifest['dist'] = {'integrity': self.integrity(manifest['name']), 'tarball': 'https://registry.npmjs.org/example.tgz'}
        self.publications[manifest['name']] = inventory.publication_record(manifest)
        with patch.object(inventory, 'verify_reference'):
            ledger = inventory.collect(self.source, self.repo, self.publications)
        optional = next(p for p in ledger['packages'] if p['name'] == manifest['name'])
        self.assertEqual(optional['scope'], 'support-styles')
        self.assertEqual(optional['reachability'], 'outside-selected-closure')
        self.assertEqual(optional['css'][0]['retention'], 'pending')

    def test_snapshot_validation_rejects_incoherent_closure_and_publication_records(self):
        for mutate, pattern in ((lambda p: p['dependencyScope']['buildUiPackages'].append(PREFIX + 'widget'), 'duplicate/unknown UI packages'),
                                (lambda p: self.package('widget', p)['publication'].update(integrity='sha512-truncated'), 'distribution integrity')):
            ledger = copy.deepcopy(self.ledger)
            mutate(ledger)
            with self.subTest(pattern=pattern), self.assertRaisesRegex(ValueError, pattern):
                inventory.check_snapshots(ledger, self.repo)

    def test_full_check_requires_the_pinned_clean_source_checkout(self):
        inventory.verify_reference(self.source, self.commit)
        with self.assertRaisesRegex(ValueError, 'HEAD differs'):
            inventory.verify_reference(self.source, '0' * 40)
        self.write(self.source, 'packages/client/ui-widget/src/Widget.module.css', '.changed {}\n')
        with self.assertRaisesRegex(ValueError, 'source checkout is dirty'):
            inventory.check_source(self.ledger, self.source, self.repo)

    def test_unknown_css_free_ui_package_is_not_automatically_marked_style_free(self):
        (self.source / 'packages/client/ui-widget/src/Widget.module.css').unlink()
        with patch.object(inventory, 'verify_reference'), self.assertRaisesRegex(ValueError, 'unclassified CSS-free UI package'):
            inventory.collect(self.source, self.repo, self.publications)

    def test_retained_published_css_alias_binds_only_its_actual_source(self):
        rows = [{'path': 'packages/client/ui-agent-preset/src/client/AgentPresetSection.module.css', 'sha256': '0' * 64}]
        snapshot = {'sourceManifest': 'packages/client/ui-agent-preset/package.json', 'files': [
            {'path': 'tool/design-system/upstream/ui-agent-preset/styles.css', 'sha256': '1' * 64}]}
        bound = inventory.bind_retained(PREFIX + 'agent-preset', rows, snapshot)
        self.assertEqual(bound[0]['retention'], 'retained-input')
        with self.assertRaisesRegex(ValueError, 'missing/ambiguous source binding'):
            inventory.bind_retained(PREFIX + 'agent-preset', [], snapshot)


class CheckedInInventoryTests(unittest.TestCase):
    def test_generated_inventory_and_retained_artifacts_are_consistent(self):
        ledger = inventory.read_json(ROOT / 'tool/design-system/source-inventory.generated.json')
        inventory.check_snapshots(ledger, ROOT)
        packages = ledger['packages']
        self.assertEqual(ledger['summary'], inventory.summary(packages))
        self.assertEqual(ledger['summary']['uiCssInputs'], sum(len(p['css']) for p in packages if p['scope'] == 'ui-package'))
        self.assertEqual(ledger['summary']['uiPackagesWithoutCss'], sum(p['scope'] == 'ui-package' and not p['css'] for p in packages))


if __name__ == '__main__':
    unittest.main()
