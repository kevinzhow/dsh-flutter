"""React provider driver: toolchain setup, host build, content-addressed capture cache, capture.

The provider itself is tool/parity-web (Vite host + Playwright capture.mjs). This module only
installs its dependencies, builds the host, writes the run plan and manages the cache.

Cache (shared by every worktree, PARITY_CACHE): `<cache>/react/<key>.png|.metadata.json|.key.json` where
key = sha256 of everything that can change the pixels: the dsh commit, the case/variant JSON without
Flutter-only fields, the fixtures, the host sources and capture script, the pinned fonts, the
Chromium flags, the lockfile, the browser version and, for a density above 1, the reference mode. Editing a host file or case recaptures only
what it affects; Flutter edits never invalidate it; `--refresh-react` ignores and overwrites it.
"""
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys

from . import env

CHROMIUM_ARGS = ['--disable-lcd-text', '--font-render-hinting=none']
# How the page's device scale factor is produced: `native` launches Chromium with --force-device-scale-factor=<density>
# (Blink lays out, snaps and rounds in device pixels, as on a phone); `emulated` is Playwright's deviceScaleFactor
# emulation (layout in CSS pixels, scaled afterwards). Density 1 is the same pixels either way.
REFERENCE_MODES = ('native', 'emulated')
DEFAULT_REFERENCE = 'native'
FLUTTER_ONLY_CASE_KEYS = {'flutterCaseHint', 'tolerance', 'notes', 'regions', 'title', 'category', 'suite', 'surface'}


def run_node(cmd, cwd, log, extra_env=None):
    e = env.node_env()
    e.update(extra_env or {})
    print('+', ' '.join(map(str, cmd)), flush=True)
    with open(log, 'a') as sink:
        r = subprocess.run(['nice', '-n', '15', *map(str, cmd)], cwd=cwd, env=e, stdout=sink, stderr=subprocess.STDOUT)
    return r.returncode


def setup(log):
    """Install the provider's pinned dependencies under PARITY_WEB_DEPS (never globally)."""
    deps = env.web_deps()
    deps.mkdir(parents=True, exist_ok=True)
    wanted = env.sha256_file(env.WEB / 'package-lock.json')
    stamp = deps / '.lock-sha256'
    if not (deps / 'node_modules').is_dir() or not stamp.is_file() or stamp.read_text().strip() != wanted:
        for name in ('package.json', 'package-lock.json'):
            shutil.copy(env.WEB / name, deps / name)
        if run_node(['npm', 'ci', '--ignore-scripts', '--no-audit', '--no-fund'], deps, log) != 0:
            sys.exit('npm ci failed under %s; see %s' % (deps, log))
        stamp.write_text(wanted + '\n')
    link = env.WEB / 'node_modules'
    if link.is_symlink() and pathlib.Path(os.readlink(link)) != deps / 'node_modules':
        link.unlink()
    if not link.exists():
        link.symlink_to(deps / 'node_modules')
    return deps


def check_dsh_checkout():
    src = env.dsh_src()
    if not (src / 'packages' / 'client' / 'ui-primitives' / 'src').is_dir():
        sys.exit('dsh checkout not found at %s (set DSH_SRC or link .local/dsh-src)' % src)
    pin = json.loads((env.ROOT / 'docs' / 'upstream-sync.json').read_text())['dsh']['commit']
    head = env.git(src, 'rev-parse', 'HEAD')
    if head and head != pin:
        print('warning: dsh checkout is %s, pinned %s (docs/upstream-sync.json)' % (head[:9], pin[:9]), file=sys.stderr)


def build_host(out, log):
    dist = out / 'react-host'
    code = run_node(['node', env.WEB / 'build-host.mjs', '--dsh', env.dsh_src(), '--out', dist, '--deps', env.web_deps()],
                    env.WEB, log)
    if code != 0:
        sys.exit('building the React host failed; see %s' % log)
    return dist


def browser_version():
    r = subprocess.run(['node', '-e', "console.log(require('playwright-core/package.json').version)"],
                       cwd=env.WEB, env=env.node_env(), capture_output=True, text=True)
    return r.stdout.strip()


def entry_reference(entry, reference):
    """The mode an entry is really captured in: density 1 has no native/emulated difference."""
    return reference if entry['case']['viewport']['density'] != 1 else 'emulated'


def entry_key(entry, fixtures_hash, base, reference=DEFAULT_REFERENCE):
    case = {k: v for k, v in entry['case'].items() if k not in FLUTTER_ONLY_CASE_KEYS}
    case['capture'] = {k: v for k, v in case.get('capture', {}).items() if k != 'flutterKey'}
    key = {'case': case, 'variant': entry['variant'], 'fixtures': fixtures_hash, 'base': base}
    if entry_reference(entry, reference) == 'native':   # emulated keys stay what they were before the native mode
        key['reference'] = 'native'
    payload = json.dumps(key, sort_keys=True)
    return hashlib.sha256(payload.encode()).hexdigest()[:32]


