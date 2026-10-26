#!/usr/bin/env python3
"""Exercise synthetic persistent state across two APKs on an explicitly selected device."""
import argparse
import json
import re
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path
from apk_identity import identity


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--sdk', type=Path, required=True)
    p.add_argument('--build-tools', type=Path, required=True)
    p.add_argument('--serial', required=True)
    p.add_argument('--before', type=Path, required=True)
    p.add_argument('--after', type=Path, required=True)
    p.add_argument('--restore', type=Path, required=True)
    p.add_argument('--out', type=Path, required=True)
    a = p.parse_args()
    artifacts = {key: identity(value, a.build_tools / 'apksigner', a.build_tools / 'aapt') for key, value in [('before', a.before), ('after', a.after), ('restore', a.restore)]}
    if any(v['package'] != 'app.kevinzhow.whalee' for v in artifacts.values()):
        p.error('All APKs must be Whalee')
    if len({v['certificateSha256'] for v in artifacts.values()}) != 1:
        p.error('Upgrade and restoration require the same signer')
    if artifacts['before']['versionCode'] >= artifacts['after']['versionCode'] or artifacts['restore']['versionCode'] < artifacts['after']['versionCode']:
        p.error('After must increase versionCode and restore must not downgrade it')
    a.out.mkdir(parents=True, exist_ok=True)
    adb = a.sdk / 'platform-tools/adb'

    def run(*args):
        return subprocess.run([str(adb), '-s', a.serial, *map(str, args)], check=True, capture_output=True).stdout

    def launch(apk):
        run('install', '-r', apk)
        run('shell', 'am', 'force-stop', 'app.kevinzhow.whalee')
        run('shell', 'am', 'start', '-n', 'app.kevinzhow.whalee/.MainActivity')

    def scene(name, expected):
        for _ in range(12):
            run('shell', 'uiautomator', 'dump', '/sdcard/whalee-upgrade.xml')
            xml = run('exec-out', 'cat', '/sdcard/whalee-upgrade.xml')
            root = ET.fromstring(xml)
            texts = [n.get('text', '') for n in root.iter('node')]
            if all(t in texts for t in expected):
                (a.out / (name + '.xml')).write_bytes(xml)
                (a.out / (name + '.png')).write_bytes(run('exec-out', 'screencap', '-p'))
                return root
        raise RuntimeError('Synthetic upgrade scene failed: ' + name)

    restored = False
    try:
        launch(a.before)
        root = scene('before', ['Stage: before', 'Write synthetic upgrade state'])
        button = next(n for n in root.iter('node') if n.get('text') == 'Write synthetic upgrade state')
        x1, y1, x2, y2 = map(int, re.findall(r'\d+', button.get('bounds')))
        run('shell', 'input', 'tap', (x1 + x2) // 2, (y1 + y2) // 2)
        scene('seeded', ['All 8 persisted checks passed'])
        launch(a.after)
        scene('after', ['Stage: after', 'All 8 persisted checks passed'])
    finally:
        run('install', '-r', a.restore)
        run('shell', 'am', 'force-stop', 'app.kevinzhow.whalee')
        restored = True
    receipt = {'syntheticOnly': True, 'actualInstallReplace': True, 'preservedChecks': 8, 'sameSigner': True, 'formalSigningVerified': False, 'artifacts': artifacts, 'normalApkRestoredAndStopped': restored}
    (a.out / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps({'preservedChecks': 8, 'normalApkRestoredAndStopped': restored}))


if __name__ == '__main__':
    main()
