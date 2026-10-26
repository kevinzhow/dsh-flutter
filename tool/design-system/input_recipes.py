"""Compile the published single-line Input atom and reject unknown states."""
import re

SCHEMA = {
    '.wrap': 'display align-items gap height padding border border-radius background',
    '.wrap:focus-within': 'border-color',
    '.icon': 'display width height align-items justify-content color',
    '.input': 'flex min-width border outline background font-size line-height color',
    '.input::placeholder': 'color',
}
FIXED = {
    '.wrap': {'display': 'inline-flex', 'align-items': 'center'},
    '.icon': {'display': 'inline-flex', 'align-items': 'center', 'justify-content': 'center'},
    '.input': {'flex': '1', 'min-width': '0', 'border': 'none', 'outline': 'none', 'background': 'transparent'},
}


def build(rules, *, value, number, token, font_token):
    seen = set()
    for rule in rules:
        selector, props = rule['selector'], rule['declarations']
        if rule['conditions'] or selector not in SCHEMA or set(props) != set(SCHEMA[selector].split()):
            raise ValueError('untranslated input state/property: ' + selector)
        if selector in seen:
            raise ValueError('duplicate input state: ' + selector)
        seen.add(selector)
    if seen != set(SCHEMA):
        raise ValueError('missing input state')
    for selector, props in FIXED.items():
        for prop, expected in props.items():
            if value(rules, selector, prop) != expected:
                raise ValueError('untranslated input structure: ' + selector + '/' + prop)
    def get(selector, prop): return value(rules, selector, prop)
    def px(selector, prop): return number(get(selector, prop))
    def tok(selector, prop): return token(get(selector, prop))
    padding = get('.wrap', 'padding').split()
    border = re.fullmatch(r'([\d.]+px) solid (var\(--[\w-]+\))', get('.wrap', 'border'))
    if len(padding) != 2 or padding[0] != '0' or border is None:
        raise ValueError('unsupported input padding or border')
    if px('.icon', 'width') != px('.icon', 'height'):
        raise ValueError('unsupported nonsquare input icon')
    size, line = px('.input', 'font-size'), px('.input', 'line-height')
    return {'DshInputRecipe': {
        'height': px('.wrap', 'height'), 'padding': number(padding[1]),
        'gap': px('.wrap', 'gap'), 'iconSize': px('.icon', 'width'),
        'borderWidth': number(border[1]), 'borderToken': token(border[2]),
        'radiusToken': tok('.wrap', 'border-radius'), 'fillToken': tok('.wrap', 'background'),
        'focusBorderToken': tok('.wrap:focus-within', 'border-color'),
        'iconToken': tok('.icon', 'color'), 'labelToken': tok('.input', 'color'),
        'placeholderToken': tok('.input::placeholder', 'color'),
        'fontSize': size, 'lineHeight': line, 'fontToken': font_token(size, line),
    }}
