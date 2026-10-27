#!/usr/bin/env python3
"""Stage completed headed-dialog evidence; never commit, push, upload or run devices.

Run only after final capture, full preflight, four builds, native replays and
cleanup. Every runtime result below comes from a completed receipt. Diagnostic
source scrollbar screenshots remain separate from the fixed parity captures.
"""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT / 'scratch/whalee-headed-dialogs'
REFERENCE = ROOT / 'scratch/whalee-headed-reference'
BASE = '942090b4c2eded5991a92209a101fd20de787c99'
PREFIX = 'components.headed-dialogs.risk-'
THRESHOLD = 99.5
METRIC_FIELDS = ('key', 'caseId', 'kind', 'theme', 'nonTextPct', 'pixelPerfectPct', 'rgbPct',
                 'sizeReact', 'sizeFlutter', 'sideBySide')
CHECKS = {'check-deps', 'tool-tests', 'codegen', 'theme-pack', 'design-system', 'i18n',
          'icons', 'vector', 'parity', 'capability', 'format', 'analyze', 'tests'}
SENSITIVE = re.compile(
    r'-----BEGIN [^-\n]*PRIVATE KEY-----|'
    r'\b(?:sk-(?:proj-)?[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|'
    r'github_pat_[A-Za-z0-9_]{20,})\b|\bBearer\s+[A-Za-z0-9._=-]{12,}', re.I)
IMPLEMENTATION = (
    'packages/dsh_ui/lib/dsh_ui.dart',
    *('packages/dsh_ui/lib/src/' + name for name in (
        'dsh_risk_dialog.dart', 'dsh_headed_dialog.dart', 'dsh_option_sheet.dart',
        'dsh_settings.dart', 'dsh_button.dart', 'dsh_presentation.dart',
        'dsh_focus_presentation.dart', 'dsh_control_focus_modality.dart', 'dsh_recipes.g.dart')),
    'features/dsh_feature_permission_presets/lib/src/permission_widgets.dart',
    'features/dsh_feature_commands/lib/src/popup_view.dart',
)
TESTS = tuple('packages/dsh_ui/test/' + name for name in (
    'dsh_headed_dialog_test.dart', 'dsh_risk_dialog_test.dart', 'dsh_risk_dialog_focus_test.dart',
    'dsh_checkbox_test.dart', 'dsh_dialog_lifecycle_test.dart', 'dsh_focus_presentation_test.dart',
    'dsh_dialog_reader_test.dart')) + ('tool/tests/test_design_system.py',)
REPRODUCTION = (
    'tool/design-system/generate.py', 'tool/design-system/modal_recipes.py',
    'tool/design-system/risk_recipes.py', 'tool/design-system/published.py',
    'tool/design-system/css.py', 'tool/design-system/checkbox_recipes.py',
    'tool/parity-ext/build-headed-dialogs.py', 'tool/parity-ext/host/headed-dialogs.tsx',
    'apps/dsh_flutter/test/parity/cases/headed_dialogs.dart',
    'apps/dsh_flutter/test/parity/headed_dialogs_main.dart',
    'tool/parity-desktop/gpu_capture.py', 'tool/parity-desktop/weston_input.c',
    'tool/parity-desktop/headed-dialogs-cases.json',
)
SOURCE_FILES = tuple('packages/client/ui-primitives/' + name for name in (
    'src/Modal.tsx', 'src/Modal.module.css', 'src/useModalLayer.ts', 'src/focus.ts',
    'src/keyboard-composition.ts', 'src/RiskConfirmation.tsx', 'src/RiskConfirmation.module.css',
    'src/Checkbox.tsx', 'src/Checkbox.module.css', 'src/Button.tsx', 'src/Button.module.css',
    'tests/modal-layer.client.spec.tsx'))


def require(condition, message):
    if not condition:
        raise ValueError(message)


def git(*args, cwd=REPO):
    return subprocess.check_output(['git', *args], cwd=cwd, text=True).strip()


def load(path):
    return json.loads(path.read_text())


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    return digest.hexdigest()


def clean_text(value, *, code=False):
    require(not SENSITIVE.search(value), 'credential-shaped content in an evidence input')
    value = value.replace(str(ROOT), '[workspace]')
    if code:
        return value  # Preserve synthetic paths and loopback templates in reproduction code.
    value = re.sub(r'/home/[^\s\"\'<>]+', '[home-path]', value)
    value = re.sub(r'/run/user/\d+(?:/[^\s\"\'<>]*)?', '[runtime-path]', value)
    return re.sub(r'https?://(?:127\.0\.0\.1|localhost|\[::1\])(?::\d+)?[^\s\"\'<>]*',
                  '[local-runtime-url]', value)


def clean(value):
    if isinstance(value, dict):
        return {clean_text(str(key)): clean(item) for key, item in value.items()}
    if isinstance(value, list):
        return [clean(item) for item in value]
    return clean_text(value) if isinstance(value, str) else value


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(clean(value), indent=2, ensure_ascii=False) + '\n')


def copy_text(source, target, *, code=False):
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(clean_text(source.read_text(), code=code))


def copy_png(source, target):
    with Image.open(source) as picture:
        require(picture.format == 'PNG' and min(picture.size) > 0, 'invalid evidence PNG')
        picture.verify()
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def relative_path(value):
    path = Path(value)
    require(not path.is_absolute() and '..' not in path.parts, 'unsafe evidence relative path')
    return path


def proof_input(name, override=None):
    if override is not None:
        require(override.exists(), 'missing explicit source proof: ' + name)
        return override
    for base in (REPO, REFERENCE):
        path = base / '.local' / name
        if path.exists():
            return path
    raise ValueError('missing completed source proof: ' + name)


def near(left, right, message, tolerance=.02):
    require(isinstance(left, (int, float)) and isinstance(right, (int, float))
            and math.isfinite(left) and math.isfinite(right)
            and abs(left - right) <= tolerance, message)


