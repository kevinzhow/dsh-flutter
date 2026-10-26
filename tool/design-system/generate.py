#!/usr/bin/env python3
"""Generate canonical button/tab recipes from pinned, published DSH CSS.

All CSS rules, including conditional states, are retained in the JSON audit.
Unknown syntax fails; --check also verifies the reference consumer's dependency
and source package version, not only the checkout commit label.
"""
from pathlib import Path
import argparse, hashlib, json, os, re, subprocess, sys
ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
OUT = ROOT / 'packages/dsh_ui/lib/src/dsh_recipes.g.dart'
AUDIT = HERE / 'recipes.generated.json'


def css_rules(text, context=()):
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    rules = []
    while text.strip():
        start = text.find('{')
        if start < 0:
            raise ValueError('CSS trailing syntax is not a rule')
        selector = ', '.join(part.strip() for part in text[:start].strip().split(','))
        depth, end = 1, start + 1
        while end < len(text) and depth:
            depth += (text[end] == '{') - (text[end] == '}')
            end += 1
        if depth:
            raise ValueError('unclosed CSS rule')
        body, text = text[start + 1:end - 1], text[end:]
        if selector.startswith('@'):
            if not selector.startswith('@media '):
                raise ValueError('unsupported CSS condition: ' + selector)
            rules.extend(css_rules(body, (*context, selector)))
            continue
        if not selector or '{' in body or '}' in body:
            raise ValueError('unsupported nested CSS: ' + selector)
        declarations = {}
        for declaration in body.split(';'):
            if not declaration.strip():
                continue
            if ':' not in declaration:
                raise ValueError('invalid CSS declaration')
            key, value = map(str.strip, declaration.split(':', 1))
            if key in declarations:
                raise ValueError('duplicate declaration: ' + key)
            declarations[key] = value
        rules.append({'selector': selector, 'conditions': list(context), 'declarations': declarations})
    return rules


def value(rules, selector, prop):
    found = [r['declarations'][prop] for r in rules if not r['conditions'] and r['selector'] == selector and prop in r['declarations']]
    if len(found) != 1:
        raise ValueError('ambiguous/missing CSS recipe input: ' + selector + '/' + prop)
    return found[0]


def number(raw, unit='px'):
    match = re.fullmatch(r'(-?\d+(?:\.\d+)?)' + unit, raw)
    if not match:
        raise ValueError('unsupported CSS number: ' + raw)
    return float(match[1])


def token(raw):
    match = re.fullmatch(r'var\((--[\w-]+)\)', raw)
    if not match:
        raise ValueError('unsupported token expression: ' + raw)
    return match[1]


def collect(source=None):
    lock = json.loads((HERE / 'sources.lock.json').read_text())
    package = lock['packages'][0]
    folder = HERE / 'upstream/ui-primitives'
    for name, sha in package['files'].items():
        if hashlib.sha256((folder / name).read_bytes()).hexdigest() != sha:
            raise ValueError('published snapshot hash mismatch: ' + name)
    manifest = json.loads((folder / 'package.json').read_text())
    if (manifest['name'], manifest['version']) != (package['name'], package['version']):
        raise ValueError('published package identity mismatch')
    if source is not None:
        current = json.loads((source / package['sourcePackage']).read_text())
        consumer = json.loads((source / package['referenceConsumer']).read_text())
        if current['version'] != package['version']:
            raise ValueError('reference dependency version drift: regenerate from its published package')
        if consumer[package['dependencyField']].get(package['name']) != package['dependencySpecifier']:
            raise ValueError('reference dependency specifier drift: update the package lock')
        for name in package['files']:
            if name.endswith('.css'):
                original = source / Path(package['sourcePackage']).parent / 'src' / name
                if original.read_bytes() != (folder / name).read_bytes():
                    raise ValueError('reference CSS differs from pinned published package: ' + name)
    rules = {name: css_rules((folder / name).read_text()) for name in package['files'] if name.endswith('.css')}
    return lock, rules


