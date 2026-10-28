#!/usr/bin/env python3
"""Replay the explicit icon-action manifest on owned whalee-api36/5560.

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
        self.adb('shell', 'uiautomator', 'dump', '/sdcard/icon-actions.xml')
        self.xml = self.adb('exec-out', 'cat', '/sdcard/icon-actions.xml')
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

    def named(self, label, *, exact=False, exact_line=False):
        return [n for n in self.tree.iter('node') if n.get('visible-to-user') != 'false'
                and (label in self.label(n).splitlines() if exact_line else
                     self.label(n) == label if exact else label in self.label(n))]

    def targets(self, label):
        owners = {}
        for node in self.named(label, exact=True):
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

    def source_bounds(self, label):
        bounds, node = self.target(label)
        recipe = self.recipe
        # UIA reports integer physical edges. One physical pixel is the
        # maximum size discrepancy caused by quantizing both rectangle edges.
        passed = all(abs(actual - expected * self.density) <= 1 for actual, expected in
                     [(bounds[2] - bounds[0], recipe['width']),
                      (bounds[3] - bounds[1], recipe['height'])])
        proof = {'label': label, 'bounds': bounds, 'density': self.density,
                 'sourceLogicalSize': [recipe['width'], recipe['height']],
                 'clickable': node.get('clickable'), 'class': node.get('class'), 'passed': passed}
        self.geometry.append(proof)
        if not passed:
            raise RuntimeError('Real action semantics bounds do not match the source profile: ' + label)
        return bounds, node

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
            if op == 'expect':
                for label in value:
                    self.wait(lambda: bool(self.named(label, exact_line=True)), 'Visible: ' + label)
                    self.checks.append({'assertion': 'Visible: ' + label, 'passed': True})
            elif op == 'sourceButton':
                self.source_bounds(value)
                self.checks.append({'assertion': 'Source-sized clickable action: ' + value, 'passed': True})
            elif op == 'focused':
                self.wait(lambda: len(self.focused_nodes(value)) == 1,
                          'Keyboard focuses the real action: ' + value)
                bounds, owner = self.source_bounds(value)
                focused = self.focused_nodes(value)
                if len(focused) != 1:
                    raise RuntimeError('The real action lost its unique focused subtree')
                self.geometry[-1]['keyboardFocusNode'] = {
                    'bounds': self.bounds(focused[0]), 'class': focused[0].get('class'),
                    'label': self.label(focused[0]), 'ownerFocused': owner.get('focused'),
                    'sameBoundsAsLabeledAction': self.bounds(focused[0]) == bounds}
                self.checks.append({'assertion': 'Keyboard focuses the real action: ' + value, 'passed': True})
            elif op == 'tap':
                bounds, node = self.source_bounds(value)
                x, y = (bounds[0] + bounds[2]) // 2, (bounds[1] + bounds[3]) // 2
                self.inputs.append({'tap': [x, y], 'label': value, 'bounds': bounds,
                                    'semanticClickable': node.get('clickable'), 'semanticClass': node.get('class')})
                self.adb('shell', 'input', 'tap', x, y)
            elif op == 'key':
                self.inputs.append({'keycode': value})
                self.adb('shell', 'input', 'keyevent', value)
            elif op == 'chord':
                # AOSP InputShellCommand implements ordered modifier chords:
                # https://android.googlesource.com/platform/frameworks/base/+/81f52b053da6/services/core/java/com/android/server/input/InputShellCommand.java
                self.inputs.append({'keycombination': value})
                self.adb('shell', 'input', 'keycombination', *value)
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
    if (manifest.get('schema') != 'whalee-icon-actions-native/1' or
            manifest.get('fixtureTarget') != 'test/parity/icon_actions_main.dart' or
            manifest.get('android', {}).get('schema') != 'whalee-icon-actions-android-steps/1'):
        raise RuntimeError('Wrong fixture/Android manifest contract')
    steps = manifest['android']['steps']
    if not isinstance(steps, list) or not steps:
        raise RuntimeError('A nonempty literal Android step contract is required')
    captures = []
    for step in steps:
        if not isinstance(step, dict) or len(step) != 1:
            raise RuntimeError('Each Android step must name exactly one operation')
        op, value = next(iter(step.items()))
        if op in ('sourceButton', 'tap', 'focused'):
            if value not in ('Settings', 'Back', 'Close'):
                raise RuntimeError('Unexpected native action label')
        elif op == 'capture':
            if not isinstance(value, str) or not re.fullmatch('[a-z0-9-]+', value) or value in captures:
                raise RuntimeError('Invalid or duplicate capture name')
            captures.append(value)
        elif op == 'expect':
            if not isinstance(value, list) or not value or any(not isinstance(s, str) or not s for s in value):
                raise RuntimeError('Expected nonempty exact scene assertions')
        elif op in ('key', 'chord'):
            values = [value] if op == 'key' else value
            if (not isinstance(values, list) or not values or (op == 'chord' and len(values) < 2)
                    or any(type(k) is not int or not 0 < k < 300 for k in values)):
                raise RuntimeError('Invalid native keyboard input')
        else:
            raise RuntimeError('Unknown Android manifest operation')
    for op in ('tap', 'focused'):
        labels = [step[op] for step in steps if op in step]
        if set(labels) != {'Settings', 'Back', 'Close'} or len(labels) != len(set(labels)):
            raise RuntimeError('Each real action needs one pointer and one keyboard proof')
    return steps, {'sceneCount': len(captures), 'scenes': captures,
                   'inputCount': sum(any(k in step for k in ('tap', 'key', 'chord')) for step in steps),
                   'checkCount': sum(len(step['expect']) if 'expect' in step else
                                     int('sourceButton' in step or 'focused' in step) for step in steps)}


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
    record = {**identity, 'driverSha256': sha(Path(__file__)), 'contract': contract}
    apk = args.builds / 'android-fixture.apk'
    try:
        record.update(replay.owned(), apkSha256=sha(apk), sharedAdbPids=adb_servers())
        help_text = replay.adb('shell', 'input').decode(errors='replace')
        if 'keycombination' not in help_text:
            raise RuntimeError('Required Android keycombination capability unavailable')
        recipes = json.loads((args.repo / 'tool/design-system/recipes.generated.json').read_text())
        replay.recipe = recipes['metrics']['DshIconActionRecipe']
        record['installedFixtureSha256'] = replay.install_readback(apk, args.out / 'installed-fixture.apk')
        replay.adb('shell', 'am', 'force-stop', PACKAGE)
        replay.adb('shell', 'monkey', '-p', PACKAGE, '1')
        replay.run(steps)
        if (len(replay.scenes) != contract['sceneCount'] or replay.scenes != contract['scenes'] or
                len(replay.inputs) != contract['inputCount'] or len(replay.checks) != contract['checkCount']):
            raise RuntimeError('Executed inputs/scenes/checks differ from the literal manifest contract')
        if replay.identity() != identity or sha(apk) != record['apkSha256']:
            raise RuntimeError('Runtime/fixture bytes changed during replay')
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
