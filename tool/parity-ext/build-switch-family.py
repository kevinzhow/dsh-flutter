"""The real plugin-manager bundle switch at desktop and phone densities."""
from builders_api import base_case, replace_cases, themed

ORDER = 474
cases = []
for device, viewport, density in [('desktop', 800, 1), ('phone', 390, 2.625)]:
    for locale in ['en', 'zh-CN']:
        for state in ['on', 'off', 'on-disabled', 'off-disabled', 'on-focused', 'off-focused']:
            props = {'width': 720 if device == 'desktop' else 326,
                     'height': 900, 'name': 'populated', 'switchEnabled': state.startswith('on'),
                     'switchLocked': state.endswith('-disabled')}
            focused = state.endswith('-focused')
            steps = [{'type': 'focus-by-tab', 'target': 'plugin-switch-@synthetic/preview-bundle'}] if focused else None
            case = base_case(
                f'components.switch-family.plugin-{device}-{locale.split("-")[0]}-{state}',
                'Plugin bundle switch', 'plugins-preview.manager',
                {'width': viewport, 'height': 1100, 'density': density},
                [('default', state, props, steps)], locale=locale, category='extension/switch-family',
                react_hint='packages/client/ui-plugin-manager/src/client/PluginManagerPage.tsx',
                flutter_hint='features/dsh_feature_plugins/lib/src/manager_page.dart',
            )
            case['capture'] = ({'selector': '[data-parity-id="plugins-preview-surface"]',
                                'flutterKey': 'plugins-preview-surface', 'crop': 'element'} if focused else
                               {'selector': '[data-parity-id="plugin-switch-@synthetic/preview-bundle"]',
                                'flutterKey': 'plugin-switch-@synthetic/preview-bundle', 'crop': 'element'})
            cases += themed(case)
replace_cases('components.switch-family.', cases)
