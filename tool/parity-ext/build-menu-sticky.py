"""Pinned headings in the real command popup over matched synthetic options."""
from builders_api import base_case, replace_cases, themed

ORDER = 471
cases = []
for device, width, density in [('desktop', 760, 1), ('phone', 390, 2.625)]:
    for locale in ['en', 'zh-CN']:
        labels = ['Account provider', 'Local provider'] if locale == 'en' else ['账户服务商', '本地服务商']
        options = [
            {'id': f'{group}-{i}', 'label': f'Model {group}-{i}',
             'group': {'name': str(group), 'label': labels[group]}}
            for group in range(2) for i in range(9)
        ]
        for state, offset in [('initial', 0), ('pinned', 90), ('transition', 245)]:
            steps = [{'type': 'set-scroll', 'target': 'popup-list', 'offset': offset}]
            case = base_case(
                f'components.menu-sticky.command-{state}-{device}-{locale.split("-")[0]}',
                f'Command popup groups: {state}', 'input.popup',
                {'width': width + 40, 'height': 420, 'density': density},
                [('default', state, {'command': 'model', 'options': options, 'active': 0, 'width': width}, steps)],
                locale=locale, category='extension/menu-sticky',
                react_hint='packages/client/ui-commands/src/client/PopupSelectView.tsx',
                flutter_hint='features/dsh_feature_commands/test/parity/cases/command_popup.dart',
            )
            case['capture'] = {'selector': '[class*="card"]', 'flutterKey': 'command-popup-surface', 'crop': 'element'}
            cases += themed(case)
        groups = [
            {'id': str(group), 'name': labels[group],
             'models': [{'id': f'{group}-{i}', 'name': f'Model {group}-{i}'} for i in range(9)]}
            for group in range(2)
        ]
        for state, offset in [('initial', 0), ('pinned', 90), ('transition', 360)]:
            steps = [{'type': 'set-scroll', 'target': 'model-list', 'offset': offset}]
            case = base_case(
                f'components.menu-sticky.model-{state}-{device}-{locale.split("-")[0]}',
                f'Model selector groups: {state}', 'menu-sticky.model',
                {'width': width + 40, 'height': 420, 'density': density},
                [('default', state, {'groups': groups, 'width': width}, steps)],
                locale=locale, category='extension/menu-sticky',
                react_hint='packages/client/ui-model-selection/src/client/ModelSelect.tsx',
                flutter_hint='features/dsh_feature_model_selection/test/parity/cases/menu_sticky_model.dart',
            )
            case['capture'] = {'selector': '[data-parity-id="model-list"]', 'flutterKey': 'model-list', 'crop': 'element'}
            cases += themed(case)
replace_cases('components.menu-sticky.', cases)