def expected_groups():
    common = [(device, locale, theme) for device in ('desktop', 'phone')
              for locale in ('en', 'zh') for theme in ('light', 'dark')]
    return {
        'cards': {f'{PREFIX}{d}-{l}-card-{state}.{t}' for d, l, t in common
                  for state in ('off', 'on', 'off-disabled', 'on-disabled')},
        'long-cards': {f'{PREFIX}{d}-{l}-long-card-{position}.{t}' for d, l, t in common
                       for position in ('top', 'bottom')},
        'footers': {f'{PREFIX}{d}-{l}-long-footer-{position}.{t}' for d, l, t in common
                    for position in ('top', 'bottom')},
    }


def preservation_groups():
    return {
        'reader': {f'components.dialog-family.{part}-{d}-{l}-{page}.{t}'
                   for part in ('reader', 'tabs', 'panel-scrolled', 'panel-retained')
                   for d in ('desktop', 'phone') for l in ('en', 'zh')
                   for page in ('explanation', 'usage') for t in ('light', 'dark')},
        'model-checkbox': {f'components.checkbox-family.model-{d}-{l}-{state}.{t}'
                           for d in ('desktop', 'phone') for l in ('en', 'zh')
                           for state in ('off', 'on', 'off-disabled', 'on-disabled')
                           for t in ('light', 'dark')},
    }


def validate_cases(cases, expected):
    require(len(cases) == len(expected) and {case['key'] for case in cases} == expected,
            'capture keys differ from the exact declared cohort')
    for case in cases:
        require(re.fullmatch(r'[A-Za-z0-9_.-]+', case['key']), 'unsafe capture key')
        metric = case.get('nonTextPct')
        require(type(metric) in (int, float) and math.isfinite(metric) and 0 <= metric <= 100,
                'missing measured nonTextPct: ' + case['key'])
        for field in ('sizeReact', 'sizeFlutter'):
            require(len(case.get(field, [])) == 2 and all(type(n) is int and n > 0 for n in case[field]),
                    'missing capture dimensions: ' + case['key'])


def stats(cases):
    require(cases, 'empty visual group')
    return {'compared': len(cases), 'dimensionsEqual': sum(c['sizeReact'] == c['sizeFlutter'] for c in cases),
            'nonTextPassing': sum(c['nonTextPct'] >= THRESHOLD for c in cases),
            'meanNonTextPct': sum(c['nonTextPct'] for c in cases) / len(cases)}


def case_metrics(cases):
    return [{key: case[key] for key in METRIC_FIELDS if key in case} for case in cases]


def png_comparison(left, right):
    with Image.open(left) as a, Image.open(right) as b:
        a, b = a.convert('RGBA'), b.convert('RGBA')
        same = a.size == b.size and a.tobytes() == b.tobytes()
        bounds = ImageChops.difference(a, b).getbbox(alpha_only=False) if a.size == b.size and not same else None
        return {'rgbaByteEqual': same, 'sizeBefore': list(a.size), 'sizeAfter': list(b.size),
                'changedPixelBounds': list(bounds) if bounds else None}


def capture_path(folder, provider, key):
    return folder / 'visual-testing-results' / provider / (key + '.png')


def verify_capture(folder, provider, case):
    path = capture_path(folder, provider, case['key'])
    field = 'sizeReact' if provider == 'react' else 'sizeFlutter'
    with Image.open(path) as picture:
        require(picture.format == 'PNG' and list(picture.size) == case[field], 'capture/summary size mismatch')
    meta = load(path.with_suffix('.metadata.json'))
    require(meta.get('provider') == provider and meta.get('captureKey') == case['key'],
            'capture metadata identity mismatch')
    return meta


def validate_source_layout(data, browser):
    groups = expected_groups()
    expected = groups['cards'] | groups['long-cards']
    rows = data['rows']
    require(data.get('implicitScrollbarHidden') is True and len(rows) == 48
            and {row['key'] for row in rows} == expected, 'incomplete source layout coverage')
    disabled_count, long_count, disabled_tab_keys = 0, 0, set()
    for row in rows:
        require(row['browser'] == browser, 'source layout browser differs from the pinned renderer')
        state, props = row['initial'], row['props']
        nodes, focus = state['nodes'], state['focus']
        require(state['supportsDvh'] is True and state['footerOutsideContent'] is True
                and state['dialogChildren'] == ['risk-content', 'risk-footer'], 'source content/footer ownership changed')
        near(state['dpr'], 2.625 if '-phone-' in row['key'] else 1, 'source density mismatch')
        require(nodes['risk-checkbox']['checked'] is props['checked']
                and nodes['risk-checkbox']['disabled'] is props['disabled']
                and nodes['risk-confirm']['disabled'] is (props['disabled'] or not props['checked']),
                'source controlled checkbox/confirm gating proof missing')
        require(nodes['risk-content']['css']['overflowY'] == 'auto'
                and nodes['risk-content']['css']['overscrollBehaviorY'] == 'contain'
                and nodes['risk-content']['css']['scrollbarGutter'] == 'auto', 'source risk scroll profile changed')
        require(nodes['risk-dialog']['css']['gap'] == '20px'
                and nodes['risk-dialog']['css']['paddingBottom'] == '24px'
                and nodes['risk-body']['css']['marginTop'] == '20px', 'source headed spacing changed')
        if props['disabled']:
            disabled_count += 1
            require(focus['body'] is True and focus['inDialog'] is False, 'source disabled BODY focus proof missing')
            if 'afterTab' in row:
                require(row['afterTab']['focus']['id'] == 'risk-close', 'source disabled first-Tab proof changed')
                disabled_tab_keys.add(row['key'])
        else:
            require(focus['id'] == 'risk-checkbox' and focus['automatic'] is True
                    and 'none 0px' in focus['outline'], 'source preferred checkbox entry proof missing')
        if 'top' in row:
            long_count += 1
            top, bottom = row['top']['nodes'], row['bottom']['nodes']
            near(nodes['risk-dialog']['rect']['height'], state['viewport']['height'] - 48, 'source dynamic viewport cap changed')
            near(top['risk-content']['scrollTop'], 0, 'source explicit top scroll is missing')
            require(bottom['risk-content']['scrollTop'] > 0 and top['risk-footer']['rect'] == bottom['risk-footer']['rect'],
                    'source positive scroll or fixed footer proof missing')
            delta = bottom['risk-content']['scrollTop'] - top['risk-content']['scrollTop']
            for name in ('risk-header', 'risk-body'):
                near(top[name]['rect']['y'] - bottom[name]['rect']['y'], delta, 'source header/body did not scroll together')
            near(top['risk-content']['rect']['height'], 192, 'source long content height changed')
            near(top['risk-footer']['rect']['y'] - top['risk-content']['rect']['bottom'], 20, 'source long gap changed')
    require(disabled_count == 16 and long_count == 16, 'source disabled/long cohorts are incomplete')
    require({f'{PREFIX}desktop-en-card-{state}-disabled.light' for state in ('off', 'on')} <= disabled_tab_keys,
            'source disabled first-Tab examples are missing')
    return {'contexts': len(rows), 'disabledBodyFocusContexts': disabled_count, 'fixedFooterContexts': long_count,
            'disabledFirstTabCloseContexts': len(disabled_tab_keys), 'browser': browser, 'implicitScrollbarHidden': True}


