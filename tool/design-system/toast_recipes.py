"""Compile the bounded Toast primitive; actions and anchor behavior stay frozen."""
import hashlib
import json
import re


REDUCED = ('@media (prefers-reduced-motion: reduce)',)
ENTER = ('@keyframes dsh-toast-in',)
TRANSLATED = {
    ('.toast', ()): 'top max-width padding gap font-size line-height border-radius background color box-shadow animation',
    ('.icon', ()): 'color',
    ('.icon.success', ()): 'color',
    ('from', ENTER): 'transform',
    ('.toast', REDUCED): 'animation',
}
# Canonical ASCII JS decimal literals, including the release's 3e3/1e3.
# CSS's existing finite parser then checks the value without executing code.
# Unlike CSS, strict ESM does not accept a legacy leading-zero integer.
JS_NUMBER = r'(?:0(?:\.[0-9]*)?|[1-9][0-9]*(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?'
CURVE = r'(?:linear|ease|ease-in|ease-out|ease-in-out)'
WS = r'[ \t\r\n\f]'


def parse_css(text, css_rules):
    # The shared reader uses Python strip(), which would erase e.g. NBSP from
    # a selector/unit even though CSS treats it as an identifier character.
    # Gate that syntax before parsing this new contract. Literal/comment text
    # is left to the existing quote-aware reader and full context fingerprint.
    syntax = re.sub(r'''/\*.*?\*/|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*' ''',
                    '', text, flags=re.S | re.X)
    if any(char.isspace() and char not in ' \t\r\n\f' for char in syntax):
        raise ValueError('unsupported non-CSS whitespace in Toast syntax')
    return css_rules(text, allow_keyframes=True)


def context_fingerprint(rules):
    shape = []
    for rule in rules:
        fields = TRANSLATED.get((rule['selector'], tuple(rule['conditions'])), '').split()
        shape.append([rule['selector'], rule['conditions'],
                      [[prop, '$translated' if prop in fields else raw]
                       for prop, raw in rule['declarations'].items()]])
    return hashlib.sha256(json.dumps(shape, ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()


def behavior_values(behavior, bundle_sha, number):
    if set(behavior) != {'bundleSha256', 'region'} or behavior['bundleSha256'] != bundle_sha:
        raise ValueError('Toast published behavior bundle identity differs')
    region = behavior['region']
    values = {}
    shape = region
    for name in ('HOLD_MS', 'FADE_MS'):
        pattern = rf'(\bconst {name} = )({JS_NUMBER})(;)'
        matches = list(re.finditer(pattern, region))
        if len(matches) != 1:
            raise ValueError('untranslated Toast timing declaration: ' + name)
        values[name] = number(matches[0][2], '')
        shape = re.sub(pattern, lambda m: m[1] + '$' + name + m[3], shape)
    if any(value < 0 for value in values.values()):
        raise ValueError('unsupported negative Toast timing')
    if hashlib.sha256(shape.encode()).hexdigest() != '84ca94880b2ce6e348c9be57e550df6edeb7577192f1002841ee4c324ef78284':
        raise ValueError('untranslated complete Toast behavior')
    return values['HOLD_MS'], values['FADE_MS']


def build(rules, behavior, *, bundle_sha, number, token, css_number):
    if context_fingerprint(rules) != '2b75fdcb0b1a0d1ab895470a58717884c826d48858e47e95d23322c347d7095f':
        raise ValueError('untranslated Toast sheet context/selector/property/condition')

    def get(selector, prop, conditions=()):
        found = [r['declarations'][prop] for r in rules
                 if r['selector'] == selector and r['conditions'] == list(conditions)
                 and prop in r['declarations']]
        if len(found) != 1:
            raise ValueError('ambiguous/missing Toast CSS input: ' + selector + '/' + prop)
        return found[0]

    def length(raw):
        if raw.endswith('px'):
            return number(raw)
        value = number(raw, '')
        if value != 0:
            raise ValueError('unsupported unitless Toast length')
        return value

    hold, fade_ms = behavior_values(behavior, bundle_sha, number)
    padding = get('.toast', 'padding').split()
    if len(padding) != 2:
        raise ValueError('unsupported Toast padding')
    cap = re.fullmatch(rf'min\(({css_number}px),{WS}*calc\(100vw - ({css_number}px)\)\)', get('.toast', 'max-width'))
    if cap is None:
        raise ValueError('unsupported Toast content-box cap')
    enter_y = re.fullmatch(rf'translate\(-50%,{WS}*({css_number}px)\)', get('from', 'transform', ENTER))
    if enter_y is None:
        raise ValueError('unsupported Toast entry transform')
    fade_pattern = rf'dsh-toast-fade{WS}+({css_number}ms){WS}+({CURVE}){WS}+var\(--dsh-toast-hold,{WS}*({css_number}ms)\){WS}+forwards'
    animation = re.fullmatch(rf'dsh-toast-in{WS}+({css_number}ms){WS}+({CURVE}),{WS}*({fade_pattern})', get('.toast', 'animation'))
    reduced = re.fullmatch(fade_pattern, get('.toast', 'animation', REDUCED))
    if animation is None or reduced is None:
        raise ValueError('unsupported Toast motion expression/curve')
    normal_fade = (number(animation[4], 'ms'), animation[5], number(animation[6], 'ms'))
    reduced_fade = (number(reduced[1], 'ms'), reduced[2], number(reduced[3], 'ms'))
    if normal_fade != reduced_fade or normal_fade[0] != fade_ms or normal_fade[2] != hold:
        raise ValueError('Toast JS/CSS/reduced-motion timing differs')
    fields = {
        'top': length(get('.toast', 'top')),
        'maxContentWidth': number(cap[1]), 'viewportInset': number(cap[2]),
        'horizontalPadding': length(padding[1]), 'verticalPadding': length(padding[0]),
        'gap': length(get('.toast', 'gap')),
        'fontSize': number(get('.toast', 'font-size')), 'lineHeight': number(get('.toast', 'line-height')),
        'radiusToken': token(get('.toast', 'border-radius')),
        'backgroundToken': token(get('.toast', 'background')), 'labelToken': token(get('.toast', 'color')),
        'shadowToken': token(get('.toast', 'box-shadow')),
        'iconLabelToken': token(get('.icon', 'color')), 'successIconLabelToken': token(get('.icon.success', 'color')),
        'holdMs': hold, 'fadeMs': fade_ms, 'enterMs': number(animation[1], 'ms'),
        'enterOffsetY': number(enter_y[1]), 'enterCurve': animation[2], 'fadeCurve': animation[5],
    }
    if any(fields[k] <= 0 for k in ('maxContentWidth', 'fontSize', 'lineHeight')) or any(
            fields[k] < 0 for k in ('viewportInset', 'horizontalPadding', 'verticalPadding', 'gap', 'enterMs')):
        raise ValueError('unsupported Toast numeric domain')
    return {'DshToastRecipe': fields}
