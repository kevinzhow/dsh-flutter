"""Restore only the owned headed-dialog validation resources and record proof."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import time

ROOT = Path('[workspace]')
REPO = ROOT / 'scratch/whalee-headed-dialogs'
ADB = ROOT / 'toolchains/android-sdk/platform-tools/adb'
SERIAL = 'emulator-5560'
PACKAGE = 'app.kevinzhow.whalee'

def adb(*args, check=True):
    return subprocess.run([str(ADB), '-s', SERIAL, *args], check=check,
                          capture_output=True, text=True, timeout=120)

assert adb('shell', 'getprop', 'ro.boot.qemu.avd_name').stdout.strip() == 'whalee-api36'
normal = REPO / '.local/headed-dialogs-builds/android-normal.apk'
local_hash = hashlib.sha256(normal.read_bytes()).hexdigest()
adb('install', '-r', str(normal))
paths = adb('shell', 'pm', 'path', PACKAGE).stdout.strip().splitlines()
assert len(paths) == 1 and paths[0].startswith('package:')
installed_hash = adb('shell', 'sha256sum', paths[0][8:]).stdout.split()[0]
assert installed_hash == local_hash, 'Installed normal APK differs'
adb('shell', 'am', 'force-stop', PACKAGE)
assert not adb('shell', 'pidof', PACKAGE, check=False).stdout.strip()
android = json.loads((REPO / 'build/native-headed-android/receipt.json').read_text())
assert android['displayOverride']['restoredExactly'] is True
size = adb('shell', 'wm', 'size').stdout.strip()
original = android['displayOverride']['original']
assert ('Override size: ' + original['override'] in size) if original['override'] else ('Override size:' not in size)
unroot = adb('unroot').stdout.strip()
adb('wait-for-device')
assert adb('shell', 'id', '-u').stdout.strip() != '0', 'adbd is still root'
pid_files = list((REPO / 'build/native-headed-gpu').glob('*/pids.json'))
assert len(pid_files) == 2
for file in pid_files:
    for pid in json.loads(file.read_text()).values():
        assert not Path('/proc', str(pid)).exists(), 'Recorded GPU process remains alive'
adb('emu', 'kill')
for attempt in range(30):
    devices = subprocess.run([str(ADB), 'devices'], capture_output=True, text=True, check=True).stdout
    if SERIAL not in devices:
        break
    time.sleep(1)
assert SERIAL not in devices, 'Owned emulator did not stop'
assert subprocess.run([str(ADB), 'start-server'], capture_output=True).returncode == 0
record = dict(normalApkRestored=True, normalAppForceStopped=True, ownedEmulatorStopped=True,
              sharedAdbRetained=True, recordedGpuPidsAbsent=True, displayOverrideReset=True,
              adbdUnrootRequested=True, normalApkLocalSha256=local_hash,
              normalApkInstalledSha256=installed_hash, displayState=size,
              displayOriginal=original, unrootResponse=unroot, gpuPidFiles=len(pid_files))
(REPO / '.local/headed-cleanup.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps(record))