def validate_open_scroll(data):
    keys = {key for key in expected_groups()['long-cards'] if '-top.' in key}
    timings = ('ordinary-mount', 'fonts-ready-before-mount')
    rows = data['rows']
    require(data.get('implicitScrollbarHidden') is True and len(rows) == 16
            and {(r['key'], r['timing']) for r in rows} == {(key, timing) for key in keys for timing in timings},
            'source initial-scroll coverage is incomplete')
    cold_hidden, ready = 0, 0
    for row in rows:
        require(row['explicitScrollActionsApplied'] is False, 'initial-scroll proof applied explicit scrolling')
        initial = row['initial']; summary = row['initialSummary']; focus = initial['focus']
        require(focus['id'] == 'risk-checkbox' and focus['automatic'] is True
                and 'none 0px' in focus['outline'] and summary['scrollTop'] > 0,
                'source automatic initial checkbox reveal is missing')
        require(row['afterTab']['focus']['id'] == 'risk-cancel'
                and row['afterReturnToCheckbox']['focus']['id'] == 'risk-checkbox'
                and row['afterShiftTabClose']['focus']['id'] == 'risk-close', 'source keyboard traversal proof missing')
        near(row['afterShiftTabClose']['nodes']['risk-content']['scrollTop'], 0, 'Close did not reveal the source header')
        footer = initial['nodes']['risk-footer']['rect']
        require(all(row[name]['nodes']['risk-footer']['rect'] == footer
                    for name in ('afterTab', 'afterReturnToCheckbox', 'afterShiftTabClose')), 'source autofocus moved the footer')
        if row['timing'] == 'fonts-ready-before-mount':
            ready += 1
            require(row.get('preloadProof') and all(font['status'] == 'loaded' for font in row['preloadProof'])
                    and summary['checkboxFullyVisible'] is True, 'fonts-ready checkbox visibility proof missing')
            near(summary['scrollTop'], row['afterReturnToCheckbox']['nodes']['risk-content']['scrollTop'],
                 'fonts-ready autofocus differs from the settled actual maximum')
        else:
            cold_hidden += summary['checkboxFullyVisible'] is False
    return {'contexts': len(rows), 'fontsReadyContexts': ready, 'coldFontCheckboxNotFullyVisible': cold_hidden,
            'explicitScrollActionsApplied': False,
            'limitation': 'Cold fonts can change text height after native focus scrolls; explicit parity offsets do not prove Flutter default-open scroll.'}


