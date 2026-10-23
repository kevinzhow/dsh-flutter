"""Glue to the vendored raft visual-testing CLI (tool/vendor/raft-visual-testing, FSL-1.1-ALv2, unchanged).

The CLI owns manifest validation, the raw diff metrics, the side-by-side compositor and the HTML report. dsh-flutter
plugs in as the provider side, the same way raft-flutter plugs Flutter into raft's official CLI:

  results (the provider output contract)   <out>/visual-testing-results/<provider>/<id>.png + <id>.metadata.json
  providers                                react (dsh web, tool/parity-web), flutter (tool/parity_flutter)
  pair                                     react__flutter  (baseline = react)
  manifest                                 the CLI reads one case per (id), so every capture key of a dsh case
                                           (`<id>` or `<id>~<variant>`) becomes one CLI case (cli_cases())

Nothing in this module changes the vendored files; the CLI runs with its own working directory <out> through the
environment variables it documents (SLOCK_VISUAL_REPO_ROOT, SLOCK_REACT_REPO_DIR). Its runtime dependency (sharp) is
installed by `tool/parity setup` under PARITY_VT_DEPS with `corepack pnpm` and exposed to the CLI as
tool/vendor/node_modules (a git-ignored symlink next to the package, never inside it).
"""
from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import sys

from . import env, manifest as mf

BASELINE, CURRENT = 'react', 'flutter'
PAIR = '%s__%s' % (BASELINE, CURRENT)
CLI = env.VENDOR / 'src' / 'cli.mjs'
DEFAULT_TOLERANCE = {'pixelRatio': 0.02, 'layoutDp': 1, 'ignoreAntialiasing': True}
DEFAULT_SELECTOR = '[data-parity-target]'


class CliError(RuntimeError):
    pass


def pnpm_command():
    """`corepack pnpm` when corepack is on the (Node) PATH, else a plain `pnpm`."""
    path = env.node_env().get('PATH', '')
    if shutil.which('corepack', path=path):
        return ['corepack', 'pnpm']
    return ['pnpm']


def setup(log):
    """Install the CLI's pinned dependency under PARITY_VT_DEPS (never globally) and link it next to the package."""
    deps = env.vt_deps()
    deps.mkdir(parents=True, exist_ok=True)
    wanted = env.sha256_file(env.VT_GLUE / 'pnpm-lock.yaml')
    stamp = deps / '.lock-sha256'
    if not (deps / 'node_modules' / 'sharp').is_dir() or not stamp.is_file() or stamp.read_text().strip() != wanted:
        for name in ('package.json', 'pnpm-lock.yaml'):
            shutil.copy(env.VT_GLUE / name, deps / name)
        e = env.node_env()
        e.setdefault('COREPACK_ENABLE_DOWNLOAD_PROMPT', '0')
        cmd = ['nice', '-n', '15', *pnpm_command(), 'install', '--frozen-lockfile']
        print('+', ' '.join(cmd), flush=True)
        with open(log, 'a') as sink:
            code = subprocess.run(cmd, cwd=deps, env=e, stdout=sink, stderr=subprocess.STDOUT).returncode
        if code != 0:
            sys.exit('pnpm install failed under %s; see %s' % (deps, log))
        stamp.write_text(wanted + '\n')
    link = env.VENDOR.parent / 'node_modules'
    target = deps / 'node_modules'
    if link.is_symlink() and pathlib.Path(os.readlink(link)) != target:
        link.unlink()
    if not link.exists():
        link.symlink_to(target)
    return deps


def ready():
    """True when node and the CLI's dependency can be found (used to skip, not fail, offline self-checks)."""
    path = env.node_env().get('PATH', '')
    return bool(shutil.which('node', path=path)) and (env.VENDOR.parent / 'node_modules' / 'sharp').exists()


