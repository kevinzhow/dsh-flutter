"""The actual Discover category pills at desktop and phone densities."""
from builders_api import base_case, replace_cases, themed

ORDER = 476
cases = []
for device, viewport, density in [('desktop', 800, 1), ('phone', 390, 2.625)]:
    for locale in ['en', 'zh-CN']:
        for state in ['all', 'inactive', 'active', 'hover', 'active-hover', 'focus']:
            props = {'width': 720 if device == 'desktop' else 326, 'height': 900,
                     'name': 'categories', 'category': 'tools' if state in ('active', 'active-hover') else None}
            target = 'market-category-all' if state == 'all' else 'market-category-tools'
            steps = ([{'type': 'hover', 'target': target}] if state in ('hover', 'active-hover') else
                     [{'type': 'focus-by-tab', 'target': target}] if state == 'focus' else None)
            case = base_case(
                f'components.pill-family.market-{device}-{locale.split("-")[0]}-{state}',
                'Market category pill', 'plugins-preview.market',
                {'width': viewport, 'height': 1100, 'density': density},
                [('default', state, props, steps)], locale=locale, category='extension/pill-family',
                react_hint='packages/client/ui-plugin-market/src/client/DiscoverSection.tsx',
                flutter_hint='features/dsh_feature_plugins/lib/src/market_page.dart')
            case['capture'] = ({'selector': '[data-parity-id="plugins-preview-surface"]',
                                'flutterKey': 'plugins-preview-surface', 'crop': 'element'} if state == 'focus' else
                               {'selector': f'[data-parity-id="{target}"]', 'flutterKey': target, 'crop': 'element'})
            cases += themed(case)
replace_cases('components.pill-family.', cases)
