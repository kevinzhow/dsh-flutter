"""Case manifest for the dsh-flutter visual parity tool: schema, loading, validation.

A manifest is one JSON object:

    {"schema": "dsh-parity-cases/1", "name": "<suite>", "cases": [<case>, ...]}

A case names one rendered component fixture (or, later, one real screen) and every
state variant of it. Both providers (React in Chromium, Flutter in flutter_test) read the
same case and must render the same thing:

    id          components.<area>.<surface>.<name>.<theme>   (or screens.<...>.<theme>)
                lower-case segments joined by dots; the LAST segment is the theme (`light`/`dark`)
    title       human readable
    kind        renderer key. The React host registry and the Flutter case map are both keyed by
                `kind` (an exact case id in the Flutter map wins over the kind), so one renderer
                serves a whole generated family of cases.
    viewport    {width, height, density}: CSS px page size and device pixel ratio
    theme       light | dark       (dsh's own `body[data-ds-dark-theme]` switch)
    locale      en | zh-CN
    variants    [{id, name, props, interactions?}, ...]; the first variant must be `default`.
                `props` is the renderer's input and is identical for both providers;
                `interactions` are the state steps applied before the capture (see INTERACTIONS)
    capture     {selector?, flutterKey?, crop?}: the element to crop. Both default to the
                parity frame (`[data-parity-target]` / ValueKey('parity-target')).
    fixture     optional name of a JSON file in the suite's fixtures/ directory
    regions     optional named rectangles {name, x, y, width, height} (CSS px, relative to the crop)
                that the diff scores separately
    tolerance   optional {pixelRatio, layoutPx}: informative only; the verdict is in diff.py
    skip        optional true | {reason} : the case is listed but never captured
    notes       free text

Capture keys (file stems of the provider output): `<id>` for the default variant and
`<id>~<variantId>` for the others.

Provider output contract (what any provider writes, what diff/report read):

    <results>/<provider>/<captureKey>.png
    <results>/<provider>/<captureKey>.metadata.json   {provider, source, caseId, variantId, theme,
                                                       locale, viewport, image, crop, fonts, ...}

This module is self-contained and has no third-party dependency.
"""
from __future__ import annotations

import fnmatch
import json
import pathlib
import re

SCHEMA = 'dsh-parity-cases/1'
THEMES = ('light', 'dark')
LOCALES = ('en', 'zh-CN')
CAPTURE_TYPES = ('component-fixture', 'real-screen')
PROVIDERS = ('react', 'flutter')
DEFAULT_VARIANT = 'default'

SEGMENT = r'[a-z0-9]+(?:-[a-z0-9]+)*'
ID_RE = re.compile(r'^(components|screens)(?:\.%s){3,}$' % SEGMENT)
VARIANT_ID_RE = re.compile(r'^%s$' % SEGMENT)
KIND_RE = re.compile(r'^[a-z0-9]+(?:[.-][a-z0-9]+)*$')

# Interaction steps shared by both providers. `target` is the `parity-id` of an element the
# renderer marked (`data-parity-id` on the web, ValueKey on Flutter).
INTERACTIONS = {
    'hover': {'target'},        # move the mouse pointer onto the target
    'press': {'target'},        # mouse down on the target and hold
    'click': {'target'},        # mouse down + up
    'tab': set(),               # real Tab key; optional `count` (default 1): keyboard focus-visible
    'type': {'target', 'text'}, # type into the field under the target
    'wait': {'ms'},             # advance time
}
INTERACTION_OPTIONAL = {'tab': {'count'}}

CASE_KEYS = {
    'id', 'title', 'kind', 'viewport', 'theme', 'locale', 'variants', 'capture', 'fixture', 'regions',
    'tolerance', 'skip', 'notes', 'captureType', 'surface', 'category', 'suite', 'reactPathHint',
    'flutterCaseHint',
}


class ManifestError(ValueError):
    """Raised by load_manifest for unreadable or invalid manifests."""

    def __init__(self, errors):
        self.errors = list(errors)
        super().__init__('\n'.join(self.errors))


def capture_type(case):
    return case.get('captureType') or ('real-screen' if case['id'].startswith('screens.') else 'component-fixture')