def base_inputs(host_dirs):
    """Everything that is not per case."""
    return {
        'dsh': env.dsh_commit(),
        'host': env.tree_hash(env.WEB / 'host', env.WEB / 'index.html', env.WEB / 'build-host.mjs',
                              env.WEB / 'capture.mjs', env.WEB / 'pixel-crop.mjs', *host_dirs),
        'fonts': env.tree_hash(env.FONTS / 'manifest.json'),
        'chromium': CHROMIUM_ARGS,
        'lock': env.sha256_file(env.WEB / 'package-lock.json'),
        'playwright': browser_version(),
        'chromiumBuild': os.environ.get('PLAYWRIGHT_BROWSERS_PATH', ''),
    }


def capture(entries, out, results, host_dirs, fixtures_hash, refresh, cache_dir, reference=DEFAULT_REFERENCE):
    """Add only the published Toast dispatch; preserve prior provider paths."""
    from . import published_toasts
    selected = [e for e in entries if e['case']['kind'] == published_toasts.KIND]
    if not selected:
        return _capture_without_toasts(entries, out, results, host_dirs, fixtures_hash, refresh, cache_dir, reference)
    other = [e for e in entries if e['case']['kind'] != published_toasts.KIND]
    status = (_capture_without_toasts(other, out, results, host_dirs, fixtures_hash, refresh, cache_dir, reference)
              if other else {})
    status.update(published_toasts.capture(selected, out, results, reference))
    return {entry['key']: status[entry['key']] for entry in entries}


def _capture_without_toasts(entries, out, results, host_dirs, fixtures_hash, refresh, cache_dir, reference=DEFAULT_REFERENCE):
    """Route the published loaded-card kind; preserve all other provider inputs."""
    from . import published_plugin_cards
    published = [e for e in entries if e['case']['kind'] == published_plugin_cards.KIND]
    if not published:
        return _capture_generic(entries, out, results, host_dirs, fixtures_hash, refresh, cache_dir, reference)
    ordinary = [e for e in entries if e['case']['kind'] != published_plugin_cards.KIND]
    status = (_capture_generic(ordinary, out, results, host_dirs, fixtures_hash, refresh, cache_dir, reference)
              if ordinary else {})
    status.update(published_plugin_cards.capture(published, out, results, reference))
    return {entry['key']: status[entry['key']] for entry in entries}


def _capture_generic(entries, out, results, host_dirs, fixtures_hash, refresh, cache_dir, reference=DEFAULT_REFERENCE):
    """Make sure results/react/<key>.png exists for every entry; returns {key: 'cache'|'captured'|'failed'}."""
    react_dir = results / 'react'
    react_dir.mkdir(parents=True, exist_ok=True)
    cache = cache_dir / 'react'
    cache.mkdir(parents=True, exist_ok=True)
    base = base_inputs(host_dirs)
    log = out / 'react-capture.log'
    log.write_text('')
    status, misses, keys = {}, [], {}
    for e in entries:
        k = entry_key(e, fixtures_hash, base, reference)
        keys[e['key']] = k
        hit = cache / ('%s.png' % k)
        if not refresh and hit.is_file() and (cache / ('%s.metadata.json' % k)).is_file():
            shutil.copy(hit, react_dir / ('%s.png' % e['key']))
            shutil.copy(cache / ('%s.metadata.json' % k), react_dir / ('%s.metadata.json' % e['key']))
            status[e['key']] = 'cache'
        else:
            misses.append(e)
    if not misses:
        print('react: all %d captures from the cache (%s)' % (len(entries), cache))
        return status
    print('react: %d cached, capturing %d' % (len(entries) - len(misses), len(misses)))
    check_dsh_checkout()
    setup(log)
    dist = build_host(out, log)
    plan = {
        'hostDist': str(dist), 'resultsDir': str(results), 'fontsManifest': str(env.FONTS / 'manifest.json'),
        'chromiumArgs': CHROMIUM_ARGS, 'dshCommit': base['dsh'], 'reference': reference, 'entries': misses,
    }
    plan_path = out / 'react-plan.json'
    plan_path.write_text(json.dumps(plan, indent=1))
    (results / 'react-failures.json').unlink(missing_ok=True)
    code = run_node(['node', env.WEB / 'capture.mjs', '--plan', plan_path], env.WEB, log)
    failed = set()
    if (results / 'react-failures.json').is_file():
        failed = {f['key'] for f in json.loads((results / 'react-failures.json').read_text())}
    for e in misses:
        key = e['key']
        png = react_dir / ('%s.png' % key)
        if key in failed or not png.is_file():
            status[key] = 'failed'
            continue
        k = keys[key]
        shutil.copy(png, cache / ('%s.png' % k))
        shutil.copy(react_dir / ('%s.metadata.json' % key), cache / ('%s.metadata.json' % k))
        (cache / ('%s.key.json' % k)).write_text(json.dumps({'case': e['key'], 'base': base}, indent=1, sort_keys=True))
        status[key] = 'captured'
    if code != 0 and not failed:
        sys.exit('react capture failed (exit %d); see %s' % (code, log))
    return status
