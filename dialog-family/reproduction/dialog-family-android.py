"""Replay real preset-reader controls on the parent's owned emulator-5560.

The parent must start whalee-api36 and authorize execution on the final fixture.
Only this driver changes wm size, restoring the exact previous override in a
finally block. The parent restores the normal APK, stops the app, unroots and
stops its emulator after inspecting the result. No failed key is resent.
"""
from pathlib import Path
import argparse
import hashlib
import io
import json
import re
import subprocess
import xml.etree.ElementTree as ET

from PIL import Image, ImageChops


ROOT = Path('[workspace]')
REPO = ROOT / 'scratch/whalee-dialog-family'
ADB = ROOT / 'toolchains/android-sdk/platform-tools/adb'
SERIAL = 'emulator-5560'
PACKAGE = 'app.kevinzhow.whalee'
REMOTE_XML = '/sdcard/whalee-dialog-native.xml'
TABS_LABEL = 'Guide sections'
TAB_LABELS = {'explanation': 'Mode details', 'usage': 'How to use'}
SHORT_SIZE = '1080x1320'


class Replay:
    def __init__(self, out):
        self.out = out
        self.current = None
        self.xml = b''
        self.parents = {}
        self.keyboard = None
        self.scenes = []
        self.inputs = []
        self.pixel_proofs = []
        self.traversal = []
        self.display = {}

    def run(self, *args):
        return subprocess.run([str(ADB), '-s', SERIAL, *map(str, args)],
                              check=True, capture_output=True, timeout=120).stdout

    @staticmethod
    def label(node):
        return node.get('content-desc') or node.get('text') or ''

    @staticmethod
    def bounds(node):
        values = tuple(map(int, re.findall(r'-?\d+', node.get('bounds', ''))))
        if len(values) != 4 or values[2] <= values[0] or values[3] <= values[1]:
            raise RuntimeError('Missing or empty accessibility bounds')
        return values

    def dump(self):
        self.run('shell', 'uiautomator', 'dump', REMOTE_XML)
        self.xml = self.run('exec-out', 'cat', REMOTE_XML)
        self.current = ET.fromstring(self.xml)
        self.parents = {child: parent for parent in self.current.iter() for child in parent}

    def named(self, label, scope=None):
        root = self.current if scope is None else scope
        return [node for node in root.iter('node') if self.label(node) == label]

    def identified(self, identifier):
        found = [node for node in self.current.iter('node')
                 if node.get('resource-id') == identifier
                 or node.get('resource-id', '').endswith(':id/' + identifier)]
        return found[0] if len(found) == 1 else None

    def group(self):
        found = [node for node in self.named(TABS_LABEL)
                 if all(self.named(label, node) for label in TAB_LABELS.values())]
        return found[0] if len(found) == 1 else None

    def control(self, label, scope=None, first=False):
        found = []
        for node in self.named(label, scope):
            owner = node
            while owner is not None:
                if owner.get('clickable') == 'true' and owner.get('enabled') == 'true':
                    if owner not in found:
                        found.append(owner)
                    break
                if owner is scope:
                    break
                owner = self.parents.get(owner)
        if first and found:
            return min(found, key=lambda node: (self.bounds(node)[1], self.bounds(node)[0]))
        return found[0] if len(found) == 1 else None

    def tab(self, page):
        group = self.group()
        return None if group is None else self.control(TAB_LABELS[page], group)

    def panel(self, page):
        direct = self.identified('preset-guide-panel-' + page)
        if direct is not None:
            try:
                self.bounds(direct)
            except RuntimeError:
                return None
            return direct
        group = self.group()
        if group is None:
            return None
        bottom = self.bounds(group)[3]
        # Older Android bridges may omit the identifier. Select the named
        # non-clickable panel below its tab list, not its identically named tab.
        found = []
        for node in self.named(TAB_LABELS[page]):
            try:
                bounds = self.bounds(node)
            except RuntimeError:
                continue
            if node.get('clickable') != 'true' and bounds[1] >= bottom - 2:
                found.append(node)
        return found[0] if len(found) == 1 else None

    def selected(self, page):
        if self.group() is None:
            return False
        for value in TAB_LABELS:
            node = self.tab(value)
            if node is None or any(node.get(key) != expected for key, expected in {
                'selected': 'true' if value == page else 'false',
                'clickable': 'true', 'enabled': 'true', 'focusable': 'true',
            }.items()):
                return False
        return self.panel(page) is not None

    def panel_contains(self, page, text):
        panel = self.panel(page)
        return panel is not None and any(text in self.label(node) for node in panel.iter('node'))

    @staticmethod
    def focus_in(node):
        return node is not None and any(child.get('focused') == 'true' for child in node.iter('node'))

    def focus_stop(self):
        for page in TAB_LABELS:
            if self.focus_in(self.tab(page)):
                return ('tab', page)
            if self.focus_in(self.panel(page)):
                return ('panel', page)
        if self.focus_in(self.control('Close')):
            return ('close', '')
        return ('outside', '')

    def focus_signature(self):
        return tuple(sorted((node.get('resource-id', ''), self.label(node), node.get('class', ''),
                             node.get('bounds', '')) for node in self.current.iter('node')
                            if node.get('package') == PACKAGE and node.get('focused') == 'true'
                            and node.get('class') != 'android.widget.FrameLayout'))

    def native_focused(self):
        return any(node.get('class') == 'android.widget.FrameLayout'
                   and node.get('package') == PACKAGE and node.get('focusable') == 'true'
                   and node.get('focused') == 'true' for node in self.current.iter('node'))

    def wait(self, predicate, description):
        for attempt in range(1, 9):
            self.dump()
            if predicate():
                return attempt
        self.save_failure()
        raise RuntimeError('State not reached: ' + description)

    def screenshot(self):
        return self.run('exec-out', 'screencap', '-p')

    def stable_screenshot(self, rect):
        previous = None
        for _ in range(8):
            raw = self.screenshot()
            with Image.open(io.BytesIO(raw)) as picture:
                region = picture.convert('RGBA').crop(rect).tobytes()
            if region == previous:
                return raw
            previous = region
            # Observing the accessibility tree also lets a completed swipe's
            # ballistic animation settle. The input itself is never repeated.
            self.dump()
        self.save_failure()
        raise RuntimeError('Panel pixels did not settle')

    def scene(self, name, predicate, page=None):
        attempts = self.wait(predicate, name)
        rect = self.bounds(self.panel(page)) if page else None
        image = self.stable_screenshot(rect) if rect else self.screenshot()
        (self.out / (name + '.xml')).write_bytes(self.xml)
        (self.out / (name + '.png')).write_bytes(image)
        self.scenes.append({'scene': name, 'observationAttempts': attempts,
                            **({'panel': page, 'panelBounds': rect} if rect else {})})
        print('scene ' + name, flush=True)

    def save_failure(self):
        if self.xml:
            (self.out / 'failure.xml').write_bytes(self.xml)
        if not (self.out / 'failure.png').exists():
            try:
                (self.out / 'failure.png').write_bytes(self.screenshot())
            except Exception:
                pass

    def tap_node(self, node, description):
        if node is None:
            raise RuntimeError('Missing touch target: ' + description)
        a, b, c, d = self.bounds(node)
        self.inputs.append({'type': 'touch', 'target': description, 'bounds': (a, b, c, d)})
        self.run('shell', 'input', 'tap', (a + c) // 2, (b + d) // 2)

    def tap(self, label, first=False):
        self.tap_node(self.control(label, first=first), label)

    def tap_tab(self, page):
        self.tap_node(self.tab(page), TABS_LABEL + ': ' + TAB_LABELS[page])

    def event(self, code, value):
        self.run('shell', 'sendevent', self.keyboard, 1, code, value)
        self.run('shell', 'sendevent', self.keyboard, 0, 0, 0)

    def key(self, code, description, expected=None, shift=False):
        self.wait(lambda: self.native_focused() and (expected is None or expected()),
                  'native and logical focus before ' + description)
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

    def focus_close(self):
        for _ in range(12):
            self.dump()
            if self.focus_in(self.control('Close')):
                return
            before = self.focus_signature()
            self.key(15, 'Tab traversal to Close')
            self.wait(lambda: self.focus_signature() != before, 'Tab moved to another focus owner')
        raise RuntimeError('Keyboard traversal did not reach Close')

    def swipe_panel(self, page):
        node = self.panel(page)
        if node is None:
            raise RuntimeError('Missing active scroll panel')
        a, b, c, d = self.bounds(node)
        if d - b < 80:
            raise RuntimeError('Panel is too short for a contained swipe')
        x = (a + c) // 2
        start, end = b + (d - b) * 4 // 5, b + (d - b) // 5
        self.inputs.append({'type': 'touch swipe', 'panel': page, 'bounds': (a, b, c, d),
                            'start': (x, start), 'end': (x, end), 'sentOnce': True})
        self.run('shell', 'input', 'swipe', x, start, x, end, 650)

    def saved_panel_bounds(self, scene, page):
        tree = ET.parse(self.out / (scene + '.xml')).getroot()
        found = [node for node in tree.iter('node')
                 if node.get('resource-id') == 'preset-guide-panel-' + page
                 or node.get('resource-id', '').endswith(':id/preset-guide-panel-' + page)]
        if len(found) != 1:
            # A scene record keeps the exact selected live bounds even when
            # an Android bridge omits semantic identifiers from the XML.
            record = next(item for item in self.scenes if item['scene'] == scene)
            return tuple(record['panelBounds'])
        return self.bounds(found[0])

    def compare_panels(self, before, after, page, equal, purpose):
        first_rect = self.saved_panel_bounds(before, page)
        last_rect = self.saved_panel_bounds(after, page)
        if first_rect != last_rect:
            raise RuntimeError('Panel bounds changed during ' + purpose)
        with Image.open(self.out / (before + '.png')) as a, Image.open(self.out / (after + '.png')) as b:
            if a.size != b.size:
                raise RuntimeError('Viewport changed during ' + purpose)
            left = a.convert('RGBA').crop(first_rect)
            right = b.convert('RGBA').crop(last_rect)
            same = left.tobytes() == right.tobytes()
            changed_bounds = ImageChops.difference(left.convert('RGB'), right.convert('RGB')).getbbox()
        if same != equal:
            raise RuntimeError('Unexpected panel pixels during ' + purpose)
        self.pixel_proofs.append({'purpose': purpose, 'page': page, 'before': before, 'after': after,
                                  'bounds': first_rect, 'rgbaByteEqual': same,
                                  'changedBoundsInPanel': changed_bounds})

    def header_geometry(self):
        close = self.control('Close')
        group = self.group()
        if close is None or group is None:
            return None
        close_rect, tabs_rect = self.bounds(close), self.bounds(group)
        if close_rect[3] > tabs_rect[1] or close.get('focusable') != 'true':
            return None
        return {'closeBounds': close_rect, 'tabsBounds': tabs_rect}

    def display_state(self):
        text = self.run('shell', 'wm', 'size').decode().strip()
        physical = re.search(r'Physical size:\s*(\d+x\d+)', text)
        override = re.search(r'Override size:\s*(\d+x\d+)', text)
        if physical is None:
            raise RuntimeError('Could not determine original emulator display size')
        return {'physical': physical[1], 'override': override[1] if override else None}

    def launch(self):
        self.run('shell', 'am', 'force-stop', PACKAGE)
        self.run('shell', 'am', 'start', '-W', '-n', PACKAGE + '/.MainActivity')

    def open_presets(self, prefix):
        self.wait(lambda: self.native_focused() and self.control('Presets') is not None, 'fixture ready')
        self.tap('Presets')
        self.scene(prefix + '-presets', lambda: self.control('Mode details', first=True) is not None)

    def open_reader(self, page, name):
        self.tap(TAB_LABELS[page], first=True)
        heading = 'How it works' if page == 'explanation' else 'Fix a bug'
        self.scene(name, lambda: self.selected(page) and self.header_geometry() is not None
                   and self.panel_contains(page, heading), page)

    def short_reader(self):
        self.launch()
        self.open_presets('short')
        self.open_reader('explanation', 'short-explanation-initial')
        fixed_header = self.header_geometry()
        self.swipe_panel('explanation')
        self.scene('short-explanation-scrolled', lambda: self.selected('explanation')
                   and self.header_geometry() == fixed_header, 'explanation')
        self.compare_panels('short-explanation-initial', 'short-explanation-scrolled', 'explanation',
                            False, 'real explanation swipe scrolls content')
        self.tap_tab('usage')
        self.scene('short-usage-initial', lambda: self.selected('usage')
                   and self.header_geometry() == fixed_header, 'usage')
        self.swipe_panel('usage')
        self.scene('short-usage-scrolled', lambda: self.selected('usage')
                   and self.header_geometry() == fixed_header, 'usage')
        self.compare_panels('short-usage-initial', 'short-usage-scrolled', 'usage', False,
                            'real usage swipe scrolls content')
        self.tap_tab('explanation')
        self.scene('short-explanation-retained', lambda: self.selected('explanation')
                   and self.header_geometry() == fixed_header, 'explanation')
        self.compare_panels('short-explanation-scrolled', 'short-explanation-retained', 'explanation',
                            True, 'explanation preserves its independent scroll position')
        self.tap_tab('usage')
        self.scene('short-usage-retained', lambda: self.selected('usage')
                   and self.header_geometry() == fixed_header, 'usage')
        self.compare_panels('short-usage-scrolled', 'short-usage-retained', 'usage', True,
                            'usage preserves its independent scroll position')

        self.tap('Close')
        self.scene('short-touch-close', lambda: self.group() is None)
        self.open_reader('explanation', 'short-explanation-reopened')
        self.compare_panels('short-explanation-initial', 'short-explanation-reopened', 'explanation',
                            True, 'closing and reopening resets explanation to the top')
        self.tap_tab('usage')
        self.scene('short-usage-reopened', lambda: self.selected('usage'), 'usage')
        self.compare_panels('short-usage-initial', 'short-usage-reopened', 'usage', True,
                            'closing and reopening resets usage to the top')

        self.key(15, 'Tab from selected usage tab into its panel',
                 expected=lambda: self.focus_stop() == ('tab', 'usage'))
        self.scene('short-usage-panel-focused', lambda: self.selected('usage')
                   and self.focus_stop() == ('panel', 'usage'), 'usage')
        self.key(109, 'PageDown scrolls the focused usage panel',
                 expected=lambda: self.focus_stop() == ('panel', 'usage'))
        self.scene('short-usage-page-down', lambda: self.selected('usage')
                   and self.focus_stop() == ('panel', 'usage'), 'usage')
        self.compare_panels('short-usage-panel-focused', 'short-usage-page-down', 'usage', False,
                            'hardware PageDown scrolls the active panel')

        expected_stops = [('close', ''), ('tab', 'usage'), ('panel', 'usage')]
        for index, expected in enumerate(expected_stops, 1):
            self.key(15, 'Tab cycle step ' + str(index))
            self.scene('short-tab-cycle-' + str(index), lambda expected=expected:
                       self.selected('usage') and self.focus_stop() == expected
                       and self.panel('explanation') is None, 'usage')
            self.traversal.append({'step': index, 'focused': expected, 'inactivePanelAbsent': True})
        self.key(1, 'Escape closes only the active reader',
                 expected=lambda: self.focus_stop() == ('panel', 'usage'))
        self.scene('short-escape-close', lambda: self.group() is None)

    def execute(self, fixture):
        avd = self.run('shell', 'getprop', 'ro.boot.qemu.avd_name').decode().strip()
        if avd != 'whalee-api36':
            raise RuntimeError('Expected the parent-owned whalee-api36 emulator')
        self.run('root')
        self.run('wait-for-device')
        devices = self.run('shell', 'getevent', '-lp').decode()
        keyboards = re.findall(r'add device \d+: (\S+)\s+name:\s+"AT Translated Set 2 keyboard"', devices)
        if len(keyboards) != 1:
            raise RuntimeError('Expected one emulated hardware keyboard')
        self.keyboard = keyboards[0]
        self.run('install', '-r', fixture)
        self.launch()
        self.open_presets('normal')
        self.open_reader('explanation', 'normal-explanation-open')
        self.tap('Close')
        self.scene('normal-touch-close', lambda: self.group() is None)
        self.open_reader('usage', 'normal-usage-open')
        self.focus_close()
        self.scene('normal-close-keyboard-focused', lambda: self.focus_in(self.control('Close')))
        self.key(28, 'Enter activates the accessible Close button',
                 expected=lambda: self.focus_in(self.control('Close')))
        self.scene('normal-keyboard-close', lambda: self.group() is None)

        original = self.display_state()
        self.display = {'original': original, 'requestedOverride': SHORT_SIZE,
                        'density': self.run('shell', 'wm', 'density').decode().strip()}
        try:
            self.run('shell', 'wm', 'size', SHORT_SIZE)
            self.display['applied'] = self.display_state()
            if self.display['applied']['override'] != SHORT_SIZE:
                raise RuntimeError('Short viewport override was not applied')
            self.short_reader()
        except Exception:
            self.save_failure()
            raise
        finally:
            target = original['override'] or 'reset'
            self.run('shell', 'wm', 'size', target)
            self.display['restoredState'] = self.display_state()
            self.display['restoredExactly'] = self.display['restoredState'] == original
            if not self.display['restoredExactly']:
                raise RuntimeError('Original display override was not restored')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture', type=Path, default=REPO / '.local/dialog-family-builds/android-fixture.apk')
    parser.add_argument('--out', type=Path, default=REPO / 'build/native-dialog-android')
    args = parser.parse_args()
    if not args.fixture.is_file():
        parser.error('Fixture APK does not exist')
    args.out.mkdir(parents=True, exist_ok=False)
    replay = Replay(args.out)
    record = {'synthetic': True, 'ownedEmulator': SERIAL,
              'fixtureSha256': hashlib.sha256(args.fixture.read_bytes()).hexdigest(),
              'actualInputs': ['touch', 'contained panel swipes', 'emulated hardware Tab, Enter, PageDown and Escape'],
              'accessibility': 'Named tabs, identified active panels and enabled/clickable/focusable Close button read from UIAutomator',
              'keyboardReadiness': 'Native FlutterView plus expected logical focus checked before each selection or scrolling key',
              'failedSelectionKeysRetried': False,
              'cleanupOwner': 'Parent restores normal APK and stops its emulator; driver restores its wm-size override'}
    try:
        replay.execute(args.fixture)
    except Exception as error:
        replay.save_failure()
        record.update({'passed': False, 'failure': str(error), 'scenes': replay.scenes,
                       'inputs': replay.inputs, 'pixelProofs': replay.pixel_proofs,
                       'tabTraversal': replay.traversal, 'displayOverride': replay.display})
        (args.out / 'failure-receipt.json').write_text(json.dumps(record, indent=2) + '\n')
        raise
    record.update({'passed': True, 'scenes': replay.scenes, 'inputs': replay.inputs,
                   'pixelProofs': replay.pixel_proofs, 'tabTraversal': replay.traversal,
                   'displayOverride': replay.display,
                   'independentPanelScrollPreserved': True, 'reopenResetsPanelScroll': True,
                   'keyboardPageDownScrolledPanel': True, 'inactivePanelsSkippedByTab': True,
                   'accessibleHeaderCloseVerified': True})
    (args.out / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'passedScenes': len(replay.scenes), 'independentPanelScrollPreserved': True,
                      'reopenResetsPanelScroll': True, 'keyboardPageDownScrolledPanel': True,
                      'inactivePanelsSkippedByTab': True, 'displayOverrideRestored': True}))


if __name__ == '__main__':
    main()
