#!/usr/bin/env python3
"""Native Wayland replay on a private Weston 14 GL compositor.

gpu_capture.py OUT CASES.json [case-id ...]
Uses the same PARITY_DESKTOP_APP/HOST_LOG/HOME contract as app_capture.py.
Requires Weston 14, libweston-14-dev, cc, pkg-config, dbus-run-session and GPU
render-node access. Run the entire command under `sg render` if necessary.
"""
import contextlib
import json
import os
import pathlib
import re
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[2]


def need(key):
    value = os.environ.get(key)
    if not value:
        raise SystemExit(f'{key} is not set')
    return value


class Input:
    def __init__(self, fd):
        self.fd = fd
        self.keys = {}
        # Linux evdev codes for the explicitly configured US keyboard layout.
        for chars, codes in [
            ('1234567890-=', range(2, 14)),
            ('qwertyuiop[]', range(16, 28)),
            ("asdfghjkl;'`", [30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41]),
            ('zxcvbnm,./', range(44, 54)),
            ('\\ ', [43, 57]),
        ]:
            for char, code in zip(chars, codes):
                self.keys[char] = (code, False)
        for char in 'abcdefghijklmnopqrstuvwxyz':
            self.keys[char.upper()] = (self.keys[char][0], True)
        for char, base in zip('!@#$%^&*()_+{}:"~<>?|', '1234567890-=[];\'`,./\\'):
            self.keys[char] = (self.keys[base][0], True)

    def send(self, command):
        os.write(self.fd, (command + '\n').encode('ascii'))
        time.sleep(0.025)

    def click(self, x, y):
        self.send(f'move {x} {y}')
        self.send('button 272 1')  # BTN_LEFT
        self.send('button 272 0')

    def type(self, text):
        unsupported = set(text) - self.keys.keys()
        if unsupported:
            raise ValueError('The test keyboard supports printable US ASCII only')
        for char in text:
            code, shift = self.keys[char]
            if shift:
                self.send('key 42 1')
            self.send(f'key {code} 1')
            self.send(f'key {code} 0')
            if shift:
                self.send('key 42 0')

    def scroll(self, x, y, amount):
        self.send(f'move {x} {y}')
        self.send(f'scroll {amount}')


def stop(proc):
    if proc is None:
        return
    with contextlib.suppress(ProcessLookupError):
        os.killpg(proc.pid, signal.SIGTERM)
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        with contextlib.suppress(ProcessLookupError):
            os.killpg(proc.pid, signal.SIGKILL)
        proc.wait(timeout=10)


def wait_socket(path, proc):
    for _ in range(100):
        if path.exists():
            return
        if proc.poll() is not None:
            break
        time.sleep(0.1)
    raise RuntimeError('Weston failed to create its private socket; inspect weston.log')


def gpu_devices(pid, app):
    """Render nodes opened by the application, excluding its D-Bus services."""
    found = set()
    pending = [pid]
    while pending:
        current = pathlib.Path('/proc') / str(pending.pop())
        with contextlib.suppress(FileNotFoundError, ProcessLookupError):
            children = (current / 'task' / current.name / 'children').read_text()
            pending.extend(int(p) for p in children.split())
            if os.readlink(current / 'exe') != app:
                continue
            for fd in (current / 'fd').iterdir():
                with contextlib.suppress(FileNotFoundError):
                    target = os.readlink(fd)
                    if target.startswith('/dev/dri/renderD'):
                        found.add(target)
    return sorted(found)


def capture(env, directory, output):
    directory.mkdir(mode=0o700)
    subprocess.run(['weston-screenshooter'], env=env, cwd=directory,
                   stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, check=True, timeout=15)
    shots = list(directory.glob('*.png'))
    if len(shots) != 1:
        raise RuntimeError('Expected exactly one Weston output screenshot')
    shutil.move(shots[0], output)
    output.chmod(0o600)  # A failed pairing could leave a launch token visible.
    directory.rmdir()


