"""Compile the published read-only Tag geometry and its eight palettes."""
import re

TONES = ('outline', 'solid', 'neutral', 'quiet', 'success', 'info', 'warning', 'danger')
SCHEMA = {
    '.tag': 'display align-items border-radius corner-shape padding font-size line-height font-weight white-space',
    ".tag[data-tone='outline']": 'border color',
    ".tag[data-tone='solid']": 'background color',
    ".tag[data-tone='neutral']": 'background color',
    ".tag[data-tone='quiet']": 'color',
    **{f".tag[data-tone='{tone}']": 'background color' for tone in TONES[4:]},
}


def build(rules, *, value, number, token):
    seen = set()
    for rule in rules:
        selector, props = rule['selector'], rule['declarations']
        if rule['conditions'] or selector not in SCHEMA or set(props) != set(SCHEMA[selector].split()):
            raise ValueError('untranslated tag state/property: ' + selector)
        if selector in seen:
            raise ValueError('duplicate tag state: ' + selector)
        seen.add(selector)
    if seen != set(SCHEMA):
        raise ValueError('missing tag state')
    for prop, expected in {'display': 'inline-flex', 'align-items': 'center', 'corner-shape': 'round',
                           'white-space': 'nowrap'}.items():
        if value(rules, '.tag', prop) != expected:
            raise ValueError('untranslated tag structure: ' + prop)
    def get(selector, prop): return value(rules, selector, prop)
    def field(tone, prop): return get(f".tag[data-tone='{tone}']", prop)
    padding = get('.tag', 'padding').split()
    border = re.fullmatch(r'([\d.]+px) solid (var\(--[\w-]+\))', field('outline', 'border'))
    weight = get('.tag', 'font-weight')
    if len(padding) != 2 or border is None or not re.fullmatch(r'[1-9]00', weight):
        raise ValueError('unsupported tag padding, border, or weight')
    recipe = {'verticalPadding': number(padding[0]), 'horizontalPadding': number(padding[1]),
              'radius': number(get('.tag', 'border-radius')), 'fontSize': number(get('.tag', 'font-size')),
              'lineHeight': number(get('.tag', 'line-height')), 'fontWeight': float(weight),
              'outlineWidth': number(border[1]), 'outlineBorderToken': token(border[2]),
              'outlineLabelToken': token(field('outline', 'color'))}
    for tone in ('solid', 'neutral'):
        recipe[tone + 'FillToken'] = token(field(tone, 'background'))
        recipe[tone + 'LabelToken'] = token(field(tone, 'color'))
    recipe['quietLabelToken'] = token(field('quiet', 'color'))
    for tone in TONES[4:]:
        match = re.fullmatch(r'color-mix\(in srgb, (var\(--[\w-]+\)) ([\d.]+)%, transparent\)', field(tone, 'background'))
        if match is None or token(match[1]) != token(field(tone, 'color')):
            raise ValueError('unsupported tag tint: ' + tone)
        alpha = float(match[2]) / 100
        if not 0 <= alpha <= 1:
            raise ValueError('invalid tag tint: ' + tone)
        recipe[tone + 'Token'] = token(match[1])
        recipe[tone + 'Alpha'] = alpha
    return {'DshTagRecipe': recipe}
