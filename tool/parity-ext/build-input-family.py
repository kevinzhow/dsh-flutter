"""The real DSH font-settings input, including focus, at desktop and phone sizes."""
from builders_api import base_case, replace_cases, themed

ORDER = 473
cases = []
for device, width, height, density in [('desktop', 596, 720, 2), ('phone', 390, 1600, 2.625)]:
    for locale in ['en', 'zh-CN']:
        for state in ['placeholder', 'value', 'focused']:
            # Both providers receive the already-normalized persisted value.
            families = {'text': '' if state == 'placeholder' else '"Inter", sans-serif', 'code': '', 'terminal': ''}
            props = {'layout': {'direction': 'column', 'gap': 0, 'align': 'stretch'},
                     'preference': 'system', 'fontSizes': {'text': 14, 'code': 11, 'terminal': 13},
                     'fontFamilies': families, 'inputCapture': True}
            interactions = [{'type': 'click', 'target': 'font-expander'}]
            if state == 'focused':
                interactions.append({'type': 'click', 'target': 'font-text-family'})
            case = base_case(
                f'components.input-family.font-{device}-{locale.split("-")[0]}-{state}',
                'Font family input', 'settings.font',
                {'width': width, 'height': height, 'density': density},
                [('default', state, props, interactions)], locale=locale, category='extension/input-family',
                react_hint='packages/client/ui-theme/src/client/FontFamilyRow.tsx',
                flutter_hint='features/dsh_feature_theme/lib/src/theme_rows.dart',
            )
            case['capture'] = {'selector': 'span:has(> input[data-parity-id="font-text-family"])',
                               'flutterKey': 'font-text-family', 'crop': 'element'}
            cases += themed(case)
replace_cases('components.input-family.', cases)