def cli_cases(entries):
    """One CLI case per capture key (the CLI diffs `<provider>/<case id>.png`), in the CLI's own manifest schema."""
    cases = []
    for e in entries:
        case, variant = e['case'], e['variant']
        capture = case.get('capture', {})
        area = case['id'].split('.')[1]
        out = {
            'id': e['key'],
            'title': case['title'] if variant['id'] == mf.DEFAULT_VARIANT else '%s: %s' % (case['title'], variant['name']),
            'surface': case.get('surface') or area,
            'category': case.get('category') or area,
            'captureType': mf.capture_type(case),
            'fixture': case.get('fixture') or '%s.json' % case['id'],
            'viewport': case['viewport'],
            'theme': case['theme'],
            'locale': case['locale'],
            'tolerance': {**DEFAULT_TOLERANCE, **case.get('tolerance', {})},
            'capture': {'selector': capture.get('selector', DEFAULT_SELECTOR), 'crop': capture.get('crop', 'element')},
            'variants': [{'id': variant['id'], 'name': variant['name'], 'props': variant.get('props', {}),
                          'interactions': variant.get('interactions', [])}],
            'dshCaseId': case['id'],
        }
        if case.get('notes'):
            out['note'] = case['notes']
        cases.append(out)
    return cases


def write_manifest(entries, path):
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({'name': 'dsh-flutter', 'cases': cli_cases(entries)}, indent=1) + '\n')
    return path


def run_cli(args, out, log=None):
    """Run `slock-visual <args>` with <out> as its repository root. Returns captured text when `log` is None."""
    if not CLI.is_file():
        raise CliError('vendored CLI not found: %s' % CLI)
    e = env.node_env()
    e['SLOCK_VISUAL_REPO_ROOT'] = str(out)
    src = env.dsh_src()
    if src.is_dir():
        e['SLOCK_REACT_REPO_DIR'] = str(src)
    cmd = ['nice', '-n', '15', 'node', str(CLI), *args]
    pathlib.Path(out).mkdir(parents=True, exist_ok=True)
    if log:
        print('+', ' '.join(map(str, cmd)), flush=True)
        with open(log, 'a') as sink:
            r = subprocess.run(cmd, cwd=out, env=e, stdout=sink, stderr=subprocess.STDOUT)
        text = ''
    else:
        r = subprocess.run(cmd, cwd=out, env=e, capture_output=True, text=True)
        text = (r.stdout or '') + (r.stderr or '')
    if r.returncode != 0:
        raise CliError('slock-visual %s failed (exit %d)%s' % (args[0], r.returncode, '; see %s' % log if log else ':\n' + text))
    return text


def validate(entries, out, log=None):
    """The CLI's own manifest validation over the (flattened) manifest of `entries`."""
    path = write_manifest(entries, pathlib.Path(out) / 'cli-cases.json')
    return run_cli(['validate', '--manifest', str(path)], out, log)


def diff(entries, out, log=None):
    """Official diff of react vs flutter for `entries`; returns {case key: result row of the CLI}."""
    out = pathlib.Path(out)
    path = write_manifest(entries, out / 'cli-cases.json')
    shutil.rmtree(out / 'visual-testing-results' / 'diff', ignore_errors=True)
    run_cli(['diff', '--pairs', PAIR, '--manifest', str(path), '--skip-analysis'], out, log)
    data = json.loads((out / 'visual-testing-results' / 'diff' / ('%s.json' % PAIR)).read_text())
    return {row['id']: row for row in data['results']}


def site(entries, out, site_dir, run_id, subject, log=None):
    """Official HTML report (home + per-pair detail page) of the diff written by diff()."""
    out = pathlib.Path(out)
    path = write_manifest(entries, out / 'cli-cases.json')
    shutil.rmtree(site_dir, ignore_errors=True)
    run_cli(['site', '--pairs', PAIR, '--manifest', str(path), '--skip-analysis', '--site-dir', str(site_dir),
             '--run-id', run_id, '--commit-subject', subject], out, log)
    return pathlib.Path(site_dir)
