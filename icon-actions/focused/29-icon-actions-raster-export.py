#!/usr/bin/env python3
"""Export and compare canonical action regions on one explicit clean source tree.

Source scripts/pr16-env.sh. Source screenshots stay immutable. No color,
alpha, font, sigma or threshold tuning is performed; every RGBA difference is
retained, including known unmatched browser hover and native outline states.
"""
from collections import Counter
from pathlib import Path
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageChops, __version__ as pillow_version


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def identity(repo):
    git = lambda *args: subprocess.check_output(['git', '-C', str(repo), *args], text=True).strip()
    if git('status', '--porcelain'):
        raise RuntimeError('Final raster export requires a clean committed tree')
    return {'head': git('rev-parse', 'HEAD'), 'tree': git('rev-parse', 'HEAD^{tree}')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'source', 'out'):
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ('expected-head', 'expected-tree'):
        parser.add_argument('--' + name, required=True)
    args = parser.parse_args()
    repo, source, out = (getattr(args, key).resolve() for key in ('repo', 'source', 'out'))
    before = identity(repo)
    if before != {'head': args.expected_head, 'tree': args.expected_tree}:
        raise RuntimeError('Explicit final head/tree differs')
    if out.exists():
        raise RuntimeError('Refusing to overwrite raster evidence')
    source_data = json.loads((source / 'source-trace.json').read_text())
    snapshots = [s for t in source_data['traces'] for s in t['snapshots']]
    inputs = {str(path): sha(path) for path in [
        source / 'source-trace.json', source / 'provenance.json',
        *(source / s['file'] for s in snapshots),
        Path(__file__),
        repo / 'apps/dsh_flutter/test/parity/icon_actions_source_raster_test.dart',
        repo / 'features/dsh_feature_sidebar/lib/src/leading_controls.dart',
        repo / 'packages/dsh_ui/lib/src/dsh_button.dart',
        repo / 'packages/dsh_ui/lib/src/dsh_corners.dart',
        repo / 'packages/dsh_ui/lib/src/dsh_snapped_box.dart',
        repo / 'packages/dsh_ui/lib/src/dsh_pixel_snap.dart',
        repo / 'packages/dsh_ui/lib/src/dsh_focus_presentation.dart',
        repo / 'packages/dsh_ui/lib/src/dsh_icons.g.dart',
        repo / 'packages/dsh_ui/lib/src/dsh_shell_icons.g.dart',
        repo / 'packages/dsh_ui/lib/src/dsh_recipes.g.dart',
        repo / 'packages/dsh_theme/assets/themes/official.theme.json',
        repo / 'tool/design-system/sources.lock.json',
        repo / 'tool/design-system/recipes.generated.json',
        repo / 'tool/parity-fonts/manifest.json',
    ]}
    flutter = Path(shutil.which('flutter') or '').resolve()
    sdk = Path(os.environ['FLUTTER_SDK']).resolve()
    for file in [flutter, sdk / 'bin/cache/artifacts/engine/linux-x64/flutter_tester',
                 sdk / 'bin/cache/flutter.version.json']:
        inputs[str(file)] = sha(file)
    fonts = json.loads((repo / 'tool/parity-fonts/manifest.json').read_text())
    for family in fonts['families']:
        for face in family['faces']:
            file = repo / 'tool/parity-fonts' / face['file']
            if sha(file) != face['sha256']:
                raise RuntimeError('Pinned font bytes differ')
            inputs[str(file)] = sha(file)
    out.mkdir(parents=True)
    env = dict(os.environ, ICON_RASTER_SOURCE=str(source), ICON_RASTER_OUT=str(out / 'flutter'),
               ICON_RASTER_HEAD=args.expected_head, ICON_RASTER_TREE=args.expected_tree)
    env.pop('ICON_RASTER_PREPARE', None)
    with (out / 'capture.log').open('w') as log:
        completed = subprocess.run(
            [str(flutter), 'test', '--no-pub', 'test/parity/icon_actions_source_raster_test.dart',
             '--reporter', 'expanded', '-j', '1'],
            cwd=repo / 'apps/dsh_flutter', env=env, stdout=log, stderr=subprocess.STDOUT)
    if completed.returncode:
        raise RuntimeError('Raster exporter failed; complete log/output preserved')
    frames = json.loads((out / 'flutter/frames.json').read_text())
    if frames['mode'] != 'export' or any(frames[k] != v for k, v in before.items()):
        raise RuntimeError('Exporter identity differs')
    expected = {s['file'] for s in snapshots}
    if len(frames['frames']) != len(snapshots) or {s['sourceFile'] for s in frames['frames']} != expected:
        raise RuntimeError('Exported mapping does not cover the actual source snapshots exactly')
    rows = []
    for entry in frames['frames']:
        src = source / entry['sourceFile']
        flutter = out / 'flutter' / entry['flutterFile']
        if sha(src) != entry['sourceSha256'] or sha(flutter) != entry['flutterSha256']:
            raise RuntimeError('Input/output PNG hash differs from the exporter record')
        rect = entry['cropPhysical']
        with Image.open(src) as a, Image.open(flutter) as b:
            for picture in (a, b):
                if not (0 <= rect[0] < rect[2] <= picture.width and 0 <= rect[1] < rect[3] <= picture.height):
                    raise RuntimeError('Source-defined profile region lies outside a raster')
            reference, actual = a.convert('RGBA').crop(rect), b.convert('RGBA').crop(rect)
            sizes = {'source': list(a.size), 'flutter': list(b.size)}
        difference = ImageChops.difference(reference, actual)
        pixels = list(difference.getdata())
        changed = sum(any(channel != 0 for channel in pixel) for pixel in pixels)
        maximum = max(max(pixel) for pixel in pixels)
        mean = sum(sum(pixel) for pixel in pixels) / (len(pixels) * 4)
        directory = out / 'pairs' / Path(entry['sourceFile']).stem
        directory.mkdir(parents=True)
        for label, picture in [('source', reference), ('flutter', actual), ('rgba-difference', difference)]:
            picture.save(directory / (label + '.png'))
        # Keep the unmodified RGBA delta above. Its zero alpha plane can hide
        # nonzero RGB deltas in image viewers, so also retain an unamplified
        # RGB visualization; neither representation changes the statistics.
        difference.convert('RGB').save(directory / 'rgb-difference-visible.png')
        rows.append({**entry, 'physicalSurfaces': sizes,
                     'surfaceDimensionsMatch': sizes['source'] == sizes['flutter'],
                     'comparedPixels': len(pixels), 'changedPixels': changed,
                     'maxChannelError': maximum, 'meanAbsoluteRgbaError': mean,
                     'exactScopedRgbaEquality': changed == 0,
                     'pixelAcceptance': 'raw comparison only; no equality/score gate'})
    if identity(repo) != before or any(sha(Path(path)) != value for path, value in inputs.items()):
        raise RuntimeError('Final tree or source inputs changed during the export')
    comparison = {'schema': 'whalee-icon-action-raw-rgba/1', **before,
                  'scope': 'source-measured control regions, not full Web page or native route parity',
                  'profiles': dict(Counter(r['profile'] for r in rows)),
                  'comparedFrames': len(rows), 'exactCrops': sum(r['exactScopedRgbaEquality'] for r in rows),
                  'knownPendingFrames': sum(bool(r['pending']) for r in rows), 'rows': rows}
    (out / 'comparison.json').write_text(json.dumps(comparison, indent=2) + '\n')
    receipt = {'schema': 'whalee-icon-action-raster-identity/1', 'status': 'captured-and-compared',
               **before, 'inputSha256': inputs,
               'outputSha256': {str(p.relative_to(out)): sha(p) for p in sorted(out.rglob('*')) if p.is_file()},
               'comparedFrames': len(rows), 'profiles': comparison['profiles'],
               'comparisonRuntime': {'python': sys.version, 'pillow': pillow_version},
               'noPixelFittingOrAcceptanceThreshold': True,
               'pending': sorted({reason for row in rows for reason in row['pending']}),
               'outsideScope': ['Surrounding PluginManager page and native connection routes are outside this profile proof']}
    path = out / 'receipt.json'
    path.write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'status': receipt['status'], **before, 'frames': len(rows),
                      'profiles': comparison['profiles'], 'exactCrops': comparison['exactCrops'],
                      'receiptSha256': sha(path)}))


if __name__ == '__main__':
    main()
