"""Loaded package cards only; all other manager CSS/behavior stays frozen."""
import hashlib
import json
import re

TRANSLATED_FIELDS = {
    '.cards': 'gap', '.card': 'margin border-radius', '.cardHead': 'gap padding',
    '.cardIcon': 'border border-radius width height color', '.cardMain': 'gap',
    '.titleRow': 'gap', '.cardTitle': 'font-size font-weight line-height',
    '.cardOpen': 'font-size font-weight line-height', '.cardOpen:after': 'border-radius',
    '.cardLink:hover': 'background', '.cardOpen:focus-visible:after': 'outline outline-offset',
    '.cardDesc': 'color -webkit-line-clamp font-size line-height', '.cardEnd': 'gap',
    '.reason': 'color font-size line-height', '.statusTag': 'height padding font-size line-height',
}
SOURCE_SELECTOR_ALIASES = {
    '.cardOpen::after': '.cardOpen:after',
    '.cardOpen:focus-visible::after': '.cardOpen:focus-visible:after',
}


def verify_source(published, source, normalize):
    def fields(rules):
        found = {}
        for original in rules:
            rule = normalize(original)
            selector = SOURCE_SELECTOR_ALIASES.get(rule['selector'], rule['selector'])
            if rule['conditions']:
                continue  # Full-sheet context separately freezes every condition.
            for prop in TRANSLATED_FIELDS.get(selector, '').split():
                if prop in rule['declarations']:
                    key = selector, prop
                    if key in found:
                        raise ValueError('duplicate loaded card source value')
                    found[key] = rule['declarations'][prop]
        return found
    if fields(published) != fields(source):
        raise ValueError('reference loaded card CSS differs from pinned published package')


def behavior_values(behavior, bundle_sha):
    if behavior.get('bundleSha256') != bundle_sha:
        raise ValueError('loaded card published behavior bundle identity differs')
    region = behavior['region']
    presentation = behavior['presentationRegion']
    integer = r'(?:0|[1-9][0-9]*)'
    artwork_pattern = rf'\bconst CARD_ARTWORK_SIZE = ({integer});'
    prefix_pattern = r'(\bfunction packageText\(pkg, resolveText\) \{.*?\bbeta: pkg\.name\.startsWith\()("(?:\\.|[^"\\])*")(\))'
    sizes, prefixes = re.findall(artwork_pattern, region), re.findall(prefix_pattern, presentation, re.S)
    if len(sizes) != 1 or len(prefixes) != 1:
        raise ValueError('untranslated loaded card artwork/prefix declarations')
    size, prefix = float(sizes[0]), json.loads(prefixes[0][1])
    if not 0 < size < float('inf') or not re.fullmatch(r'@[a-z0-9._-]+/[a-z0-9._-]+-', prefix):
        raise ValueError('unsupported loaded card artwork size or package prefix')
    # Freeze exact complete released region, including all predicates, labels,
    # callbacks, image fallback and pending List/highlight/lifetime branches.
    # Only the two consumed values are replaced; never strip literal whitespace.
    shape = re.sub(artwork_pattern, 'const CARD_ARTWORK_SIZE = ARTWORK;', region)
    presentation_shape = re.sub(prefix_pattern, lambda m: m[1] + 'PREFIX' + m[3], presentation, flags=re.S)
    fingerprint = hashlib.sha256(json.dumps([shape, presentation_shape], ensure_ascii=False, separators=(',', ':')).encode()).hexdigest()
    if fingerprint != 'd27c897ad046cf82d09786448a52ee9065a09771b043fabed612809e8ff49995':
        raise ValueError('untranslated loaded card published behavior')
    return size, prefix


