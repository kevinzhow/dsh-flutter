"""Compile the published HeaderLeadingControls profile, without executing JS.

This profile is deliberately separate from SidebarRoot's iconButton: the
Header keeps its secondary label in every state and defines only :hover.
"""
import hashlib
import re


# All three rules, including structural declarations and conditional scope.
SHAPE = [
    ('.controls', (), ('align-items', 'display', 'gap')),
    ('.iconButton', (), ('align-items', 'background', 'border', 'border-radius',
                        'color', 'cursor', 'display', 'flex', 'height',
                        'justify-content', 'padding', 'width')),
    ('.iconButton:hover', (), ('background',)),
]


def behavior_values(region):
    # The immutable release skeleton covers both labels/shortcuts, native
    # button type, callbacks, class bindings and icon identities. Only the two
    # repeated numeric inputs are translated. Unknown behavior fails closed.
    body = re.sub(r'/\*[\s\S]*?\*/|//[^\n]*', '', region)
    delays = re.findall(r'\bdelayMs:\s*(\d+)\s*,', body)
    sizes = re.findall(r'\bsize:\s*(\d+)\s*}', body)
    if (len(delays) != 2 or len(set(delays)) != 1 or
            len(sizes) != 2 or len(set(sizes)) != 1 or int(sizes[0]) <= 0):
        raise ValueError('untranslated HeaderLeadingControls repeated timing/icon inputs')
    shape = re.sub(r'delayMs:\s*\d+', 'delayMs: DELAY', body)
    shape = re.sub(r'size:\s*\d+', 'size: ICON_SIZE', shape)
    digest = hashlib.sha256(re.sub(r'\s+', '', shape).encode()).hexdigest()
    # ui-sidebar 0.2.1-rc.2 client.js HeaderLeadingControls.js region, with
    # numeric inputs replaced above. Region bytes remain in the locked JSON.
    if digest != 'd16309f6a44f1281de6d4d045f7a8fb6ce38d3e0abb37344275fa6e411325abe':
        raise ValueError('untranslated HeaderLeadingControls behavior')
    return int(delays[0]), float(sizes[0])


def focus_values(context, token):
    focus = context['focus']
    if (len(focus) != 3 or any(r['conditions'] for r in focus) or
            focus[0]['selector'] != ':root' or
            focus[0]['declarations'] != {'--dsw-focus-ring-width': '2px'} or
            focus[1]['selector'] != ':focus-visible' or
            set(focus[1]['declarations']) != {'outline-color', 'outline-width'} or
            focus[2]['selector'] != 'html[data-input-modality=pointer] body :focus-visible:not(:read-write)' or
            focus[2]['declarations'] != {'--dsw-focus-ring-color': 'transparent', 'outline-color': '#0000'}):
        raise ValueError('untranslated HeaderLeadingControls global focus structure')
    color = re.fullmatch(r'var\((--[\w-]+),var\((--[\w-]+)\)\)', focus[1]['declarations']['outline-color'])
    if color is None:
        raise ValueError('untranslated HeaderLeadingControls global focus color')
    region = context['inputModality']['region']
    body = re.sub(r'/\*[\s\S]*?\*/|//[^\n]*', '', region)
    if hashlib.sha256(re.sub(r'\s+', '', body).encode()).hexdigest() != '302331c7cfbc02ce0873fc6c4ed77e08e3287418ed0a0f9f9225c4121cfc47c8':
        raise ValueError('untranslated HeaderLeadingControls input modality')
    return {'focusWidthToken': token(focus[1]['declarations']['outline-width']),
            'focusToken': token('var(' + color[1] + ')', inherits_if_unset=True),
            'focusFallbackToken': token('var(' + color[2] + ')')}


def build(sheet, behavior, *, focus_context, number, token):
    actual = [(r['selector'], tuple(r['conditions']),
               tuple(sorted(r['declarations']))) for r in sheet]
    if actual != SHAPE:
        raise ValueError('untranslated HeaderLeadingControls state/property/condition')
    controls, button, hover = [r['declarations'] for r in sheet]
    for declarations, required in [
        (controls, {'align-items': 'center', 'display': 'flex'}),
        (button, {'align-items': 'center', 'justify-content': 'center',
                  'background': '0 0', 'border': 'none', 'cursor': 'pointer',
                  'display': 'inline-flex', 'flex': 'none', 'padding': '0'}),
    ]:
        if any(declarations[key] != val for key, val in required.items()):
            raise ValueError('untranslated HeaderLeadingControls structural value')
    delay, icon = behavior_values(behavior['region'])
    width, height, gap = (number(button['width']), number(button['height']),
                          number(controls['gap']))
    if width <= 0 or height <= 0 or gap < 0:
        raise ValueError('untranslated HeaderLeadingControls dimensions')
    return {'DshHeaderLeadingRecipe': {
        'width': width, 'height': height, 'controlsGap': gap,
        'iconSize': icon, 'tooltipDelayMs': delay,
        'radiusToken': token(button['border-radius']),
        'labelToken': token(button['color']),
        'hoverToken': token(hover['background']),
        **focus_values(focus_context, token),
    }}
