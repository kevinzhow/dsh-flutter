"""Theme sampling for the extension suite.

The DEFAULT theme (`light`) runs every case. `dark` only re-skins it, so it keeps 1-2 representative
cases per surface (surface = first three id segments, `components.<area>.<surface>`):

  1. the FIRST case of the surface in builder order (the default variant);
  2. one DENSE case: the first case whose name (id without the surface prefix and the theme
     suffix) contains a density keyword, else the LAST case of the surface; skipped when it is
     the same case as (1).

The choice is deterministic: it depends only on builder order and ids. Switch:

  PARITY_EXT_ALL_THEMES=1   every case of every theme (no sampling)
"""
from __future__ import annotations

import os

from .manifest import surface_of

DEFAULT_THEME = 'light'
SAMPLED_THEMES = ('dark',)
DENSE_WORDS = ('long', 'many', 'dense', 'mixed', 'gallery', 'filled', 'full', 'rich', 'multi', 'batch', 'all')


def case_name(case):
    """Case id without the `components.<area>.<surface>.` prefix and the theme suffix."""
    parts = case['id'].split('.')
    if parts[-1] == case.get('theme'):
        parts = parts[:-1]
    return '.'.join(parts[3:])


def _is_dense(name):
    return any(w in set(name.replace('.', '-').split('-')) for w in DENSE_WORDS)


def representative_names(cases):
    """-> ordered [name, ...] (1-2) kept per surface, from one theme's cases of that surface."""
    names = [case_name(c) for c in cases]
    keep = [names[0]]
    dense = next((n for n in names[1:] if _is_dense(n)), None) or names[-1]
    if dense not in keep:
        keep.append(dense)
    return keep


def sample_themes(manifest, environ=None):
    environ = os.environ if environ is None else environ
    if environ.get('PARITY_EXT_ALL_THEMES') == '1':
        return manifest
    surfaces = {}
    for c in manifest['cases']:
        if c.get('theme') in SAMPLED_THEMES:
            surfaces.setdefault((c['theme'], surface_of(c['id'])), []).append(c)
    keep = set()
    for cases in surfaces.values():
        wanted = set(representative_names(cases))
        keep.update(c['id'] for c in cases if case_name(c) in wanted)
    return {**manifest, 'cases': [c for c in manifest['cases']
                                  if c.get('theme') not in SAMPLED_THEMES or c['id'] in keep]}


def sampled_themes_note(environ=None):
    environ = os.environ if environ is None else environ
    if environ.get('PARITY_EXT_ALL_THEMES') == '1':
        return 'all themes, every case (PARITY_EXT_ALL_THEMES=1)'
    return 'light complete; dark sampled to 1-2 cases per surface (PARITY_EXT_ALL_THEMES=1 for all)'
