#!/usr/bin/env python3
"""Prepare two unsent JSON requests for a verified 225-file Card Artifact.

No CLI/network/credential/device/Git/product operations. Source the absolute
pr16-env.sh. First run --phase assets after the owner freshly reads the Artifact.
The generated request adds only new PNG paths: the complete current file set and
index remain byte-identical. After the owner publishes it and freshly reads the
result, run --phase complete with --phase1-dir and --phase1-result. The second
request includes the final index and all224 PNG paths, using {sha256,size} only
for assets verified in that actual readback. Each request is bounded to20MiB
JSON and255 listed paths. An obsolete or incomplete report/phase/readback fails
closed. Output directories must be fresh; this script never publishes them.
"""
from __future__ import annotations
import argparse
import base64
from collections import Counter
import hashlib
from html.parser import HTMLParser
import importlib.util
import json
from pathlib import Path, PurePosixPath
import re
import sys
import tempfile
import uuid

from PIL import Image

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('card_report_transport_contract', ROOT / 'scripts/plugin-cards-report.py')
report = importlib.util.module_from_spec(spec); spec.loader.exec_module(report)
contract = report.contract
require = contract.require
REQUEST_BUDGET = 20 * 1024**2
HARD_REQUEST_CAP = 24 * 1024**2
INLINE_FILE_CAP = 10 * 1024**2
VERSION_FILE_CAP, REQUEST_FILE_CAP = 500, 255


def encode(value):
    return (json.dumps(value, ensure_ascii=False, separators=(',', ':'), allow_nan=False) + '\n').encode()


def sha(value): return hashlib.sha256(value).hexdigest()


def regular(path):
    require(path.is_file() and not path.is_symlink(), 'regular nonlinked file required: ' + path.name)
    return path.read_bytes()


def json_read(path):
    return json.loads(regular(path), parse_constant=lambda x: (_ for _ in ()).throw(ValueError('nonfinite JSON')))


def file_map(rows):
    require(isinstance(rows, list) and rows and len(rows) <= VERSION_FILE_CAP, 'nonempty bounded file manifest required')
    result = {}
    for row in rows:
        require(isinstance(row, dict), 'file row must be an object')
        require(isinstance(row.get('path'), str), 'file path must be a string')
        name = str(contract.safe_relative(row.get('path')))
        size = row.get('size', row.get('bytes'))
        require(name not in result and re.fullmatch('[0-9a-f]{64}', str(row.get('sha256')))
                and type(size) is int and size > 0, 'duplicate/malformed manifest file')
        result[name] = {'sha256': row['sha256'], 'size': size}
    return result


def rows_of(files):
    return [{'path': name, **value} for name, value in sorted(files.items())]


def manifest_digest(files): return sha(encode(rows_of(files)))


class ImageSources(HTMLParser):
    def __init__(self):
        super().__init__(); self.images = []; self.external = []

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        if tag == 'img': self.images.append(values.get('src'))
        for key in ('src', 'href'):
            if values.get(key, '').startswith(('http:', 'https:', '//', 'data:')):
                self.external.append(values[key])
        if tag in ('iframe', 'link', 'base'): self.external.append(tag)