def surface_of(case_id):
    """`components.<area>.<surface>` (first three id segments)."""
    return '.'.join(case_id.split('.')[:3])


def capture_key(case_id, variant_id):
    return case_id if variant_id == DEFAULT_VARIANT else '%s~%s' % (case_id, variant_id)


def is_skipped(case):
    skip = case.get('skip')
    return skip is True or (isinstance(skip, dict) and skip.get('enabled', True) is not False)


def _num(value, *, positive=True):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and (value > 0 if positive else True)


def _validate_interaction(step, where, errors):
    if not isinstance(step, dict):
        errors.append('%s: interaction must be an object' % where)
        return
    kind = step.get('type')
    if kind not in INTERACTIONS:
        errors.append('%s: unknown interaction type %r (known: %s)' % (where, kind, ', '.join(sorted(INTERACTIONS))))
        return
    required = INTERACTIONS[kind]
    allowed = required | INTERACTION_OPTIONAL.get(kind, set()) | {'type'}
    for key in required:
        if key not in step:
            errors.append('%s: %s interaction needs %r' % (where, kind, key))
    for key in step:
        if key not in allowed:
            errors.append('%s: %s interaction has unknown key %r' % (where, kind, key))
    if kind == 'wait' and 'ms' in step and not _num(step['ms'], positive=False):
        errors.append('%s: wait.ms must be a number' % where)
    if kind == 'tab' and 'count' in step and not (isinstance(step['count'], int) and step['count'] > 0):
        errors.append('%s: tab.count must be a positive integer' % where)


def validate_case(case, where='case'):
    """-> list of error strings (empty = valid)."""
    errors = []
    if not isinstance(case, dict):
        return ['%s: must be an object' % where]
    cid = case.get('id')
    where = '%s %s' % (where, cid) if isinstance(cid, str) else where
    unknown = set(case) - CASE_KEYS
    if unknown:
        errors.append('%s: unknown key(s) %s' % (where, ', '.join(sorted(unknown))))
    if not isinstance(cid, str) or not ID_RE.match(cid):
        errors.append('%s: id must look like components.<area>.<surface>.<name>.<theme> '
                      '(lower-case segments, at least 3 after the prefix)' % where)
    theme = case.get('theme')
    if theme not in THEMES:
        errors.append('%s: theme must be one of %s' % (where, ', '.join(THEMES)))
    elif isinstance(cid, str) and cid.split('.')[-1] != theme:
        errors.append('%s: the last id segment must be the theme (%s)' % (where, theme))
    if not isinstance(case.get('title'), str) or not case['title'].strip():
        errors.append('%s: title is required' % where)
    kind = case.get('kind')
    if not isinstance(kind, str) or not KIND_RE.match(kind):
        errors.append('%s: kind is required (lower-case, dots/dashes)' % where)
    if case.get('locale') not in LOCALES:
        errors.append('%s: locale must be one of %s' % (where, ', '.join(LOCALES)))
    if 'captureType' in case:
        if case['captureType'] not in CAPTURE_TYPES:
            errors.append('%s: captureType must be one of %s' % (where, ', '.join(CAPTURE_TYPES)))
        elif isinstance(cid, str) and case['captureType'] != ('real-screen' if cid.startswith('screens.') else 'component-fixture'):
            errors.append('%s: captureType %s does not match the id prefix' % (where, case['captureType']))
    vp = case.get('viewport')
    if not isinstance(vp, dict) or set(vp) != {'width', 'height', 'density'} or not all(_num(v) for v in vp.values()):
        errors.append('%s: viewport must be {width, height, density}, all positive numbers' % where)
    variants = case.get('variants')
    if not isinstance(variants, list) or not variants:
        errors.append('%s: variants must be a non-empty list' % where)
    else:
        seen = set()
        for i, v in enumerate(variants):
            vw = '%s variants[%d]' % (where, i)
            if not isinstance(v, dict):
                errors.append('%s: must be an object' % vw)
                continue
            vid = v.get('id')
            if not isinstance(vid, str) or not VARIANT_ID_RE.match(vid):
                errors.append('%s: id must be a lower-case slug' % vw)
            elif vid in seen:
                errors.append('%s: duplicate variant id %s' % (vw, vid))
            else:
                seen.add(vid)
            if i == 0 and vid != DEFAULT_VARIANT:
                errors.append('%s: the first variant must have id "default"' % vw)
            if not isinstance(v.get('name'), str):
                errors.append('%s: name is required' % vw)
            if not isinstance(v.get('props', {}), dict):
                errors.append('%s: props must be an object' % vw)
            steps = v.get('interactions', [])
            if not isinstance(steps, list):
                errors.append('%s: interactions must be a list' % vw)
            else:
                for j, step in enumerate(steps):
                    _validate_interaction(step, '%s interactions[%d]' % (vw, j), errors)
            for key in set(v) - {'id', 'name', 'props', 'interactions'}:
                errors.append('%s: unknown key %r' % (vw, key))
    capture = case.get('capture', {})
    if not isinstance(capture, dict) or set(capture) - {'selector', 'flutterKey', 'crop'}:
        errors.append('%s: capture may only contain selector, flutterKey, crop' % where)
    elif capture.get('crop', 'element') not in ('element', 'viewport'):
        errors.append('%s: capture.crop must be element or viewport' % where)
    regions = case.get('regions', [])
    if not isinstance(regions, list):
        errors.append('%s: regions must be a list' % where)
    else:
        names = set()
        for i, r in enumerate(regions):
            ok = (isinstance(r, dict) and set(r) == {'name', 'x', 'y', 'width', 'height'}
                  and isinstance(r['name'], str) and _num(r['width']) and _num(r['height'])
                  and _num(r['x'], positive=False) and _num(r['y'], positive=False))
            if not ok:
                errors.append('%s regions[%d]: must be {name, x, y, width, height}' % (where, i))
            elif r['name'] in names:
                errors.append('%s regions[%d]: duplicate region name %s' % (where, i, r['name']))
            else:
                names.add(r['name'])
    if 'fixture' in case and not (isinstance(case['fixture'], str) and re.match(r'^[A-Za-z0-9_.-]+\.json$', case['fixture'])):
        errors.append('%s: fixture must be a file name ending in .json (no directories)' % where)
    return errors


