#!/usr/bin/env python3
"""Settings surfaces: the General section's appearance, font, permission rows and the composite column.

React host: host/settings.tsx mounts dsh's real AppearanceRow, FontSettingsGroup (FontSizeRow, FontFamilyRow),
PermissionRow and GeneralSection with fixed store snapshots, no-op writes and the real `settings.theme` /
`settings.permission` dictionaries. Flutter: the owning package's test/parity cases. Kinds and props (the same JSON
reaches both providers; `layout` is the shared column spec {direction: column, gap: 0, align: stretch}):

  settings.appearance  {layout, preference: light|dark|system}
                       parity ids: cube-light, cube-dark, cube-system
  settings.font        {layout, fontSizes: {text, code, terminal}, fontFamilies: {text, code, terminal}}
                       the text size row with its expander; the region of three font fields and the code and terminal size
                       rows appears after a real click on `font-expander` (an interaction step, never a prop)
                       parity ids: font-expander, font-{text,code,terminal}-{up,down} (stepper arrows, opacity 0 until the
                       stepper is hovered or focused), font-{text,code,terminal}-family (the text inputs)
  settings.permission  {layout, state: {status: idle|loading|ready|saving|unavailable|error, error: string|null,
                       writable: bool, currentValue: string, options: [{id, label}]}}
                       parity id: permission-selector (the closed selector pill; the menu and the full-access confirmation
                       are overlays and never captured). `unavailable` renders nothing and has no case.
  settings.general     {layout, permission: <permission state>, preference, fontSizes, fontFamilies}
                       GeneralSection with the permission (order -20), appearance (10) and font-size (11) rows in one
                       `settings.general.item` list-slot wrapper, so the section strips the last row's separator;
                       parity ids of all three rows above

The option label is what the host sends; the row shows it through dsh's displayPermissionPreset: a label equal to the
preset id (or to the English product label) of read-only / workspace-write / danger-full-access becomes the localized
product label, any other name is title-cased from its kebab-case form (`team-review` -> `Team Review`).

Sizes: viewport width 390 with the 16px frame padding gives the 358px column of the phone Settings page, density 2. The
rows are not wrapped in dsh's 800px panel. Every case height is the measured content height of the React render plus the
32px frame padding, rounded up to whole CSS pixels (the 0.5px separators make some rows fractional). Heights depend on
text wrapping at 358px, so they are encoded per case; the host checks them: a case whose content does not fill its frame
fails the React capture with the measured height. Variants of one case therefore share one height.

Ids: components.settings.<surface>.<name>.<theme>. All content is invented.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from builders_api import base_case, replace_cases, themed  # noqa: E402
from parity_lib import env, fonts  # noqa: E402

ORDER = 420
UI = 'packages/client/'
HINT_APPEARANCE = UI + 'ui-theme/src/client/AppearanceRow.tsx'
HINT_FONT = UI + 'ui-theme/src/client/FontSettingsGroup.tsx'
HINT_PERMISSION = UI + 'ui-permission-presets/src/client/PermissionRow.tsx'
HINT_GENERAL = UI + 'ui-settings-general/src/client/GeneralSection.tsx'
LAYOUT = {'direction': 'column', 'gap': 0, 'align': 'stretch'}
WIDTH = 390
PADDING = 32  # the parity frame's 16px padding on both axes

# Case heights (CSS px, frame included), measured from the React render at the 358px column; see the module docstring.
HEIGHTS = {
    'appearance.system': 363, 'appearance.zh-cn': 363,
    'font.collapsed': 126, 'font.expanded': 1315, 'font.expanded-custom': 1315, 'font.zh-cn': 1063,
    'permission.workspace-write': 145, 'permission.short-label': 127, 'permission.zh-cn': 109,
    'general.defaults': 570, 'general.zh-cn': 516, 'general.font-expanded-full': 1741,
}

DEFAULT_SIZES = {'text': 14, 'code': 11, 'terminal': 13}
NO_FAMILIES = {'text': '', 'code': '', 'terminal': ''}
CUSTOM_SIZES = {'text': 16, 'code': 13, 'terminal': 15}
CUSTOM_FAMILIES = {'text': '"Inter", sans-serif', 'code': '"JetBrains Mono", "Fira Code", monospace',
                   'terminal': '"Cascadia Mono", "苹方", monospace'}
ZH_FAMILIES = {'text': '"苹方", "微软雅黑", sans-serif', 'code': '"Fira Code", monospace', 'terminal': ''}

PRESETS = [{'id': 'read-only', 'label': 'read-only'}, {'id': 'workspace-write', 'label': 'workspace-write'},
           {'id': 'danger-full-access', 'label': 'danger-full-access'}]
CUSTOM_PRESETS = PRESETS + [{'id': 'team-review', 'label': 'team-review'}]


def permission(current='workspace-write', *, status='ready', error=None, writable=True, options=PRESETS):
    return {'status': status, 'error': error, 'writable': writable, 'currentValue': current,
            'options': [dict(o) for o in options]}


def theme_props(preference='system', sizes=DEFAULT_SIZES, families=NO_FAMILIES, **extra):
    return {'layout': LAYOUT, 'preference': preference, 'fontSizes': dict(sizes), 'fontFamilies': dict(families), **extra}


def height(key):
    return HEIGHTS[key]


def make(surface, name, title, kind, variants, hint, locale='en'):
    """One case template; `variants` is [(id, name, props, interactions)], all of the same rendered height."""
    return themed(base_case('components.settings.%s.%s' % (surface, name), title, kind,
                            {'width': WIDTH, 'height': height('%s.%s' % (surface, name)), 'density': 2}, variants,
                            locale=locale, category='extension/settings', react_hint=hint))


EXPAND = [{'type': 'click', 'target': 'font-expander'}]


def expanded(*steps):
    return EXPAND + list(steps)


# ---- appearance --------------------------------------------------------------------------------------------------
appearance = make('appearance', 'system', 'Appearance row: preference cubes', 'settings.appearance', [
    ('default', 'System selected', theme_props('system'), None),
    ('pref-light', 'Light selected', theme_props('light'), None),
    ('pref-dark', 'Dark selected', theme_props('dark'), None),
    ('hover', 'Hover on an unselected cube', theme_props('system'), [{'type': 'hover', 'target': 'cube-light'}]),
], HINT_APPEARANCE)
appearance += make('appearance', 'zh-cn', 'Appearance row in Chinese', 'settings.appearance', [
    ('default', 'System selected', theme_props('system'), None),
    ('pref-dark', 'Dark selected', theme_props('dark'), None),
], HINT_APPEARANCE, locale='zh-CN')
replace_cases('components.settings.appearance.', appearance)

# ---- font --------------------------------------------------------------------------------------------------------
font = make('font', 'collapsed', 'Font size row, region collapsed', 'settings.font', [
    ('default', 'Defaults 14 / 11 / 13', theme_props(), None),
    ('hover', 'Hover on the increase arrow', theme_props(), [{'type': 'hover', 'target': 'font-text-up'}]),
    ('minimum', 'Minimum 10, decrease arrow disabled', theme_props(sizes={**DEFAULT_SIZES, 'text': 10}),
     [{'type': 'hover', 'target': 'font-text-down'}]),
    ('maximum', 'Maximum 22, increase arrow disabled', theme_props(sizes={**DEFAULT_SIZES, 'text': 22}),
     [{'type': 'hover', 'target': 'font-text-up'}]),
], HINT_FONT)
font += make('font', 'expanded', 'Font settings expanded, default fonts', 'settings.font', [
    ('default', 'Expanded, empty font fields', theme_props(), expanded()),
    ('hover', 'Hover on the code size increase arrow', theme_props(), expanded({'type': 'hover', 'target': 'font-code-up'})),
    ('limits', 'Sizes at their limits (22 / 16 / 10), hover on the terminal decrease arrow',
     theme_props(sizes={'text': 22, 'code': 16, 'terminal': 10}), expanded({'type': 'hover', 'target': 'font-terminal-down'})),
], HINT_FONT)
font += make('font', 'expanded-custom', 'Font settings expanded, user fonts and sizes', 'settings.font', [
    ('default', 'Expanded, fonts set', theme_props(sizes=CUSTOM_SIZES, families=CUSTOM_FAMILIES), expanded()),
], HINT_FONT)
font += make('font', 'zh-cn', 'Font settings expanded in Chinese', 'settings.font', [
    ('default', 'Expanded, fonts set', theme_props(sizes=CUSTOM_SIZES, families=ZH_FAMILIES), expanded()),
], HINT_FONT, locale='zh-CN')
replace_cases('components.settings.font.', font)

# ---- permission --------------------------------------------------------------------------------------------------


def permission_props(current='workspace-write', **kwargs):
    return {'layout': LAYOUT, 'state': permission(current, **kwargs)}


perm = make('permission', 'workspace-write', 'Permission row, wrapped description', 'settings.permission', [
    ('default', 'workspace-write selected', permission_props(), None),
    ('custom', 'A host preset outside the built-in three', permission_props('team-review', options=CUSTOM_PRESETS), None),
    ('hover', 'Hover on the selector', permission_props(), [{'type': 'hover', 'target': 'permission-selector'}]),
    ('saving', 'Saving: selected label, disabled', permission_props(status='saving'), None),
    ('error', 'Error text replaces the description',
     permission_props(status='error', error='Could not save the permission default. Try again.'), None),
    ('not-writable', 'Host does not allow writes: selector disabled', permission_props(writable=False), None),
], HINT_PERMISSION)
perm += make('permission', 'short-label', 'Permission row, short selector label', 'settings.permission', [
    ('default', 'read-only selected', permission_props('read-only'), None),
    ('full-access', 'danger-full-access selected', permission_props('danger-full-access'), None),
    ('loading', 'Loading: no options yet, label Loading, disabled', permission_props('', status='loading', options=[]), None),
], HINT_PERMISSION)
perm += make('permission', 'zh-cn', 'Permission row in Chinese', 'settings.permission', [
    ('default', 'workspace-write selected', permission_props(), None),
    ('full-access', 'danger-full-access selected', permission_props('danger-full-access'), None),
    ('loading', 'Loading', permission_props('', status='loading', options=[]), None),
], HINT_PERMISSION, locale='zh-CN')
replace_cases('components.settings.permission.', perm)

# ---- general (composite) -----------------------------------------------------------------------------------------


def general_props(preference='system', sizes=DEFAULT_SIZES, families=NO_FAMILIES, current='workspace-write'):
    return theme_props(preference, sizes, families, permission=permission(current))


general = make('general', 'defaults', 'General section at defaults', 'settings.general', [
    ('default', 'Font group collapsed', general_props(), None)], HINT_GENERAL)
general += make('general', 'zh-cn', 'General section in Chinese', 'settings.general', [
    ('default', 'Font group collapsed', general_props(preference='dark'), None)], HINT_GENERAL, locale='zh-CN')
general += make('general', 'font-expanded-full', 'General section, font group expanded', 'settings.general', [
    ('default', 'Expanded, fonts set', general_props('light', CUSTOM_SIZES, CUSTOM_FAMILIES, 'read-only'), expanded())], HINT_GENERAL)
replace_cases('components.settings.general.', general)

# Every character the Chinese cases draw must have a glyph in the pinned CJK subset (tool/parity-fonts): the case props
# and the real zh dictionaries the rows read their copy from.
zh_text = ''
for case in appearance + font + perm + general:
    if case['locale'] == 'zh-CN':
        zh_text += repr(case['variants'])
for path in ('ui-theme/src/client/locales.ts', 'ui-permission-presets/src/client/locales.ts'):
    zh_text += (env.dsh_src() / UI / path).read_text(encoding='utf-8')
missing = fonts.uncovered_cjk(zh_text)
if missing:
    sys.exit('Chinese cases use characters outside the pinned CJK subset: %s' % ''.join(missing))
