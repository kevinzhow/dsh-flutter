"""Compile the published headed RiskConfirmation profile, including its cap."""
import re


RULES = {
    '.confirmation': 'width max-height overflow',
    '.confirmationContent': 'min-height overflow-y overscroll-behavior',
    '.warning': 'display align-items gap color font-size line-height',
    '.warning p': 'margin',
    '.warningIcon': 'flex margin-top color',
    '.acknowledgement': 'display align-items gap margin-top color font-size line-height cursor',
    '.acknowledgement input': 'flex width height margin accent-color cursor',
    '.acknowledgement input:focus-visible': 'outline outline-offset',
    '.acknowledgement input:disabled': 'cursor',
    '.modalAction': 'min-width',
    '.confirmAction': 'min-width',
}
SUPPORTS = '@supports (height: 100dvh)'


def warning_icon_size(behavior):
    icon = re.findall(
        r'IconWarningOutlineRegular,\s*\{\s*size:\s*([\d.]+),\s*'
        r'className:\s*([A-Za-z_$][\w$]*)\.warningIcon\s*\}', behavior)
    if len(icon) != 1:
        raise ValueError('published risk warning icon declaration changed')
    # These are structural contracts of the published risk profile, not layout
    # hints: the complete header/body content scrolls while the footer is a
    # separate Modal property, and the acknowledgement owns initial focus.
    fragments = (
        r'onClose:\s*onCancel,\s*title,\s*closeLabel,',
        r'className:\s*([A-Za-z_$][\w$]*)\.confirmation\s*\?\?\s*"",\s*'
        r'contentClassName:\s*\1\.confirmationContent\s*\?\?\s*"",\s*footer:',
        r'variant:\s*"outline",\s*className:\s*[\w$]+\.modalAction,\s*onClick:\s*onCancel,',
        r'variant:\s*"primary",\s*className:\s*[\w$]+\.confirmAction,\s*'
        r'disabled:\s*disabled\s*\|\|\s*!acknowledged,\s*onClick:\s*onConfirm,',
        r'type:\s*"checkbox",\s*checked:\s*acknowledged,\s*disabled,\s*'
        r'"data-modal-autofocus":\s*true,',
        r'onChange:\s*\(event\)\s*=>\s*\{\s*'
        r'onAcknowledgedChange\(event\.currentTarget\.checked\);\s*\}',
    )
    if any(len(re.findall(fragment, behavior)) != 1 for fragment in fragments):
        raise ValueError('untranslated published risk content/footer/control structure')
    return float(icon[0][0])


def verify_source_icon(behavior, source):
    icons = re.findall(r'<IconWarningOutlineRegular\s+size=\{([\d.]+)\}\s+'
                       r'className=\{css\.warningIcon\}\s*/>', source)
    if len(icons) != 1 or float(icons[0]) != warning_icon_size(behavior):
        raise ValueError('reference risk warning icon differs from its published bundle')


def build(rules, behavior, *, value, number, token, font_token):
    seen = set()
    for rule in rules:
        selector, props, conditions = rule['selector'], rule['declarations'], rule['conditions']
        key = (selector, tuple(conditions))
        if key in seen:
            raise ValueError('duplicate risk dialog state: ' + selector)
        seen.add(key)
        if conditions:
            if conditions != [SUPPORTS] or selector != '.confirmation' or set(props) != {'max-height'}:
                raise ValueError('untranslated risk dialog conditional state: ' + selector)
        elif selector not in RULES or set(props) != set(RULES[selector].split()):
            raise ValueError('untranslated risk dialog state/property: ' + selector)
    required = {(selector, ()) for selector in RULES} | {('.confirmation', (SUPPORTS,))}
    if seen != required:
        raise ValueError('missing risk dialog state')

    def get(selector, prop): return value(rules, selector, prop)
    def px(selector, prop):
        raw = get(selector, prop)
        return 0.0 if raw == '0' else number(raw)
    for selector, declarations in {
        '.confirmation': {'overflow': 'hidden'},
        '.confirmationContent': {'overflow-y': 'auto', 'overscroll-behavior': 'contain'},
        '.warning': {'display': 'flex', 'align-items': 'flex-start'},
        '.warning p': {'margin': '0'},
        '.warningIcon': {'flex': 'none'},
    }.items():
        for prop, expected in declarations.items():
            if get(selector, prop) != expected:
                raise ValueError('untranslated risk dialog structure: ' + selector + '/' + prop)

    width = re.fullmatch(r'min\(([^,]+),\s*100%\)', get('.confirmation', 'width'))
    height = re.fullmatch(r'([\d.]+)%', get('.confirmation', 'max-height'))
    dynamic = next(rule['declarations']['max-height'] for rule in rules if rule['conditions'])
    cap = re.fullmatch(r'calc\(100dvh - ([^)]+)\)', dynamic)
    if width is None or height is None or cap is None:
        raise ValueError('unsupported risk dialog bounded width or dynamic viewport cap')
    size, line = px('.warning', 'font-size'), px('.warning', 'line-height')
    recipe = {
        'width': number(width[1]), 'maxHeightFactor': float(height[1]) / 100,
        'dynamicViewportInset': number(cap[1]), 'contentMinHeight': px('.confirmationContent', 'min-height'),
        'warningGap': px('.warning', 'gap'), 'warningFontSize': size, 'warningLineHeight': line,
        'warningFontToken': font_token(size, line), 'warningLabelToken': token(get('.warning', 'color')),
        'warningIconTop': px('.warningIcon', 'margin-top'), 'warningIconSize': warning_icon_size(behavior),
        'errorIconToken': token(get('.warningIcon', 'color')),
        'actionMinWidth': px('.modalAction', 'min-width'), 'confirmMinWidth': px('.confirmAction', 'min-width'),
    }
    if (recipe['width'] <= 0 or not 0 < recipe['maxHeightFactor'] <= 1
            or any(recipe[field] < 0 for field in ('dynamicViewportInset', 'contentMinHeight', 'warningGap',
                                                  'warningIconTop', 'actionMinWidth', 'confirmMinWidth'))
            or recipe['warningIconSize'] <= 0):
        raise ValueError('invalid risk dialog geometry')
    return {'DshRiskDialogRecipe': recipe}
