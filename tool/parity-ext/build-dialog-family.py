"""Real preset-guide readers, tab rows and independently retained scroll panels.

Scroll cases use a short viewport so both real, unchanged source panels overflow.
Every retained-panel capture has a direct-scroll baseline at the same viewport,
offset and selected page; their pixels can therefore verify source preservation.
"""
from builders_api import base_case, replace_cases, themed

ORDER = 479
cases = []
OFFSETS = {'explanation': 100, 'usage': 150}
for device, viewport, height, density in [('desktop', 800, 1100, 1), ('phone', 390, 844, 2.625)]:
    for locale in ['en', 'zh-CN']:
        for part in ['reader', 'tabs', 'panel-scrolled', 'panel-retained']:
            for page in ['explanation', 'usage']:
                scroll_case = part.startswith('panel-')
                target = ('preset-guide-dialog' if part == 'reader' else 'preset-guide-tabs'
                          if part == 'tabs' else 'preset-guide-panel-' + page)
                trigger = 'details' if page == 'explanation' else 'usage'
                steps = [{'type': 'click', 'target': 'preset-guide-standard-' + trigger}]
                if scroll_case:
                    steps.append({'type': 'set-scroll', 'target': 'preset-guide-panel-' + page,
                                  'offset': OFFSETS[page]})
                if part == 'panel-retained':
                    other = 'usage' if page == 'explanation' else 'explanation'
                    steps += [
                        {'type': 'click', 'target': 'preset-guide-tab-' + other},
                        {'type': 'set-scroll', 'target': 'preset-guide-panel-' + other,
                         'offset': OFFSETS[other]},
                        {'type': 'click', 'target': 'preset-guide-tab-' + page},
                    ]
                case = base_case(
                    f'components.dialog-family.{part}-{device}-{locale.split("-")[0]}-{page}',
                    f'Preset guide {part} ({page})', 'agents-tasks.guide',
                    {'width': viewport, 'height': 420 if scroll_case else height, 'density': density},
                    [('default', part + '-' + page,
                      {'width': 600 if device == 'desktop' else 326, 'height': 900, 'name': 'coding'}, steps)],
                    locale=locale, category='extension/dialog-family',
                    react_hint='packages/client/ui-agent-preset/src/client/PresetGuideDialog.tsx',
                    flutter_hint='features/dsh_feature_agent_management/lib/src/presets.dart')
                case['capture'] = {'selector': f'[data-parity-id="{target}"]',
                                   'flutterKey': target, 'crop': 'element'}
                cases += themed(case)
replace_cases('components.dialog-family.', cases)