class VerifiedReport:
    def __init__(self, folder, stage, head, tree):
        require(folder.is_dir() and not folder.is_symlink(), 'completed report directory required')
        self.folder, self.stage = folder, stage
        self.receipt_bytes = regular(folder / 'build-receipt.json')
        self.receipt = json.loads(self.receipt_bytes)
        r = self.receipt
        require(r.get('schema') == 'whalee-plugin-cards-report/1' and r.get('head') == head and r.get('tree') == tree
                and re.fullmatch('[0-9a-f]{40}', head) and re.fullmatch('[0-9a-f]{40}', tree),
                'explicit exact final report head/tree required')
        require(r.get('builderSha256') == contract.digest(ROOT / 'scripts/plugin-cards-report.py'), 'report builder changed; regenerate report')
        self.evidence = report.Evidence(stage)
        accepted, pairs, _ = report.validate(self.evidence)
        require(accepted['head'] == head and accepted['tree'] == tree
                and r.get('stageManifestSha256') == self.evidence.manifest_sha256
                and r.get('visual') == accepted['visual'], 'report is not bound to completed exact final stage')
        self.files = file_map(r.get('files'))
        require(len(self.files) == r.get('requestFiles') == 225 and r.get('compositeAssets') == 224
                and r.get('originalFrames') == 448 and 'index.html' in self.files, 'exact225 report file set required')
        self.assets = set(self.files) - {'index.html'}
        require(all(n.startswith('assets/') and n.endswith('.png') for n in self.assets), 'report asset domain must be PNG paths')
        self.data = {}
        for name, row in self.files.items():
            raw = regular(folder / name)
            require(sha(raw) == row['sha256'] and len(raw) == row['size'], 'report file changed: ' + name)
            require(len(raw) <= INLINE_FILE_CAP, 'file exceeds supported inline10MiB cap')
            self.data[name] = raw
        require({p.relative_to(folder).as_posix() for p in (folder / 'assets').rglob('*') if p.is_file()} == self.assets,
                'report has missing or extra asset paths')
        document = self.data['index.html'].decode()
        require(contract.common.clean_text(document) == document, 'private path or credential signature in report')
        parser = ImageSources(); parser.feed(document)
        require(len(parser.images) == len(set(parser.images)) == 224 and set(parser.images) == self.assets
                and not parser.external, 'final HTML does not reference each complete relative asset exactly once')
        require(sum(len(v) for v in self.data.values()) == r.get('rawVersionBytes')
                and len(self.data['index.html']) == r.get('htmlBytes')
                and sum(len(self.data[n]) for n in self.assets) == r.get('assetBytes'), 'report byte totals differ')
        composites = r.get('composites', {})
        require(len(composites) == 224 and set(composites) == {p['key'] for p in pairs}
                and {c['path'] for c in composites.values()} == self.assets, 'complete composite mapping missing')
        indexed = {p['key']: p for p in pairs}
        for key, c in composites.items():
            require(c.get('bothOriginalRectanglesRGBAIdentical') is True and c.get('resized') is False
                    and c.get('recolored') is False and c.get('croppedToFit') is False
                    and c.get('sha256') == self.files[c['path']]['sha256']
                    and c.get('bytes') == self.files[c['path']]['size'], 'lossless composite identity missing')
            with Image.open(folder / c['path']) as image:
                require(image.format == 'PNG' and list(image.size) == c.get('size'), 'composite PNG size differs')
                picture = image.convert('RGBA')
                rectangles = []
                for provider, rect_name, hash_name in (('react', 'sourceRect', 'sourceSha256'), ('flutter', 'flutterRect', 'flutterSha256')):
                    rect = c.get(rect_name)
                    require(isinstance(rect, list) and len(rect) == 4 and all(type(x) is int and x >= 0 for x in rect), 'invalid original composite rectangle')
                    x, y, w, h = rect
                    require(w > 0 and h > 0 and x + w <= picture.width and y + h <= picture.height, 'original rectangle outside composite')
                    original_name = f'cards/{provider}/{key}.png'
                    require(c.get(hash_name) == indexed[key][hash_name] == self.evidence.files[original_name]['sha256'], 'original frame identity differs')
                    with self.evidence.image(original_name) as original:
                        require(original.size == (w, h) and picture.crop((x, y, x + w, y + h)).tobytes() == original.tobytes(),
                                'composite changed original RGBA rectangle')
                    rectangles.append((x, y, w, h))
                a, b = rectangles
                require(a[0] + a[2] <= b[0] or b[0] + b[2] <= a[0] or a[1] + a[3] <= b[1] or b[1] + b[3] <= a[1],
                        'original frame rectangles overlap')
        self.head, self.tree = head, tree
        self.final_digest = manifest_digest(self.files)

    def recheck(self):
        require(regular(self.folder / 'build-receipt.json') == self.receipt_bytes
                and all(sha(regular(self.folder / name)) == row['sha256'] for name, row in self.files.items()),
                'report changed during preparation')
        self.evidence.recheck()


def result_of(value, action):
    require(isinstance(value, dict) and value.get('ok') is True and isinstance(value.get('data'), dict),
            'successful actual Artifact receipt required')
    data = value['data']
    require(data.get('service', 'artifact-share') == 'artifact-share' and data.get('action', action) == action
            and (data.get('status') in (None, 200, 201)), 'wrong Artifact action/service/status')
    result = data.get('result')
    require(isinstance(result, dict) and isinstance(result.get('artifact'), dict) and isinstance(result.get('version'), dict),
            'Artifact/version readback missing')
    return result


