"""Compile the published Switch atom and reject untranslated CSS states."""
import re

SCHEMA = {
    '.switch': 'box-sizing position flex width height padding border border-radius corner-shape background cursor',
    ".switch[aria-checked='true']": 'background',
    '.switch:disabled': 'cursor opacity',
    '.switch:focus-visible': 'outline outline-offset',
    '.thumb': 'display width height border-radius corner-shape background transition',
    ".switch[aria-checked='false'] .thumb": 'background',
    ".switch[aria-checked='true'] .thumb": 'transform',
}
FIXED = {
    '.switch': {'box-sizing': 'border-box', 'position': 'relative', 'flex': '0 0 auto',
                'border': '0', 'corner-shape': 'round', 'cursor': 'pointer'},
    '.switch:disabled': {'cursor': 'default'},
    '.thumb': {'display': 'block', 'border-radius': '50%', 'corner-shape': 'round'},
}


def build(rules, *, value, number, token):
    seen = set()
    for rule in rules:
        selector, props = rule['selector'], rule['declarations']
        if rule['conditions'] or selector not in SCHEMA or set(props) != set(SCHEMA[selector].split()):
            raise ValueError('untranslated switch state/property: ' + selector)
        if selector in seen:
            raise ValueError('duplicate switch state: ' + selector)
        seen.add(selector)
    if seen != set(SCHEMA):
        raise ValueError('missing switch state')
    for selector, props in FIXED.items():
        for prop, expected in props.items():
            if value(rules, selector, prop) != expected:
                raise ValueError('untranslated switch structure: ' + selector + '/' + prop)
    def get(selector, prop): return value(rules, selector, prop)
    def px(selector, prop): return number(get(selector, prop))
    def tok(selector, prop): return token(get(selector, prop))
    outline = re.fullmatch(r'var\((--[\w-]+)\) solid var\((--[\w-]+),\s*var\((--[\w-]+)\)\)', get('.switch:focus-visible', 'outline'))
    transition = re.fullmatch(r'transform ([\d.]+)ms ease', get('.thumb', 'transition'))
    translate = re.fullmatch(r'translateX\(([\d.]+)px\)', get(".switch[aria-checked='true'] .thumb", 'transform'))
    if outline is None or transition is None or translate is None:
        raise ValueError('unsupported switch focus or transition')
    width, height = px('.switch', 'width'), px('.switch', 'height')
    thumb, padding = px('.thumb', 'width'), px('.switch', 'padding')
    if thumb != px('.thumb', 'height') or thumb + 2 * padding != height or float(translate[1]) != width - thumb - 2 * padding:
        raise ValueError('unsupported switch thumb geometry')
    return {'DshSwitchRecipe': {
        'width': width, 'height': height, 'padding': padding, 'thumbSize': thumb,
        'radius': px('.switch', 'border-radius'), 'disabledOpacity': number(get('.switch:disabled', 'opacity'), ''),
        'transitionMs': float(transition[1]), 'focusOffset': px('.switch:focus-visible', 'outline-offset'),
        'focusWidthToken': outline[1], 'focusToken': outline[2], 'focusFallbackToken': outline[3],
        'offTrackToken': tok('.switch', 'background'), 'onTrackToken': tok(".switch[aria-checked='true']", 'background'),
        'offThumbToken': tok(".switch[aria-checked='false'] .thumb", 'background'), 'onThumbToken': tok('.thumb', 'background'),
    }}
