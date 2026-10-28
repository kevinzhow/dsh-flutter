#!/usr/bin/env python3
"""Reconstruct every locked retained input from integrity-verified npm archives.

No package code is executed. Cached archives are revalidated on every run. A bad
cache entry fails and is preserved; only missing entries may be downloaded.
"""
import argparse
import base64
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import sys
import tarfile
import tempfile
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener


ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
MAX_ARCHIVE_BYTES = 64 * 1024 * 1024


def module(name):
    spec = importlib.util.spec_from_file_location('release_' + name, HERE / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


inventory, published = module('source_inventory'), module('published')


def canonical_identity(package):
    name, version = package['name'], package['version']
    if (not re.fullmatch(r'@deepseek-ai/dsh-client-ui-[a-z0-9]+(?:-[a-z0-9]+)*', name)
            or not re.fullmatch(r'\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?', version)):
        raise ValueError('unsupported locked npm identity: ' + name + '@' + version)
    leaf = name.split('/')[1]
    url = 'https://registry.npmjs.org/' + name + '/-/' + leaf + '-' + version + '.tgz'
    if package['tarball'] != url:
        raise ValueError('locked tarball must be the exact public npm package/version URL: ' + name)
    if not package['integrity'].startswith('sha512-'):
        raise ValueError('published.verify_snapshot requires locked SHA-512 integrity: ' + name)
    return url


def load_plan(repo):
    lock_path = repo / 'tool/design-system/sources.lock.json'
    inventory_path = repo / 'tool/design-system/source-inventory.generated.json'
    lock, ledger = inventory.read_json(lock_path), inventory.read_json(inventory_path)
    # This validates the complete retained lock/file set as well as the inventory
    # bindings. It is additional to, not a substitute for, archive reconstruction.
    inventory.check_snapshots(ledger, repo)
    records = {record['name']: record for record in ledger['packages']}
    plan = []
    for package in lock['packages']:
        canonical_identity(package)
        record = records[package['name']]
        publication = record['publication']
        if (publication['name'], publication['version'], publication['tarball'], publication['integrity']) != (
                package['name'], package['version'], package['tarball'], package['integrity']):
            raise ValueError('locked archive and inventory publication identity differ: ' + package['name'])
        if publication['registryVersionUrl'] != inventory.registry_url(package['name'], package['version']):
            raise ValueError('inventory publication endpoint differs from locked identity: ' + package['name'])
        plan.append((package, record, repo / 'tool/design-system/upstream' / package['snapshotFolder']))
    if not plan:
        raise ValueError('empty locked release-input plan')
    return lock, plan


def archive_path(cache, package):
    canonical_identity(package)
    return cache / (package['name'].removeprefix('@').replace('/', '-') + '-' + package['version'] + '.tgz')


def archive_hashes(path):
    if not path.is_file() or path.is_symlink():
        raise ValueError('archive is missing or is not a regular owned cache file: ' + path.name)
    sha256, sha512 = hashlib.sha256(), hashlib.sha512()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(64 * 1024), b''):
            sha256.update(chunk)
            sha512.update(chunk)
    return {'sha256': sha256.hexdigest(), 'integrity': 'sha512-' + base64.b64encode(sha512.digest()).decode()}


def verify_integrity(path, package, context):
    hashes = archive_hashes(path)
    if hashes['integrity'] != package['integrity']:
        raise ValueError(context + ' archive integrity mismatch: ' + path.name
                         + '; entry preserved, no automatic replacement')
    return hashes


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, message, headers, newurl):
        raise ValueError('redirect refused for locked public npm archive')


def download_archive(package, destination):
    url = canonical_identity(package)
    # Do not read npm credentials, netrc, proxy credentials, cookies or a package
    # manager's configuration. Fetch one literal public HTTPS URL, no redirects.
    opener = build_opener(ProxyHandler({}), NoRedirects())
    request = Request(url, headers={'User-Agent': 'Whalee-source-input-verifier/1'})
    with opener.open(request, timeout=30) as response, destination.open('wb') as stream:
        if response.geturl() != url:
            raise ValueError('response URL differs from locked public npm archive')
        size = 0
        while chunk := response.read(64 * 1024):
            size += len(chunk)
            if size > MAX_ARCHIVE_BYTES:
                raise ValueError('locked archive exceeds verifier download size limit')
            stream.write(chunk)
        stream.flush()
        os.fsync(stream.fileno())


