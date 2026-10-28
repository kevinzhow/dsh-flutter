#!/usr/bin/env python3
"""Replay the prepared actual-manager loaded-card manifest on owned whalee-api36/5560.

Source scripts/pr16-env.sh first. This driver never starts an emulator, changes
display settings, runs adb root, or stops the shared ADB server. Inputs are sent
once; readiness polling never retries them. --cleanup restores the exact normal
APK, verifies its installed bytes, and stops only the identified owned emulator.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
ADB = ROOT / 'toolchains/android-sdk/platform-tools/adb'
PACKAGE = 'app.kevinzhow.whalee'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def adb_servers():
    found = []
    for process in Path('/proc').iterdir():
        if not process.name.isdigit():
            continue
        try:
            args = (process / 'cmdline').read_bytes().split(b'\0')
            if (process / 'exe').resolve().name == 'adb' and b'server' in args:
                found.append(int(process.name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    return sorted(found)


def owned_emulator_pids():
    found = []
    for process in Path('/proc').iterdir():
        if not process.name.isdigit():
            continue
        try:
            args = (process / 'cmdline').read_bytes().split(b'\0')
            if (b'-avd' in args and args[args.index(b'-avd') + 1] == b'whalee-api36'
                    and b'-port' in args and args[args.index(b'-port') + 1] == b'5560'):
                found.append(int(process.name))
        except (FileNotFoundError, ProcessLookupError, PermissionError, IndexError):
            pass
    return sorted(found)


class Replay:
    def __init__(self, args):
        self.args = args
        self.inputs, self.scenes, self.checks, self.geometry = [], [], [], []
        self.diagnostics = []
        self.xml = b''

    def adb(self, *args):
        return subprocess.check_output(
            [str(ADB), '-s', self.args.serial, *map(str, args)],
            stderr=subprocess.PIPE, timeout=45)

    def identity(self, *, normal=False):
        args = self.args
        marker = args.builds / ('normal.ready' if normal else 'android-fixture.ready')
        if not marker.is_file():
            raise RuntimeError('Exact candidate readiness marker missing')
        identity = {key: (args.builds / file).read_text().strip() for key, file in
                    [('runtimeHead', 'runtime-head.txt'), ('runtimeTree', 'runtime-tree.txt')]}
        if identity != {'runtimeHead': args.expected_head, 'runtimeTree': args.expected_tree}:
            raise RuntimeError('Build identity differs from the explicitly assigned runtime')
        for suffix, expected in [('HEAD', args.expected_head), ('HEAD^{tree}', args.expected_tree)]:
            if subprocess.check_output(['git', '-C', str(args.repo), 'rev-parse', suffix], text=True).strip() != expected:
                raise RuntimeError('Repository differs from the built runtime')
        if subprocess.check_output(['git', '-C', str(args.repo), 'status', '--porcelain'], text=True).strip():
            raise RuntimeError('Runtime repository must be clean')
        if sha(args.manifest) != args.manifest_sha256:
            raise RuntimeError('Input/acceptance manifest bytes changed')
        return {**identity, 'manifestSha256': args.manifest_sha256}

    def owned(self):
        avd = self.adb('emu', 'avd', 'name').decode().splitlines()[0].strip()
        if avd != 'whalee-api36' or self.args.serial != 'emulator-5560':
            raise RuntimeError('Refusing an unowned AVD/port')
        size = self.adb('shell', 'wm', 'size').decode().strip()
        density = self.adb('shell', 'wm', 'density').decode().strip()
        uid = self.adb('shell', 'id', '-u').decode().strip()
        if uid != '2000' or 'Override' in size or 'Override' in density:
            raise RuntimeError('Ordinary ADB shell and unchanged display settings required')
        api = self.adb('shell', 'getprop', 'ro.build.version.sdk').decode().strip()
        if api != '36':
            raise RuntimeError('The explicitly owned API36 AVD is required')
        match = re.fullmatch(r'Physical density:\s*(\d+)', density)
        if match is None:
            raise RuntimeError('Cannot establish unmodified physical density')
        self.density = int(match[1]) / 160
        physical = re.fullmatch(r'Physical size:\s*(\d+)x(\d+)', size)
        if physical is None:
            raise RuntimeError('Cannot establish the original physical display')
        self.physical_width = int(physical[1])
        return {'avd': avd, 'serial': self.args.serial, 'displaySize': size,
                'displayDensity': density, 'androidApi': api, 'adbdShellUid': uid,
                'displayOverrideApplied': False, 'adbRootUsed': False}

    @staticmethod
    def label(node):
        return node.get('content-desc') or node.get('text') or node.get('hint') or ''

    @staticmethod
    def bounds(node):
        bounds = tuple(map(int, re.findall(r'-?\d+', node.get('bounds', ''))))
        if len(bounds) != 4 or bounds[0] >= bounds[2] or bounds[1] >= bounds[3]:
            raise RuntimeError('Empty accessibility bounds')
        return bounds

    def dump(self):
        self.adb('shell', 'uiautomator', 'dump', '/sdcard/plugin-cards.xml')
        self.xml = self.adb('exec-out', 'cat', '/sdcard/plugin-cards.xml')
        try:
            self.tree = ET.fromstring(self.xml)
        except ET.ParseError:
            name = 'invalid-xml-' + str(len(self.diagnostics)) + '.bin'
            (self.args.out / name).write_bytes(self.xml)
            self.diagnostics.append(name)
            raise
        self.parents = {child: parent for parent in self.tree.iter() for child in parent}

    def wait(self, predicate, description):
        until = time.monotonic() + 25
        while time.monotonic() < until:
            try:
                self.dump()
            except ET.ParseError:
                time.sleep(.2)
                continue
            if predicate():
                return
            time.sleep(.2)
        self.capture('failed-' + str(len(self.scenes)), dump=False)
        raise RuntimeError(description)

    @staticmethod
    def action_label_matches(content, label):
        return (content == label or content.startswith(label + '\n')
                or content.startswith(label + ', '))

    def named(self, label, *, exact=False, exact_line=False):
        return [n for n in self.tree.iter('node') if n.get('visible-to-user') != 'false'
                and ((self.action_label_matches(self.label(n), label)
                      if n.get('clickable') == 'true' else label in self.label(n).splitlines()) if exact_line else
                     self.label(n) == label if exact else label in self.label(n))]

    def targets(self, label):
        owners = {}
        # Android can combine the exact Semantics label and its descriptive
        # hint as "label, hint". Keep the full description, and require the
        # label at the start with a native separator rather than a substring.
        for node in self.tree.iter('node'):
            content = self.label(node)
            if (node.get('visible-to-user') == 'false'
                    or not self.action_label_matches(content, label)):
                continue
            owner = node
            while owner is not None and owner.get('clickable') != 'true':
                owner = self.parents.get(owner)
            if owner is not None and owner.get('enabled') != 'false':
                owners[self.bounds(owner)] = owner
        return owners

    def target(self, label):
        self.wait(lambda: len(self.targets(label)) == 1, 'Unique real action: ' + label)
        bounds, node = next(iter(self.targets(label).items()))
        return bounds, node

    def focused_nodes(self, label):
        targets = self.targets(label)
        if len(targets) != 1:
            return []
        bounds, owner = next(iter(targets.items()))
        # Flutter can expose keyboard focus below its named button container.
        # Only this exact subtree and identical hit bounds qualify; a focused
        # field elsewhere cannot satisfy the real action's focus check.
        return [n for n in owner.iter('node') if n.get('focused') == 'true'
                and self.bounds(n) == bounds]

    def switch_node(self, label):
        def candidates():
            return {self.bounds(node): node for node in self.named(label, exact_line=True)
                    if node.get('checkable') == 'true' or 'Switch' in node.get('class', '')}
        self.wait(lambda: len(candidates()) == 1, 'Unique independent switch: ' + label)
        return next(iter(candidates().items()))

    def source_card(self, value):
        bounds, node = self.target(value['label'])
        recipe = self.card_recipe
        logical_width = self.physical_width / self.density
        page_inset = min(48, max(24, logical_width * .04))
        content_width = min(960, logical_width - page_inset * 2)
        expected_left = (logical_width - content_width) / 2 + recipe['horizontalMargin']
        base_height = recipe['headPadding'] * 2 + recipe['iconHeight'] + 2 * max(
            1, int(recipe['iconBorderWidth'] * self.density)) / self.density
        actual_height = (bounds[3] - bounds[1]) / self.density
        passed = (abs(bounds[0] - expected_left * self.density) <= 1 and
                  abs(bounds[2] - (logical_width - expected_left) * self.density) <= 1 and
                  (abs(actual_height - base_height) * self.density <= 1
                   if value['height'] == 'base' else actual_height > base_height))
        proof = {'type': 'card', 'label': value['label'], 'bounds': bounds,
                 'nativeContentDescription': self.label(node),
                 'density': self.density, 'sourceBaseHeight': base_height,
                 'expectedLogicalLeft': expected_left, 'heightMode': value['height'],
                 'clickable': node.get('clickable'), 'passed': passed}
        self.geometry.append(proof)
        self.last_card_bounds, self.card_base_height = bounds, base_height
        if not passed:
            raise RuntimeError('Actual loaded-card semantic bounds differ from source layout')

    def source_switch(self, value):
        bounds, node = self.switch_node(value['label'])
        recipe = self.switch_recipe
        passed = (all(abs(actual - expected * self.density) <= 1 for actual, expected in
                      [(bounds[2] - bounds[0], recipe['width']),
                       (bounds[3] - bounds[1], recipe['height'])]) and
                  (node.get('enabled') != 'false') is value['enabled'] and
                  node.get('checked') == str(value['checked']).lower())
        self.geometry.append({'type': 'switch', 'label': value['label'], 'bounds': bounds,
                              'enabled': node.get('enabled'), 'checked': node.get('checked'),
                              'class': node.get('class'), 'passed': passed})
        if not passed:
            raise RuntimeError('Independent source-sized switch state/bounds differ')

    def tap_bounds(self, bounds, label, node=None, *, point=None, purpose='tap'):
        x, y = point or ((bounds[0] + bounds[2]) // 2, (bounds[1] + bounds[3]) // 2)
        self.inputs.append({'tap': [x, y], 'label': label, 'bounds': bounds,
                            'purpose': purpose, 'semanticClickable': None if node is None else node.get('clickable'),
                            'semanticClass': None if node is None else node.get('class')})
        self.adb('shell', 'input', 'tap', x, y)

    def capture(self, label, *, dump=True):
        if dump:
            self.dump()
        (self.args.out / (label + '.xml')).write_bytes(self.xml)
        (self.args.out / (label + '.png')).write_bytes(self.adb('exec-out', 'screencap', '-p'))
        self.scenes.append(label)
        print('Captured ' + label, flush=True)

    def run(self, steps):
        for step in steps:
            op, value = next(iter(step.items()))
            if op in ('expect', 'absent'):
                for label in value:
                    self.wait(lambda: bool(self.named(label, exact_line=True)) == (op == 'expect'), op + ': ' + label)
                    self.checks.append({'assertion': op + ': ' + label, 'passed': True})
            elif op == 'sourceCard':
                self.source_card(value)
                self.checks.append({'assertion': 'Source card layout: ' + value['label'], 'passed': True})
            elif op == 'sourceSwitch':
                self.source_switch(value)
                self.checks.append({'assertion': 'Independent source switch: ' + value['label'], 'passed': True})
            elif op == 'focused':
                self.wait(lambda: len(self.focused_nodes(value)) == 1, 'Unique actual focus owner: ' + value)
                bounds, owner = self.target(value)
                focused = self.focused_nodes(value)[0]
                self.geometry.append({'type': 'focus', 'label': value, 'bounds': bounds,
                                      'focusedBounds': self.bounds(focused), 'class': focused.get('class'),
                                      'sameBoundsAsLabeledAction': self.bounds(focused) == bounds, 'passed': True})
                self.checks.append({'assertion': 'Keyboard focuses independent action: ' + value, 'passed': True})
            elif op == 'tap':
                bounds, node = self.target(value)
                self.tap_bounds(bounds, value, node)
            elif op == 'tapDisabled':
                bounds, node = self.switch_node(value)
                if node.get('enabled') != 'false' or node.get('clickable') == 'true':
                    raise RuntimeError('Disabled-switch proof requires an actually disabled native target')
                self.tap_bounds(bounds, value, node, purpose='disabled switch must absorb without opening')
            elif op == 'tapText':
                def candidates():
                    return {self.bounds(n): n for n in self.named(value, exact=True)}
                self.wait(lambda: len(candidates()) == 1, 'Unique visible metadata region')
                bounds, node = next(iter(candidates().items()))
                card = self.last_card_bounds
                passed = (node.get('clickable') != 'true' and card[0] <= bounds[0] < bounds[2] <= card[2]
                          and bounds[1] >= card[1] + self.card_base_height * self.density - 1
                          and bounds[3] <= card[3] + 1)
                self.geometry.append({'type': 'metadata', 'bounds': bounds, 'card': card, 'passed': passed})
                if not passed:
                    raise RuntimeError('Metadata target is not its distinct source line below the card head')
                self.tap_bounds(bounds, value, node, purpose='actual metadata region opens the owning card')
            elif op == 'edgeTap':
                bounds, node = self.target(value['label'])
                inset = abs(self.card_recipe['horizontalMargin']) / 4 * self.density
                point = (round(bounds[0] + inset), round(bounds[1] + inset) if value['corner']
                         else (bounds[1] + bounds[3]) // 2)
                self.tap_bounds(bounds, value['label'], node, point=point,
                                purpose='outside source contour' if value['corner'] else 'extended side margin')
            elif op == 'key':
                self.inputs.append({'keycode': value})
                self.adb('shell', 'input', 'keyevent', value)
            elif op == 'capture':
                self.capture(value)
            else:
                raise RuntimeError('Unknown manifest operation: ' + op)

    def install_readback(self, apk, evidence):
        self.adb('install', '-r', apk)
        installed = self.adb('shell', 'pm', 'path', PACKAGE).decode().strip()
        if not installed.startswith('package:') or '\n' in installed:
            raise RuntimeError('Expected one installed APK path')
        self.adb('pull', installed.removeprefix('package:'), evidence)
        actual = sha(evidence)
        if actual != sha(apk):
            raise RuntimeError('Installed APK bytes differ; pulled evidence retained')
        # Keep the successful readback too, so the offline evidence validator
        # can independently rehash the installed fixture and restored app.
        return actual


def manifest_contract(args):
    if sha(args.manifest) != args.manifest_sha256:
        raise RuntimeError('Explicit manifest SHA256 differs')
    manifest = json.loads(args.manifest.read_text())
    if (manifest.get('schema') != 'whalee-plugin-cards-native/1' or
            manifest.get('fixtureTarget') != 'test/parity/plugin_cards_main.dart' or
            manifest.get('android', {}).get('schema') != 'whalee-plugin-cards-android-steps/1'):
        raise RuntimeError('Wrong loaded-card fixture/Android contract')
    source = manifest.get('scenarioInput', {})
    helper = args.repo / source.get('path', '..')
    if (source.get('path') != 'apps/dsh_flutter/test/parity/helpers/plugin_card_fixture.dart' or
            not helper.is_file() or sha(helper) != source.get('sha256')):
        raise RuntimeError('Shared scenario/helper bytes differ from the prepared contract')
    steps = manifest['android']['steps']
    if not isinstance(steps, list) or not steps:
        raise RuntimeError('Nonempty literal Android contract required')
    captures, inputs, checks = [], 0, 0
    text_ops = {'tap', 'tapDisabled', 'tapText', 'focused'}
    for step in steps:
        if not isinstance(step, dict) or len(step) != 1:
            raise RuntimeError('Each step must name one operation')
        op, value = next(iter(step.items()))
        if op in ('expect', 'absent'):
            if not isinstance(value, list) or not value or any(not isinstance(x, str) or not x for x in value):
                raise RuntimeError('Explicit nonempty exact-line assertions required')
            checks += len(value)
        elif op in text_ops:
            if not isinstance(value, str) or not value:
                raise RuntimeError('Explicit real target label required')
            inputs += int(op != 'focused'); checks += int(op == 'focused')
        elif op in ('sourceCard', 'sourceSwitch', 'edgeTap'):
            keys = {'sourceCard': {'label', 'height'}, 'sourceSwitch': {'label', 'enabled', 'checked'},
                    'edgeTap': {'label', 'corner'}}[op]
            if not isinstance(value, dict) or set(value) != keys or not isinstance(value['label'], str) or not value['label']:
                raise RuntimeError('Invalid source geometry/input contract')
            if op == 'sourceCard' and value['height'] not in ('base', 'tall'):
                raise RuntimeError('Unknown card height contract')
            if any(type(value[k]) is not bool for k in keys - {'label', 'height'}):
                raise RuntimeError('Native booleans must be explicit')
            checks += int(op != 'edgeTap'); inputs += int(op == 'edgeTap')
        elif op == 'key':
            if type(value) is not int or not 0 < value < 300:
                raise RuntimeError('Invalid Android key')
            inputs += 1
        elif op == 'capture':
            if not isinstance(value, str) or not re.fullmatch('[a-z0-9-]+', value) or value in captures:
                raise RuntimeError('Invalid or duplicate capture')
            captures.append(value)
        else:
            raise RuntimeError('Unknown Android operation: ' + op)
    required = {'default', 'corner', 'edge-open', 'back-list', 'switch-only', 'title-keyboard',
                'title-enter', 'switch-keyboard', 'switch-space', 'locked-switch', 'refused',
                'wrap', 'image-fallback', 'no-description', 'metadata', 'metadata-open'}
    if not required <= set(captures):
        raise RuntimeError('Required loaded-card evidence phase missing')
    if (sum('sourceCard' in step for step in steps) < 6 or
            sum('sourceSwitch' in step for step in steps) < 5 or
            {step['focused'] for step in steps if 'focused' in step} !=
            {'View Synthetic plugin', 'Enable Synthetic plugin'} or
            {step['edgeTap']['corner'] for step in steps if 'edgeTap' in step} != {False, True} or
            [step['tapDisabled'] for step in steps if 'tapDisabled' in step] != ['Enable Synthetic plugin'] or
            len([step for step in steps if 'tapText' in step]) != 1):
        raise RuntimeError('Required layout, independent-focus, contour or disabled/metadata proof missing')
    return steps, {'sceneCount': len(captures), 'scenes': captures, 'inputCount': inputs, 'checkCount': checks}


def cleanup(replay, identity):
    args = replay.args
    record = {**identity, **replay.owned(), 'normalApkLocalSha256': sha(args.builds / 'android-normal.apk')}
    before_servers, before_emulators = adb_servers(), owned_emulator_pids()
    record['sharedAdbPidsBefore'] = before_servers
    record['ownedEmulatorPidsBefore'] = before_emulators
    try:
        record['normalApkInstalledSha256'] = replay.install_readback(
            args.builds / 'android-normal.apk', args.out / 'installed-normal.apk')
        record['normalApkRestored'] = record['normalApkLocalSha256'] == record['normalApkInstalledSha256']
        replay.adb('shell', 'am', 'force-stop', PACKAGE)
        stopped = subprocess.run([str(ADB), '-s', args.serial, 'shell', 'pidof', PACKAGE], capture_output=True, timeout=30)
        record['normalAppForceStopped'] = stopped.returncode == 1 and not stopped.stdout.strip()
        if not record['normalAppForceStopped']:
            raise RuntimeError('Normal app process remains active')
        replay.adb('emu', 'kill')
        until = time.monotonic() + 20
        while time.monotonic() < until:
            devices = subprocess.check_output([str(ADB), 'devices'], text=True)
            if args.serial not in devices and all(not Path('/proc', str(pid)).exists() for pid in before_emulators):
                break
            time.sleep(.5)
        record['ownedEmulatorStopped'] = (args.serial not in devices and bool(before_emulators) and
                                           all(not Path('/proc', str(pid)).exists() for pid in before_emulators))
        record['sharedAdbPidsAfter'] = adb_servers()
        record['sharedAdbRetained'] = bool(before_servers) and set(before_servers) <= set(record['sharedAdbPidsAfter'])
        record['passed'] = record['ownedEmulatorStopped'] and record['sharedAdbRetained']
        if not record['passed']:
            raise RuntimeError('Owned emulator/shared ADB cleanup could not be established')
    except Exception as error:
        record.update(passed=False, error=str(error))
        raise
    finally:
        (args.out / 'cleanup.json').write_text(json.dumps(record, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('repo', 'builds', 'manifest', 'out'):
        parser.add_argument('--' + name, type=Path, required=True)
    for name in ('expected-head', 'expected-tree', 'manifest-sha256'):
        parser.add_argument('--' + name, required=True)
    parser.add_argument('--serial', default='emulator-5560')
    parser.add_argument('--cleanup', action='store_true')
    args = parser.parse_args()
    for key in ('repo', 'builds', 'manifest', 'out'):
        setattr(args, key, getattr(args, key).resolve())
    for key, length in [('expected_head', 40), ('expected_tree', 40), ('manifest_sha256', 64)]:
        if not re.fullmatch('[0-9a-f]{' + str(length) + '}', getattr(args, key)):
            raise RuntimeError('Exact object IDs and manifest SHA256 required')
    steps, contract = manifest_contract(args)
    replay = Replay(args)
    identity = replay.identity(normal=args.cleanup)
    if args.cleanup:
        if not args.out.is_dir() or (args.out / 'cleanup.json').exists():
            raise RuntimeError('Cleanup requires its retained replay folder and a fresh cleanup receipt')
        original = json.loads((args.out / 'receipt.json').read_text())
        if any(original.get(k) != v for k, v in identity.items()):
            raise RuntimeError('Cleanup identity differs from retained replay')
        cleanup(replay, identity)
        return
    args.out.mkdir(parents=True, exist_ok=False)
    record = {'schema': 'whalee-plugin-cards-android-runtime/1', **identity, 'driverSha256': sha(Path(__file__)), 'contract': contract}
    apk = args.builds / 'android-fixture.apk'
    try:
        record.update(replay.owned(), apkSha256=sha(apk), sharedAdbPids=adb_servers())
        recipes = json.loads((args.repo / 'tool/design-system/recipes.generated.json').read_text())
        replay.card_recipe = recipes['metrics']['DshPluginCardRecipe']
        replay.switch_recipe = recipes['metrics']['DshSwitchRecipe']
        record['installedFixtureSha256'] = replay.install_readback(apk, args.out / 'installed-fixture.apk')
        replay.adb('shell', 'am', 'force-stop', PACKAGE)
        replay.adb('shell', 'monkey', '-p', PACKAGE, '1')
        replay.run(steps)
        if (len(replay.scenes) != contract['sceneCount'] or replay.scenes != contract['scenes'] or
                len(replay.inputs) != contract['inputCount'] or len(replay.checks) != contract['checkCount']):
            raise RuntimeError('Executed inputs/scenes/checks differ from the literal manifest contract')
        if (replay.identity() != identity or sha(apk) != record['apkSha256'] or
                sha(Path(__file__)) != record['driverSha256']):
            raise RuntimeError('Runtime/fixture/driver bytes changed during replay')
        record['passed'] = True
        print(json.dumps({'passed': True, **contract}), flush=True)
    except Exception as error:
        record.update(passed=False, error=str(error))
        raise
    finally:
        record.update(inputs=replay.inputs, scenes=replay.scenes, checks=replay.checks,
                      geometryProofs=replay.geometry, dumpDiagnostics=replay.diagnostics)
        (args.out / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')


if __name__ == '__main__':
    main()