def validate_tiny_gutter(data, folder):
    rows = data['rows']
    expected = {(d, t, s, m) for d in ('desktop', 'phone') for t in ('light', 'dark')
                for s in ('short', 'long') for m in ('parity-default', 'diagnostic-visible')}
    expected |= {(d, 'light', 'tiny', 'parity-default') for d in ('desktop', 'phone')}
    require(len(rows) == 18 and {(r['device'], r['theme'], r['scenario'], r['mode']) for r in rows} == expected,
            'source tiny/conditional-gutter coverage is incomplete')
    images, measured = [], []
    for row in rows:
        state = row['state']; extra = state['additional']; nodes = state['nodes']
        dialog, content, footer = (nodes[name]['rect'] for name in ('risk-dialog', 'risk-content', 'risk-footer'))
        require(extra['contentScrollbarGutter'] == 'auto' and extra['contentOverflowY'] == 'auto'
                and extra['webkitScrollbarWidth'] == '5px' and extra['dialogOverflow'] == 'hidden',
                'source dynamic scrollbar structure changed')
        near(extra['gapFromContentToFooter'], 20, 'tiny source incorrectly compacts the content/footer gap')
        require(extra['thumbBackground'] == extra['thumbVariable'] == extra['l1Variable']
                and extra['thumbBorderLeft'] == extra['thumbBorderRight'] == '0px'
                and extra['trackMarginBlockStart'] == extra['trackMarginBlockEnd'] == '0px',
                'source inherited l1 scrollbar palette/geometry changed')
        if row['theme'] == 'dark':
            require(extra['l1Variable'] != extra['l2Variable'], 'source l1/l2 palette distinction is missing')
        image = relative_path(row['image']); require(len(image.parts) == 1, 'unsafe source diagnostic PNG name')
        require((folder / image).is_file(), 'missing source diagnostic PNG')
        images.append(image)
        visible = row['mode'] == 'diagnostic-visible'
        require(row['implicitScrollbarHidden'] is not visible, 'source diagnostic scrollbar mode is mislabeled')
        overflow_gutter = visible and row['scenario'] == 'long'
        physical = (13 if row['device'] == 'phone' else 5) if overflow_gutter else 0
        near(extra['actualGutterDevicePx'], physical, 'source conditional gutter pixel width changed')
        near(extra['actualGutterCssPx'], physical / state['dpr'], 'source conditional gutter CSS width changed')
        if row['scenario'] == 'tiny':
            near(dialog['height'], 32, 'source tiny cap changed')
            near(content['height'], 0, 'source tiny content did not collapse')
            near(footer['height'], 36, 'source tiny footer shrank')
            intersection = max(0, min(dialog['bottom'], footer['bottom']) - max(dialog['y'], footer['y']))
            near(intersection, 12, 'source tiny footer clipping changed')
            near(extra['footerClippedHeight'], intersection, 'source tiny footer intersection proof differs')
        if overflow_gutter:
            require(row['gutter']['widthDevicePx'] == physical, 'source gutter PNG width proof missing')
            gutter_image = image.with_suffix('.gutter.png')
            rgba = tuple(map(int, re.fullmatch(r'rgb\((\d+),\s*(\d+),\s*(\d+)\)', extra['l1Variable']).groups())) + (255,)
            with Image.open(folder / gutter_image) as picture:
                picture = picture.convert('RGBA')
                require(picture.width == physical and all(any(picture.getpixel((x, y)) == rgba
                        for y in range(picture.height)) for x in range(picture.width)),
                        'source l1 thumb does not paint every measured gutter column')
            images.append(gutter_image)
        measured.append({key: row[key] for key in ('device', 'theme', 'scenario', 'mode')} | {
            'gutterDevicePx': physical, 'gutterCssPx': extra['actualGutterCssPx'],
            'thumbColor': extra['l1Variable'], 'footerIntersection': extra['footerClippedHeight']})
    require(len(images) == 22 and len(set(images)) == 22, 'source diagnostic PNG coverage is incomplete')
    return {'contexts': len(rows), 'diagnosticOnly': True, 'rows': measured}, images


def validate_gpu(folder, manifest):
    cases = manifest['cases']
    require(len(cases) == 2 and len({c['id'] for c in cases}) == 2, 'expected two native GPU sizes')
    require({p.parent.name for p in folder.glob('*/environment.json')} == {c['id'] for c in cases},
            'GPU replay coverage differs from its manifest')
    rows = []
    keep = ('weston', 'renderer', 'appRenderDevices', 'glVersion', 'appRenderer', 'backend',
            'cursorIncluded', 'captureAssertions', 'pairedHost', 'size', 'theme', 'locale')
    for case in cases:
        require(re.fullmatch(r'[A-Za-z0-9_.-]+', case['id']), 'unsafe GPU case name')
        directory = folder / case['id']; env = load(directory / 'environment.json')
        expected = [step['expect'] for step in case['app'] if 'expect' in step]
        actual = env.get('captureAssertions', [])
        require(expected and len(actual) == len(expected)
                and all(result.get('passed') is True
                        and all(result.get(key) == value for key, value in spec.items())
                        for spec, result in zip(expected, actual)), 'GPU assertions are incomplete, changed or failed')
        require(env.get('backend') == 'native-wayland' and env.get('appRenderDevices')
                and not re.search(r'llvmpipe|softpipe|swrast|software', env.get('renderer', ''), re.I)
                and env.get('size') == [case['width'], case['height']], 'native hardware GPU/size proof missing')
        for pid in load(directory / 'pids.json').values():
            try:
                os.kill(int(pid), 0)
            except ProcessLookupError:
                pass
            else:
                raise ValueError('a recorded native GPU PID is still alive')
        captures = [step['capture'] for step in case['app'] if 'capture' in step]
        require(captures and len(captures) == len(set(captures)), 'GPU capture names are missing/duplicated')
        for name in captures:
            require(re.fullmatch(r'[A-Za-z0-9_-]+', name) and (directory / (name + '.png')).is_file(),
                    'missing named GPU capture')
        require((folder / (case['id'] + '.png')).is_file(), 'missing final GPU capture')
        rows.append({'case': case['id'], 'environment': {key: env[key] for key in keep if key in env},
                     'captures': captures, 'assertions': len(actual)})
    return rows


def android_contract(script):
    tree = ast.parse(script.read_text())
    scenes, pairs = [], []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr == 'scene' and node.args and isinstance(node.args[0], ast.Constant):
            scenes.append(node.args[0].value)
        if node.func.attr == 'compare' and len(node.args) == 5 and all(isinstance(v, ast.Constant) for v in node.args):
            pairs.append(tuple(v.value for v in node.args))
    require(scenes and len(scenes) == len(set(scenes)) and pairs, 'native Android driver contract is missing')
    return set(scenes), pairs


