"""Compile the published checkbox and risk acknowledgement profiles."""
import re

PRIMITIVE = {
    '.checkbox': 'display align-items gap font-size line-height color cursor',
    '.checkbox input': 'flex width height margin accent-color cursor',
    '.checkbox input:focus-visible': 'outline outline-offset',
    '.checkbox:has(input:disabled)': 'cursor opacity',
}
RISK = {
    '.acknowledgement': 'display align-items gap margin-top color font-size line-height cursor',
    '.acknowledgement input': 'flex width height margin accent-color cursor',
    '.acknowledgement input:focus-visible': 'outline outline-offset',
    '.acknowledgement input:disabled': 'cursor',
}


def build(primitive, risk, native, *, value, number, token, font_token):
    def validate(rules, schema, prefix, fixed):
        selected = [r for r in rules if r['selector'].startswith(prefix)]
        seen = set()
        for rule in selected:
            selector, props = rule['selector'], rule['declarations']
            if rule['conditions'] or selector not in schema or set(props) != set(schema[selector].split()):
                raise ValueError('untranslated checkbox state/property: ' + selector)
            if selector in seen:
                raise ValueError('duplicate checkbox state: ' + selector)
            seen.add(selector)
        if seen != set(schema):
            raise ValueError('missing checkbox state: ' + prefix)
        for selector, props in fixed.items():
            for prop, expected in props.items():
                if value(selected, selector, prop) != expected:
                    raise ValueError('untranslated checkbox structure: ' + selector + '/' + prop)
        return selected

    p = validate(primitive, PRIMITIVE, '.checkbox', {
        '.checkbox': {'display': 'inline-flex', 'align-items': 'center', 'cursor': 'pointer'},
        '.checkbox input': {'flex': '0 0 auto', 'margin': '0', 'cursor': 'inherit'},
        '.checkbox:has(input:disabled)': {'cursor': 'default'},
    })
    r = validate(risk, RISK, '.acknowledgement', {
        '.acknowledgement': {'display': 'flex', 'align-items': 'flex-start', 'cursor': 'pointer'},
        '.acknowledgement input': {'flex': 'none', 'cursor': 'pointer'},
        '.acknowledgement input:disabled': {'cursor': 'default'},
    })
    def get(rules, selector, prop): return value(rules, selector, prop)
    def px(rules, selector, prop): return number(get(rules, selector, prop))
    def tok(rules, selector, prop): return token(get(rules, selector, prop))
    def focus(rules, selector):
        match = re.fullmatch(r'var\((--[\w-]+)\) solid var\((--[\w-]+),\s*var\((--[\w-]+)\)\)',
                             get(rules, selector, 'outline'))
        if match is None:
            raise ValueError('unsupported checkbox focus outline')
        return (*match.groups(), px(rules, selector, 'outline-offset'))
    pf = focus(p, '.checkbox input:focus-visible')
    rf = focus(r, '.acknowledgement input:focus-visible')
    if pf != rf:
        raise ValueError('checkbox profiles use different focus outlines')
    width, height = px(p, '.checkbox input', 'width'), px(p, '.checkbox input', 'height')
    if width != height or width != px(r, '.acknowledgement input', 'width') or height != px(r, '.acknowledgement input', 'height'):
        raise ValueError('unsupported checkbox size')
    margin = get(r, '.acknowledgement input', 'margin').split()
    if len(margin) != 3 or margin[1:] != ['0', '0']:
        raise ValueError('unsupported checkbox risk margin')
    risk_size = px(r, '.acknowledgement', 'font-size')
    risk_line = px(r, '.acknowledgement', 'line-height')
    expected_geometry = {'radius', 'borderWidth', 'backgroundInsetRatio', 'checkStartX', 'checkStartY',
                         'checkStepX', 'checkStepY', 'checkEndXFromRight', 'checkEndY', 'checkStrokeRatio',
                         'accentLightnessAdjust'}
    if native.get('schema') != 'dsh-chromium-checkbox/1' or set(native['geometry']) != expected_geometry:
        raise ValueError('unrecognized Chromium checkbox geometry')
    geometry = native['geometry']
    if not all(type(v) is float and 0 <= v <= 2 for v in geometry.values()):
        raise ValueError('invalid Chromium checkbox metric')
    native_fields = dict(geometry)
    for mode in ('light', 'dark'):
        states = native['palette'][mode]
        if set(states) != {'normal', 'hover', 'pressed', 'disabled'}:
            raise ValueError('unrecognized Chromium checkbox states')
        for state, fields in states.items():
            if set(fields) != {'offFill', 'offBorder', 'onMark', 'onFillSample'} or not all(re.fullmatch(r'#[0-9a-f]{6}', c) for c in fields.values()):
                raise ValueError('invalid Chromium checkbox palette')
        if any(states[state]['offFill'] != states['normal']['offFill'] or states[state]['onMark'] != states['normal']['onMark'] for state in ('hover', 'pressed')):
            raise ValueError('unsupported Chromium checkbox hover fill/mark')
        def argb(color): return int('ff' + color[1:], 16)
        native_fields[mode + 'OffFill'] = argb(states['normal']['offFill'])
        native_fields[mode + 'OffDisabledFill'] = argb(states['disabled']['offFill'])
        for state in ('normal', 'hover', 'pressed', 'disabled'):
            native_fields[mode + 'OffBorder' + state.capitalize()] = argb(states[state]['offBorder'])
        native_fields[mode + 'OnMark'] = argb(states['normal']['onMark'])
        native_fields[mode + 'OnDisabledMark'] = argb(states['disabled']['onMark'])
        native_fields[mode + 'OnDisabledFill'] = argb(states['disabled']['onFillSample'])
    return {'DshCheckboxNativeRecipe': native_fields, 'DshCheckboxRecipe': {
        'size': width, 'gap': px(p, '.checkbox', 'gap'), 'riskGap': px(r, '.acknowledgement', 'gap'),
        'fontSize': px(p, '.checkbox', 'font-size'), 'lineHeight': px(p, '.checkbox', 'line-height'),
        'riskFontSize': risk_size, 'riskLineHeight': risk_line, 'riskFontToken': font_token(risk_size, risk_line),
        'riskInputTop': number(margin[0]), 'riskMarginTop': px(r, '.acknowledgement', 'margin-top'),
        'labelToken': tok(p, '.checkbox', 'color'), 'riskLabelToken': tok(r, '.acknowledgement', 'color'),
        'accentToken': tok(p, '.checkbox input', 'accent-color'), 'riskAccentToken': tok(r, '.acknowledgement input', 'accent-color'),
        'disabledOpacity': number(get(p, '.checkbox:has(input:disabled)', 'opacity'), ''),
        'focusWidthToken': pf[0], 'focusToken': pf[1], 'focusFallbackToken': pf[2], 'focusOffset': pf[3],
    }}