def build(rules, behavior, *, bundle_sha, value, number, token, css_number):
    get = lambda selector, prop: value(rules, selector, prop)
    px = lambda selector, prop: number(get(selector, prop))
    tok = lambda selector, prop: token(get(selector, prop))
    fixed = {
        '.cards': {'display': 'flex', 'flex-direction': 'column', 'margin': '0', 'padding': '0', 'list-style': 'none'},
        '.card': {'min-width': '0'}, '.cardHead': {'display': 'flex', 'align-items': 'center'},
        '.cardIcon': {'display': 'inline-flex', 'flex': 'none', 'align-items': 'center', 'justify-content': 'center'},
        '.packageImage': {'object-fit': 'contain'},
        '.cardMain': {'display': 'flex', 'flex-direction': 'column', 'flex': '1', 'min-width': '0'},
        '.titleRow': {'display': 'flex', 'align-items': 'center', 'flex-wrap': 'wrap', 'min-width': '0'},
        '.cardTitle': {'text-overflow': 'ellipsis', 'white-space': 'nowrap', 'overflow': 'hidden'},
        '.cardLink': {'position': 'relative'},
        '.cardOpen': {'max-width': '100%', 'color': 'inherit', 'font': 'inherit', 'text-align': 'left', 'cursor': 'pointer', 'background': '0 0', 'border': '0', 'padding': '0'},
        '.cardOpen:after': {'content': '""', 'position': 'absolute', 'inset': '0'},
        '.cardOpen:focus-visible': {'outline': 'none'},
        '.cardDesc': {'-webkit-box-orient': 'vertical', 'display': '-webkit-box', 'overflow': 'hidden'},
        '.cardEnd': {'display': 'inline-flex', 'position': 'relative', 'flex': 'none', 'align-items': 'center', 'z-index': '1'},
        '.reason': {'overflow-wrap': 'anywhere', 'white-space': 'pre-wrap', 'margin': '0'},
    }
    for selector, props in fixed.items():
        if any(get(selector, prop) != expected for prop, expected in props.items()):
            raise ValueError('untranslated loaded card structure: ' + selector)
    for prop in ('font-size', 'font-weight', 'line-height'):
        unit = '' if prop == 'font-weight' else 'px'
        if number(get('.cardTitle', prop), unit) != number(get('.cardOpen', prop), unit):
            raise ValueError('untranslated differing loaded card title typography')
    if tok('.card', 'border-radius') != tok('.cardOpen:after', 'border-radius'):
        raise ValueError('untranslated differing loaded card focus contour')
    margin = get('.card', 'margin').split()
    if len(margin) != 2 or margin[0] != '0':
        raise ValueError('unsupported loaded card margin')
    border = re.fullmatch(rf'({css_number}px) solid (var\(--[\w-]+\))', get('.cardIcon', 'border'))
    focus = re.fullmatch(r'var\((--[\w-]+)\) solid var\((--[\w-]+),\s*var\((--[\w-]+)\)\)', get('.cardOpen:focus-visible:after', 'outline'))
    if border is None or focus is None:
        raise ValueError('unsupported loaded card frame/focus expression')
    artwork, prefix = behavior_values(behavior, bundle_sha)
    card = {
        'horizontalMargin': number(margin[1]), 'radiusToken': tok('.card', 'border-radius'),
        'hoverToken': tok('.cardLink:hover', 'background'), 'headGap': px('.cardHead', 'gap'),
        'headPadding': px('.cardHead', 'padding'), 'iconWidth': px('.cardIcon', 'width'),
        'iconHeight': px('.cardIcon', 'height'), 'iconBorderWidth': number(border[1]),
        'iconBorderToken': token(border[2]), 'iconRadiusToken': tok('.cardIcon', 'border-radius'),
        'iconLabelToken': tok('.cardIcon', 'color'), 'artworkSize': artwork,
        'mainGap': px('.cardMain', 'gap'), 'titleRowGap': px('.titleRow', 'gap'),
        'titleFontSize': px('.cardTitle', 'font-size'), 'titleLineHeight': px('.cardTitle', 'line-height'),
        'titleWeight': number(get('.cardTitle', 'font-weight'), ''),
        'titleMaxLines': 1.0 if get('.cardTitle', 'white-space') == 'nowrap' else None,
        'descriptionFontSize': px('.cardDesc', 'font-size'), 'descriptionLineHeight': px('.cardDesc', 'line-height'),
        'descriptionMaxLines': number(get('.cardDesc', '-webkit-line-clamp'), ''),
        'descriptionToken': tok('.cardDesc', 'color'), 'endGap': px('.cardEnd', 'gap'),
        'focusWidthToken': token('var(' + focus[1] + ')'),
        'focusToken': token('var(' + focus[2] + ')', inherits_if_unset=True),
        'focusFallbackToken': token('var(' + focus[3] + ')'),
        'focusOffset': px('.cardOpen:focus-visible:after', 'outline-offset'),
        'errorFontSize': px('.reason', 'font-size'), 'errorLineHeight': px('.reason', 'line-height'),
        'errorToken': tok('.reason', 'color'), 'experimentalPrefix': prefix,
    }
    padding = get('.statusTag', 'padding').split()
    if len(padding) != 2: raise ValueError('unsupported plugin status tag padding')
    length = lambda raw: number(raw, '') if raw in ('0', '+0', '-0') else number(raw)
    status = {'contentHeight': px('.statusTag', 'height'), 'verticalPadding': length(padding[0]),
              'horizontalPadding': length(padding[1]), 'fontSize': px('.statusTag', 'font-size'),
              'lineHeightFactor': number(get('.statusTag', 'line-height'), '')}
    positive = ('iconWidth', 'iconHeight', 'artworkSize', 'titleFontSize', 'titleLineHeight',
                'descriptionFontSize', 'descriptionLineHeight', 'errorFontSize', 'errorLineHeight')
    nonnegative = ('headGap', 'headPadding', 'iconBorderWidth', 'mainGap', 'titleRowGap', 'endGap')
    lines = card['descriptionMaxLines']
    gap = px('.cards', 'gap')
    if (any(card[k] <= 0 for k in positive) or any(card[k] < 0 for k in nonnegative)
            or card['titleWeight'] not in range(100, 1000, 100)
            or lines <= 0 or not lines.is_integer() or gap < 0
            or any(status[k] <= 0 for k in ('contentHeight', 'fontSize', 'lineHeightFactor'))
            or min(status['verticalPadding'], status['horizontalPadding']) < 0):
        raise ValueError('unsupported loaded card/status dimensions or typography')
    return {'DshPluginCardListRecipe': {'gap': gap}, 'DshPluginCardRecipe': card,
            'DshPluginStatusTagRecipe': status}