def validate_android(folder, script, fixture_hash):
    receipt = load(folder / 'receipt.json'); expected, pairs = android_contract(script)
    scenes = receipt.get('scenes', [])
    require(receipt.get('passed') is True and receipt.get('fixtureSha256') == fixture_hash
            and len(scenes) == len(expected) and {s['scene'] for s in scenes} == expected,
            'Android receipt is incomplete or tested a different fixture')
    require(receipt.get('actualInputs') and receipt.get('failedSelectionKeysRetried') is False
            and receipt.get('inputs') and all(item.get('sentOnce') is True for item in receipt['inputs'])
            and receipt.get('displayOverride', {}).get('restoredExactly') is True,
            'Android input provenance or exact display restoration is missing')
    for name in ('normalEnterGateVerified', 'explicitAcknowledgementRequired', 'disabledAckAndConfirmBlocked',
                 'accessibleCloseTouchAndEnter', 'longAutofocusRevealsAcknowledgement', 'headerAndBodyScrollTogether',
                 'footerBoundsRemainFixed', 'tabRevealsHeaderAndAcknowledgement', 'reopenResetsStateAndDefaultScroll',
                 'restoresEachFixtureOpener'):
        require(receipt.get(name) is True, 'missing Android behavior proof: ' + name)
    for scene in scenes:
        require(re.fullmatch(r'[A-Za-z0-9_-]+', scene['scene']), 'unsafe Android scene name')
        ET.parse(folder / (scene['scene'] + '.xml'))
        require((folder / (scene['scene'] + '.png')).is_file(), 'missing Android scene PNG')
    proofs = receipt.get('pixelProofs', [])
    require(len(proofs) == len(pairs) and {
        (p['before'], p['after'], p['region'], p['rgbaByteEqual'], p['purpose']) for p in proofs} == set(pairs),
        'Android measured pixel proofs differ from the driver contract')
    for proof in proofs:
        require(proof['before'] in expected and proof['after'] in expected, 'Android proof references an unknown scene')
        bounds = proof['bounds']
        require(len(bounds) == 4 and all(type(n) is int for n in bounds), 'invalid Android proof crop')
        with Image.open(folder / (proof['before'] + '.png')) as left, Image.open(folder / (proof['after'] + '.png')) as right:
            require(left.size == right.size and 0 <= bounds[0] < bounds[2] <= left.width
                    and 0 <= bounds[1] < bounds[3] <= left.height, 'Android proof crop/viewport mismatch')
            same = left.convert('RGBA').crop(bounds).tobytes() == right.convert('RGBA').crop(bounds).tobytes()
        require(same is proof['rgbaByteEqual'], 'Android recorded RGBA proof differs from its images')
    return receipt


def validate_cleanup(receipt, normal_hash):
    for name in ('normalApkRestored', 'normalAppForceStopped', 'ownedEmulatorStopped', 'sharedAdbRetained',
                 'recordedGpuPidsAbsent', 'displayOverrideReset', 'adbdUnrootRequested'):
        require(receipt.get(name) is True, 'missing completed runtime cleanup: ' + name)
    require(receipt.get('normalApkLocalSha256') == normal_hash
            and receipt.get('normalApkInstalledSha256') == normal_hash, 'normal APK restoration hash mismatch')


def published_inputs(lock, source):
    selected = {
        'ui-primitives': ('Modal.module.css', 'RiskConfirmation.module.css', 'Checkbox.module.css',
                          'Button.module.css', 'modal-layer.json', 'package.json', 'LICENSE'),
        'ui-theme': ('base.css', 'gradient-shadow-text.css', 'scrollbar.css', 'focus.css', 'package.json', 'LICENSE'),
    }
    snapshots = []
    require(git('rev-parse', 'HEAD', cwd=source) == lock['referenceCommit'], 'reference checkout differs from source lock')
    for package in lock['packages']:
        current = load(source / package['sourcePackage'])
        consumer = load(source / package['referenceConsumer'])
        require(current['version'] == package['version']
                and consumer[package['dependencyField']].get(package['name']) == package['dependencySpecifier'],
                'reference package dependency/version drift')
        for declaration in package.get('referenceConsumers', []):
            extra = load(source / declaration['path'])
            require(extra[declaration['dependencyField']].get(package['name']) == declaration['dependencySpecifier'],
                    'additional reference consumer drift')
        for name, digest in package.get('referenceSourceSha256', {}).items():
            require(sha256(source / name) == digest, 'reference source hash differs: ' + name)
        for name in selected.get(package['snapshotFolder'], ()):
            file = REPO / 'tool/design-system/upstream' / package['snapshotFolder'] / name
            require(name in package['files'] and sha256(file) == package['files'][name], 'published snapshot hash mismatch')
            snapshots.append((file, package['snapshotFolder'], name))
    return snapshots