def read_server(value, artifact, base, seen):
    result = result_of(value, 'read_artifact')
    current, version = result['artifact'], result['version']
    require(current.get('id', current.get('artifact_id')) == artifact
            and current.get('artifact_id', artifact) == artifact
            and str(uuid.UUID(base)) == base and version.get('id') == base
            and type(seen) is int and seen > 0 and type(version.get('number')) is int and version['number'] > 0
            and type(result.get('seen')) is int and result.get('seen') == seen,
            'explicit fresh read/base/seen/Artifact identity differs')
    require(version.get('current', True) is True and current.get('current_revision_id', base) == base
            and version.get('entry', 'index.html') == 'index.html', 'fresh current index version required')
    files = file_map(version.get('files'))
    require('index.html' in files, 'current page has no inherited index')
    return files, result


def compatible_base(existing, final):
    require(set(existing) <= set(final), 'base contains stale extra paths outside exact final225 set')
    require(all(name == 'index.html' or value == final[name] for name, value in existing.items()),
            'phase1 would overwrite an existing asset and could break the current page')


def inline_file(raw, png):
    require(len(raw) <= INLINE_FILE_CAP, 'inline file exceeds10MiB cap')
    return {'content_base64': base64.b64encode(raw).decode('ascii')} if png else {'content': raw.decode()}


def final_metadata(verified):
    v = verified.receipt['visual']
    return {'title': report.TITLE, 'description': f"224组真实来源与Flutter插件卡片对照，非文字99.5%达标{v['nonTextAtLeast99_5']}/224；覆盖不代表完成。"}


def request(artifact, base, seen, files, metadata):
    payload = {'artifact': artifact, 'base': base, 'seen': seen, 'entry': 'index.html', **metadata, 'files': files}
    raw = encode(payload)
    require(0 < len(files) <= REQUEST_FILE_CAP and len(raw) <= REQUEST_BUDGET and len(raw) < HARD_REQUEST_CAP,
            'request exceeds20MiB/255path preparation cap; no transport fallback attempted')
    return payload, raw


def retained_metadata(server):
    artifact, version = server['artifact'], server['version']
    title = version.get('title', artifact.get('title'))
    require(isinstance(title, str) and title and contract.common.clean_text(title) == title, 'current title missing/private')
    metadata = {'title': title}
    if isinstance(artifact.get('description'), str):
        require(contract.common.clean_text(artifact['description']) == artifact['description'], 'private current description')
        metadata['description'] = artifact['description']
    return metadata


def phase1(verified, server_files, server, artifact, base, seen):
    compatible_base(server_files, verified.files)
    missing = sorted(verified.assets - set(server_files))
    require(missing, 'all assets already present; no phase1 upload is needed')
    entries = {name: inline_file(verified.data[name], True) for name in missing}
    # Balance actual serialized asset costs between the requests, including the
    # final HTML. Stable path order makes the partition reproducible.
    target = (sum(len(encode({n: entries[n]})) for n in missing) + len(encode(inline_file(verified.data['index.html'], False)))) / 2
    selected, used = [], 0
    for name in missing:
        if used >= target: break
        selected.append(name); used += len(encode({name: entries[name]}))
    if not selected: selected = missing[:1]
    metadata = retained_metadata(server)
    payload, raw = request(artifact, base, seen, {name: entries[name] for name in selected}, metadata)
    require('index.html' not in payload['files'] and not (set(selected) & set(server_files)), 'phase1 must only add new PNG paths')
    after = {**server_files, **{name: verified.files[name] for name in selected}}
    final_files = {'index.html': inline_file(verified.data['index.html'], False)}
    for name in sorted(verified.assets):
        final_files[name] = verified.files[name] if name in after else inline_file(verified.data[name], True)
    # Placeholder UUID has the same encoded length. The final payload is emitted
    # only after the real fresh read and phase1 publish receipt validate.
    _, next_raw = request(artifact, '00000000-0000-0000-0000-000000000001', seen, final_files, final_metadata(verified))
    return payload, raw, {'uploadPaths': selected, 'expectedFilesAfterPublish': rows_of(after),
            'preservedCurrentFiles': rows_of(server_files), 'currentIndexUnchanged': server_files['index.html'],
            'baseVersionNumber': server['version']['number'],
            'predictedSecondRequestBytes': len(next_raw), 'retainedMetadata': metadata}