def main():
    out = pathlib.Path(sys.argv[1]).resolve()
    out.mkdir(parents=True, exist_ok=True)
    app = str(pathlib.Path(need('PARITY_DESKTOP_APP')).resolve())
    home = pathlib.Path(need('PARITY_DESKTOP_HOME')).resolve()
    log = pathlib.Path(need('PARITY_DESKTOP_HOST_LOG'))
    match = re.search(r'http://127\.0\.0\.1:\d+/\?token=\S+', log.read_text())
    if not match:
        raise SystemExit('No isolated host launch link found')
    version = subprocess.check_output(['weston', '--version'], text=True).strip()
    if not version.startswith('weston 14.'):
        raise SystemExit('The test input module requires Weston 14 and matching libweston-14-dev')
    module = out / 'whalee-test-input.so'
    flags = shlex.split(subprocess.check_output(
        ['pkg-config', '--cflags', '--libs', 'libweston-14'], text=True))
    subprocess.run(['cc', '-std=gnu11', '-Wall', '-Wextra', '-Werror', '-shared', '-fPIC',
                    str(pathlib.Path(__file__).with_name('weston_input.c')), '-o', str(module), *flags], check=True)
    cases = json.loads(pathlib.Path(sys.argv[2]).read_text())['cases']
    only = sys.argv[3:]
    cases = [c for c in cases if not only or c['id'] in only]
    if not cases:
        raise SystemExit('No matching cases')
    runtime_base = pathlib.Path(need('XDG_RUNTIME_DIR'))
    if len(str(runtime_base / 'whalee-12345678' / 'wayland-test')) >= 104:
        raise SystemExit('XDG_RUNTIME_DIR is too long for a Unix socket; use a short private directory')
    for c in cases:
        case_out = out / c['id']
        case_out.mkdir(exist_ok=True)
        case_home = home / c['id']
        if case_home.exists():
            raise SystemExit(f'Refusing to overwrite existing settings: {case_home}')
        case_home.mkdir(parents=True)
        with tempfile.TemporaryDirectory(prefix='whalee-', dir=runtime_base) as runtime:
            read_fd, write_fd = os.pipe()
            weston = app_proc = None
            try:
                env = dict(os.environ, XDG_RUNTIME_DIR=runtime, WAYLAND_DISPLAY='wayland-test',
                           GDK_BACKEND='wayland', GTK_USE_PORTAL='0', HOME=str(case_home),
                           XDG_CONFIG_HOME=str(case_home / '.config'),
                           XDG_DATA_HOME=str(case_home / '.local/share'),
                           WHALEE_WINDOW_SIZE=f"{c['width']}x{c['height']}",
                           WHALEE_PIN_FONTS=str(ROOT / 'tool/parity-fonts/manifest.json'))
                for key in ['DISPLAY', 'LIBGL_ALWAYS_SOFTWARE', 'FLUTTER_LINUX_RENDERER',
                            'WHALEE_PLATFORM_BRIGHTNESS', 'WHALEE_TEST_INPUT_FD']:
                    env.pop(key, None)
                if c['theme'] == 'dark':
                    env['WHALEE_PLATFORM_BRIGHTNESS'] = 'dark'
                if c['locale'] == 'zh':
                    env.update(LC_ALL='zh_CN.UTF-8', LANGUAGE='zh_CN')
                config = pathlib.Path(runtime) / 'weston.ini'
                config.write_text('[keyboard]\nkeymap_layout=us\n')
                with (case_out / 'weston.log').open('w') as wl:
                    weston = subprocess.Popen([
                        'weston', '--backend=headless', '--renderer=gl', '--shell=kiosk-shell.so',
                        '--socket=wayland-test', f'--width={c["width"]}', f'--height={c["height"]}',
                        '--idle-time=0', '--debug', f'--config={config}', f'--modules={module}',
                    ], env=dict(env, WHALEE_TEST_INPUT_FD=str(read_fd)), pass_fds=(read_fd,),
                        stdout=wl, stderr=wl, start_new_session=True)
                os.close(read_fd)
                read_fd = None
                wait_socket(pathlib.Path(runtime) / 'wayland-test', weston)
                weston_log = (case_out / 'weston.log').read_text()
                renderer = re.findall(r'GL renderer: (.+)', weston_log)
                if not renderer or re.search(r'llvmpipe|softpipe|swrast|software', renderer[-1], re.I):
                    raise RuntimeError('Hardware GL renderer was not established')
                app_log = case_out / 'app.log'
                app_log.touch(mode=0o600)
                app_log.chmod(0o600)
                with app_log.open('w') as al:
                    app_proc = subprocess.Popen(['dbus-run-session', '--', app], env=env,
                                                stdout=al, stderr=al, start_new_session=True)
                (case_out / 'pids.json').write_text(json.dumps({'weston': weston.pid, 'app': app_proc.pid}))
                time.sleep(6)
                devices = gpu_devices(app_proc.pid, app)
                if app_proc.poll() is not None or not devices:
                    raise RuntimeError('App did not stay running with an open GPU render node')
                screen = Input(write_fd)
                w, h = c['width'], c['height']
                if w < 600:
                    field = (w // 2, 468 + (h - 915) // 2)
                    connect = (58, 667 + (h - 915) // 2)
                else:
                    field = (w // 2, 370 + (h - 720) // 2)
                    connect = (441 + (w - 1280) // 2, 568 + (h - 720) // 2)
                screen.click(*field)
                screen.type(match.group(0))
                screen.click(*connect)
                time.sleep(7)
                for step in c['app']:
                    if 'click' in step:
                        screen.click(*step['click'])
                        time.sleep(0.8)
                    elif 'wait' in step:
                        time.sleep(step['wait'] / 1000)
                    elif 'scroll' in step:
                        screen.scroll(*step['scroll'])
                        time.sleep(0.8)
                    elif 'capture' in step:
                        label = step['capture']
                        if not re.fullmatch(r'[a-z0-9_-]+', label):
                            raise ValueError('Capture labels must contain only a-z, 0-9, _ and -')
                        capture(env, case_out / 'capture', case_out / f'{label}.png')
                    else:
                        raise ValueError('Unknown app step')
                time.sleep(1.5)
                capture(env, case_out / 'capture', out / f'{c["id"]}.png')
                (case_out / 'environment.json').write_text(json.dumps({
                    'weston': version, 'renderer': renderer[-1], 'appRenderDevices': devices,
                    'glVersion': re.findall(r'\bGL version: (.+)', weston_log),
                    'appRenderer': re.findall(r'Using the Impeller rendering backend \(([^)]+)\)', app_log.read_text()),
                    'backend': 'native-wayland', 'kernel': os.uname().release,
                    'size': [w, h], 'theme': c['theme'], 'locale': c['locale'],
                }, indent=2) + '\n')
                print('gpu', c['id'], renderer[-1])
            finally:
                try:
                    stop(app_proc)
                finally:
                    try:
                        stop(weston)
                    finally:
                        os.close(write_fd)
                        if read_fd is not None:
                            os.close(read_fd)


if __name__ == '__main__':
    main()
