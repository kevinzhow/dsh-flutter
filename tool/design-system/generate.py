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
    rules = {name: css_rules((folder / name).read_text(), allow_keyframes=name in ('Tooltip.module.css', 'Modal.module.css'),
                             allow_supports=name == 'RiskConfirmation.module.css')
             for name in package['files'] if name.endswith('.css')}
    browser = lock['rendererSnapshots']['chromiumCheckbox']
    if browser['path'] != 'upstream/chromium/checkbox-native.json':
        raise ValueError('unexpected Chromium checkbox snapshot path')
    if browser['license'] != 'upstream/chromium/LICENSE' or hashlib.sha256((HERE / browser['license']).read_bytes()).hexdigest() != browser['licenseSha256']:
        raise ValueError('Chromium checkbox license snapshot mismatch')
    snapshot = (HERE / browser['path']).read_bytes()
    if hashlib.sha256(snapshot).hexdigest() != browser['sha256']:
        raise ValueError('Chromium checkbox snapshot hash mismatch')
    native_checkbox = json.loads(snapshot)
    if native_checkbox['browser'] != browser['browser'] or native_checkbox['sourceSha256'] != browser['sourceSha256']:
        raise ValueError('Chromium checkbox provenance mismatch')
    rules['ChromiumCheckbox'] = native_checkbox
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

    market = next(p for p in lock['packages'] if p['snapshotFolder'] == 'ui-plugin-market')
    market_folder = HERE / 'upstream' / market['snapshotFolder']
    market_classes = json.loads((market_folder / 'classes.json').read_text())
    market_rules = css_rules((market_folder / 'DiscoverSection.module.css').read_text(), allow_keyframes=True)
    for rule in market_rules:
        rule['selector'] = published.unhash_selectors(rule['selector'], market_classes)
    rules['DiscoverSection.module.css'] = market_rules
    if source is not None:
        original = source / Path(market['sourcePackage']).parent / 'src/client/DiscoverSection.module.css'
        select = lambda rs: [normalized_rule(r) for r in rs if r['selector'].startswith('.categories')]
        if select(market_rules) != select(css_rules(original.read_text(), allow_keyframes=True)):
            raise ValueError('reference category CSS differs from pinned published market package')

    modal_spec = importlib.util.spec_from_file_location('modal_recipes', HERE / 'modal_recipes.py')
    modal = importlib.util.module_from_spec(modal_spec)
    modal_spec.loader.exec_module(modal)
    preset = next(p for p in lock['packages'] if p['snapshotFolder'] == 'ui-agent-preset')
    preset_folder = HERE / 'upstream' / preset['snapshotFolder']
    guide_classes = json.loads((preset_folder / 'guide-classes.json').read_text())
    guide = css_rules((preset_folder / 'PresetGuideDialog.module.css').read_text())
    for rule in guide:
        rule['selector'] = published.unhash_selectors(rule['selector'], guide_classes)
    if source is not None:
        original = source / Path(preset['sourcePackage']).parent / 'src/client/PresetGuideDialog.module.css'
        modal.verify_guide_source(guide, css_rules(original.read_text()))
    rules['PresetGuideDialog.module.css'] = [modal.normalize(rule) for rule in guide]
    roster_classes = json.loads((preset_folder / 'roster-classes.json').read_text())
    roster = css_rules((preset_folder / 'styles.css').read_text(), allow_keyframes=True, allow_supports=True)
    for rule in roster:
        rule['selector'] = published.unhash_selectors(rule['selector'], roster_classes)
    rules['AgentPresetSection.styles.css'] = roster  # audited; not a migrated roster recipe
    theme_folder = HERE / 'upstream/ui-theme'
    rules['PlatformMenuMaterial'] = [
        rule for rule in css_rules((theme_folder / 'design-platform.css').read_text())
        if 'html[data-platform' in rule['selector']
    ]
    token_names = {'--ds-transition-duration', '--ds-ease-in-out', '--dsw-mask-blur'}
    theme_tokens = []
    for name in ('base.css', 'gradient-shadow-text.css'):
        for rule in css_rules((theme_folder / name).read_text()):
            selected = {key: value for key, value in rule['declarations'].items() if key in token_names}
            if selected:
                theme_tokens.append({**rule, 'declarations': selected})
    rules['ModalContext'] = {
        'themeTokens': theme_tokens,
        'scrollbarRules': css_rules((theme_folder / 'scrollbar.css').read_text(), allow_supports=True),
        'modalBehavior': json.loads((HERE / 'upstream/ui-primitives/modal-layer.json').read_text()),
        'readerBehavior': json.loads((preset_folder / 'reader-behavior.json').read_text()),
    }
    if source is not None:
        risk_spec = importlib.util.spec_from_file_location('risk_recipes', HERE / 'risk_recipes.py')
        risk = importlib.util.module_from_spec(risk_spec)
        risk_spec.loader.exec_module(risk)
        primitive = next(p for p in lock['packages'] if p['snapshotFolder'] == 'ui-primitives')
        risk.verify_source_icon(rules['ModalContext']['modalBehavior']['risk'],
                                (source / Path(primitive['sourcePackage']).parent / 'src/RiskConfirmation.tsx').read_text())
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
    'ShortcutKeys.module.css': {
        '.keys': 'display flex align-items gap color font-size line-height white-space',
        '.key': 'box-sizing display align-items justify-content font',
        '.tooltip': 'color font-size line-height gap',
        '.tooltip .key': 'min-width height padding border-radius border background',
        '.separator': 'font',
        '.joined': 'box-sizing height padding border-radius background',
        '.joined .key': 'min-width height padding border background',
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
    # Structural keycap values cannot drift without a renderer change.
    shortcut_fixed = {
        '.keys': {'display': 'inline-flex', 'flex': 'none', 'align-items': 'center', 'white-space': 'nowrap'},
        '.key': {'box-sizing': 'border-box', 'display': 'inline-flex', 'align-items': 'center', 'justify-content': 'center', 'font': 'inherit'},
        '.tooltip': {'color': 'inherit'},
        '.tooltip .key': {'border': '0'},
        '.separator': {'font': 'inherit'},
        '.joined': {'box-sizing': 'border-box'},
        '.joined .key': {'min-width': '0', 'height': 'auto', 'padding': '0', 'border': '0', 'background': 'transparent'},
    }
    for selector, props in shortcut_fixed.items():
        for prop, expected in props.items():
            if value(sheets['ShortcutKeys.module.css'], selector, prop) != expected:
                raise ValueError('untranslated shortcut value: ' + selector + '/' + prop)
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


def chrome_size_token(size):
    pack = json.loads((ROOT / 'packages/dsh_theme/assets/themes/official.theme.json').read_text())
    candidates = [name for name, style in pack['common']['typography'].items()
                  if name.startswith('--dsw-font-xx') and style['size'] == size
                  and style['weight'] == 400 and style['style'] == 'normal' and style['family'] == 'text']
    if len(candidates) != 1:
        raise ValueError('ambiguous chrome typography rung for shortcut size: ' + str(size))
    return candidates[0]


def profile_font_token(size, line):
    # Profiles can override weight (the guide's 20/28 is 600 while the
    # corresponding named theme rung is 500). Preserve its configurable face.
    pack = json.loads((ROOT / 'packages/dsh_theme/assets/themes/official.theme.json').read_text())
    candidates = [(style['weight'], name) for name, style in pack['common']['typography'].items()
                  if style['size'] == size and style['line'] == line
                  and style['style'] == 'normal' and style['family'] == 'text']
    if not candidates:
        raise ValueError('missing typography rung for modal profile: ' + str(size))
    minimum = min(weight for weight, _ in candidates)
    selected = [name for weight, name in candidates if weight == minimum]
    if len(selected) != 1:
        raise ValueError('ambiguous typography rung for modal profile: ' + str(size))
    return selected[0]


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
    label_transition = get(t, '.tab', 'transition').split()
    if (len(transition) != 3 or transition[0] != 'transform' or transition[2] != 'ease'
            or len(label_transition) != 3 or label_transition[0] != 'color' or label_transition[2] != 'ease'):
        raise ValueError('unsupported tab transition')
    tab_border = get(t, '.indicator', 'border').split()
    if len(tab_border) != 3 or tab_border[1] != 'solid':
        raise ValueError('unsupported tab border')
    tab_padding = get(t, '.tab', 'padding').split()
    if len(tab_padding) != 2 or tab_padding[0] != '0':
        raise ValueError('unsupported tab padding')
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
            'labelTransitionMs': number(label_transition[1], 'ms'),
            'labelPadding': number(tab_padding[1]),
            'focusLineWidth': px(t, '.tab:focus-visible', 'text-decoration-thickness'),
            'focusLineOffset': px(t, '.tab:focus-visible', 'text-underline-offset'),
            'backgroundToken': tok(t, '.tabs', 'background'), 'radiusToken': tok(t, '.tabs', 'border-radius'),
            'indicatorBackgroundToken': tok(t, '.indicator', 'background'),
            'indicatorRadiusToken': tok(t, '.indicator', 'border-radius'),
            'labelToken': tok(t, '.tab', 'color'),
            'outlineToken': token(tab_border[2]), 'outlineWidth': number(tab_border[0]),
            'activeLabelToken': tok(t, ".tab:hover, .tab[aria-selected='true']", 'color'),
        },
    }
    shortcut = sheets['ShortcutKeys.module.css']
    metrics['DshShortcutKeysRecipe'] = {
        'plainGap': px(shortcut, '.keys', 'gap'),
        'plainFontSize': px(shortcut, '.keys', 'font-size'),
        'plainLineHeight': px(shortcut, '.keys', 'line-height'),
        'plainFontToken': chrome_size_token(px(shortcut, '.keys', 'font-size')),
        'plainColorToken': tok(shortcut, '.keys', 'color'),
        'tooltipGap': px(shortcut, '.tooltip', 'gap'),
        'tooltipFontSize': px(shortcut, '.tooltip', 'font-size'),
        'tooltipLineHeight': px(shortcut, '.tooltip', 'line-height'),
        'tooltipFontToken': chrome_size_token(px(shortcut, '.tooltip', 'font-size')),
        'keyMinWidth': px(shortcut, '.tooltip .key', 'min-width'),
        'keyHeight': px(shortcut, '.tooltip .key', 'height'),
        'keyRadius': px(shortcut, '.tooltip .key', 'border-radius'),
        'keyFillToken': tok(shortcut, '.tooltip .key', 'background'),
    }
    key_padding = get(shortcut, '.tooltip .key', 'padding').split()
    joined_padding = get(shortcut, '.joined', 'padding').split()
    if len(key_padding) != 2 or key_padding[0] != '0' or len(joined_padding) != 2 or joined_padding[0] != '0':
        raise ValueError('unsupported tooltip keycap padding')
    if (px(shortcut, '.joined', 'height') != metrics['DshShortcutKeysRecipe']['keyHeight'] or
            px(shortcut, '.joined', 'border-radius') != metrics['DshShortcutKeysRecipe']['keyRadius'] or
            tok(shortcut, '.joined', 'background') != metrics['DshShortcutKeysRecipe']['keyFillToken']):
        raise ValueError('unsupported differing joined keycap geometry')
    metrics['DshShortcutKeysRecipe'].update({'keyPadding': number(key_padding[1]), 'joinedPadding': number(joined_padding[1])})
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
    tooltip_spec = importlib.util.spec_from_file_location('tooltip_recipes', HERE / 'tooltip_recipes.py')
    tooltip = importlib.util.module_from_spec(tooltip_spec)
    tooltip_spec.loader.exec_module(tooltip)
    metrics.update(tooltip.build(sheets['Tooltip.module.css'], value=value, number=number, token=token, font_token=ladder_token))
    input_spec = importlib.util.spec_from_file_location('input_recipes', HERE / 'input_recipes.py')
    input_recipe = importlib.util.module_from_spec(input_spec)
    input_spec.loader.exec_module(input_recipe)
    metrics.update(input_recipe.build(sheets['Input.module.css'], value=value, number=number, token=token, font_token=ladder_token))
    switch_spec = importlib.util.spec_from_file_location('switch_recipes', HERE / 'switch_recipes.py')
    switch_recipe = importlib.util.module_from_spec(switch_spec)
    switch_spec.loader.exec_module(switch_recipe)
    metrics.update(switch_recipe.build(sheets['Switch.module.css'], value=value, number=number, token=token))
    checkbox_spec = importlib.util.spec_from_file_location('checkbox_recipes', HERE / 'checkbox_recipes.py')
    checkbox = importlib.util.module_from_spec(checkbox_spec)
    checkbox_spec.loader.exec_module(checkbox)
    metrics.update(checkbox.build(sheets['Checkbox.module.css'], sheets['RiskConfirmation.module.css'], sheets['ChromiumCheckbox'],
                                  value=value, number=number, token=token, font_token=ladder_token))
    pill_spec = importlib.util.spec_from_file_location('pill_recipes', HERE / 'pill_recipes.py')
    pill = importlib.util.module_from_spec(pill_spec)
    pill_spec.loader.exec_module(pill)
    metrics.update(pill.build(sheets['Pill.module.css'], sheets['DiscoverSection.module.css'],
                              value=value, number=number, token=token, font_token=ladder_token))
    tag_spec = importlib.util.spec_from_file_location('tag_recipes', HERE / 'tag_recipes.py')
    tag = importlib.util.module_from_spec(tag_spec)
    tag_spec.loader.exec_module(tag)
    metrics.update(tag.build(sheets['Tag.module.css'], value=value, number=number, token=token))
    modal_spec = importlib.util.spec_from_file_location('modal_recipes', HERE / 'modal_recipes.py')
    modal = importlib.util.module_from_spec(modal_spec)
    modal_spec.loader.exec_module(modal)
    metrics.update(modal.build(sheets['Modal.module.css'], sheets['PresetGuideDialog.module.css'], sheets['ModalContext'],
                               value=value, number=number, token=token, font_token=profile_font_token))
    risk_spec = importlib.util.spec_from_file_location('risk_recipes', HERE / 'risk_recipes.py')
    risk = importlib.util.module_from_spec(risk_spec)
    risk_spec.loader.exec_module(risk)
    metrics.update(risk.build(sheets['RiskConfirmation.module.css'], sheets['ModalContext']['modalBehavior']['risk'],
                              value=value, number=number, token=token, font_token=profile_font_token))
    platform_spec = importlib.util.spec_from_file_location('platform_material_recipes', HERE / 'platform_material_recipes.py')
    platform = importlib.util.module_from_spec(platform_spec)
    platform_spec.loader.exec_module(platform)
    metrics.update(platform.build(sheets['PlatformMenuMaterial']))
    package = lock['packages'][0]
    lines = ['// Generated by tool/design-system/generate.py; do not edit.', *['// From ' + p['name'] + ' ' + p['version'] + '.' for p in lock['packages']], '']
    for name, fields in metrics.items():
        lines.append('abstract final class ' + name + ' {')
        for name, v in fields.items():
            if isinstance(v, str):
                kind, rendered = 'String', "'" + v + "'"
            elif type(v) is int:
                kind, rendered = 'int', hex(v)
            else:
                kind, rendered = 'double', repr(v)
            lines.append('  static const ' + kind + ' ' + name + ' = ' + rendered + ';')
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
