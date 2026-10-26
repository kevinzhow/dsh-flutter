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


# File loading also works under python -I and when imported by tool tests.
import importlib.util
_css_spec = importlib.util.spec_from_file_location('design_css', HERE / 'css.py')
_css = importlib.util.module_from_spec(_css_spec)
_css_spec.loader.exec_module(_css)
split_outside, css_rules = _css.split_outside, _css.css_rules


def value(rules, selector, prop):
    found = [r['declarations'][prop] for r in rules if not r['conditions'] and r['selector'] == selector and prop in r['declarations']]
    if len(found) != 1:
        raise ValueError('ambiguous/missing CSS recipe input: ' + selector + '/' + prop)
    return found[0]


def number(raw, unit='px'):
    match = re.fullmatch(r'(-?(?:\d+(?:\.\d+)?|\.\d+))' + unit, raw)
    if not match:
        raise ValueError('unsupported CSS number: ' + raw)
    return float(match[1])


def token(raw):
    match = re.fullmatch(r'var\((--[\w-]+)\)', raw)
    if not match:
        raise ValueError('unsupported token expression: ' + raw)
    return match[1]


BUTTON_CLASSES = ('addGroup', 'addButton', 'addPrimary', 'addMore', 'iconButton', 'infoButton')


def button_rules(rules):
    return [r for r in rules if any(re.search(r'\.' + name + r'(?![\w-])', r['selector']) for name in BUTTON_CLASSES)]


def normalized_rule(rule):
    # Only the published minifier's observed transformations are accepted.
    # Do not erase arbitrary syntax, selector combinators or conditional scope.
    def normalized(text):
        text = re.sub(r"\[role=['\"]menuitem['\"]\]", '[role=menuitem]', text)
        text = re.sub(r'(?<![\w.])0\.(\d+)', r'.\1', text)
        return re.sub(r'\s*,\s*', ',', text.strip())
    props = {k: normalized(v) for k, v in rule['declarations'].items()}
    if props.get('background') == '0 0': props['background'] = 'transparent'
    return {'selector': normalized(rule['selector']), 'conditions': rule['conditions'], 'declarations': props}


def verify_feature_source(published, source):
    if [normalized_rule(r) for r in button_rules(published)] != [normalized_rule(r) for r in button_rules(source)]:
        raise ValueError('reference button CSS differs from pinned published plugin package')
    menu_rules = lambda rules: [normalized_rule(r) for r in rules if '.addMenu' in r['selector']]
    if menu_rules(published) != menu_rules(source):
        raise ValueError('reference menu CSS differs from pinned published plugin package')


def collect(source=None):
    spec = importlib.util.spec_from_file_location('published', HERE / 'published.py')
    published = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(published)
    lock = published.verify_packages(source)
    package = lock['packages'][0]
    folder = HERE / 'upstream' / package['snapshotFolder']
    if source is not None:
        for name in package['files']:
            if name.endswith('.css'):
                original = source / Path(package['sourcePackage']).parent / 'src' / name
                if original.read_bytes() != (folder / name).read_bytes():
                    raise ValueError('reference CSS differs from pinned published package: ' + name)
    rules = {name: css_rules((folder / name).read_text()) for name in package['files'] if name.endswith('.css')}
    # The feature package publishes CSS inside its bundle. These are decoded
    # verbatim CSS bytes and the static class export, never executed JS.
    spec = importlib.util.spec_from_file_location('published', HERE / 'published.py')
    published = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(published)
    package = lock['packages'][1]
    folder = HERE / 'upstream' / package['snapshotFolder']
    classes = json.loads((folder / 'classes.json').read_text())
    feature = css_rules((folder / 'PluginManagerPage.module.css').read_text(), allow_keyframes=True)
    for rule in feature:
        rule['selector'] = published.unhash_selectors(rule['selector'], classes)
        rule['selector'] = re.sub(r"\[role=['\"]menuitem['\"]\]", '[role=menuitem]', rule['selector'])
    rules['PluginManagerPage.module.css'] = feature
    if source is not None:
        original = source / Path(package['sourcePackage']).parent / 'src/client/PluginManagerPage.module.css'
        verify_feature_source(feature, css_rules(original.read_text(), allow_keyframes=True))

    dock = next(p for p in lock['packages'] if p['snapshotFolder'] == 'ui-dockkit')
    dock_css = (HERE / 'upstream/ui-dockkit/dockkit.module.css').read_bytes()
    if source is not None and dock_css != (source / Path(dock['sourcePackage']).parent / 'src/components/dockkit.module.css').read_bytes():
        raise ValueError('reference dock CSS differs from pinned published package')
    rules['dockkit.module.css'] = css_rules(dock_css.decode(), allow_keyframes=True)

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

