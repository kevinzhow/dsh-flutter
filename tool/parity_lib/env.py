"""Paths and toolchain discovery shared by tool/parity and tool/parity-ext/run.

Everything machine specific comes from environment variables with portable defaults:

  DSH_SRC                the pinned dsh checkout (default <repo>/.local/dsh-src); read-only
  PARITY_WEB_DEPS        directory that holds the React provider's node_modules
                         (default <repo>/.local/parity-web); created by `tool/parity setup`
  PARITY_NODE_BIN        directory with node + npm (Node >= 24); default: the first node on PATH
  PARITY_BROWSERS        PLAYWRIGHT_BROWSERS_PATH override (default: Playwright's own)
  FLUTTER_SDK            Flutter SDK directory (default: .fvmrc pin under ~/fvm or ~/flutter-sdks)
  PARITY_OUT             output directory (default <repo>/build/parity, build/parity-ext for the extension suite)
  PARITY_CACHE           React capture cache shared by all worktrees (default
                         <main checkout>/../dsh-flutter-wt/.parity-cache)
  PARITY_REPORTS_ROOT    publish target (no default); PARITY_BASE_URL: URL prefix of that root (optional)
"""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
TOOL = ROOT / 'tool'
WEB = TOOL / 'parity-web'
SHARED = TOOL / 'parity-shared'
EXT = TOOL / 'parity-ext'
FONTS = TOOL / 'parity-fonts'
FLUTTER_PKG = TOOL / 'parity_flutter'


def dsh_src():
    return pathlib.Path(os.environ.get('DSH_SRC', str(ROOT / '.local' / 'dsh-src')))


def web_deps():
    return pathlib.Path(os.environ.get('PARITY_WEB_DEPS', str(ROOT / '.local' / 'parity-web')))


def git(cwd, *args):
    r = subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ''


def dsh_commit():
    """Commit of the dsh checkout; falls back to the pin in docs/upstream-sync.json."""
    head = git(dsh_src(), 'rev-parse', 'HEAD')
    if head:
        return head
    pin = json.loads((ROOT / 'docs' / 'upstream-sync.json').read_text())
    return pin['dsh']['commit']


def default_cache():
    env = os.environ.get('PARITY_CACHE')
    if env:
        return pathlib.Path(env)
    common = git(ROOT, 'rev-parse', '--path-format=absolute', '--git-common-dir')
    main = pathlib.Path(common).parent if common else ROOT
    return main.parent / 'dsh-flutter-wt' / '.parity-cache'


def node_env():
    env = {k: v for k, v in os.environ.items() if not k.lower().startswith('npm_config_')}
    node_bin = os.environ.get('PARITY_NODE_BIN')
    if node_bin:
        env['PATH'] = node_bin + os.pathsep + env.get('PATH', '')
    if os.environ.get('PARITY_BROWSERS'):
        env['PLAYWRIGHT_BROWSERS_PATH'] = os.environ['PARITY_BROWSERS']
    return env


def flutter_env():
    env = dict(os.environ)
    pin = json.loads((ROOT / '.fvmrc').read_text())['flutter']
    candidates = [pathlib.Path(os.environ['FLUTTER_SDK'])] if os.environ.get('FLUTTER_SDK') else []
    home = pathlib.Path.home()
    candidates += [home / 'fvm' / 'versions' / pin, home / 'flutter-sdks' / 'versions' / pin]
    for c in candidates:
        if (c / 'bin' / 'flutter').exists():
            env['PATH'] = str(c / 'bin') + os.pathsep + env.get('PATH', '')
            return env
    if not shutil.which('flutter'):
        sys.exit('flutter %s not found: set FLUTTER_SDK' % pin)
    return env


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def tree_hash(*paths, suffixes=('.ts', '.tsx', '.mjs', '.css', '.json', '.html')):
    """Content hash of files (or every matching file under directories); order independent of the filesystem."""
    h = hashlib.sha256()
    files = []
    for p in map(pathlib.Path, paths):
        if p.is_dir():
            files += [f for f in p.rglob('*') if f.is_file() and f.suffix in suffixes and 'node_modules' not in f.parts]
        elif p.is_file():
            files.append(p)
    for f in sorted(files):
        h.update(str(f.relative_to(ROOT) if f.is_relative_to(ROOT) else f).encode())
        h.update(f.read_bytes())
    return h.hexdigest()