def ensure_archive(package, cache, offline, download=None):
    cache = Path(cache)
    if cache.is_symlink():
        raise ValueError('release archive cache must not be a symlink')
    target = archive_path(cache, package)
    if target.exists() or target.is_symlink():
        verify_integrity(target, package, 'cached')
        return target, 'cache-hit'
    if offline:
        raise ValueError('offline: missing locked archive cache entry: ' + target.name)
    cache.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix='.' + target.name + '.partial-', dir=cache)
    os.close(descriptor)
    partial = Path(temporary)
    try:
        (download or download_archive)(package, partial)
        verify_integrity(partial, package, 'downloaded')
        try:
            # Publish the complete verified file atomically, without replacing
            # a cache entry that another process may have installed meanwhile.
            os.link(partial, target)
            origin = 'downloaded'
        except FileExistsError:
            verify_integrity(target, package, 'concurrently cached')
            origin = 'cache-hit'
        return target, origin
    finally:
        partial.unlink(missing_ok=True)


def verify_archive(path, package, record, folder):
    before = verify_integrity(path, package, 'cached')
    with tarfile.open(path) as archive:
        manifests = [member for member in archive.getmembers() if member.name == 'package/package.json']
        if len(manifests) != 1 or not manifests[0].isfile():
            raise ValueError('archive package manifest is missing/duplicate/not regular: ' + package['name'])
        manifest = json.loads(archive.extractfile(manifests[0]).read(), object_pairs_hook=inventory.unique_object)
    if (manifest.get('name'), manifest.get('version')) != (package['name'], package['version']):
        raise ValueError('archive package identity/version mismatch: ' + package['name'])
    if inventory.dependencies(manifest) != record['publication']['dependencies']:
        raise ValueError('archive dependency declarations differ from inventory publication: ' + package['name'])
    # Existing decoder verifies archive integrity again, extracts only declared
    # static files/JSON literals, and compares CSS/classes/behavior/metadata.
    verified = published.verify_snapshot(path, package, folder)
    after = verify_integrity(path, package, 'cached after reconstruction')
    if before != after:
        raise ValueError('archive changed during snapshot reconstruction: ' + package['name'])
    return {'name': package['name'], 'version': package['version'], 'tarball': package['tarball'],
            'integrity': package['integrity'], 'archiveFile': path.name, 'archiveSha256': after['sha256'],
            'archiveUnchanged': True, 'snapshotFiles': len(verified),
            'extractionKind': package.get('extractionKind', 'plugin-css'), 'verified': True}


def verify_all(repo, cache, offline=False):
    started = datetime.now(timezone.utc).isoformat()
    identity_paths = {'sourceLockSha256': repo / 'tool/design-system/sources.lock.json',
                      'sourceInventorySha256': repo / 'tool/design-system/source-inventory.generated.json',
                      'verificationToolSha256': Path(__file__).resolve(),
                      'publishedVerifierSha256': HERE / 'published.py',
                      'inventoryVerifierSha256': HERE / 'source_inventory.py'}
    identities = {name: inventory.sha(path) for name, path in identity_paths.items()}
    lock, plan = load_plan(repo)
    results = []
    for package, record, folder in plan:
        try:
            path, origin = ensure_archive(package, cache, offline)
            result = verify_archive(path, package, record, folder)
            result['archiveOrigin'] = origin
            results.append(result)
        except (ValueError, OSError, KeyError, tarfile.TarError) as error:
            raise ValueError(package['name'] + ': ' + str(error)) from error
    if identities != {name: inventory.sha(path) for name, path in identity_paths.items()}:
        raise ValueError('verification inputs changed during archive reconstruction; no success receipt')
    load_plan(repo)  # Retained files must still match their locked hashes too.
    return {'schema': 'dsh-release-input-verification/1', 'referenceCommit': lock['referenceCommit'],
            **identities, 'verificationInputsUnchanged': True,
            'startedAt': started, 'completedAt': datetime.now(timezone.utc).isoformat(),
            'offline': offline, 'packageCount': len(results),
            'verifiedSnapshotFiles': sum(row['snapshotFiles'] for row in results),
            'verification': 'published.verify_snapshot; no JavaScript execution',
            'meaning': 'Reconstruction of locked retained inputs only; whole-family implementation and visual acceptance are not assessed.',
            'allPassed': True, 'packages': results}


def write_receipt(path, receipt):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix='.' + path.name + '.', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'w') as stream:
            stream.write(inventory.encode(receipt))
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cache-dir', type=Path, default=Path(os.environ.get('DSH_RELEASE_CACHE', ROOT / '.local/release-input-archives')))
    parser.add_argument('--offline', action='store_true', help='require every locked archive already in cache; never fetch')
    parser.add_argument('--receipt', type=Path, help='write a complete machine-readable verification receipt after success')
    args = parser.parse_args(argv)
    try:
        receipt = verify_all(ROOT, args.cache_dir, args.offline)
        if args.receipt:
            write_receipt(args.receipt, receipt)
        print('release-inputs: PASS; reconstructed ' + str(receipt['packageCount']) + ' locked releases / '
              + str(receipt['verifiedSnapshotFiles']) + ' retained snapshots; cached archives revalidated; no JS execution')
    except (ValueError, OSError, KeyError, tarfile.TarError) as error:
        print('release-inputs: ' + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
