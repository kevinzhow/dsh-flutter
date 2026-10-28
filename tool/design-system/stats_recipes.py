"""Compile the published, shared statistics popover and its composer trigger.

Unknown selectors, declarations, conditions and unconsumed structure fail closed.
Source CSS dimensions and release placement constants are emitted, not copied
into feature code. The panel is shared by session and per-turn statistics.
"""
from pathlib import Path
import json
import re

HERE = Path(__file__).resolve().parent


def normalized(rule, normalize_rule):
    result = normalize_rule(rule)
    result['selector'] = re.sub(r"\[aria-expanded=['\"]true['\"]\]", '[aria-expanded=true]', result['selector'])
    result['declarations'] = {
        k: re.sub(r'calc\((100vw - [\d.]+px)\)', r'\1', v)
        for k, v in result['declarations'].items()
    }
    return result


def verify_source_behavior(behavior, source):
    for name in ('PANEL_MARGIN', 'PANEL_GAP'):
        current = re.findall(r'const ' + name + r' = ([\d.]+)', source)
        release = re.findall(r'const ' + name + r' = ([\d.]+)', behavior['region'])
        if len(current) != 1 or current != release:
            raise ValueError('reference statistics placement differs from published package: ' + name)


def build(sheets, behavior, *, value, number, token, font_token):
    schema = json.loads((HERE / 'stats-contract.json').read_text())
    consumed = set()
    def get(sheet, selector, prop):
        consumed.add((sheet, selector, prop))
        return value(sheets[sheet], selector, prop)
    for name, expected in schema.items():
        rules = sheets[name]
        if (len(rules) != len(expected) or any(r['conditions'] for r in rules)
                or {r['selector'] for r in rules} != set(expected)):
            raise ValueError('untranslated statistics state/condition: ' + name)
        for rule in rules:
            if set(rule['declarations']) != set(expected[rule['selector']]):
                raise ValueError('untranslated statistics property: ' + name + ' ' + rule['selector'])
    panel, pill = 'stat-dialog.module.css', 'StatsPills.module.css'
    p = lambda selector, prop: get(panel, selector, prop)
    s = lambda selector, prop: get(pill, selector, prop)
    def px(raw):
        return 0.0 if raw == '0' else number(raw)
    def pair(raw):
        parts = raw.split()
        if len(parts) != 2:
            raise ValueError('untranslated statistics pair: ' + raw)
        return [px(part) for part in parts]
    def width(prop):
        match = re.fullmatch(r'min\(([\d.]+)px,\s*100vw - ([\d.]+)px\)', p('.panel', prop))
        if match is None:
            raise ValueError('unsupported statistics viewport width: ' + prop)
        return float(match[1]), float(match[2])
    minimum, inset = width('min-width')
    maximum, max_inset = width('max-width')
    if inset != max_inset:
        raise ValueError('statistics min/max viewport caps disagree')
    grid = re.fullmatch(r'minmax\(([\d.]+)px,\s*auto\) minmax\(0,\s*1fr\)', p('.details', 'grid-template-columns'))
    rule = re.fullmatch(r'([\d.]+)px solid var\((--[\w-]+)\)', p('.titleRule', 'border-top'))
    if grid is None or rule is None:
        raise ValueError('unsupported statistics grid or title rule')
    anchor_font = re.fullmatch(r'calc\(var\(--dsh-content-font-size-secondary,\s*([\d.]+)px\) - ([\d.]+)px\)', s('.anchor', 'font-size'))
    anchor_line = re.fullmatch(r'calc\(([\d.]+)px \+ var\(--dsh-content-font-delta-secondary,\s*0px\)\)', s('.anchor', 'line-height'))
    if anchor_font is None or anchor_line is None:
        raise ValueError('unsupported statistics content font scaling')
    size, line = px(p('.panel', 'font-size')), px(p('.panel', 'line-height'))
    row_gap, col_gap = pair(p('.details', 'gap'))
    pad_v, pad_h = pair(s('.pill', 'padding'))
    sep_v, sep_h = pair(s('.sep', 'margin'))
    if sep_v != 0:
        raise ValueError('unsupported statistics separator vertical margin')
    placement = {}
    for name in ('PANEL_MARGIN', 'PANEL_GAP'):
        values = re.findall(r'const ' + name + r' = ([\d.]+);', behavior['region'])
        if len(values) != 1:
            raise ValueError('published statistics placement missing/ambiguous: ' + name)
        placement[name] = float(values[0])
    if inset != 2 * placement['PANEL_MARGIN']:
        raise ValueError('statistics viewport width and placement margins disagree')
    icon = px(p('.titleLabel svg', 'width'))
    if px(p('.titleLabel svg', 'height')) != icon:
        raise ValueError('non-square statistics heading icon')
    pill_icon = px(s('.pill svg', 'width'))
    if px(s('.pill svg', 'height')) != pill_icon:
        raise ValueError('non-square statistics pill icon')
    metrics = {
        'DshStatPanelRecipe': {
            'minWidth': minimum, 'maxWidth': maximum,
            'viewportMargin': placement['PANEL_MARGIN'], 'anchorGap': placement['PANEL_GAP'],
            'padding': px(p('.panel', 'padding')), 'radiusToken': token(p('.panel', 'border-radius')),
            'fillToken': token(p('.panel', 'background')), 'shadowToken': token(p('.panel', 'box-shadow')),
            'strokeToken': token(p('.panel', '--dsw-elevation-stroke-color')),
            'fontSize': size, 'lineHeight': line, 'fontToken': font_token(size, line),
            'labelToken': token(p('.panel', 'color')), 'titleToken': token(p('.title', 'color')),
            'titleWeight': number(p('.title', 'font-weight'), ''),
            'titleGap': px(p('.title', 'gap')), 'titleBottomMargin': px(p('.title', 'margin-bottom')),
            'ruleBottomMargin': px(p('.titleRule', 'margin-bottom')),
            'ruleWidth': float(rule[1]), 'ruleToken': rule[2],
            'iconSize': icon, 'iconGap': px(p('.titleLabel', 'gap')),
            'labelMinWidth': float(grid[1]), 'rowGap': row_gap, 'columnGap': col_gap,
            'detailLabelToken': token(p('.details', 'color')),
            'detailValueToken': token(p('.details dd', 'color')),
        },
        'DshStatsPillRecipe': {
            'fontBase': float(anchor_font[1]) - float(anchor_font[2]),
            'lineBase': float(anchor_line[1]), 'fontScale': 'secondary',
            'paddingVertical': pad_v, 'paddingHorizontal': pad_h,
            'gap': px(s('.pill', 'gap')), 'iconSize': pill_icon,
            'radiusToken': token(s('.pill', 'border-radius')),
            'labelToken': token(s('.pill', 'color')),
            'activeLabelToken': token(s('button.pill:hover,button.pill[aria-expanded=true]', 'color')),
            'activeFillToken': token(s('button.pill:hover,button.pill[aria-expanded=true]', 'background')),
            'separatorToken': token(s('.sep', 'color')), 'separatorMargin': sep_h,
        },
    }
    if (minimum <= 0 or maximum < minimum
            or metrics['DshStatPanelRecipe']['titleWeight'] not in range(100, 1000, 100)):
        raise ValueError('unsupported statistics width bounds or title weight')
    # Explicitly support source filtering and width/ellipsis contracts. A new
    # surface or layout model must be implemented before these can change.
    for name, rules in schema.items():
        for selector, props in rules.items():
            for prop, expected in props.items():
                if ((name, selector, prop) not in consumed
                        and value(sheets[name], selector, prop) != expected):
                    raise ValueError('untranslated statistics structure: ' + name + ' ' + selector + '/' + prop)
    return metrics