PLUGIN_BUTTON_SCHEMA = {
    '.addGroup': 'flex align-items display',
    '.infoButton': 'width height color flex padding',
    '.iconButton:focus-visible': 'outline outline-offset',
    '.iconButton': 'border-radius width height color cursor background border justify-content align-items display',
    '.iconButton:hover:not(:disabled)': 'background color',
    '.iconButton:disabled': 'opacity cursor',
    '.addButton, .addPrimary, .addMore': 'border-radius height padding font-size line-height',
    '.addPrimary': 'border-top-right-radius border-bottom-right-radius',
    '.addMore': 'border-left border-top-left-radius border-bottom-left-radius width padding',
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
    rules = button_rules(sheets['PluginManagerPage.module.css'])
    seen = set()
    for rule in rules:
        selector, props = rule['selector'], rule['declarations']
        if rule['conditions'] or selector not in PLUGIN_BUTTON_SCHEMA or set(props) != set(PLUGIN_BUTTON_SCHEMA[selector].split()):
            raise ValueError('untranslated plugin button state/property: ' + selector)
        seen.add(selector)
    if seen != set(PLUGIN_BUTTON_SCHEMA): raise ValueError('missing plugin button state')
    primitive_fixed = {
        '.button': {'box-sizing': 'border-box', 'display': 'inline-flex', 'align-items': 'center', 'justify-content': 'center', 'border': 'none', 'cursor': 'pointer', 'background': 'transparent'},
        '.button:disabled': {'cursor': 'not-allowed'},
        '.outline': {'background': 'transparent'},
        '.icon': {'display': 'inline-flex', 'align-items': 'center', 'justify-content': 'center'},
    }
    for selector, props in primitive_fixed.items():
        for prop, expected in props.items():
            if value(sheets['Button.module.css'], selector, prop) != expected:
                raise ValueError('untranslated primitive button value: ' + selector + '/' + prop)
    if value(sheets['Button.module.css'], '.icon', 'width') != value(sheets['Button.module.css'], '.icon', 'height'):
        raise ValueError('untranslated nonsquare button icon')
    # Structural rules not represented by dynamic Dart fields cannot change
    # silently. New values need an intentional renderer implementation.
    fixed = {
        '.addGroup': {'flex': 'none', 'align-items': 'stretch', 'display': 'inline-flex'},
        '.infoButton': {'flex': 'none', 'padding': '0'},
        '.iconButton': {'cursor': 'pointer', 'background': '0 0', 'border': '0', 'justify-content': 'center', 'align-items': 'center', 'display': 'inline-flex'},
        '.iconButton:disabled': {'cursor': 'default'},
        '.addPrimary': {'border-top-right-radius': '0', 'border-bottom-right-radius': '0'},
        '.addMore': {'border-top-left-radius': '0', 'border-bottom-left-radius': '0', 'padding': '0'},
    }
    for selector, values in fixed.items():
        for prop, expected in values.items():
            if value(rules, selector, prop) != expected:
                raise ValueError('untranslated plugin button value: ' + selector + '/' + prop)


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
    p = sheets['PluginManagerPage.module.css']
    add = '.addButton, .addPrimary, .addMore'
    add_padding = get(p, add, 'padding').split()
    if len(add_padding) != 2 or add_padding[0] != '0': raise ValueError('unsupported add button padding')
    divider = re.fullmatch(r'([.\d]+px) solid color-mix\(in srgb,\s*var\((--[\w-]+)\) ([\d.]+)%,\s*transparent\)', get(p, '.addMore', 'border-left'))
    focus = re.fullmatch(r'var\((--[\w-]+)\) solid var\((--[\w-]+),\s*var\((--[\w-]+)\)\)', get(p, '.iconButton:focus-visible', 'outline'))
    if divider is None or focus is None: raise ValueError('unsupported plugin button divider/focus')
    metrics['DshAddButtonRecipe'] = {
        'height': px(p, add, 'height'), 'padding': number(add_padding[1]),
        'fontToken': ladder_token(px(p, add, 'font-size'), px(p, add, 'line-height')),
        'radiusToken': tok(p, add, 'border-radius'),
        'moreWidth': px(p, '.addMore', 'width'), 'dividerWidth': number(divider[1]),
        'dividerToken': divider[2], 'dividerAlpha': float(divider[3]) / 100,
    }
    metrics['DshIconActionRecipe'] = {
        'width': px(p, '.iconButton', 'width'), 'height': px(p, '.iconButton', 'height'),
        'infoWidth': px(p, '.infoButton', 'width'), 'infoHeight': px(p, '.infoButton', 'height'),
        'radiusToken': tok(p, '.iconButton', 'border-radius'),
        'labelToken': tok(p, '.iconButton', 'color'),
        'infoLabelToken': tok(p, '.infoButton', 'color'),
        'hoverLabelToken': tok(p, '.iconButton:hover:not(:disabled)', 'color'),
        'hoverToken': tok(p, '.iconButton:hover:not(:disabled)', 'background'),
        'disabledOpacity': number(get(p, '.iconButton:disabled', 'opacity'), ''),
        'focusWidthToken': focus[1], 'focusToken': focus[2], 'focusFallbackToken': focus[3],
        'focusOffset': px(p, '.iconButton:focus-visible', 'outline-offset'),
    }
    menu_spec = importlib.util.spec_from_file_location('menu_recipes', HERE / 'menu_recipes.py')
    menu = importlib.util.module_from_spec(menu_spec)
    menu_spec.loader.exec_module(menu)
    metrics.update(menu.build(sheets, value=value, number=number, token=token, css_rules=css_rules))
    package = lock['packages'][0]
    lines = ['// Generated by tool/design-system/generate.py; do not edit.', *['// From ' + p['name'] + ' ' + p['version'] + '.' for p in lock['packages']], '']
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