# The renderer currently understands these two families. A new state/property
# must be deliberately translated before regenerating, even if its CSS parses.
SUPPORTED = {
    'Button.module.css': {
        '.button': 'box-sizing display align-items justify-content gap border border-radius cursor font-size line-height color background padding',
        '.button:disabled': 'cursor opacity', '.md': 'height',
        '.sm': 'height font-size line-height padding border-radius',
        '.primary': 'background color', '.primary:hover:not(:disabled)': 'background',
        '.ghost:hover:not(:disabled)': 'background', '.ghost:active:not(:disabled)': 'background',
        '.outline': 'border background', '.outline:hover:not(:disabled)': 'background',
        '.toolbar': 'background', '.toolbar:hover:not(:disabled)': 'background',
        '.icon': 'display width height align-items justify-content',
    },
    'SegmentedTabs.module.css': {
        '.tabs': 'position display padding border-radius background',
        '.indicator': 'position inset box-sizing border border-radius background transition pointer-events',
        '.tab': 'position justify-content height padding border-radius font-size line-height background color transition',
        ".tab:hover, .tab[aria-selected='true']": 'background color',
        ".tab[aria-selected='true']": 'font-weight',
        '.tab:focus-visible': 'outline text-decoration text-decoration-thickness text-underline-offset',
    },
}


def validate_supported(sheets):
    for name, schema in SUPPORTED.items():
        seen = set()
        for rule in sheets[name]:
            selector, props = rule['selector'], rule['declarations']
            if rule['conditions']:
                if (rule['conditions'] != ['@media (prefers-reduced-motion: reduce)']
                        or selector != '.indicator, .tab' or props != {'transition': 'none'}):
                    raise ValueError('untranslated conditional recipe: ' + name + ' ' + selector)
            else:
                if selector not in schema or set(props) != set(schema[selector].split()):
                    raise ValueError('untranslated recipe state/property: ' + name + ' ' + selector)
                seen.add(selector)
        if seen != set(schema):
            raise ValueError('missing recipe state: ' + name)


def ladder_token(size, line):
    pack = json.loads((ROOT / 'packages/dsh_theme/assets/themes/official.theme.json').read_text())
    candidates = [name for name, style in pack['common']['typography'].items() if style['size'] == size and style['line'] == line and style['weight'] == 400 and style['style'] == 'normal' and style['family'] == 'text']
    if len(candidates) != 1:
        raise ValueError('ambiguous typography rung for source recipe size: ' + str(size))
    return candidates[0]


