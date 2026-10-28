"""Compile the actual published ModelSelect menu profile, not a phone sheet."""
import re


def normalize(rule, normalize_rule):
    rule = normalize_rule(rule)
    props = rule['declarations']
    if props.get('flex') == '0 0 auto': props['flex'] = 'none'
    if props.get('flex') == '1 1 auto': props['flex'] = 'auto'
    if props.get('transition') == 'transform 120ms ease': props['transition'] = 'transform .12s'
    if props.get('border') == '0 solid transparent': props['border'] = '0 solid #0000'
    if props.get('border-color') == 'transparent': props['border-color'] = '#0000'
    for prop in ('min-width', 'max-width', 'max-height'):
        if prop in props:
            props[prop] = re.sub(r'calc\((100v[wh] - [\d.]+px)\)', r'\1', props[prop])
    return rule

RULES = {
    '.root': 'min-width position',
    '.trigger': 'border-radius min-width max-width height color cursor background border outline align-items gap padding font-size font-weight line-height display',
    '.trigger:hover:not(:disabled)': 'background',
    '.trigger:focus-visible:not([data-selection-focus])': 'box-shadow',
    '.trigger:disabled': 'color cursor',
    '.triggerLabel': 'text-overflow white-space min-width overflow',
    '.triggerEffort': 'text-overflow white-space min-width color flex-shrink overflow',
    '.triggerIcon': 'display flex',
    '.triggerLabel,.triggerEffort': 'display',
    '.chevron': 'color flex transition',
    '.chevronOpen': 'transform',
    '.menu': 'z-index --dsw-elevation-stroke-color width min-width max-width max-height box-shadow color --dsh-scrollbar-thumb --dsh-scrollbar-thumb-hover border flex-direction padding display position overflow',
    '.status,.empty': 'color padding font-size line-height',
    '.error,.warning': 'border-radius background color justify-content align-items gap margin-bottom padding font-size line-height display',
    '.warning': 'background color',
    '.retry': 'color font cursor background border flex padding font-weight',
    '.searchRow': 'flex-shrink margin position',
    '.searchRow .search': 'border-radius background border height padding display',
    '.searchRow .searchWithQuery': 'padding-right',
    '.searchClear': 'corner-shape width height color cursor background border border-radius justify-content align-items padding display position top right transform',
    '.searchClear:hover,.searchClear:focus-visible': 'background outline',
    '.searchRow .search:focus-within': 'border-color',
    '.searchRow .search input': 'padding font-size line-height',
    '.searchRow .search input::placeholder': 'color',
    '.groups': 'min-height overflow-y',
    '.option': 'box-sizing border-radius width min-width min-height color text-align cursor background border outline align-items gap padding display',
    '.option:not(.modelOption):hover:not(:disabled),.option:focus-visible,.optionActive:not(:disabled)': 'background',
    '.selected': 'background',
    '.option:disabled': 'color cursor',
    '.optionCopy': 'flex-direction flex min-width display',
    '.modelName': 'color text-overflow white-space font-size font-weight line-height overflow',
    '.check': 'color flex place-items display',
    '.check svg': 'width height',
    '.cell': 'box-sizing border-radius width min-width height color cursor text-align background border outline align-items gap padding font-size line-height display',
    '.cell:hover,.cell:focus-visible': 'background',
    '.cellLabel': 'white-space flex',
    '.cellValue': 'text-overflow white-space text-align min-width color flex overflow',
    '.cellChevron': 'width height color flex',
}


