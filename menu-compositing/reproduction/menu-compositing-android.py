"""Actual touch/key replay of the bounded menu-compositing candidate.

Run only after sourcing scripts/pr16-env.sh and starting whalee-api36. This
installs the synthetic fixture; --cleanup restores and verifies the normal APK
after the final replay, then stops only the owned emulator.
Every click comes from current accessibility bounds, and failed clicks are
never retried. Screenshots, XML, inputs and assertions are retained together.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import time
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops


ROOT = Path('[workspace]')
REPO = ROOT / 'scratch/whalee-menu-compositing'
BUILD = REPO / '.local/menu-compositing-builds'
EXPECTED_HEAD = '4feb2c38e63fc61f0e2a6dab125bd5709be7ccb2'
EXPECTED_TREE = 'a32ed26154623c6ee9ced491712348f44330557f'
ADB = ROOT / 'toolchains/android-sdk/platform-tools/adb'
PACKAGE = 'app.kevinzhow.whalee'


def build_identity(*, normal=False):
    head = (BUILD / 'runtime-head.txt').read_text().strip()
    tree = (BUILD / 'runtime-tree.txt').read_text().strip()
    marker = BUILD / ('normal.ready' if normal else 'android-fixture.ready')
    if head != EXPECTED_HEAD or tree != EXPECTED_TREE or not marker.is_file():
        raise RuntimeError('Menu build identity or readiness does not match the assigned candidate')
    return {'runtimeHead': head, 'runtimeTree': tree}


class Replay:
    def __init__(self, serial, out):
        self.serial, self.out = serial, out
        self.tree = None
        self.parents = {}
        self.inputs, self.scenes, self.checks = [], [], []
        self.dump_diagnostics = []
        self.geometry_proofs = []

    def adb(self, *args):
        return subprocess.check_output(
            [str(ADB), '-s', self.serial, *map(str, args)],
            stderr=subprocess.PIPE, timeout=45,
        )

    @staticmethod
    def label(node):
        return node.get('content-desc') or node.get('text') or node.get('hint') or ''

    @staticmethod
    def bounds(node):
        values = tuple(map(int, re.findall(r'-?\d+', node.get('bounds', ''))))
        if len(values) != 4 or values[2] <= values[0] or values[3] <= values[1]:
            raise RuntimeError('Empty accessibility bounds')
        return values

    def dump(self):
        status = self.adb('shell', 'uiautomator', 'dump', '/sdcard/menu-compositing.xml')
        self.xml = self.adb('exec-out', 'cat', '/sdcard/menu-compositing.xml')
        try:
            self.tree = ET.fromstring(self.xml)
        except ET.ParseError:
            name = 'invalid-accessibility-dump-' + str(len(self.dump_diagnostics))
            (self.out / (name + '.bin')).write_bytes(self.xml)
            self.dump_diagnostics.append({'file': name + '.bin', 'status': status.decode(errors='replace')})
            raise
        self.parents = {child: parent for parent in self.tree.iter() for child in parent}

    def named(self, fragment, *, exact=False):
        return [node for node in self.tree.iter('node')
                if (self.label(node) == fragment if exact else fragment in self.label(node))
                and node.get('visible-to-user') != 'false']

    def wait(self, predicate, description):
        until = time.monotonic() + 25
        while time.monotonic() < until:
            try:
                self.dump()
            except ET.ParseError:
                # Readiness retries never resend an input. Preserve every bad
                # response so a transient ADB/UIA failure cannot disappear.
                time.sleep(.2)
                continue
            if predicate():
                self.checks.append({'assertion': description, 'passed': True})
                return
            time.sleep(.2)
        self.capture('failed-' + str(len(self.scenes)), dump=False)
        raise RuntimeError(description)

    def visible(self, fragment):
        self.wait(lambda: bool(self.named(fragment)), 'Visible: ' + fragment)

    def absent(self, fragment):
        self.wait(lambda: not self.named(fragment), 'Absent: ' + fragment)

    def click(self, fragment, *, exact=False, min_y=0, avoid_label=None):
        def candidates():
            found = {}
            for node in self.named(fragment, exact=exact):
                owner = node
                while owner is not None and owner.get('clickable') != 'true':
                    owner = self.parents.get(owner)
                if owner is None or owner.get('enabled') == 'false':
                    continue
                bounds = self.bounds(owner)
                if bounds[1] >= min_y:
                    found[bounds] = owner
            return found
        self.wait(lambda: len(candidates()) == 1, 'Unique touch target: ' + fragment)
        bounds = next(iter(candidates()))
        touch_rect = bounds
        occluder = None
        if avoid_label is not None:
            overlays = {self.bounds(node) for node in self.named(avoid_label)}
            if not overlays:
                raise RuntimeError('Missing foreground panel bounds: ' + avoid_label)
            occluder = max(overlays, key=lambda rect: (rect[2] - rect[0]) * (rect[3] - rect[1]))
            left, top, right, bottom = bounds
            a, b, c, d = occluder
            ix0, iy0, ix1, iy1 = max(left, a), max(top, b), min(right, c), min(bottom, d)
            if ix0 < ix1 and iy0 < iy1:
                visible = [(left, top, right, iy0), (left, iy1, right, bottom),
                           (left, iy0, ix0, iy1), (ix1, iy0, right, iy1)]
                visible = [rect for rect in visible if rect[0] < rect[2] and rect[1] < rect[3]]
                if not visible:
                    raise RuntimeError('Target fully covered by foreground panel: ' + fragment)
                touch_rect = max(visible, key=lambda rect: (rect[2] - rect[0]) * (rect[3] - rect[1]))
        x, y = (touch_rect[0] + touch_rect[2]) // 2, (touch_rect[1] + touch_rect[3]) // 2
        owner = candidates()[bounds]
        self.inputs.append({'tap': [x, y], 'label': fragment, 'bounds': bounds,
                            'semanticClass': owner.get('class'), 'semanticClickable': owner.get('clickable'),
                            'visibleTouchRect': touch_rect, 'occludingBounds': occluder})
        self.adb('shell', 'input', 'tap', x, y)
        return bounds

    def key(self, code):
        self.inputs.append({'keycode': code})
        self.adb('shell', 'input', 'keyevent', code)

    def capture(self, name, *, dump=True):
        if dump:
            self.dump()
        self.out.mkdir(parents=True, exist_ok=True)
        (self.out / (name + '.xml')).write_bytes(self.xml)
        (self.out / (name + '.png')).write_bytes(self.adb('exec-out', 'screencap', '-p'))
        self.scenes.append(name)
        print('Captured ' + name, flush=True)

    def unchanged(self, first, second, rect, description):
        with Image.open(self.out / (first + '.png')) as a, Image.open(self.out / (second + '.png')) as b:
            # RGB avoids RGBA getbbox's alpha-only default: an opaque input
            # has a zero difference alpha plane even when color pixels differ.
            same = ImageChops.difference(a.convert('RGB').crop(rect), b.convert('RGB').crop(rect)).getbbox() is None
        self.checks.append({'assertion': description, 'passed': same, 'rect': rect,
                            'before': first, 'after': second})
        if not same:
            raise RuntimeError(description)

    def menu_above(self, launcher, description):
        settings = {self.bounds(node) for node in self.named('Settings')}
        passed = bool(settings) and all(rect[3] <= launcher[1] for rect in settings)
        self.geometry_proofs.append({'assertion': description, 'passed': passed,
                                     'launcher': launcher, 'settings': sorted(settings)})
        if not passed:
            raise RuntimeError(description)

    def compact_model_menu(self, launcher, viewport):
        panels = {self.bounds(node) for node in self.named('Model and reasoning effort')}
        width, height = viewport
        passed = len(panels) == 1 and all(
            0 <= left < right <= width and 0 <= top < bottom <= launcher[1]
            and right - left < width and bottom - top < height / 2
            for left, top, right, bottom in panels)
        self.geometry_proofs.append({'assertion': 'Model root is compact, within viewport and above its launcher',
                                     'passed': passed, 'launcher': launcher,
                                     'panels': sorted(panels), 'viewport': viewport})
        if not passed:
            raise RuntimeError('Model root is compact, within viewport and above its launcher')

    def run(self):
        self.visible('New session')
        self.capture('sidebar-initial')
        self.click('New session', exact=True)
        self.visible('Sidebar action: new-session')
        self.capture('sidebar-new-session')
        more = self.click('More')
        self.visible('Settings')
        self.capture('sidebar-more-menu')
        self.menu_above(more, 'More menu Settings row is above the footer launcher')
        self.key(111)
        self.absent('Settings')
        self.click('More')
        self.visible('Settings')
        self.click('Statistics', exact=True)
        self.visible('231 turns')
        self.capture('statistics-initial')
        self.click('231 turns')
        self.visible('Session statistics')
        self.capture('statistics-activity')
        self.click('1616M', avoid_label='Session statistics')
        self.visible('Token usage')
        self.absent('Session statistics')
        self.capture('statistics-usage-one-tap')
        self.key(111)
        self.absent('Token usage')
        self.click('231 turns')
        self.visible('Session statistics')
        self.key(4)
        self.absent('Session statistics')
        self.capture('statistics-system-back')
        self.click('Model', exact=True)
        self.visible('Selection: none')
        self.capture('model-closed')
        model_trigger = self.click('DeepSeek V4.1 Flash')
        self.visible('Effort')
        self.capture('model-root')
        with Image.open(self.out / 'model-root.png') as shot:
            width, height = shot.size
        self.compact_model_menu(model_trigger, (width, height))
        self.unchanged('model-closed', 'model-root', (0, height // 4, width // 2, height // 2),
                       'Opening the desktop-style menu adds no viewport mask')
        self.click('Model\n', min_y=100)
        self.visible('Search models')
        self.capture('model-directory')
        self.key(111)
        self.visible('Effort')
        self.capture('model-escape-to-root')
        self.key(111)
        self.absent('Effort')
        self.click('DeepSeek V4.1 Flash')
        self.click('Effort\n', min_y=100)
        self.visible('Low')
        self.capture('model-efforts')
        self.click('Low', exact=True)
        self.visible('Selection: deepseek-official/flash/low')
        self.capture('model-effort-selected')
        self.click('DeepSeek V4.1 Flash')
        self.click('Model\n', min_y=100)
        self.visible('Search models')
        def focused_search():
            return {self.bounds(child) for parent in self.named('Search models')
                    for child in parent.iter('node')
                    if child.get('class') == 'android.widget.EditText' and child.get('focused') == 'true'}
        self.wait(lambda: len(focused_search()) == 1,
                  'Search autofocus reaches its unique native editable descendant')
        self.inputs.append({'text': 'Pro', 'focusedSearchBounds': next(iter(focused_search()))})
        self.adb('shell', 'input', 'text', 'Pro')
        self.visible('DeepSeek V4.1 Pro')
        self.wait(lambda: not self.named('DeepSeek V4.1 Flash', exact=True)
                  and not self.named('Alpha', exact=True),
                  'Search removes unmatched Flash and Alpha model options')
        self.capture('model-search')
        self.click('DeepSeek V4.1 Pro', exact=True)
        self.visible('Selection: deepseek-official/pro/default')
        self.capture('model-selected')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--serial', default='emulator-5560')
    parser.add_argument('--out', type=Path, default=REPO / 'build/native-menu-compositing-android')
    parser.add_argument('--cleanup', action='store_true')
    args = parser.parse_args()
    if args.cleanup:
        cleanup(args.serial, args.out)
        return
    identity = build_identity()
    args.out.mkdir(parents=True, exist_ok=False)
    replay = Replay(args.serial, args.out)
    avd = replay.adb('emu', 'avd', 'name').decode().splitlines()[0].strip()
    if avd != 'whalee-api36':
        raise RuntimeError('Refusing to install on an unowned AVD: ' + avd)
    apk = BUILD / 'android-fixture.apk'
    receipt = {'avd': avd, 'serial': args.serial, 'apkSha256': hashlib.sha256(apk.read_bytes()).hexdigest(),
               **identity,
               'displaySize': replay.adb('shell', 'wm', 'size').decode().strip(),
               'displayDensity': replay.adb('shell', 'wm', 'density').decode().strip(),
               'androidApi': replay.adb('shell', 'getprop', 'ro.build.version.sdk').decode().strip()}
    try:
        replay.adb('install', '-r', apk)
        replay.adb('shell', 'am', 'force-stop', PACKAGE)
        replay.adb('shell', 'monkey', '-p', PACKAGE, '1')
        replay.run()
        receipt['passed'] = True
        print('Native Android replay passed', flush=True)
    except Exception as error:
        receipt.update(passed=False, error=str(error))
        raise
    finally:
        receipt.update(inputs=replay.inputs, scenes=replay.scenes, checks=replay.checks,
                       geometryProofs=replay.geometry_proofs,
                       dumpDiagnostics=replay.dump_diagnostics)
        (args.out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')


def cleanup(serial, out):
    identity = build_identity(normal=True)
    replay = Replay(serial, out)
    avd = replay.adb('emu', 'avd', 'name').decode().splitlines()[0].strip()
    if avd != 'whalee-api36':
        raise RuntimeError('Refusing cleanup on an unowned AVD: ' + avd)
    normal = BUILD / 'android-normal.apk'
    fixture = BUILD / 'android-fixture.apk'
    sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    record = {'avd': avd, 'serial': serial,
              **identity,
              'fixtureSha256': sha(fixture), 'normalSha256': sha(normal)}
    record['displaySize'] = replay.adb('shell', 'wm', 'size').decode().strip()
    record['displayDensity'] = replay.adb('shell', 'wm', 'density').decode().strip()
    replay.adb('install', '-r', normal)
    installed = replay.adb('shell', 'pm', 'path', PACKAGE).decode().strip()
    if not installed.startswith('package:') or '\n' in installed:
        raise RuntimeError('Expected one installed APK path')
    installed_file = out / 'installed-normal.apk'
    replay.adb('pull', installed.removeprefix('package:'), installed_file)
    record['installedNormalSha256'] = sha(installed_file)
    if record['installedNormalSha256'] != record['normalSha256']:
        raise RuntimeError('Installed normal APK differs from the built APK')
    installed_file.unlink()
    replay.adb('shell', 'am', 'force-stop', PACKAGE)
    stopped = subprocess.run([str(ADB), '-s', serial, 'shell', 'pidof', PACKAGE], capture_output=True, timeout=30)
    record['appStopped'] = stopped.returncode == 1 and not stopped.stdout.strip()
    record['adbdShellUid'] = replay.adb('shell', 'id', '-u').decode().strip()
    record['noDisplayOverride'] = all('Override' not in record[key] for key in ('displaySize', 'displayDensity'))
    if not record['appStopped'] or record['adbdShellUid'] != '2000' or not record['noDisplayOverride']:
        raise RuntimeError('Normal app/display/ADB cleanup verification failed')
    replay.adb('emu', 'kill')
    until = time.monotonic() + 20
    while time.monotonic() < until:
        devices = subprocess.check_output([str(ADB), 'devices']).decode()
        if serial not in devices:
            break
        time.sleep(.5)
    record['ownedEmulatorStopped'] = serial not in devices
    record['sharedAdbPreserved'] = 'List of devices attached' in devices
    record.update(normalApkRestored=record['installedNormalSha256'] == record['normalSha256'],
                  normalAppForceStopped=record['appStopped'],
                  normalApkLocalSha256=record['normalSha256'],
                  normalApkInstalledSha256=record['installedNormalSha256'],
                  sharedAdbRetained=record['sharedAdbPreserved'],
                  displayOverrideApplied=False, adbRootUsed=False)
    record['passed'] = record['ownedEmulatorStopped'] and record['sharedAdbPreserved']
    (out / 'cleanup.json').write_text(json.dumps(record, indent=2) + '\n')
    if not record['passed']:
        raise RuntimeError('Owned emulator cleanup failed')


if __name__ == '__main__':
    main()
