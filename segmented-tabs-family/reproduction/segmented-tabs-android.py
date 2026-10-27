"""Replay real plugin and preset-guide tabs on the owned emulator-5560.

Run only after the parent has started its owned userdebug emulator and approved
the final fixture build. This driver leaves the fixture installed for inspection;
the parent restores the normal APK, stops the app, unroots and stops its emulator.
Every key is sent once. Polling observes state and never resends a failed key.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops


ROOT = Path('[workspace]')
REPO = ROOT / 'scratch/whalee-segmented-tabs'
ADB = ROOT / 'toolchains/android-sdk/platform-tools/adb'
SERIAL = 'emulator-5560'
PACKAGE = 'app.kevinzhow.whalee'
REMOTE_XML = '/sdcard/whalee-segmented-native.xml'
PLUGIN_GROUP = ('Plugin views', ('Installed', 'Discover'))
GUIDE_GROUP = ('Guide sections', ('Mode details', 'How to use'))


class Replay:
    def __init__(self, out):
        self.out = out
        self.current = None
        self.xml = b''
        self.parents = {}
        self.keyboard = None
        self.scenes = []
        self.inputs = []
        self.focus_pixel_proof = None

    def run(self, *args):
        return subprocess.run(
            [str(ADB), '-s', SERIAL, *map(str, args)], check=True,
            capture_output=True, timeout=120,
        ).stdout

    def dump(self):
        self.run('shell', 'uiautomator', 'dump', REMOTE_XML)
        self.xml = self.run('exec-out', 'cat', REMOTE_XML)
        self.current = ET.fromstring(self.xml)
        self.parents = {child: parent for parent in self.current.iter() for child in parent}

    @staticmethod
    def label(node):
        return node.get('content-desc') or node.get('text') or ''

    @staticmethod
    def bounds(node):
        values = list(map(int, re.findall(r'-?\d+', node.get('bounds', ''))))
        if len(values) != 4:
            raise RuntimeError('Malformed accessibility bounds')
        a, b, c, d = values
        if c <= a or d <= b:
            raise RuntimeError('Empty accessibility bounds')
        return a, b, c, d

    def named(self, name, scope=None):
        return [node for node in (self.current if scope is None else scope).iter('node') if self.label(node) == name]

    def contains(self, text):
        return any(text in self.label(node) for node in self.current.iter('node'))

    def group(self, spec):
        name, tabs = spec
        found = [node for node in self.named(name) if all(self.named(tab, node) for tab in tabs)]
        return found[0] if len(found) == 1 else None

    def control(self, name, scope=None, first=False):
        # UIAutomator may put a label on a child View of its clickable owner.
        # Read state and tap bounds from that owner, without assuming a class
        # for Flutter's new tab semantics role.
        found = []
        for node in self.named(name, scope):
            owner = node
            while owner is not None:
                if owner.get('clickable') == 'true':
                    if owner not in found:
                        found.append(owner)
                    break
                if owner is scope:
                    break
                owner = self.parents.get(owner)
        found = [node for node in found if node.get('enabled') == 'true']
        if first and found:
            return min(found, key=lambda node: (self.bounds(node)[1], self.bounds(node)[0]))
        return found[0] if len(found) == 1 else None

    def tab(self, spec, name):
        group = self.group(spec)
        return None if group is None else self.control(name, group)

    def tab_state(self, spec, name, **expected):
        node = self.tab(spec, name)
        return node is not None and all(node.get(key) == value for key, value in expected.items())

    def selected(self, spec, name, focused=None):
        if self.group(spec) is None:
            return False
        for tab in spec[1]:
            expected = {'selected': 'true' if tab == name else 'false',
                        'clickable': 'true', 'enabled': 'true', 'focusable': 'true'}
            if focused is not None:
                expected['focused'] = 'true' if tab == focused else 'false'
            if not self.tab_state(spec, tab, **expected):
                return False
        return True

    def native_focused(self):
        return any(
            node.get('class') == 'android.widget.FrameLayout'
            and node.get('package') == PACKAGE
            and node.get('focusable') == 'true'
            and node.get('focused') == 'true'
            for node in self.current.iter('node')
        )

    def wait(self, predicate, context):
        for attempt in range(1, 9):
            self.dump()
            if predicate():
                return attempt
        (self.out / 'failure.xml').write_bytes(self.xml)
        raise RuntimeError('State not reached: ' + context)

    def scene(self, name, predicate):
        attempts = self.wait(predicate, name)
        (self.out / (name + '.xml')).write_bytes(self.xml)
        (self.out / (name + '.png')).write_bytes(self.run('exec-out', 'screencap', '-p'))
        self.scenes.append({'scene': name, 'observationAttempts': attempts})

    def tap_node(self, node, description):
        if node is None:
            raise RuntimeError('Missing touch target: ' + description)
        a, b, c, d = self.bounds(node)
        self.inputs.append({'type': 'touch', 'target': description})
        self.run('shell', 'input', 'tap', (a + c) // 2, (b + d) // 2)

    def tap(self, name, first=False):
        self.tap_node(self.control(name, first=first), name)

    def tap_tab(self, spec, name):
        self.tap_node(self.tab(spec, name), spec[0] + ': ' + name)

    def event(self, code, value):
        self.run('shell', 'sendevent', self.keyboard, 1, code, value)
        self.run('shell', 'sendevent', self.keyboard, 0, 0, 0)

    def key(self, code, description, focus=None, shift=False):
        self.wait(self.native_focused, 'native FlutterView focused before ' + description)
        if focus is not None and not self.tab_state(*focus, focused='true'):
            raise RuntimeError('Tab lacks logical focus before ' + description)
        self.inputs.append({'type': 'emulated hardware key', 'key': description,
                            'linuxCode': code, 'shift': shift, 'sentOnce': True})
        if shift:
            self.event(42, 1)
        try:
            self.event(code, 1)
            self.event(code, 0)
        finally:
            if shift:
                self.event(42, 0)

    def focus_by_tab(self, spec, name):
        # These are successive traversal steps, not retries of a failed action.
        # Each step is observed before deciding whether another Tab is needed.
        for step in range(40):
            self.dump()
            if self.tab_state(spec, name, focused='true'):
                return step
            self.key(15, 'Tab traversal to ' + name)
        raise RuntimeError('Hardware Tab traversal never reached ' + name)

    def launch(self):
        self.run('shell', 'am', 'force-stop', PACKAGE)
        self.run('shell', 'am', 'start', '-W', '-n', PACKAGE + '/.MainActivity')

    def compare_focus_pixels(self, before_name, after_name, spec):
        node = self.group(spec)
        if node is None:
            raise RuntimeError('Tab group absent for focus-pixel check')
        a, b, c, d = self.bounds(node)
        with Image.open(self.out / (before_name + '.png')) as before, Image.open(self.out / (after_name + '.png')) as after:
            region = (max(0, a), max(0, b), min(before.width, c), min(before.height, d))
            changed = ImageChops.difference(before.convert('RGB').crop(region), after.convert('RGB').crop(region))
            bbox = changed.getbbox()
            if bbox is None:
                raise RuntimeError('Keyboard focus changed no pixels in the tab group')
        self.focus_pixel_proof = {'before': before_name, 'after': after_name,
                                  'region': region, 'changedBoundsInRegion': bbox}

    def execute(self, fixture):
        self.run('root')  # Only the parent's owned userdebug emulator-5560.
        self.run('wait-for-device')
        devices = self.run('shell', 'getevent', '-lp').decode()
        keyboards = re.findall(r'add device \d+: (\S+)\s+name:\s+"AT Translated Set 2 keyboard"', devices)
        if len(keyboards) != 1:
            raise RuntimeError('Expected one emulated hardware keyboard')
        self.keyboard = keyboards[0]
        self.run('install', '-r', fixture)
        self.launch()
        self.scene('plugin-initial', lambda: self.native_focused() and self.selected(PLUGIN_GROUP, 'Installed'))
        self.tap_tab(PLUGIN_GROUP, 'Discover')
        self.scene('plugin-touch-discover', lambda: self.selected(PLUGIN_GROUP, 'Discover', 'Discover'))
        self.tap_tab(PLUGIN_GROUP, 'Installed')
        self.scene('plugin-touch-installed', lambda: self.selected(PLUGIN_GROUP, 'Installed', 'Installed'))

        self.launch()
        self.scene('plugin-keyboard-initial', lambda: self.native_focused() and self.selected(PLUGIN_GROUP, 'Installed'))
        steps = self.focus_by_tab(PLUGIN_GROUP, 'Installed')
        if steps == 0:
            raise RuntimeError('Cold fixture unexpectedly began with the plugin tab focused')
        self.scene('plugin-keyboard-focus', lambda: self.selected(PLUGIN_GROUP, 'Installed', 'Installed'))
        self.compare_focus_pixels('plugin-keyboard-initial', 'plugin-keyboard-focus', PLUGIN_GROUP)

        for code, description, before, after in [
            (106, 'ArrowRight', 'Installed', 'Discover'),
            (106, 'ArrowRight wraps', 'Discover', 'Installed'),
            (105, 'ArrowLeft wraps', 'Installed', 'Discover'),
            (102, 'Home', 'Discover', 'Installed'),
            (107, 'End', 'Installed', 'Discover'),
        ]:
            self.key(code, description, (PLUGIN_GROUP, before))
            self.scene('plugin-' + description.lower().replace(' ', '-'),
                       lambda after=after: self.selected(PLUGIN_GROUP, after, after))

        self.key(15, 'Tab leaves plugin tab list', (PLUGIN_GROUP, 'Discover'))
        self.scene('plugin-tab-leaves-group', lambda: self.selected(PLUGIN_GROUP, 'Discover')
                   and all(not self.tab_state(PLUGIN_GROUP, tab, focused='true') for tab in PLUGIN_GROUP[1]))
        self.key(15, 'Shift+Tab returns to selected plugin tab', shift=True)
        self.scene('plugin-shift-tab-selected', lambda: self.selected(PLUGIN_GROUP, 'Discover', 'Discover'))

        self.tap('Presets')
        self.scene('presets', lambda: self.contains('New task default: Standard mode')
                   and self.control('Mode details', first=True) is not None)
        # SyntheticAgentsTasks lists Standard first. Choose its topmost help
        # button because the real preset cards intentionally reuse this label.
        self.tap('Mode details', first=True)
        self.scene('guide-initial-selected-focus', lambda: self.selected(GUIDE_GROUP, 'Mode details', 'Mode details')
                   and self.contains('How it works') and not self.contains('Fix a bug'))
        self.tap_tab(GUIDE_GROUP, 'How to use')
        self.scene('guide-touch-usage', lambda: self.selected(GUIDE_GROUP, 'How to use', 'How to use')
                   and self.contains('Fix a bug') and not self.contains('How it works'))

        for code, description, before, after, body in [
            (102, 'Home', 'How to use', 'Mode details', 'How it works'),
            (107, 'End', 'Mode details', 'How to use', 'Fix a bug'),
            (106, 'ArrowRight wraps', 'How to use', 'Mode details', 'How it works'),
            (105, 'ArrowLeft wraps', 'Mode details', 'How to use', 'Fix a bug'),
        ]:
            self.key(code, description, (GUIDE_GROUP, before))
            self.scene('guide-' + description.lower().replace(' ', '-'),
                       lambda after=after, body=body: self.selected(GUIDE_GROUP, after, after) and self.contains(body))

        self.key(15, 'Tab leaves guide tab list', (GUIDE_GROUP, 'How to use'))
        self.scene('guide-tab-leaves-group', lambda: self.selected(GUIDE_GROUP, 'How to use')
                   and all(not self.tab_state(GUIDE_GROUP, tab, focused='true') for tab in GUIDE_GROUP[1]))
        self.key(15, 'Shift+Tab returns to selected guide tab', shift=True)
        self.scene('guide-shift-tab-selected', lambda: self.selected(GUIDE_GROUP, 'How to use', 'How to use'))
        self.tap('Close')
        self.scene('guide-closed', lambda: self.group(GUIDE_GROUP) is None and self.contains('New task default: Standard mode'))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture', type=Path, default=REPO / '.local/segmented-tabs-builds/android-fixture.apk')
    parser.add_argument('--out', type=Path, default=REPO / 'build/native-segmented-android')
    args = parser.parse_args()
    if not args.fixture.is_file():
        parser.error('Fixture APK does not exist')
    args.out.mkdir(parents=True, exist_ok=False)
    replay = Replay(args.out)
    record = {
        'synthetic': True, 'ownedEmulator': SERIAL,
        'fixtureSha256': hashlib.sha256(args.fixture.read_bytes()).hexdigest(),
        'actualInputs': ['touch', 'emulated hardware Tab, Shift+Tab, ArrowLeft, ArrowRight, Home and End'],
        'accessibility': 'Named tab groups; selected, focused, focusable, enabled and clickable tab owners read from UIAutomator',
        'keyboardReadiness': 'Native FlutterView focus checked immediately before every key; expected logical tab focus checked for selection keys',
        'failedSelectionKeysRetried': False,
        'cleanupOwner': 'Parent restores the normal APK and stops its owned emulator after inspection',
    }
    try:
        replay.execute(args.fixture)
    except Exception as error:
        record.update({'passed': False, 'failure': str(error), 'scenes': replay.scenes, 'inputs': replay.inputs})
        (args.out / 'failure-receipt.json').write_text(json.dumps(record, indent=2) + '\n')
        if replay.xml:
            (args.out / 'failure.xml').write_bytes(replay.xml)
        raise
    record.update({'passed': True, 'scenes': replay.scenes, 'inputs': replay.inputs,
                   'focusUnderlineChangedPixels': replay.focus_pixel_proof is not None,
                   'focusPixelProof': replay.focus_pixel_proof})
    (args.out / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'passedScenes': len(replay.scenes), 'tabSemanticsAndKeyboardVerified': True,
                      'guidePanelChanged': True, 'focusUnderlineChangedPixels': True}))


if __name__ == '__main__':
    main()
