"""Segmented controls in the real plugin manager and agent preset guide."""
from builders_api import base_case, replace_cases, themed

ORDER = 478
cases = []
for device, viewport, density in [('desktop', 800, 1), ('phone', 390, 2.625)]:
    for locale in ['en', 'zh-CN']:
        for family in ['manager', 'guide']:
            group = 'plugin-manager-tabs' if family == 'manager' else 'preset-guide-tabs'
            first = 'plugin-manager-tab-installed' if family == 'manager' else 'preset-guide-tab-explanation'
            other = 'plugin-manager-tab-discover' if family == 'manager' else 'preset-guide-tab-usage'
            for state in ['initial', 'other', 'hover', 'focus']:
                steps = [] if family == 'manager' else [{'type': 'click', 'target': 'preset-guide-standard-details'}]
                if state == 'other': steps.append({'type': 'click', 'target': other})
                if state == 'hover': steps.append({'type': 'hover', 'target': other})
                if state == 'focus': steps.append({'type': 'focus-by-tab', 'target': first})
                case = base_case(
                    f'components.segmented-tabs.{family}-{device}-{locale.split("-")[0]}-{state}',
                    'Plugin tabs' if family == 'manager' else 'Preset guide tabs',
                    'plugins-preview.manager' if family == 'manager' else 'agents-tasks.guide',
                    {'width': viewport, 'height': 1100, 'density': density},
                    [('default', state, {'width': (720 if family == 'manager' else 600) if device == 'desktop' else 326,
                                          'height': 900, 'name': 'populated' if family == 'manager' else 'coding'}, steps)],
                    locale=locale, category='extension/segmented-tabs',
                    react_hint='packages/client/ui-plugin-manager/src/client/PluginManagerPage.tsx' if family == 'manager'
                        else 'packages/client/ui-agent-preset/src/client/PresetGuideDialog.tsx',
                    flutter_hint='features/dsh_feature_plugins/lib/src/manager_page.dart' if family == 'manager'
                        else 'features/dsh_feature_agent_management/lib/src/presets.dart')
                case['capture'] = {'selector': f'[data-parity-id="{group}"]', 'flutterKey': group, 'crop': 'element'}
                cases += themed(case)
replace_cases('components.segmented-tabs.', cases)