def render(lock, sheets):
    validate_supported(sheets)
    b, t = sheets['Button.module.css'], sheets['SegmentedTabs.module.css']
    get = lambda rules, selector, prop: value(rules, selector, prop)
    px = lambda rules, selector, prop: number(get(rules, selector, prop))
    tok = lambda rules, selector, prop: token(get(rules, selector, prop))
    padding = get(b, '.button', 'padding').split()
    small_padding = get(b, '.sm', 'padding').split()
    if padding[0] != '0' or small_padding[0] != '0' or len(padding) != 2 or len(small_padding) != 2:
        raise ValueError('unsupported button padding')
    outline = get(b, '.outline', 'border').split()
    if len(outline) != 3 or outline[1] != 'solid':
        raise ValueError('unsupported button outline')
    transition = get(t, '.indicator', 'transition').split()
    if len(transition) != 3 or transition[0] != 'transform':
        raise ValueError('unsupported tab transition')
    tab_border = get(t, '.indicator', 'border').split()
    if len(tab_border) != 3 or tab_border[1] != 'solid':
        raise ValueError('unsupported tab border')
    weight_selector = '.tab[aria-selected=\'true\']'
    metrics = {
        'DshButtonRecipe': {
            'height': px(b, '.md', 'height'), 'smallHeight': px(b, '.sm', 'height'),
            'padding': number(padding[1]), 'smallPadding': number(small_padding[1]),
            'fontSize': px(b, '.button', 'font-size'), 'lineHeight': px(b, '.button', 'line-height'),
            'fontToken': ladder_token(px(b, '.button', 'font-size'), px(b, '.button', 'line-height')),
            'smallFontToken': ladder_token(px(b, '.sm', 'font-size'), px(b, '.sm', 'line-height')),
            'smallFontSize': px(b, '.sm', 'font-size'), 'smallLineHeight': px(b, '.sm', 'line-height'),
            'gap': px(b, '.button', 'gap'), 'iconSize': px(b, '.icon', 'width'),
            'disabledOpacity': number(get(b, '.button:disabled', 'opacity'), ''),
            'outlineWidth': number(outline[0]), 'outlineToken': token(outline[2]),
            'labelToken': tok(b, '.button', 'color'),
            'primaryLabelToken': tok(b, '.primary', 'color'),
            'primaryToken': tok(b, '.primary', 'background'),
            'primaryHoverToken': tok(b, '.primary:hover:not(:disabled)', 'background'),
            'hoverToken': tok(b, '.ghost:hover:not(:disabled)', 'background'),
            'outlineHoverToken': tok(b, '.outline:hover:not(:disabled)', 'background'),
            'activeToken': tok(b, '.ghost:active:not(:disabled)', 'background'),
            'toolbarToken': tok(b, '.toolbar', 'background'),
            'toolbarHoverToken': tok(b, '.toolbar:hover:not(:disabled)', 'background'),
            'radiusToken': tok(b, '.button', 'border-radius'), 'smallRadiusToken': tok(b, '.sm', 'border-radius'),
        },
        'DshSegmentedTabRecipe': {
            'padding': px(t, '.tabs', 'padding'), 'height': px(t, '.tab', 'height'),
            'fontSize': px(t, '.tab', 'font-size'), 'lineHeight': px(t, '.tab', 'line-height'),
            'selectedWeight': number(get(t, weight_selector, 'font-weight'), ''),
            'transitionMs': number(transition[1], 'ms'),
            'focusLineWidth': px(t, '.tab:focus-visible', 'text-decoration-thickness'),
            'backgroundToken': tok(t, '.tabs', 'background'), 'radiusToken': tok(t, '.tabs', 'border-radius'),
            'indicatorBackgroundToken': tok(t, '.indicator', 'background'),
            'indicatorRadiusToken': tok(t, '.indicator', 'border-radius'),
            'labelToken': tok(t, '.tab', 'color'),
            'outlineToken': token(tab_border[2]), 'outlineWidth': number(tab_border[0]),
            'activeLabelToken': tok(t, ".tab:hover, .tab[aria-selected='true']", 'color'),
        },
    }
    package = lock['packages'][0]
    lines = ['// Generated by tool/design-system/generate.py; do not edit.', '// From ' + package['name'] + ' ' + package['version'] + '.', '']
    for name, fields in metrics.items():
        lines.append('abstract final class ' + name + ' {')
        for name, v in fields.items():
            rendered = json.dumps(v) if isinstance(v, str) else repr(v)
            if isinstance(v, str): rendered = "'" + v + "'"
            lines.append('  static const ' + ('String' if isinstance(v, str) else 'double') + ' ' + name + ' = ' + rendered + ';')
        lines += ['}', '']
    audit = {'source': lock, 'sheets': sheets, 'metrics': metrics}
    dart = '\n'.join(lines)
    formatter = os.environ.get('DART', 'dart')
    dart = subprocess.check_output([formatter, 'format', '--output=show', '--stdin-name=' + str(OUT)], input=dart, text=True).rsplit('Formatted ', 1)[0]
    return dart, json.dumps(audit, indent=2) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--snapshot-only', action='store_true', help='Verify vendored published bytes without a reference checkout')
    parser.add_argument('--src', type=Path, default=Path(os.environ.get('DSH_SRC', ROOT / '.local/dsh-src')))
    args = parser.parse_args()
    try:
        lock, sheets = collect(None if args.snapshot_only else args.src)
        dart, audit = render(lock, sheets)
        for path, text in [(OUT, dart), (AUDIT, audit)]:
            if args.check:
                if not path.exists() or path.read_text() != text:
                    raise ValueError('stale generated design recipe: ' + str(path.relative_to(ROOT)))
            else:
                path.write_text(text)
    except (ValueError, KeyError, OSError) as error:
        print('design-system:', error, file=sys.stderr)
        return 1
    print('design-system: published version, consumer dependency, CSS and recipes agree')
    return 0

if __name__ == '__main__':
    sys.exit(main())