def validate_phase1(verified, folder, publish_result, read_files, read_result, artifact, base, seen):
    plan_bytes = regular(folder / 'plan.json'); plan = json.loads(plan_bytes)
    payload_bytes = regular(folder / 'publish.json'); payload = json.loads(payload_bytes)
    require(plan.get('schema') == 'whalee-plugin-cards-publish-plan/1' and plan.get('phase') == 'assets'
            and plan.get('artifact') == artifact and plan.get('head') == verified.head and plan.get('tree') == verified.tree
            and plan.get('reportBuildReceiptSha256') == sha(verified.receipt_bytes)
            and plan.get('finalManifestSha256') == verified.final_digest
            and file_map(plan.get('finalFiles')) == verified.files
            and plan.get('payloadSha256') == sha(payload_bytes) and plan.get('payloadBytes') == len(payload_bytes),
            'phase1 plan/payload belongs to a changed or different report')
    selected = plan.get('uploadPaths')
    require(isinstance(selected, list) and selected and len(selected) == len(set(selected))
            and set(selected) <= verified.assets, 'phase1 asset selection missing/duplicate/foreign')
    preserved = file_map(plan.get('preservedCurrentFiles'))
    compatible_base(preserved, verified.files)
    require(not (set(selected) & set(preserved)), 'phase1 overwrote inherited assets')
    after = {**preserved, **{n: verified.files[n] for n in selected}}
    require(file_map(plan.get('expectedFilesAfterPublish')) == after and plan.get('currentIndexUnchanged') == preserved['index.html'],
            'phase1 intermediate file set changed index or retained resources')
    expected_payload, expected_bytes = request(artifact, plan['base'], plan['seen'],
           {n: inline_file(verified.data[n], True) for n in selected}, plan['retainedMetadata'])
    require(payload == expected_payload and payload_bytes == expected_bytes and 'index.html' not in payload['files'],
            'phase1 actual prepared request differs from selected PNG-only update')
    published = result_of(publish_result, 'publish_artifact')
    pv = published['version']
    require(published['artifact'].get('id', published['artifact'].get('artifact_id')) == artifact
            and type(plan.get('baseVersionNumber')) is int and plan['baseVersionNumber'] > 0
            and pv.get('base') == plan['base'] and type(pv.get('number')) is int
            and pv['number'] == plan['baseVersionNumber'] + 1
            and pv.get('id') == base and base != plan['base'],
            'actual phase1 publication identity/base/version missing or stale')
    require(type(seen) is int and seen > 0 and read_result.get('seen') == seen
            and ('seen' not in published or type(published['seen']) is int and published['seen'] > 0),
            'fresh actual activity watermark required independently of revision number')
    require(file_map(pv.get('files')) == after and read_files == after
            and read_result['version']['id'] == pv['id'] and read_result['version']['number'] == pv['number'],
            'fresh full phase1 readback is incomplete, changed or from another version')
    return plan, sha(plan_bytes), sha(encode(publish_result))


def phase2(verified, existing, server, artifact, base, seen, phase_dir, publish_result):
    compatible_base(existing, verified.files)
    prior, plan_sha, publication_sha = validate_phase1(verified, phase_dir, publish_result, existing, server, artifact, base, seen)
    files = {'index.html': inline_file(verified.data['index.html'], False)}
    reused, uploaded = [], []
    for name in sorted(verified.assets):
        if name in existing:
            require(existing[name] == verified.files[name], 'already uploaded asset has wrong stored identity')
            files[name] = dict(verified.files[name]); reused.append(name)
        else:
            files[name] = inline_file(verified.data[name], True); uploaded.append(name)
    require(set(files) == set(verified.files) and len(files) == 225 and len(existing) <= VERSION_FILE_CAP,
            'final version/request must preserve exact225 paths')
    payload, raw = request(artifact, base, seen, files, final_metadata(verified))
    expected = {**existing, **verified.files}
    require(expected == verified.files, 'inherited paths would change final225 set')
    return payload, raw, {'uploadPaths': ['index.html', *uploaded], 'storedAssetReferences': reused,
        'expectedFilesAfterPublish': rows_of(verified.files), 'phase1PlanSha256': plan_sha,
        'baseVersionNumber': server['version']['number'],
        'phase1PublicationReceiptSha256': publication_sha, 'currentIndexUnchangedUntilThisAtomicRequest': existing['index.html'],
        'finalPageCompleteAfterSuccessfulPublicationOnly': True}


