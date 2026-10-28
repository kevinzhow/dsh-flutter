"""Real archive reconstruction and failure behavior, using offline fixtures."""
import base64
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('verify_release_inputs', ROOT / 'tool/design-system/verify_release_inputs.py')
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseInputTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.repo, self.cache = self.base / 'repo', self.base / 'cache'
        self.repo.mkdir()
        self.name, self.version = '@deepseek-ai/dsh-client-ui-fixture', '0.2.1-rc.2'
        self.folder = self.repo / 'tool/design-system/upstream/ui-fixture'
        self.folder.mkdir(parents=True)
        manifest = {'name': self.name, 'version': self.version}
        self.members = {'package/package.json': release.inventory.encode(manifest).encode(),
                        'package/LICENSE': b'MIT\n', 'package/lib/Fixture.module.css': b'.fixture { color: red; }\n',
                        'package/lib/index.js': b'throw new Error("must never be executed")\n'}
        self.archive = self.base / 'fixture.tgz'
        self.write_archive(self.archive, self.members)
        for name, member in {'package.json': 'package/package.json', 'LICENSE': 'package/LICENSE',
                             'Fixture.module.css': 'package/lib/Fixture.module.css'}.items():
            (self.folder / name).write_bytes(self.members[member])
        self.package = {'name': self.name, 'version': self.version,
                        'tarball': 'https://registry.npmjs.org/' + self.name + '/-/dsh-client-ui-fixture-' + self.version + '.tgz',
                        'integrity': self.integrity(self.archive), 'snapshotFolder': 'ui-fixture',
                        'sourcePackage': 'packages/client/ui-fixture/package.json', 'extractionKind': 'plain-files',
                        'files': {name: release.inventory.sha(self.folder / name) for name in ('package.json', 'LICENSE', 'Fixture.module.css')},
                        'archiveFiles': {'package.json': 'package/package.json', 'LICENSE': 'package/LICENSE',
                                         'Fixture.module.css': 'package/lib/Fixture.module.css'}}
        self.lock = {'referenceCommit': 'a' * 40, 'packages': [self.package]}
        self.update_records()

    @staticmethod
    def integrity(path):
        return 'sha512-' + base64.b64encode(hashlib.sha512(path.read_bytes()).digest()).decode()

    @staticmethod
    def write_archive(path, members):
        with tarfile.open(path, 'w:gz') as archive:
            for name, data in members.items():
                item = tarfile.TarInfo(name)
                item.size = len(data)
                archive.addfile(item, io.BytesIO(data))

    def update_records(self):
        here = self.repo / 'tool/design-system'
        here.mkdir(parents=True, exist_ok=True)
        (here / 'sources.lock.json').write_text(release.inventory.encode(self.lock))
        files = [{'path': 'tool/design-system/upstream/ui-fixture/' + name, 'sha256': digest}
                 for name, digest in sorted(self.package['files'].items())]
        publication = {'name': self.name, 'version': self.version,
                       'registryVersionUrl': release.inventory.registry_url(self.name, self.version),
                       'tarball': self.package['tarball'], 'integrity': self.package['integrity'],
                       'dependencies': release.inventory.dependencies({})}
        self.record = {'name': self.name, 'version': self.version, 'scope': 'ui-package', 'reachability': 'runtime',
                       'sourceManifest': {'path': self.package['sourcePackage'], 'sha256': 'b' * 64},
                       'sourceDependencies': release.inventory.dependencies({}), 'publication': publication,
                       'snapshot': {'status': 'retained-subset', 'sourceManifest': self.package['sourcePackage'],
                                    'version': self.version, 'integrity': self.package['integrity'], 'files': files},
                       'css': [{'path': 'packages/client/ui-fixture/src/Fixture.module.css', 'sha256': 'c' * 64,
                                'retention': 'retained-input', 'retainedInputs': ['tool/design-system/upstream/ui-fixture/Fixture.module.css']}],
                       'noCssClassification': None}
        self.ledger = {'schema': release.inventory.SCHEMA, 'meaning': release.inventory.MEANING,
                       'referenceCommit': self.lock['referenceCommit'],
                       'workspaceManifest': {'path': 'pnpm-workspace.yaml', 'sha256': 'd' * 64},
                       'snapshotLockSha256': release.inventory.sha(here / 'sources.lock.json'),
                       'dependencyScope': {
                           'roots': [{'name': 'root' + str(index), 'path': path, 'version': self.version, 'sha256': 'e' * 64}
                                     for index, path in enumerate(release.inventory.ROOT_MANIFESTS)],
                           'runtimeFields': list(release.inventory.RUNTIME_FIELDS), 'buildFields': list(release.inventory.DEPENDENCY_FIELDS),
                           'workspacePackages': 4, 'runtimeWorkspacePackages': 4, 'buildWorkspacePackages': 4,
                           'runtimeUiPackages': [self.name], 'buildUiPackages': [self.name]},
                       'summary': release.inventory.summary([self.record]), 'packages': [self.record]}
        self.write_ledger()

    def write_ledger(self):
        (self.repo / 'tool/design-system/source-inventory.generated.json').write_text(release.inventory.encode(self.ledger))

    def cached(self, data=None):
        self.cache.mkdir(exist_ok=True)
        path = release.archive_path(self.cache, self.package)
        path.write_bytes(self.archive.read_bytes() if data is None else data)
        return path

    def test_offline_run_reconstructs_all_locked_files_using_existing_decoder(self):
        path = self.cached()
        before = path.read_bytes()
        with patch.object(release, 'download_archive', side_effect=AssertionError('offline attempted network')):
            with patch.object(release.published, 'verify_snapshot', wraps=release.published.verify_snapshot) as decoder:
                with patch('subprocess.run', side_effect=AssertionError('package code execution attempted')):
                    receipt = release.verify_all(self.repo, self.cache, offline=True)
        decoder.assert_called_once_with(path, self.package, self.folder)
        self.assertTrue(receipt['allPassed'])
        self.assertTrue(receipt['offline'])
        self.assertEqual(receipt['packageCount'], len(self.lock['packages']))
        self.assertEqual(receipt['verifiedSnapshotFiles'], len(self.package['files']))
        self.assertEqual(receipt['packages'][0]['archiveOrigin'], 'cache-hit')
        self.assertTrue(receipt['packages'][0]['archiveUnchanged'])
        self.assertEqual(path.read_bytes(), before)

    def test_corrupted_cache_is_preserved_and_never_silently_redownloaded(self):
        path = self.cached(b'corrupt cache')
        download = Mock(side_effect=AssertionError('bad cache must not be replaced'))
        with self.assertRaisesRegex(ValueError, 'cached archive integrity mismatch.*entry preserved'):
            release.ensure_archive(self.package, self.cache, False, download)
        download.assert_not_called()
        self.assertEqual(path.read_bytes(), b'corrupt cache')

    def test_offline_missing_cache_entry_never_fetches_or_creates_cache(self):
        download = Mock()
        with self.assertRaisesRegex(ValueError, 'offline: missing locked archive'):
            release.ensure_archive(self.package, self.cache, True, download)
        download.assert_not_called()
        self.assertFalse(self.cache.exists())

    def test_download_is_missing_only_integrity_checked_and_atomically_published(self):
        target = release.archive_path(self.cache, self.package)
        def download(package, partial):
            self.assertFalse(target.exists())
            self.assertEqual(partial.parent, self.cache)
            self.assertNotEqual(partial, target)
            partial.write_bytes(self.archive.read_bytes())
        first = Mock(side_effect=download)
        path, origin = release.ensure_archive(self.package, self.cache, False, first)
        self.assertEqual((path, origin), (target, 'downloaded'))
        self.assertEqual(path.read_bytes(), self.archive.read_bytes())
        self.assertEqual(list(self.cache.glob('.*partial-*')), [])
        second = Mock(side_effect=AssertionError('cache hit attempted download'))
        self.assertEqual(release.ensure_archive(self.package, self.cache, False, second), (target, 'cache-hit'))
        first.assert_called_once()
        second.assert_not_called()

    def test_incomplete_or_wrong_download_is_not_installed(self):
        def wrong(package, partial):
            partial.write_bytes(b'not the locked release')
        with self.assertRaisesRegex(ValueError, 'downloaded archive integrity mismatch'):
            release.ensure_archive(self.package, self.cache, False, wrong)
        self.assertEqual(list(self.cache.iterdir()), [])
        def interrupted(package, partial):
            partial.write_bytes(b'partial')
            raise OSError('connection interrupted')
        with self.assertRaisesRegex(OSError, 'connection interrupted'):
            release.ensure_archive(self.package, self.cache, False, interrupted)
        self.assertEqual(list(self.cache.iterdir()), [])

    def test_atomic_publication_does_not_replace_concurrently_corrupted_entry(self):
        target = release.archive_path(self.cache, self.package)
        def race(package, partial):
            partial.write_bytes(self.archive.read_bytes())
            target.write_bytes(b'concurrent bad entry')
        with self.assertRaisesRegex(ValueError, 'concurrently cached archive integrity mismatch'):
            release.ensure_archive(self.package, self.cache, False, race)
        self.assertEqual(target.read_bytes(), b'concurrent bad entry')
        self.assertEqual(list(self.cache.glob('.*partial-*')), [])

    def test_cache_symlinks_are_not_followed(self):
        path = release.archive_path(self.cache, self.package)
        self.cache.mkdir()
        path.symlink_to(self.archive)
        with self.assertRaisesRegex(ValueError, 'not a regular owned cache file'):
            release.ensure_archive(self.package, self.cache, True)
        self.assertTrue(path.is_symlink())

    def test_only_exact_public_locked_package_version_urls_are_allowed(self):
        for url in ('https://example.org/release.tgz', self.package['tarball'] + '?token=not-a-real-token',
                    self.package['tarball'].replace('https://', 'https://user@'),
                    self.package['tarball'].replace(self.version, '0.2.0'), 'file:///local/archive.tgz'):
            package = copy.deepcopy(self.package)
            package['tarball'] = url
            with self.subTest(url=url), self.assertRaisesRegex(ValueError, 'exact public npm package/version URL'):
                release.ensure_archive(package, self.cache, False, Mock())
        for name, version in (('@another-scope/dsh-client-ui-fixture', self.version), (self.name, '../other')):
            package = {**self.package, 'name': name, 'version': version}
            with self.subTest(name=name, version=version), self.assertRaisesRegex(ValueError, 'unsupported locked npm identity'):
                release.canonical_identity(package)

    def test_inventory_and_lock_publication_identities_must_agree(self):
        self.record['publication']['integrity'] = 'sha512-' + base64.b64encode(b'x' * 64).decode()
        self.write_ledger()
        with self.assertRaisesRegex(ValueError, 'inventory publication identity differ'):
            release.load_plan(self.repo)

    def test_lock_and_inventory_rehashing_cannot_hide_released_css_drift(self):
        self.cached()
        css = self.folder / 'Fixture.module.css'
        css.write_text('.fixture { color: blue; }\n')
        # Both editable records deliberately agree with the wrong local CSS.
        # The released archive must still be the independent reconstruction input.
        self.package['files']['Fixture.module.css'] = release.inventory.sha(css)
        self.update_records()
        release.load_plan(self.repo)
        with self.assertRaisesRegex(ValueError, 'published plain-file snapshot mismatch: Fixture.module.css'):
            release.verify_all(self.repo, self.cache, offline=True)

    def test_integrity_verified_archive_with_wrong_manifest_identity_fails(self):
        members = {**self.members, 'package/package.json': b'{"name":"wrong-package","version":"0.2.1-rc.2"}\n'}
        self.write_archive(self.archive, members)
        self.package['integrity'] = self.integrity(self.archive)
        self.update_records()
        self.cached()
        with self.assertRaisesRegex(ValueError, 'archive package identity/version mismatch'):
            release.verify_all(self.repo, self.cache, offline=True)

    def test_archive_dependency_declarations_must_match_published_inventory(self):
        members = {**self.members, 'package/package.json': release.inventory.encode({
            'name': self.name, 'version': self.version, 'dependencies': {'unexpected-package': '1.0.0'}}).encode()}
        self.write_archive(self.archive, members)
        self.package['integrity'] = self.integrity(self.archive)
        self.update_records()
        self.cached()
        with self.assertRaisesRegex(ValueError, 'archive dependency declarations differ'):
            release.verify_all(self.repo, self.cache, offline=True)

    def test_receipt_cannot_bind_to_inventory_changed_during_verification(self):
        self.cached()
        actual = release.published.verify_snapshot
        def changing_inventory(path, package, folder):
            actual(path, package, folder)
            with (self.repo / 'tool/design-system/source-inventory.generated.json').open('a') as stream:
                stream.write(' ')
        with patch.object(release.published, 'verify_snapshot', side_effect=changing_inventory):
            with self.assertRaisesRegex(ValueError, 'verification inputs changed during'):
                release.verify_all(self.repo, self.cache, offline=True)

    def test_retained_file_mutation_after_decoder_cannot_produce_success(self):
        self.cached()
        actual = release.published.verify_snapshot
        def changing_snapshot(path, package, folder):
            actual(path, package, folder)
            (folder / 'Fixture.module.css').write_text('.changed-after-decoding {}\n')
        with patch.object(release.published, 'verify_snapshot', side_effect=changing_snapshot):
            with self.assertRaisesRegex(ValueError, 'retained input hash drift'):
                release.verify_all(self.repo, self.cache, offline=True)

    def test_redirects_are_refused_instead_of_fetching_another_identity(self):
        with self.assertRaisesRegex(ValueError, 'redirect refused'):
            release.NoRedirects().redirect_request(None, None, 302, 'Moved', {}, 'https://example.org/elsewhere')

    def test_cli_writes_receipt_only_after_complete_success(self):
        self.cached()
        receipt = self.base / 'receipts/success.json'
        with patch.object(release, 'ROOT', self.repo), patch('builtins.print'):
            self.assertEqual(release.main(['--cache-dir', str(self.cache), '--offline', '--receipt', str(receipt)]), 0)
        saved = json.loads(receipt.read_text())
        self.assertTrue(saved['allPassed'])
        self.assertEqual(saved['sourceLockSha256'], release.inventory.sha(self.repo / 'tool/design-system/sources.lock.json'))
        self.assertNotIn(str(self.base), receipt.read_text())
        self.assertEqual(list(receipt.parent.glob('.success.json.*')), [])
        release.archive_path(self.cache, self.package).write_bytes(b'bad')
        failure = receipt.parent / 'failed.json'
        with patch.object(release, 'ROOT', self.repo), patch('builtins.print'):
            self.assertEqual(release.main(['--cache-dir', str(self.cache), '--offline', '--receipt', str(failure)]), 1)
        self.assertFalse(failure.exists())


class CheckedInReleasePlanTests(unittest.TestCase):
    def test_every_current_locked_package_has_one_inventory_bound_archive(self):
        lock, plan = release.load_plan(ROOT)
        self.assertEqual(len(plan), len(lock['packages']))
        self.assertEqual({p['name'] for p, _, _ in plan}, {p['name'] for p in lock['packages']})


if __name__ == '__main__':
    unittest.main()