def validate_manifest(manifest):
    """-> list of error strings (empty = valid)."""
    if not isinstance(manifest, dict):
        return ['manifest must be a JSON object']
    errors = []
    if manifest.get('schema') != SCHEMA:
        errors.append('schema must be %r' % SCHEMA)
    if not isinstance(manifest.get('name'), str):
        errors.append('name is required')
    cases = manifest.get('cases')
    if not isinstance(cases, list):
        return errors + ['cases must be a list']
    seen = {}
    for i, case in enumerate(cases):
        errors += validate_case(case, 'cases[%d]' % i)
        cid = case.get('id') if isinstance(case, dict) else None
        if isinstance(cid, str):
            if cid in seen:
                errors.append('duplicate case id %s (cases[%d] and cases[%d])' % (cid, seen[cid], i))
            seen[cid] = i
    return errors


def load_manifest(path):
    """Read + validate; raises ManifestError listing every problem."""
    path = pathlib.Path(path)
    try:
        manifest = json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        raise ManifestError(['%s: %s' % (path, exc)])
    errors = validate_manifest(manifest)
    if errors:
        raise ManifestError(['%s: %s' % (path, e) for e in errors])
    return manifest


def entries(manifest):
    """Every capturable (case, variant) pair as dicts {key, case, variant}; skipped cases omitted."""
    out = []
    for case in manifest['cases']:
        if is_skipped(case):
            continue
        for variant in case['variants']:
            out.append({'key': capture_key(case['id'], variant['id']), 'case': case, 'variant': variant})
    return out


def split_patterns(text):
    return [p.strip() for p in (text or '').split(',') if p.strip()]


def matches(key, patterns):
    """Glob match (`*` crosses dots) of a capture key or case id against comma-list patterns."""
    return not patterns or any(fnmatch.fnmatchcase(key, p) or fnmatch.fnmatchcase(key.split('~')[0], p)
                               for p in patterns)


def select(manifest_entries, patterns):
    pats = split_patterns(patterns) if isinstance(patterns, str) else list(patterns or [])
    return [e for e in manifest_entries if matches(e['key'], pats)]
