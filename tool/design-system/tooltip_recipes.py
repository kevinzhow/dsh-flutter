"""Compile tooltip geometry and fail on unimplemented published states."""
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent


def build(rules, *, value, number, token, font_token):
    contract = json.loads((HERE / 'tooltip-contract.json').read_text())
    expected = contract['rules']
    if len(rules) != len(expected): raise ValueError('untranslated tooltip rule')
    for actual, original in zip(rules, expected):
        if (actual['selector'], actual['conditions'], set(actual['declarations'])) != (
                original['selector'], original['conditions'], set(original['declarations'])):
            raise ValueError('untranslated tooltip state/condition/property')
    consumed = set()
    def get(selector, prop):
        consumed.add((selector, prop))
        return value(rules, selector, prop)
    def px(selector, prop): return number(get(selector, prop))
    def tok(selector, prop): return token(get(selector, prop))
    pad = get('.bubble', 'padding').split()
    if len(pad) != 2: raise ValueError('unsupported tooltip padding')
    animation = re.fullmatch(r'tooltip-in ([\d.]+)ms var\((--[\w-]+)\)', get('.bubble', 'animation'))
    if animation is None: raise ValueError('unsupported tooltip animation')
    placement = json.loads((HERE / 'upstream/ui-primitives/tooltip-placement.json').read_text())
    patterns = {'signature': r'\bgap = ([\d.]+)', 'anchor': r'r\.right \+ ([\d.]+)',
                'fit': r'edgeMargin = ([\d.]+)'}
    fields = {'signature': 'gap', 'anchor': 'rightGap', 'fit': 'margin'}
    numbers = {}
    for part, pattern in patterns.items():
        matches = re.findall(pattern, placement[part])
        if len(matches) != 1: raise ValueError('unsupported tooltip placement ' + part)
        numbers[fields[part]] = float(matches[0])
        if placement[part] != contract[part].replace('$' + fields[part], matches[0]):
            raise ValueError('untranslated tooltip placement ' + part)
    size = px('.bubble', 'font-size')
    line = px('.bubble', 'line-height')
    recipe = {
        'gap': px('.bubble', 'gap'),
        'maxViewportFraction': number(get('.bubble', 'max-width'), 'vw') / 100,
        'paddingVertical': number(pad[0]), 'paddingHorizontal': number(pad[1]),
        'shortcutEndPadding': px('.bubble[data-has-shortcut]', 'padding-inline-end'),
        'shortcutOnlyPadding': px('.bubble[data-has-shortcut]:not(:has(.label))', 'padding'),
        'radiusToken': tok('.bubble', 'border-radius'), 'fillToken': tok('.bubble', 'background'),
        'labelToken': tok('.bubble', 'color'), 'fontSize': size, 'lineHeight': line,
        'fontToken': font_token(size, line), 'animationMs': float(animation[1]), 'easingToken': animation[2],
        'defaultGap': numbers['gap'], 'rightGap': numbers['rightGap'], 'viewportMargin': numbers['margin'],
    }
    for actual, original in zip(rules, expected):
        for prop, expected_value in original['declarations'].items():
            if (actual['conditions'] or (actual['selector'], prop) not in consumed) and actual['declarations'][prop] != expected_value:
                raise ValueError('untranslated tooltip structural value: ' + actual['selector'] + '/' + prop)
    return {'DshTooltipRecipe': recipe}
