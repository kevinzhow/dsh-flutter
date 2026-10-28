"""The real StatsPills trigger opens its published statistics popover.

Content beneath the card is deliberately visible and varied, so the material
and its backdrop filtering are exercised rather than hidden by a flat canvas.
The right-edge cohort verifies the actual viewport clamp.
"""
from builders_api import base_case, replace_cases, themed

ORDER = 520
cases = []
for device, width, density, platform in [('desktop', 800, 1, 'other'),
                                         ('mac', 800, 1, 'darwin'),
                                         ('phone', 390, 2.625, 'other')]:
    for locale in ['en', 'zh-CN']:
        for stat in ['activity', 'usage']:
            for edge in [False, True]:
                name = stat + ('-right-edge' if edge else '')
                case = base_case(
                    f'components.reported-stats.{device}-{locale.split("-")[0]}-{name}',
                    f'Real statistics popover {device} {name}', 'reported.stats',
                    {'width': width, 'height': 400, 'density': density},
                    [('default', name, {'stat': stat, 'edge': edge, 'platform': platform},
                      [{'type': 'click', 'target': 'stats-trigger'}])],
                    locale=locale, category='extension/reported-stats',
                    react_hint='packages/client/ui-chat/src/client/chat/StatsPills.tsx',
                    flutter_hint='features/dsh_feature_chat/lib/src/stats_pills.dart')
                case['capture'] = {'selector': '[data-parity-id="stats-panel"]',
                                   'flutterKey': 'stats-panel', 'crop': 'element'}
                cases += themed(case)
replace_cases('components.reported-stats.', cases)
