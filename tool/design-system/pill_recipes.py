"""Compile the published pill and the market category-group recipe."""
import re

PILL = {
    '.pill': 'display align-items gap height padding border border-radius corner-shape font-size line-height color background',
    '.interactive': 'cursor',
    '.interactive:hover': 'background',
    '.active': 'color background box-shadow',
}
CATEGORY = {'.categories': 'display flex-wrap align-items gap'}


def build(pill, market, *, value, number, token, font_token):
    def validate(rules, schema, prefix=None):
        selected = rules if prefix is None else [r for r in rules if r['selector'].startswith(prefix)]
        seen = set()
        for rule in selected:
            selector, props = rule['selector'], rule['declarations']
            if rule['conditions'] or selector not in schema or set(props) != set(schema[selector].split()):
                raise ValueError('untranslated pill state/property: ' + selector)
            if selector in seen:
                raise ValueError('duplicate pill state: ' + selector)
            seen.add(selector)
        if seen != set(schema):
            raise ValueError('missing pill state')
        return selected

    p = validate(pill, PILL)
    c = validate(market, CATEGORY, '.categories')
    for rules, selector, fixed in [
        (p, '.pill', {'display': 'inline-flex', 'align-items': 'center', 'border': 'none', 'corner-shape': 'round'}),
        (p, '.interactive', {'cursor': 'pointer'}),
        (c, '.categories', {'display': 'flex', 'flex-wrap': 'wrap', 'align-items': 'center'}),
    ]:
        for prop, expected in fixed.items():
            if value(rules, selector, prop) != expected:
                raise ValueError('untranslated pill structure: ' + selector + '/' + prop)
    def get(rules, selector, prop): return value(rules, selector, prop)
    def px(rules, selector, prop): return number(get(rules, selector, prop))
    def tok(rules, selector, prop): return token(get(rules, selector, prop))
    padding = get(p, '.pill', 'padding').split()
    shadow = re.fullmatch(r'inset 0 0 0 ([\d.]+px) (var\(--[\w-]+\))', get(p, '.active', 'box-shadow'))
    if len(padding) != 2 or padding[0] != '0' or shadow is None:
        raise ValueError('unsupported pill padding or active inset')
    size, line = px(p, '.pill', 'font-size'), px(p, '.pill', 'line-height')
    return {'DshPillRecipe': {
        'height': px(p, '.pill', 'height'), 'padding': number(padding[1]),
        'gap': px(p, '.pill', 'gap'), 'radius': px(p, '.pill', 'border-radius'),
        'fontSize': size, 'lineHeight': line, 'fontToken': font_token(size, line),
        'labelToken': tok(p, '.pill', 'color'), 'fillToken': tok(p, '.pill', 'background'),
        'hoverToken': tok(p, '.interactive:hover', 'background'),
        'activeLabelToken': tok(p, '.active', 'color'), 'activeFillToken': tok(p, '.active', 'background'),
        'activeBorderWidth': number(shadow[1]), 'activeBorderToken': token(shadow[2]),
        'categoryGap': px(c, '.categories', 'gap'),
    }}
