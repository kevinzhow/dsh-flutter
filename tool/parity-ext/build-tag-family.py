"""Tags in the real agent-preset and shell settings components."""
from builders_api import base_case, replace_cases, themed

ORDER = 477
cases = []
for device, viewport, density in [('desktop', 800, 1), ('phone', 390, 2.625)]:
    for locale in ['en', 'zh-CN']:
        for label, target in [('selected', 'preset-tag-standard'), ('built-in', 'preset-tag-ptc'), ('custom', 'preset-tag-reviewer')]:
            case = base_case(
                f'components.tag-family.preset-{device}-{locale.split("-")[0]}-{label}',
                'Agent preset tag', 'agents-tasks.preset',
                {'width': viewport, 'height': 1600, 'density': density},
                [('default', label, {'width': 600 if device == 'desktop' else 326, 'height': 1250, 'name': 'coding'}, None)],
                locale=locale, category='extension/tag-family',
                react_hint='packages/client/ui-agent-preset/src/client/AgentPresetSection.tsx',
                flutter_hint='features/dsh_feature_agent_management/lib/src/presets.dart')
            case['capture'] = {'selector': f'[data-parity-id="{target}"]', 'flutterKey': target, 'crop': 'element'}
            cases += themed(case)
        case = base_case(
            f'components.tag-family.shell-{device}-{locale.split("-")[0]}-override',
            'Shell setting override tag', 'model-settings.shell',
            {'width': viewport, 'height': 1600, 'density': density},
            [('default', 'override', {'width': 600 if device == 'desktop' else 326, 'name': 'overridden'}, None)],
            locale=locale, category='extension/tag-family',
            react_hint='packages/client/ui-settings-shell/src/client/ShellCard.tsx',
            flutter_hint='features/dsh_feature_settings/lib/src/common_settings.dart')
        case['capture'] = {'selector': '[data-parity-id="timeoutMs-overridden"]',
                           'flutterKey': 'timeoutMs-overridden', 'crop': 'element'}
        cases += themed(case)
        for kind in ('conditional', 'disabled', 'failed'):
            module = '@synthetic/' + kind
            case = base_case(
                f'components.tag-family.inventory-{device}-{locale.split("-")[0]}-{kind}',
                'Plugin inventory status tag', 'plugins-preview.inventory',
                {'width': viewport, 'height': 1600, 'density': density},
                [('default', kind, {'width': 600 if device == 'desktop' else 326, 'height': 1250, 'name': 'tags'}, None)],
                locale=locale, category='extension/tag-family',
                react_hint='packages/client/ui-settings-plugin-inventory/src/client/PluginInventorySettingsTab.tsx',
                flutter_hint='features/dsh_feature_plugins/lib/src/inventory.dart')
            case['capture'] = {'selector': f'[data-plugin-module="{module}"] [data-tone]',
                               'flutterKey': f'inventory-tag-{module}', 'crop': 'element'}
            cases += themed(case)
replace_cases('components.tag-family.', cases)
