#!/usr/bin/env python3
"""Captures the running Whalee desktop build (Linux, on a private Xvfb) in the states of cases.json.

    app_capture.py OUT CASES.json [case-id ...]

Environment: PARITY_DESKTOP_APP (the built bundle's executable), PARITY_DESKTOP_HOST_LOG (the host's log with its
launch link), PARITY_DESKTOP_HOME (an empty directory used as the app's HOME and settings root). The app is started with
WHALEE_WINDOW_SIZE (the case's size) and WHALEE_PIN_FONTS (tool/parity-fonts), once per case, and stopped by the PID this
script recorded. The display is created here too (its PID is recorded the same way) and stopped at the end. No process
outside the ones started here is touched.
"""
import json, os, pathlib, re, shutil, signal, subprocess, sys, time

from Xlib import X, XK, display
from Xlib.ext import xtest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FONTS = ROOT / 'tool' / 'parity-fonts' / 'manifest.json'


def need(key):
    value = os.environ.get(key)
    if not value:
        raise SystemExit('%s is not set' % key)
    return value


class Screen:
    def __init__(self, name):
        self.name = name
        self.d = display.Display(name)

    def sync(self):
        self.d.sync()

    def move(self, x, y):
        xtest.fake_input(self.d, X.MotionNotify, x=int(x), y=int(y)); self.sync()

    def button(self, b, down):
        xtest.fake_input(self.d, X.ButtonPress if down else X.ButtonRelease, b); self.sync()

    def click(self, x, y):
        self.move(x, y); time.sleep(0.1); self.button(1, True); time.sleep(0.05); self.button(1, False)

    def type(self, text):
        shift = self.d.keysym_to_keycode(XK.XK_Shift_L)
        names = {' ': 'space', ':': 'colon', '/': 'slash', '?': 'question', '=': 'equal', '.': 'period', '-': 'minus',
                 '_': 'underscore', '%': 'percent', '&': 'ampersand'}
        for ch in text:
            sym = XK.string_to_keysym(names.get(ch, ch)) if (ch in names or len(ch) > 1) else ord(ch)
            codes = list(self.d.keysym_to_keycodes(sym))
            if not codes:
                continue
            kc, idx = codes[0]
            if idx & 1:
                xtest.fake_input(self.d, X.KeyPress, shift)
            xtest.fake_input(self.d, X.KeyPress, kc); xtest.fake_input(self.d, X.KeyRelease, kc)
            if idx & 1:
                xtest.fake_input(self.d, X.KeyRelease, shift)
            self.sync(); time.sleep(0.01)


def window_geometry(display_name):
    for _ in range(40):
        out = subprocess.run(['xwininfo', '-display', display_name, '-name', 'Whalee'], capture_output=True, text=True).stdout
        m = {k: re.search(k + r':\s+(-?\d+)', out) for k in ('Absolute upper-left X', 'Absolute upper-left Y', 'Width', 'Height')}
        if all(m.values()):
            return [int(v.group(1)) for v in m.values()]
        time.sleep(0.5)
    raise SystemExit('no Whalee window on %s' % display_name)


def main():
    out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
    cases = json.loads(pathlib.Path(sys.argv[2]).read_text())['cases']
    only = sys.argv[3:]
    app, log, home = need('PARITY_DESKTOP_APP'), need('PARITY_DESKTOP_HOST_LOG'), need('PARITY_DESKTOP_HOME')
    link = re.search(r'http://127\.0\.0\.1:\d+/\?token=\S+', pathlib.Path(log).read_text()).group(0)
    name = ':%d' % int(os.environ.get('PARITY_DESKTOP_DISPLAY', '91'))
    pids = out / 'pids.txt'
    xvfb = subprocess.Popen(['Xvfb', name, '-screen', '0', '2400x1500x24', '-nolisten', 'tcp'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    pids.write_text('xvfb %d\n' % xvfb.pid)
    time.sleep(2)
    screen = Screen(name)
    try:
        for c in cases:
            if only and c['id'] not in only:
                continue
            # A fresh settings root per case: the sidebar remembers which groups are open.
            case_home = pathlib.Path(home) / c['id']
            shutil.rmtree(case_home, ignore_errors=True)
            case_home.mkdir(parents=True)
            env = dict(os.environ, DISPLAY=name, LIBGL_ALWAYS_SOFTWARE='1', GDK_BACKEND='x11', HOME=str(case_home),
                       XDG_CONFIG_HOME=str(case_home / '.config'), XDG_DATA_HOME=str(case_home / '.local/share'),
                       WHALEE_WINDOW_SIZE='%dx%d' % (c['width'], c['height']), WHALEE_PIN_FONTS=str(FONTS))
            if c['theme'] == 'dark':
                env['WHALEE_PLATFORM_BRIGHTNESS'] = 'dark'
            if c['locale'] == 'zh':
                env['LC_ALL'] = 'zh_CN.UTF-8'; env['LANGUAGE'] = 'zh_CN'
            proc = subprocess.Popen([app], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            with pids.open('a') as f:
                f.write('app %d\n' % proc.pid)
            try:
                time.sleep(6)
                x, y, w, h = window_geometry(name)
                if os.environ.get('PARITY_DESKTOP_DEBUG'):
                    subprocess.run(['import', '-display', name, '-window', 'root', '-crop', '%dx%d+%d+%d' % (w, h, x, y), '+repage',
                                    str(out / ('%s.pairing.png' % c['id']))], check=True)
                # Pairing: the link goes into the focused field, Connect sits below the form.
                if w < 600:
                    # The phone pairing page: the link field, then Connect below the plain-http notice.
                    screen.click(x + w // 2, y + 468 + (h - 915) // 2); time.sleep(0.3)
                    screen.type(link); time.sleep(0.5)
                    screen.click(x + 58, y + 667 + (h - 915) // 2); time.sleep(7)
                else:
                    screen.click(x + w // 2, y + 370 + (h - 720) // 2); time.sleep(0.3)
                    screen.type(link); time.sleep(0.5)
                    screen.click(x + 441 + (w - 1280) // 2, y + 568 + (h - 720) // 2); time.sleep(7)
                for i, step in enumerate(c['app']):
                    if 'click' in step:
                        screen.click(x + step['click'][0], y + step['click'][1])
                        time.sleep(0.8)
                    elif 'wait' in step:
                        time.sleep(step['wait'] / 1000)
                    if os.environ.get('PARITY_DESKTOP_DEBUG'):
                        subprocess.run(['import', '-display', name, '-window', 'root', '-crop', '%dx%d+%d+%d' % (w, h, x, y), '+repage',
                                        str(out / ('%s.step%d.png' % (c['id'], i)))], check=True)
                time.sleep(1.5)
                shot = out / ('%s.png' % c['id'])
                subprocess.run(['import', '-display', name, '-window', 'root', '-crop', '%dx%d+%d+%d' % (w, h, x, y), '+repage', str(shot)], check=True)
                print('app', c['id'])
            finally:
                proc.send_signal(signal.SIGTERM)
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()
    finally:
        xvfb.send_signal(signal.SIGTERM)
        xvfb.wait(timeout=10)


if __name__ == '__main__':
    main()
