"""Actual existing PluginManager toolbar using the canonical iconAction profile.

Native pairing/repair/scanner routes adopt this profile; they have no exact Web
page counterpart. These real manager screens supplement the source profile
state matrix and native route callback checks.
"""
from builders_api import base_case, replace_cases, themed

ORDER = 472
cases = []
for state in ('idle', 'hover'):
    for device, viewport, density in [('desktop', 800, 1), ('phone', 390, 2.625)]:
        for locale in ('en', 'zh-CN'):
            interactions = ([{'type': 'hover', 'target': 'plugin-refresh'},
                             {'type': 'wait', 'ms': 600}] if state == 'hover' else None)
            case = base_case(
                f'components.icon-actions.manager-refresh-{state}-{device}-{locale.split("-")[0]}',
                f'Actual PluginManager refresh action ({state})', 'plugins-preview.manager',
                {'width': viewport, 'height': 1100, 'density': density},
                [('default', state, {'width': 720 if device == 'desktop' else 326,
                                    'height': 900, 'name': 'populated'}, interactions)],
                locale=locale, category='extension/icon-actions',
                react_hint='packages/client/ui-plugin-manager/src/client/PluginManagerPage.tsx',
                flutter_hint='features/dsh_feature_plugins/lib/src/manager_page.dart')
            case['capture'] = {'selector': '[data-parity-id="plugins-preview-surface"]',
                               'flutterKey': 'plugins-preview-surface', 'crop': 'element'}
            cases += themed(case)
replace_cases('components.icon-actions.manager-refresh-', cases)