def prepare(args):
    script_sha = contract.digest(Path(__file__))
    require(args.out.parent.is_dir() and not args.out.exists() and not args.out.is_symlink(), 'fresh external preparation output required')
    require(not args.out.resolve().is_relative_to(args.report.resolve())
            and not args.out.resolve().is_relative_to(args.stage.resolve()), 'preparation output must not modify immutable report/stage')
    require(re.fullmatch(r'pt_[0-9a-f-]{36}', args.artifact) and str(uuid.UUID(args.artifact[3:])) == args.artifact[3:], 'existing Artifact ID required')
    verified = VerifiedReport(args.report, args.stage, args.head, args.tree)
    raw_read = regular(args.fresh_read); read = json.loads(raw_read)
    existing, server = read_server(read, args.artifact, args.base, args.seen)
    if args.phase == 'assets':
        require(args.phase1_dir is None and args.phase1_result is None, 'phase1 must not cite a previous prepared publication')
        payload, raw, details = phase1(verified, existing, server, args.artifact, args.base, args.seen)
    else:
        require(args.phase1_dir is not None and args.phase1_result is not None, 'phase2 requires actual completed phase1 plan/result')
        payload, raw, details = phase2(verified, existing, server, args.artifact, args.base, args.seen,
                                     args.phase1_dir, json_read(args.phase1_result))
    plan = {'schema': 'whalee-plugin-cards-publish-plan/1', 'phase': args.phase, 'artifact': args.artifact,
            'base': args.base, 'seen': args.seen, 'head': args.head, 'tree': args.tree,
            'reportBuildReceiptSha256': sha(verified.receipt_bytes), 'stageManifestSha256': verified.evidence.manifest_sha256,
            'finalManifestSha256': verified.final_digest, 'finalFiles': rows_of(verified.files),
            'rawFinalVersionBytes': sum(v['size'] for v in verified.files.values()),
            'freshReadReceiptSha256': sha(raw_read), 'payloadSha256': sha(raw), 'payloadBytes': len(raw),
            'listedPaths': len(payload['files']), 'requestBudgetBytes': REQUEST_BUDGET, 'published': False,
            'builderSha256': script_sha, 'quotaUnknown': True,
            'ownerMustFreshReadImmediatelyBeforeSending': True,
            'publicationOperationsPerformed': 0, **details}
    instructions = ('This is an unsent offline preparation. Re-read the current Artifact and comments immediately before sending. '
        'If base/seen changed, regenerate this request. Seen is an activity watermark, not the revision number: '
        'comments may change it without changing the base version. The service enforces the optimistic base/seen condition. '
        'Phase1 adds only new PNG files, preserving every existing file and the old index. '
        'Do not replace the visible index with a partial Card page. After a successful phase1 response, read that exact version again '
        'and use its real base/seen plus the retained phase1 response to prepare phase2. Phase2 atomically introduces the complete '
        'final index and the remaining PNG bytes, referencing already-read-back PNGs by SHA256 and size. '
        'Check the actual server quota response; the helper does not infer a plan or recommend an upgrade. '
        'After phase2 succeeds, read back and independently compare the exact225 final paths/hashes/sizes with plan.json.\n')
    with tempfile.TemporaryDirectory(prefix='.plugin-cards-publish-plan-', dir=args.out.parent) as tmp:
        target = Path(tmp) / args.out.name; target.mkdir()
        (target / 'publish.json').write_bytes(raw)
        (target / 'plan.json').write_bytes(encode(plan))
        (target / 'README.txt').write_text(instructions)
        require(regular(args.fresh_read) == raw_read, 'server-read input changed during preparation')
        require(contract.digest(Path(__file__)) == script_sha, 'transport helper changed during preparation')
        verified.recheck()
        require(not args.out.exists(), 'output appeared during preparation'); target.rename(args.out)
    print(json.dumps({k: plan[k] for k in ('phase', 'head', 'tree', 'payloadBytes', 'listedPaths', 'rawFinalVersionBytes', 'published')}))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--phase', choices=('assets', 'complete'), required=True)
    for name in ('report', 'stage', 'fresh-read', 'out'): parser.add_argument('--' + name, type=Path, required=True)
    for name in ('head', 'tree', 'artifact', 'base'): parser.add_argument('--' + name, required=True)
    parser.add_argument('--seen', type=int, required=True)
    parser.add_argument('--phase1-dir', type=Path)
    parser.add_argument('--phase1-result', type=Path)
    prepare(parser.parse_args())

if __name__ == '__main__': main()
