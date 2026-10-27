"""Replay the headed risk fixture on the parent's owned emulator-5560.

PREPARATION ONLY until the parent starts whalee-api36 and authorizes execution.
Invoke after sourcing the absolute scripts/pr16-env.sh. This driver installs the
fixture and uses actual touch and one-shot emulated hardware keys. It restores
its exact wm-size override in finally; the parent restores the normal APK,
stops the app, unroots, and stops its emulator. No failed key is resent.
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
REPO = ROOT / 'scratch/whalee-headed-dialogs'
ADB = ROOT / 'toolchains/android-sdk/platform-tools/adb'
SERIAL = 'emulator-5560'
PACKAGE = 'app.kevinzhow.whalee'
REMOTE_XML = '/sdcard/whalee-headed-native.xml'
SHORT_SIZE = '1080x1320'
OPEN_NORMAL = 'Open risk confirmation'
OPEN_LONG = 'Open long risk confirmation'
OPEN_DISABLED = 'Open disabled risk confirmation'
ACK = 'I understand the risks and want to continue'
CONFIRM = 'Enable Full access'
CANCEL = 'Cancel'
CLOSE = 'Close'


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
        self.display = {}
        self.traversal = []

    def run(self, *args):
        return subprocess.run([str(ADB), '-s', SERIAL, *map(str, args)],
                              check=True, capture_output=True, timeout=120).stdout

    @staticmethod
    def label(node):
        return node.get('content-desc') or node.get('text') or ''

    @staticmethod
    def bounds(node):
        if node is None:
            raise RuntimeError('Missing accessibility node')
        values = tuple(map(int, re.findall(r'-?\d+', node.get('bounds', ''))))
        if len(values) != 4 or values[2] <= values[0] or values[3] <= values[1]:
            raise RuntimeError('Missing or empty accessibility bounds')
        return values

    @staticmethod
    def inside(inner, outer):
        return (inner[0] >= outer[0] and inner[1] >= outer[1]
                and inner[2] <= outer[2] and inner[3] <= outer[3])

    def dump(self):
        self.run('shell', 'uiautomator', 'dump', REMOTE_XML)
        self.xml = self.run('exec-out', 'cat', REMOTE_XML)
        self.current = ET.fromstring(self.xml)
        self.parents = {child: parent for parent in self.current.iter() for child in parent}

    def named(self, label):
        return [node for node in self.current.iter('node') if self.label(node) == label]

    def identified(self, identifier):
        found = [node for node in self.current.iter('node')
                 if node.get('resource-id') == identifier
                 or node.get('resource-id', '').endswith(':id/' + identifier)]
        return found[0] if len(found) == 1 else None

    def button(self, label):
        # A disabled Flutter button can have clickable=false. Select its
        # actual button semantic owner, not only enabled GestureDetectors.
        found = []
        for node in self.named(label):
            owner = node
            while owner is not None:
                if owner.get('class') == 'android.widget.Button':
                    if owner not in found:
                        found.append(owner)
                    break
                owner = self.parents.get(owner)
        return found[0] if len(found) == 1 else None

    def checkbox(self):
        found = [node for node in self.named(ACK)
                 if node.get('class') == 'android.widget.CheckBox'
                 or node.get('checkable') == 'true']
        return found[0] if len(found) == 1 else None

    def button_state(self, label, **expected):
        node = self.button(label)
        return node is not None and all(node.get(key) == value for key, value in expected.items())

    def checkbox_state(self, **expected):
        node = self.checkbox()
        return node is not None and all(node.get(key) == value for key, value in expected.items())

    def content(self):
        direct = self.identified('risk-content')
        if direct is not None:
            try:
                self.bounds(direct)
                return direct
            except RuntimeError:
                pass
        # ValueKeys may not be surfaced as resource IDs on Android. The
        # fixture has one scrollable foreground pane; the home is a Column.
        # Keep this fallback semantic and dynamic, without page coordinates.
        candidates = []
        footer = self.footer_geometry()
        for node in self.current.iter('node'):
            if node.get('package') != PACKAGE or node.get('scrollable') != 'true':
                continue
            try:
                rect = self.bounds(node)
            except RuntimeError:
                continue
            if footer is not None and rect[3] <= footer['region'][1] and rect[3] - rect[1] > 80:
                candidates.append(node)
        return candidates[0] if len(candidates) == 1 else None

    def visible(self, node, within=None):
        if node is None or node.get('visible-to-user') == 'false':
            return False
        try:
            rect = self.bounds(node)
        except RuntimeError:
            return False
        return within is None or self.inside(rect, within)

    def close_visible(self):
        pane = self.content()
        return pane is not None and self.visible(self.button(CLOSE), self.bounds(pane))

    @staticmethod
    def focus_in(node):
        return node is not None and any(child.get('focused') == 'true' for child in node.iter('node'))

    def focused(self, label):
        return self.focus_in(self.checkbox() if label == ACK else self.button(label))

    def native_focused(self):
        return any(node.get('class') == 'android.widget.FrameLayout'
                   and node.get('package') == PACKAGE and node.get('focusable') == 'true'
                   and node.get('focused') == 'true' for node in self.current.iter('node'))

    def focus_signature(self):
        return tuple(sorted((node.get('resource-id', ''), self.label(node), node.get('class', ''),
                             node.get('bounds', '')) for node in self.current.iter('node')
                            if node.get('package') == PACKAGE and node.get('focused') == 'true'
                            and node.get('class') != 'android.widget.FrameLayout'))

    def footer_geometry(self):
        cancel, confirm = self.button(CANCEL), self.button(CONFIRM)
        if cancel is None or confirm is None:
            return None
        try:
            a, b = self.bounds(cancel), self.bounds(confirm)
        except RuntimeError:
            return None
        if a[1] != b[1] or a[3] != b[3] or a[2] > b[0]:
            return None
        return {'cancel': a, 'confirm': b,
                'region': (a[0], min(a[1], b[1]), b[2], max(a[3], b[3]))}

    def home(self, decision=None, opened=None):
        return (all(self.button(label) is not None for label in (OPEN_NORMAL, OPEN_LONG, OPEN_DISABLED))
                and self.button(CONFIRM) is None
                and (decision is None or bool(self.named('Decision: ' + decision)))
                and (opened is None or bool(self.named('Opened: ' + str(opened)))))

    def long_bottom(self, checked=False):
        pane = self.content()
        return (pane is not None and self.checkbox_state(
                    checked='true' if checked else 'false', enabled='true', focused='true')
                and self.visible(self.checkbox(), self.bounds(pane))
                and not self.close_visible()
                and self.button_state(CONFIRM, enabled='true' if checked else 'false'))

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
            # Observe settling; never repeat the touch/selection key.
            self.dump()
        self.save_failure()
        raise RuntimeError('Dialog pixels did not settle')

    def scene(self, name, predicate, scroll=False):
        attempts = self.wait(predicate, name)
        pane = self.content() if scroll else None
        footer = self.footer_geometry()
        pane_rect = self.bounds(pane) if pane is not None else None
        raw = self.stable_screenshot(pane_rect) if pane_rect else self.screenshot()
        if not predicate():
            self.save_failure()
            raise RuntimeError('Scene changed while settling: ' + name)
        (self.out / (name + '.xml')).write_bytes(self.xml)
        (self.out / (name + '.png')).write_bytes(raw)
        self.scenes.append({'scene': name, 'observationAttempts': attempts,
                            **({'contentBounds': pane_rect} if pane_rect else {}),
                            **({'footerBounds': footer} if footer else {}),
                            'focusSignature': self.focus_signature()})
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
        rect = self.bounds(node)
        self.inputs.append({'type': 'touch', 'target': description, 'bounds': rect, 'sentOnce': True})
        self.run('shell', 'input', 'tap', (rect[0] + rect[2]) // 2, (rect[1] + rect[3]) // 2)

    def tap(self, label):
        self.tap_node(self.button(label), label)

    def event(self, code, value):
        self.run('shell', 'sendevent', self.keyboard, 1, code, value)
        self.run('shell', 'sendevent', self.keyboard, 0, 0, 0)

    def key(self, code, description, expected=None, shift=False):
        self.wait(lambda: self.native_focused() and (expected is None or expected()),
                  'native and expected logical focus before ' + description)
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
        for _ in range(8):
            self.dump()
            if self.focused(CLOSE):
                return
            before = self.focus_signature()
            self.key(15, 'Tab navigation to accessible Close')
            self.wait(lambda: self.focus_signature() != before, 'Tab advanced to a new focus owner')
        raise RuntimeError('Keyboard traversal did not reach Close')

    def swipe_content(self, direction):
        pane = self.content()
        if pane is None:
            raise RuntimeError('Missing unique accessibility scroll pane')
        a, b, c, d = self.bounds(pane)
        if d - b < 100:
            raise RuntimeError('Content pane is too short for contained swipe')
        x, height = (a + c) // 2, d - b
        start, end = ((b + height * 4 // 5, b + height // 5) if direction == 'up'
                      else (b + height // 10, b + height * 9 // 10))
        self.inputs.append({'type': 'contained touch swipe', 'direction': direction,
                            'contentBounds': (a, b, c, d), 'start': (x, start),
                            'end': (x, end), 'sentOnce': True})
        self.run('shell', 'input', 'swipe', x, start, x, end, 650)

    def record_for(self, scene):
        return next(item for item in self.scenes if item['scene'] == scene)

    def compare(self, before, after, region, equal, purpose):
        left_record, right_record = self.record_for(before), self.record_for(after)
        key = 'contentBounds' if region == 'content' else 'footerBounds'
        first, last = left_record[key], right_record[key]
        if region == 'footer':
            first, last = first['region'], last['region']
        first, last = tuple(first), tuple(last)
        if first != last:
            raise RuntimeError(region + ' bounds changed during ' + purpose)
        with Image.open(self.out / (before + '.png')) as a, Image.open(self.out / (after + '.png')) as b:
            if a.size != b.size:
                raise RuntimeError('Viewport changed during ' + purpose)
            left, right = a.convert('RGBA').crop(first), b.convert('RGBA').crop(last)
            same = left.tobytes() == right.tobytes()
            changed = ImageChops.difference(left.convert('RGB'), right.convert('RGB')).getbbox()
        if same != equal:
            raise RuntimeError('Unexpected ' + region + ' pixels during ' + purpose)
        self.pixel_proofs.append({'purpose': purpose, 'region': region, 'bounds': first,
                                  'before': before, 'after': after, 'rgbaByteEqual': same,
                                  'changedBoundsInRegion': changed})

    def launch(self):
        self.run('shell', 'am', 'force-stop', PACKAGE)
        self.run('shell', 'am', 'start', '-W', '-n', PACKAGE + '/.MainActivity')

    def normal_cases(self):
        self.launch()
        self.scene('normal-home', lambda: self.native_focused() and self.home('No decision', 0))
        self.tap(OPEN_NORMAL)
        self.scene('normal-off', lambda: self.checkbox_state(checked='false', focused='true',
                   enabled='true', clickable='true') and self.button_state(CONFIRM, enabled='false', clickable='false'))
        self.key(28, 'Enter on unchecked acknowledgement must not confirm', expected=lambda: self.focused(ACK))
        self.scene('normal-enter-blocked', lambda: self.checkbox_state(checked='false', focused='true')
                   and self.button_state(CONFIRM, enabled='false', clickable='false'))
        self.key(57, 'Space explicitly acknowledges risk', expected=lambda: self.focused(ACK))
        self.scene('normal-space-checked', lambda: self.checkbox_state(checked='true', focused='true')
                   and self.button_state(CONFIRM, enabled='true', clickable='true'))
        self.key(15, 'Tab from acknowledgement to Cancel', expected=lambda: self.focused(ACK))
        self.scene('normal-cancel-focused', lambda: self.focused(CANCEL))
        self.key(15, 'Tab from Cancel to Confirm', expected=lambda: self.focused(CANCEL))
        self.scene('normal-confirm-focused', lambda: self.focused(CONFIRM))
        self.key(28, 'Enter activates acknowledged Confirm', expected=lambda: self.focused(CONFIRM))
        self.scene('normal-confirmed', lambda: self.home('Confirmed', 1) and self.focused(OPEN_NORMAL))

        self.tap(OPEN_NORMAL)
        self.scene('normal-reopened-off', lambda: self.checkbox_state(checked='false', focused='true')
                   and self.button_state(CLOSE, enabled='true', clickable='true', focusable='true'))
        self.tap(CLOSE)
        self.scene('normal-touch-close-canceled', lambda: self.home('Canceled', 2) and self.focused(OPEN_NORMAL))

        self.tap(OPEN_DISABLED)
        self.scene('disabled-open', lambda: self.checkbox_state(checked='false', enabled='false', clickable='false')
                   and self.button_state(CONFIRM, enabled='false', clickable='false')
                   and self.button_state(CLOSE, enabled='true', clickable='true', focusable='true'))
        self.tap_node(self.checkbox(), 'disabled acknowledgement must stay unchecked')
        self.scene('disabled-ack-touch-blocked', lambda: self.checkbox_state(checked='false', enabled='false')
                   and self.button_state(CONFIRM, enabled='false'))
        self.tap_node(self.button(CONFIRM), 'disabled Confirm must not close')
        self.scene('disabled-confirm-touch-blocked', lambda: self.checkbox_state(checked='false', enabled='false')
                   and self.button_state(CONFIRM, enabled='false'))
        self.focus_close()
        self.scene('disabled-accessible-close-focused', lambda: self.focused(CLOSE)
                   and self.button_state(CLOSE, enabled='true', clickable='true', focusable='true'))
        self.key(28, 'Enter activates disabled-dialog accessible Close', expected=lambda: self.focused(CLOSE))
        self.scene('disabled-close-canceled', lambda: self.home('Canceled', 3) and self.focused(OPEN_DISABLED))

    def long_cases(self):
        # Restart makes Opened deterministic and avoids relying on old fixture state.
        self.launch()
        self.scene('long-home', lambda: self.native_focused() and self.home('No decision', 0))
        self.tap(OPEN_LONG)
        self.scene('long-autofocus-bottom', lambda: self.long_bottom(False), scroll=True)
        fixed_footer = self.footer_geometry()
        self.key(15, 'Shift+Tab reveals the header Close at the top',
                 expected=lambda: self.focused(ACK), shift=True)
        self.scene('long-close-at-top', lambda: self.focused(CLOSE) and self.close_visible()
                   and self.footer_geometry() == fixed_footer, scroll=True)
        original_close = self.bounds(self.button(CLOSE))
        self.compare('long-autofocus-bottom', 'long-close-at-top', 'content', False,
                     'keyboard Close scrolls the full content/header back to the top')
        self.compare('long-autofocus-bottom', 'long-close-at-top', 'footer', True,
                     'fixed unchecked footer stays pixel-identical while header/content scroll')

        self.swipe_content('up')
        self.scene('long-contained-swipe', lambda: self.footer_geometry() == fixed_footer
                   and (not self.close_visible() or self.bounds(self.button(CLOSE))[1] < original_close[1]), scroll=True)
        self.compare('long-close-at-top', 'long-contained-swipe', 'content', False,
                     'real contained swipe moves the header and warning body')
        self.compare('long-close-at-top', 'long-contained-swipe', 'footer', True,
                     'contained content swipe leaves both fixed footer actions unchanged')
        self.swipe_content('down')
        self.scene('long-swipe-returned-top', lambda: self.focused(CLOSE) and self.close_visible()
                   and self.bounds(self.button(CLOSE)) == original_close
                   and self.footer_geometry() == fixed_footer, scroll=True)
        self.key(15, 'Tab from header Close reveals acknowledgement at bottom', expected=lambda: self.focused(CLOSE))
        self.scene('long-keyboard-ack-bottom', lambda: self.long_bottom(False)
                   and self.footer_geometry() == fixed_footer, scroll=True)
        self.key(15, 'Tab from long acknowledgement reaches Cancel', expected=lambda: self.focused(ACK))
        self.scene('long-cancel-focused', lambda: self.focused(CANCEL)
                   and self.footer_geometry() == fixed_footer, scroll=True)
        self.key(28, 'Enter activates reachable long-dialog Cancel', expected=lambda: self.focused(CANCEL))
        self.scene('long-canceled', lambda: self.home('Canceled', 1) and self.focused(OPEN_LONG))

        self.tap(OPEN_LONG)
        self.scene('long-reopened-default-bottom', lambda: self.long_bottom(False), scroll=True)
        self.compare('long-autofocus-bottom', 'long-reopened-default-bottom', 'content', True,
                     'reopening resets unchecked state and repeats default automatic bottom reveal')
        self.compare('long-autofocus-bottom', 'long-reopened-default-bottom', 'footer', True,
                     'reopened unchecked footer returns to identical pixels')
        self.key(57, 'Space acknowledges the reopened long dialog', expected=lambda: self.focused(ACK))
        self.scene('long-checked', lambda: self.long_bottom(True), scroll=True)
        self.key(15, 'Tab from checked long acknowledgement to Cancel', expected=lambda: self.focused(ACK))
        self.scene('long-checked-cancel-focused', lambda: self.focused(CANCEL)
                   and self.button_state(CONFIRM, enabled='true'), scroll=True)
        self.key(15, 'Tab from long Cancel to enabled Confirm', expected=lambda: self.focused(CANCEL))
        self.scene('long-confirm-focused', lambda: self.focused(CONFIRM)
                   and self.button_state(CONFIRM, enabled='true'), scroll=True)
        self.key(28, 'Enter confirms the long acknowledged dialog', expected=lambda: self.focused(CONFIRM))
        self.scene('long-confirmed', lambda: self.home('Confirmed', 2) and self.focused(OPEN_LONG))

    def display_state(self):
        text = self.run('shell', 'wm', 'size').decode().strip()
        physical = re.search(r'Physical size:\s*(\d+x\d+)', text)
        override = re.search(r'Override size:\s*(\d+x\d+)', text)
        if physical is None:
            raise RuntimeError('Could not determine original emulator display size')
        return {'physical': physical[1], 'override': override[1] if override else None}

    def execute(self, fixture, short_size):
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
        self.normal_cases()
        original = self.display_state()
        self.display = {'original': original, 'requestedOverride': short_size,
                        'densityUnchanged': self.run('shell', 'wm', 'density').decode().strip()}
        try:
            if short_size:
                self.run('shell', 'wm', 'size', short_size)
                self.display['applied'] = self.display_state()
                if self.display['applied']['override'] != short_size:
                    raise RuntimeError('Short viewport override was not applied')
            self.long_cases()
        except Exception:
            self.save_failure()
            raise
        finally:
            if short_size:
                self.run('shell', 'wm', 'size', original['override'] or 'reset')
            self.display['restoredState'] = self.display_state()
            self.display['restoredExactly'] = self.display['restoredState'] == original
            if not self.display['restoredExactly']:
                raise RuntimeError('Original display override was not restored')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixture', type=Path, default=REPO / '.local/headed-dialogs-builds/android-fixture.apk')
    parser.add_argument('--out', type=Path, default=REPO / 'build/native-headed-android')
    parser.add_argument('--short-size', default=SHORT_SIZE,
                        help='Temporary wm size for long scenes; defaults to 1080x1320')
    parser.add_argument('--keep-size', action='store_true', help='Skip the optional wm-size override')
    args = parser.parse_args()
    if not args.fixture.is_file():
        parser.error('Fixture APK does not exist')
    if not re.fullmatch(r'\d+x\d+', args.short_size):
        parser.error('--short-size must be WIDTHxHEIGHT')
    args.out.mkdir(parents=True, exist_ok=False)
    replay = Replay(args.out)
    record = {'synthetic': True, 'ownedEmulator': SERIAL,
              'fixtureSha256': hashlib.sha256(args.fixture.read_bytes()).hexdigest(),
              'actualInputs': ['touch', 'contained risk-content swipes',
                               'emulated hardware Enter, Space, Tab and Shift+Tab'],
              'accessibility': 'Native checkbox checked/enabled/clickable/focused state and accessible Close; '
                               'dynamic identified or unique scrollable pane; fixed footer button bounds',
              'keyboardReadiness': 'Native FlutterView and expected logical focus checked before every selection key',
              'failedSelectionKeysRetried': False,
              'pixelAcceptance': 'Exact RGBA equality for unchanged unchecked footer and reopened default bottom; '
                                 'changed content pixels for keyboard reveal and actual contained swipe',
              'pageDownClaimed': False,
              'cleanupOwner': 'Driver restores its exact wm-size override; parent restores normal APK, '
                              'stops the app, unroots and stops its emulator'}
    try:
        replay.execute(args.fixture, None if args.keep_size else args.short_size)
    except Exception as error:
        replay.save_failure()
        record.update({'passed': False, 'failure': str(error), 'scenes': replay.scenes,
                       'inputs': replay.inputs, 'pixelProofs': replay.pixel_proofs,
                       'displayOverride': replay.display})
        (args.out / 'failure-receipt.json').write_text(json.dumps(record, indent=2) + '\n')
        raise
    record.update({'passed': True, 'scenes': replay.scenes, 'inputs': replay.inputs,
                   'pixelProofs': replay.pixel_proofs, 'displayOverride': replay.display,
                   'normalEnterGateVerified': True, 'explicitAcknowledgementRequired': True,
                   'disabledAckAndConfirmBlocked': True, 'accessibleCloseTouchAndEnter': True,
                   'longAutofocusRevealsAcknowledgement': True,
                   'headerAndBodyScrollTogether': True, 'footerBoundsRemainFixed': True,
                   'tabRevealsHeaderAndAcknowledgement': True,
                   'reopenResetsStateAndDefaultScroll': True,
                   'restoresEachFixtureOpener': True})
    (args.out / 'receipt.json').write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({'passedScenes': len(replay.scenes), 'pixelProofs': len(replay.pixel_proofs),
                      'longDefaultBottomVerified': True, 'footerFixedVerified': True,
                      'displayOverrideRestored': replay.display['restoredExactly']}))


if __name__ == '__main__':
    main()
