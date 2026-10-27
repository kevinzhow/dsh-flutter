"""Real risk acknowledgement and source model-input checkbox comparisons."""
from builders_api import base_case, replace_cases, themed

ORDER = 475
cases = []
for device, width, density in [('desktop', 800, 1), ('phone', 390, 2.625)]:
    for locale in ['en', 'zh-CN']:
        for state in ['off', 'on', 'focus']:
            actions = ([{'type': 'click', 'target': 'risk-acknowledge'}] if state == 'on' else
                       [{'type': 'focus-by-tab', 'target': 'risk-acknowledge'}] if state == 'focus' else None)
            case = base_case(
                f'components.checkbox-family.risk-{device}-{locale.split("-")[0]}-{state}',
                'Risk acknowledgement', 'checkbox-family.risk',
                {'width': width, 'height': 900, 'density': density},
                [('default', state, {}, actions)], locale=locale, category='extension/checkbox-family',
                react_hint='packages/client/ui-primitives/src/RiskConfirmation.tsx',
                flutter_hint='packages/dsh_ui/lib/src/dsh_option_sheet.dart')
            case['capture'] = ({'selector': '[role="dialog"]', 'flutterKey': 'risk-dialog', 'crop': 'element'}
                               if state == 'focus' else
                               {'selector': '[data-parity-id="risk-acknowledge"]', 'flutterKey': 'risk-acknowledge', 'crop': 'element'})
            cases += themed(case)
        for state in ['off', 'on', 'off-disabled', 'on-disabled']:
            props = {'width': 480 if device == 'desktop' else 326,
                     'checked': state.startswith('on'), 'disabled': state.endswith('disabled')}
            case = base_case(
                f'components.checkbox-family.model-{device}-{locale.split("-")[0]}-{state}',
                'Model input checkbox', 'checkbox-family.model',
                {'width': width, 'height': 900, 'density': density},
                [('default', state, props, None)], locale=locale, category='extension/checkbox-family',
                react_hint='packages/client/ui-settings-models/src/client/ModelInputTypes.tsx',
                flutter_hint='packages/dsh_ui/lib/src/dsh_settings.dart')
            case['capture'] = {'selector': '[data-parity-id="model-image"]', 'flutterKey': 'model-image', 'crop': 'element'}
            cases += themed(case)
replace_cases('components.checkbox-family.', cases)