def build(rules, behavior, *, value, number, token, font_token, font_size_token):
    seen = set()
    for rule in rules:
        selector = rule['selector']
        if (selector in seen or rule['conditions'] or selector not in RULES
                or set(rule['declarations']) != set(RULES[selector].split())):
            raise ValueError('untranslated model menu state/property: ' + selector)
        seen.add(selector)
    if seen != set(RULES):
        raise ValueError('missing model menu state')
    def get(selector, prop): return value(rules, selector, prop)
    def px(selector, prop): return number(get(selector, prop))
    def dimensions(raw, count):
        parts = raw.split()
        if len(parts) != count:
            raise ValueError('unsupported model menu padding')
        return [0.0 if p == '0' else number(p) for p in parts]
    for selector, prop, expected in [
        ('.menu', 'position', 'fixed'), ('.menu', 'width', 'max-content'),
        ('.menu', 'overflow', 'hidden'), ('.groups', 'overflow-y', 'auto'),
        ('.selected', 'background', 'transparent'),
        ('.cellValue', 'text-overflow', 'ellipsis'),
    ]:
        if get(selector, prop) != expected:
            raise ValueError('untranslated model menu structure: ' + selector + '/' + prop)
    bounds = []
    for prop, viewport in [('min-width', 'vw'), ('max-width', 'vw'), ('max-height', 'vh')]:
        match = re.fullmatch(r'min\(([^,]+),100' + viewport + r' - ([^)]+)\)', get('.menu', prop))
        if match is None:
            raise ValueError('unsupported model menu viewport bound: ' + prop)
        bounds.extend([number(match[1]), number(match[2])])
    if bounds[1] != bounds[3]:
        raise ValueError('untranslated model menu min/max viewport inset mismatch')
    placement = re.search(r'const MARGIN = ([\d.]+);.*?let x = rect.right - lw;.*?let y = rect.top - ([\d.]+) - lh;', behavior, re.S)
    if placement is None or not all(s in behavior for s in [
        'Math.min(Math.max(x, MARGIN), window.innerWidth - lw - MARGIN)',
        'Math.min(Math.max(y, MARGIN), window.innerHeight - lh - MARGIN)',
    ]):
        raise ValueError('untranslated model menu placement')
    trigger_cap = re.fullmatch(r'min\(([\d.]+)px,([\d.]+)cqw\)', get('.trigger', 'max-width'))
    if trigger_cap is None:
        raise ValueError('unsupported model trigger width cap')
    ty, tx = dimensions(get('.option', 'padding'), 2)
    cell_y, cell_x = dimensions(get('.cell', 'padding'), 2)
    trigger_y, trigger_r, _, trigger_l = dimensions(get('.trigger', 'padding'), 4)
    size, line = px('.modelName', 'font-size'), px('.modelName', 'line-height')
    cell_size, cell_line = px('.cell', 'font-size'), px('.cell', 'line-height')
    status_size, status_line = px('.status,.empty', 'font-size'), px('.status,.empty', 'line-height')
    error_y, error_x = dimensions(get('.error,.warning', 'padding'), 2)
    search_y, search_x = dimensions(get('.searchRow .search', 'padding'), 2)
    search_top, _, search_bottom = dimensions(get('.searchRow', 'margin'), 3)
    return {'DshModelMenuRecipe': {
        'minWidth': bounds[0], 'viewportWidthInset': bounds[1],
        'maxWidth': bounds[2], 'maxHeight': bounds[4], 'viewportHeightInset': bounds[5],
        'portalMargin': float(placement[1]), 'anchorGap': float(placement[2]),
        'padding': px('.menu', 'padding'),
        'rowHeight': px('.option', 'min-height'), 'rowGap': px('.option', 'gap'),
        'rowHorizontalPadding': tx, 'rowVerticalPadding': ty,
        'rowFontSize': size, 'rowLineHeight': line, 'rowFontToken': font_token(size, cell_line),
        'rowFontWeight': number(get('.modelName', 'font-weight'), ''),
        'radiusToken': token(get('.option', 'border-radius')),
        'labelToken': token(get('.menu', 'color')),
        'disabledToken': token(get('.option:disabled', 'color')),
        'hoverToken': token(get('.cell:hover,.cell:focus-visible', 'background')),
        'checkSize': px('.check svg', 'width'), 'checkToken': token(get('.check', 'color')),
        'cellHeight': px('.cell', 'height'), 'cellGap': px('.cell', 'gap'),
        'cellHorizontalPadding': cell_x, 'cellVerticalPadding': cell_y,
        'cellFontSize': cell_size, 'cellLineHeight': cell_line, 'cellFontToken': font_token(cell_size, cell_line),
        'valueToken': token(get('.cellValue', 'color')),
        'chevronSize': px('.cellChevron', 'width'), 'chevronToken': token(get('.cellChevron', 'color')),
        'triggerHeight': px('.trigger', 'height'), 'triggerGap': px('.trigger', 'gap'),
        'triggerMaxWidth': float(trigger_cap[1]), 'triggerWidthFactor': float(trigger_cap[2]) / 100,
        'triggerRadiusToken': token(get('.trigger', 'border-radius')),
        'triggerLeftPadding': trigger_l, 'triggerRightPadding': trigger_r,
        'triggerFontToken': font_token(px('.trigger', 'font-size'), px('.trigger', 'line-height')),
        'triggerFontSize': px('.trigger', 'font-size'), 'triggerLineHeight': px('.trigger', 'line-height'),
        'triggerFontWeight': number(get('.trigger', 'font-weight'), ''),
        'triggerLabelToken': token(get('.trigger', 'color')),
        'triggerEffortToken': token(get('.triggerEffort', 'color')),
        'statusPadding': px('.status,.empty', 'padding'), 'statusFontSize': status_size,
        'statusLineHeight': status_line, 'statusFontToken': font_token(status_size, status_line),
        'statusToken': token(get('.status,.empty', 'color')),
        'errorHorizontalPadding': error_x, 'errorVerticalPadding': error_y,
        'errorGap': px('.error,.warning', 'gap'), 'errorBottomMargin': px('.error,.warning', 'margin-bottom'),
        'errorFontSize': px('.error,.warning', 'font-size'), 'errorLineHeight': px('.error,.warning', 'line-height'),
        'errorFontToken': font_size_token(px('.error,.warning', 'font-size')),
        'retryFontWeight': number(get('.retry', 'font-weight'), ''),
        'errorFillToken': token(get('.error,.warning', 'background')),
        'errorLabelToken': token(get('.error,.warning', 'color')),
        'warningFillToken': token(get('.warning', 'background')), 'warningLabelToken': token(get('.warning', 'color')),
        'searchHorizontalPadding': search_x, 'searchVerticalPadding': search_y,
        'searchTopMargin': search_top, 'searchBottomMargin': search_bottom,
        'searchClearSize': px('.searchClear', 'width'), 'searchClearRight': px('.searchClear', 'right'),
        'searchQueryRightPadding': px('.searchRow .searchWithQuery', 'padding-right'),
        'searchFontSize': px('.searchRow .search input', 'font-size'),
        'scrollbarToken': token(get('.menu', '--dsh-scrollbar-thumb')),
        'scrollbarHoverToken': token(get('.menu', '--dsh-scrollbar-thumb-hover')),
    }}