def copy_capture_set(stage, folder, cases, destination, *, differences=False):
    for case in cases:
        for provider in ('react', 'flutter'):
            verify_capture(folder, provider, case)
            file = capture_path(folder, provider, case['key'])
            copy_png(file, stage / destination / provider / file.name)
            write_json(stage / destination / provider / file.with_suffix('.metadata.json').name,
                       load(file.with_suffix('.metadata.json')))
        if differences:
            relative = relative_path(case['sideBySide'])
            require(relative.parts[:3] == ('visual-testing-results', 'diff', 'react__flutter'),
                    'unexpected comparison image path')
            copy_png(folder / relative, stage / destination / 'diff' / relative.name)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-head', required=True, help='full source commit used for all four runtime builds')
    parser.add_argument('--visual', type=Path, default=REPO / 'build/parity-headed-final')
    parser.add_argument('--before', type=Path, default=REPO / 'build/parity-headed-regression-before')
    parser.add_argument('--regression', type=Path, default=REPO / 'build/parity-headed-regression-after')
    parser.add_argument('--preflight', type=Path, default=REPO / '.local/headed-full.json')
    parser.add_argument('--builds', type=Path, default=REPO / '.local/headed-dialogs-builds')
    parser.add_argument('--gpu', type=Path, default=REPO / 'build/native-headed-gpu')
    parser.add_argument('--gpu-cases', type=Path, default=REPO / 'tool/parity-desktop/headed-dialogs-cases.json')
    parser.add_argument('--android', type=Path, default=REPO / 'build/native-headed-android')
    parser.add_argument('--cleanup', '--cleanup-receipt', dest='cleanup', type=Path,
                        default=REPO / '.local/headed-cleanup.json')
    parser.add_argument('--source-measurements', type=Path)
    parser.add_argument('--open-scroll', type=Path)
    parser.add_argument('--tiny-gutter', type=Path)
    parser.add_argument('--dest', type=Path, default=ROOT / 'scratch/whalee-menu-sticky-evidence/headed-dialogs')
    args = parser.parse_args()
    require(not args.dest.exists() and args.dest.parent.is_dir(), 'inspect destination; it must be new under an existing evidence worktree')
    require(not git('status', '--porcelain'), 'final implementation must be clean')
    require(re.fullmatch(r'[0-9a-f]{40}', args.runtime_head), 'runtime head must be a full SHA')
    head, tree = git('rev-parse', 'HEAD'), git('rev-parse', 'HEAD^{tree}')
    runtime_head = git('rev-parse', args.runtime_head + '^{commit}')
    runtime_tree = git('rev-parse', runtime_head + '^{tree}')
    runtime_paths = ('apps/dsh_flutter/lib', 'features/*/lib', 'packages/*/lib',
                     'apps/dsh_flutter/test/parity', 'pubspec.yaml', 'pubspec.lock')
    require(not git('diff', '--name-only', runtime_head, head, '--', *runtime_paths),
            'product/native fixture changed after runtime builds')
    protected = ('tool/parity-fonts', 'tool/parity_lib', 'tool/vendor/raft-visual-testing',
                 'tool/parity-ext/glyph-mask.py', 'tool/parity-web/capture.mjs', 'tool/parity-web/pixel-crop.mjs',
                 'apps/dsh_flutter/lib/src/platform/pinned_fonts.dart')
    require(not git('diff', '--name-only', BASE, head, '--', *protected), 'font/classifier/reference-capture inputs changed')
    full = load(args.preflight)
    require(full.get('headTree') == tree and full.get('fast') is False
            and set(full.get('results', {})) == CHECKS
            and all(row['state'] == 'ok' for row in full['results'].values()), 'missing successful exact-tree full thirteen-check preflight')

    groups = expected_groups(); expected = set().union(*groups.values())
    cases = load(args.visual / 'summary.json')['cases']; validate_cases(cases, expected)
    for case in cases:
        for provider in ('react', 'flutter'):
            verify_capture(args.visual, provider, case)
    measured = {'thresholdPct': THRESHOLD, 'allCaptures': stats(cases),
                'groups': {name: stats([c for c in cases if c['key'] in keys]) for name, keys in groups.items()},
                'cases': case_metrics(cases)}
    footer_pairs = []
    for bottom in sorted(key for key in groups['footers'] if '-bottom.' in key):
        top = bottom.replace('-bottom.', '-top.')
        for provider in ('react', 'flutter'):
            footer_pairs.append({'provider': provider, 'top': top, 'bottom': bottom,
                                 **png_comparison(capture_path(args.visual, provider, top), capture_path(args.visual, provider, bottom))})
    require(len(footer_pairs) == 16 and all(row['rgbaByteEqual'] for row in footer_pairs),
            'fixed footer top/bottom images differ; eight pairs per provider are required')

    preserved_groups = preservation_groups(); preserved_keys = set().union(*preserved_groups.values())
    before = load(args.before / 'summary.json')['cases']; validate_cases(before, preserved_keys)
    after = load(args.regression / 'summary.json')['cases']; validate_cases(after, preserved_keys)
    previous = {case['key']: case for case in before}; preservation = []
    for case in after:
        group = next(name for name, keys in preserved_groups.items() if case['key'] in keys)
        for provider in ('react', 'flutter'):
            verify_capture(args.before, provider, previous[case['key']]); verify_capture(args.regression, provider, case)
            preservation.append({'provider': provider, 'case': case['key'], 'group': group,
                                 **png_comparison(capture_path(args.before, provider, case['key']),
                                                  capture_path(args.regression, provider, case['key']))})
    require(len(preservation) == 192 and all(row['rgbaByteEqual'] for row in preservation),
            'the 96-case reader/model preservation cohort differs in a provider')

    source_measure = proof_input('headed-source-measurements.json', args.source_measurements)
    source_open = proof_input('headed-open-scroll.json', args.open_scroll)
    source_tiny = proof_input('headed-tiny-gutter', args.tiny_gutter)
    proofs = {'layout': load(source_measure), 'open': load(source_open), 'tiny': load(source_tiny / 'measurements.json')}
    lock = load(REPO / 'tool/design-system/sources.lock.json')
    browser = lock['rendererSnapshots']['chromiumCheckbox']['browser']
    layout_summary = validate_source_layout(proofs['layout'], browser)
    open_summary = validate_open_scroll(proofs['open'])
    tiny_summary, tiny_images = validate_tiny_gutter(proofs['tiny'], source_tiny)
    footer_width = proof_input('headed-footer-width.json')
    proofs['footer-width'] = load(footer_width)
    require(proofs['footer-width'].get('diagnostic') is True
            and proofs['footer-width'].get('acceptanceUnchanged') is True,
            'wide-label source diagnostic must remain separate from acceptance')
    wide = proofs['footer-width']['after']['nodes']
    near(wide['risk-cancel']['rect']['width'], 72, 'source wide-label Cancel minimum changed')
    near(wide['risk-confirm']['rect']['width'], 312, 'source wide-label Confirm shrink changed')
    near(wide['risk-confirm']['rect']['right'], wide['risk-footer']['rect']['right'] - 24,
         'source wide-label actions do not fit the footer')
    proof_scripts = [proof_input(name) for name in ('headed-source-measure.mjs', 'headed-open-scroll.mjs',
                                                   'headed-tiny-gutter.mjs', 'headed-footer-width.mjs')]

    builds = []
    for name, log in (('android-fixture.apk', 'android-fixture.log'), ('android-normal.apk', 'android-normal.log'),
                      ('linux-fixture/dsh_flutter', 'linux-fixture.log'), ('linux-normal/dsh_flutter', 'linux-normal.log')):
        file = args.builds / name
        require(file.is_file() and 'Built ' in (args.builds / log).read_text(), 'missing successful runtime build: ' + name)
        row = {'name': name, 'sha256': sha256(file)}
        if name.endswith('/dsh_flutter'):
            row['applicationLibrarySha256'] = sha256(file.parent / 'lib/libapp.so')
        builds.append(row)
    for name, expected_value in (('runtime-head.txt', runtime_head), ('runtime-tree.txt', runtime_tree)):
        file = args.builds / name
        if file.exists():
            require(file.read_text().strip() == expected_value, 'runtime build identity differs from operator declaration')
    build_hashes = {row['name']: row['sha256'] for row in builds}
    gpu = validate_gpu(args.gpu, load(args.gpu_cases))
    android_script = ROOT / 'scripts/headed-dialogs-android.py'
    android = validate_android(args.android, android_script, build_hashes['android-fixture.apk'])
    cleanup = load(args.cleanup); validate_cleanup(cleanup, build_hashes['android-normal.apk'])
    dsh = Path(os.environ.get('DSH_SRC', str(ROOT / 'dsh-flutter/.local/dsh-src')))
    snapshots = published_inputs(lock, dsh)
    for name in (*IMPLEMENTATION, *TESTS, *REPRODUCTION):
        require((REPO / name).is_file(), 'missing whitelisted implementation/test/reproduction source: ' + name)

    limitations = [
        'The 64 source parity images retain implicit --hide-scrollbars. The 18-context visible-gutter diagnostics are separate and do not replace acceptance captures.',
        'Cold source font loading can leave the preferred checkbox partially hidden; fonts-ready source mounting reaches the settled maximum. Explicit top/bottom parity actions do not establish default-open scrolling.',
        'Disabled source entry leaves focus on BODY in all 16 measured contexts; first Tab reaches Close in the two sampled desktop English/light contexts. Flutter keeps focus in the foreground dialog; that platform difference is intentional.',
        'Generic headed footer shrink weights use outer intrinsic widths; arbitrary simultaneous shrinking can differ from CSS content-box weights. The measured risk case freezes Cancel at its minimum and gives Confirm the exact remaining width.',
        'Only the declared headed RiskConfirmation profile is migrated; other modal profiles and selection-sheet adaptations remain tracked separately.',
        'The model checkbox preservation fixture is synthetic context; the Flutter model editor is not yet wired to this atom.',
        'GPU recorder environments establish hardware rendering and assertions but do not hash the executable; the runtime source/build identity is operator-declared and checked for product equivalence.',
        'The fixed 99.5% non-text threshold is reported by group. No overall visual completion, deployment or release is claimed.',
    ]
    receipt = {
        'implementationHead': head, 'tree': tree, 'runtimeBuildHead': runtime_head, 'runtimeBuildTree': runtime_tree,
        'runtimeHeadDeclaredByOperator': True, 'productAndNativeFixtureInputsEqualToBuildHead': True,
        'changesSinceRuntimeBuild': git('diff', '--name-only', runtime_head, head).splitlines(),
        'protectedInputsComparedAgainst': BASE, 'fontClassifierAndThresholdChanged': False,
        'referenceDshCommit': lock['referenceCommit'], 'syntheticOnly': True,
        'fullLocalPreflight': full, 'artifacts': builds, 'visual': measured['allCaptures'], 'visualGroups': measured['groups'],
        'footerPairs': footer_pairs, 'preservation': preservation,
        'preservationCounts': {name: len(keys) for name, keys in preserved_groups.items()},
        'sourceLayout': layout_summary, 'sourceInitialScroll': open_summary, 'sourceTinyAndGutter': tiny_summary,
        'sourceWideLabelDiagnostic': {'cancelWidth': 72, 'confirmWidth': 312, 'acceptanceUnchanged': True},
        'sourceProofSha256': {name: sha256(path) for name, path in
                              [('layout', source_measure), ('open', source_open), ('tiny', source_tiny / 'measurements.json'),
                               ('wideLabelDiagnostic', footer_width)]},
        'sourceProofScripts': [{'name': path.name, 'sha256': sha256(path)} for path in proof_scripts],
        'implementationFiles': [{'path': name, 'sha256': sha256(REPO / name)} for name in IMPLEMENTATION],
        'testSources': [{'path': name, 'sha256': sha256(REPO / name)} for name in TESTS],
        'referenceSourceFiles': [{'path': name, 'sha256': sha256(dsh / name)} for name in SOURCE_FILES],
        'gpu': [{'case': row['case'], 'assertions': row['assertions'], 'captures': len(row['captures'])} for row in gpu],
        'nativeReproduction': {'androidScriptSha256': sha256(android_script),
                               'gpuManifestSha256': sha256(args.gpu_cases),
                               'gpuRecorderSha256': sha256(REPO / 'tool/parity-desktop/gpu_capture.py')},
        'android': android, 'runtimeCleanup': cleanup, 'limitations': limitations, 'releaseOrDeployment': False,
    }
    with tempfile.TemporaryDirectory(prefix='.headed-staging-', dir=args.dest.parent) as temporary:
        stage = Path(temporary) / args.dest.name; stage.mkdir()
        copy_capture_set(stage, args.visual, cases, 'components', differences=True)
        write_json(stage / 'components/summary.json', measured)
        manifest = load(args.visual / 'cases.sampled.json')
        case_ids = {case['caseId'] for case in cases}
        manifest['cases'] = [case for case in manifest['cases'] if case['id'] in case_ids]
        require(len(manifest['cases']) == len(case_ids), 'selected capture manifest is incomplete')
        write_json(stage / 'components/cases.json', manifest)
        write_json(stage / 'fixed-footer/rgba.json', footer_pairs)
        copy_capture_set(stage, args.before, before, 'regression/before')
        copy_capture_set(stage, args.regression, after, 'regression/after')
        write_json(stage / 'regression/summary.json', {'groups': receipt['preservationCounts'], 'pairs': preservation,
                                                     'before': case_metrics(before), 'after': case_metrics(after)})
        for name, data in proofs.items():
            write_json(stage / 'browser-probe' / (name + '.json'), data)
        for image in tiny_images:
            copy_png(source_tiny / image, stage / 'browser-probe/tiny-gutter' / image)
        for script in proof_scripts:
            copy_text(script, stage / 'reproduction' / script.name, code=True)
        for name in ('headed-reference-report.md', 'headed-open-scroll-report.md'):
            for base in (REPO, REFERENCE):
                path = base / '.local' / name
                if path.exists():
                    copy_text(path, stage / 'browser-probe' / name)
                    break
        if (source_tiny / 'receipt.md').exists():
            copy_text(source_tiny / 'receipt.md', stage / 'browser-probe/tiny-gutter/README.md')
        for row in gpu:
            directory = args.gpu / row['case']
            write_json(stage / 'gpu' / row['case'] / 'environment.json', row['environment'])
            for name in row['captures']:
                copy_png(directory / (name + '.png'), stage / 'gpu' / row['case'] / (name + '.png'))
            copy_png(args.gpu / (row['case'] + '.png'), stage / 'gpu' / (row['case'] + '.png'))
        for scene in android['scenes']:
            name = scene['scene']
            copy_png(args.android / (name + '.png'), stage / 'android' / (name + '.png'))
            copy_text(args.android / (name + '.xml'), stage / 'android' / (name + '.xml'))
        write_json(stage / 'android/receipt.json', android)
        write_json(stage / 'preflight.json', full); write_json(stage / 'cleanup.json', cleanup)
        write_json(stage / 'receipt.json', receipt)
        copy_text(ROOT / 'notes/headed-dialog-remaining.md', stage / 'remaining-visual-differences.md')
        for name in ('sources.lock.json', 'families.json', 'recipes.generated.json', 'theme.generated.json'):
            write_json(stage / name, load(REPO / 'tool/design-system' / name))
        write_json(stage / 'font-pins.json', load(REPO / 'tool/parity-fonts/manifest.json'))
        for file, folder, name in snapshots:
            copy_text(file, stage / 'published-inputs' / folder / name, code=file.suffix in ('.json', '.css'))
        for name in SOURCE_FILES:
            copy_text(dsh / name, stage / 'reference-source' / name, code=True)
        for names, destination in ((IMPLEMENTATION, 'implementation'), (TESTS, 'tests'), (REPRODUCTION, 'reproduction')):
            for name in names:
                copy_text(REPO / name, stage / destination / name, code=True)
        copy_text(android_script, stage / 'reproduction/headed-dialogs-android.py', code=True)
        copy_text(Path(__file__), stage / 'reproduction/headed-dialogs-publish.py', code=True)
        for name in ('headed-dialogs-builds.sh', 'headed-dialogs-gpu.sh', 'headed-dialogs-cleanup.py'):
            path = ROOT / 'scripts' / name
            if path.exists():
                copy_text(path, stage / 'reproduction' / name, code=True)
        overall = measured['allCaptures']
        text = (
            '# Headed Modal and RiskConfirmation evidence\n\n'
            'RiskConfirmation now uses the canonical generated headed Modal, controlled acknowledgement and '
            'fixed footer. The full content block, including header and warning, scrolls together.\n\n'
            f'The 64 actual-source comparisons include 32 normal cards, 16 long cards and 16 footer crops. '
            f'{overall["dimensionsEqual"]} have matching dimensions, {overall["nonTextPassing"]} meet the unchanged '
            f'99.5% non-text threshold, and mean non-text agreement is {overall["meanNonTextPct"]:.3f}%. '
            'The groups are reported separately. All eight top/bottom footer pairs in each provider are RGBA-identical. '
            'The prior 64 reader and 32 model-checkbox cases are also RGBA-identical in each provider.\n\n'
            'Source proofs cover 48 layout/control contexts, 16 default-open font/focus contexts and 18 tiny/gutter '
            'contexts. The tiny 32px card keeps its 20px gap and clips the natural footer to a 12px vertical '
            'intersection. Visible classic scrollbars reserve 5/13 physical columns only with overflow and inherit '
            'the l1 palette. Their no-hide screenshots remain diagnostic; the parity reference keeps its original '
            'hidden-scrollbar flag. Cold-font autofocus and the disabled source BODY-focus limitation are recorded.\n\n'
            f'The exact final tree passed all 13 preflight checks. Two hardware GPU replays contain '
            f'{sum(row["assertions"] for row in gpu)} verified assertions; Android completed {len(android["scenes"])} '
            f'scenes and {len(android["pixelProofs"])} independently recomputed pixel proofs. Four build hashes, '
            'runtime source equivalence and normal-APK/process cleanup are recorded. Native counts come from '
            'the completed receipts and their reproduction contracts.\n\n'
            + '\n'.join('- ' + item for item in limitations) + '\n')
        (stage / 'README.md').write_text(text)
        require(git('rev-parse', 'HEAD') == head and not git('status', '--porcelain'),
                'implementation changed during evidence staging')
        require(not args.dest.exists(), 'destination appeared during evidence staging')
        stage.rename(args.dest)
    print(json.dumps({'evidenceFiles': sum(path.is_file() for path in args.dest.rglob('*')),
                      'head': head, 'tree': tree, 'visual': measured['allCaptures'],
                      'footerPairsPerProvider': len(footer_pairs) // 2, 'preservedCasesPerProvider': len(preservation) // 2,
                      'gpuAssertions': sum(row['assertions'] for row in gpu), 'androidScenes': len(android['scenes'])}))


if __name__ == '__main__':
    main()
