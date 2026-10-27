"""Actual controlled RiskConfirmation cards and fixed-footer overflow cases.

The old risk checkbox cohort and preset-reader cohort stay separate. Long
content repeats the same localized source warning, and explicit scroll offsets
avoid relying on the browser's automatic checkbox focus scrolling.
"""
from builders_api import base_case, replace_cases, themed

ORDER = 480
cases = []
profiles = [
    ('card-off', False, False, False, None, 'risk-dialog'),
    ('card-on', True, False, False, None, 'risk-dialog'),
    ('card-off-disabled', False, True, False, None, 'risk-dialog'),
    ('card-on-disabled', True, True, False, None, 'risk-dialog'),
    ('long-card-top', True, False, True, 0, 'risk-dialog'),
    ('long-card-bottom', True, False, True, 1000000, 'risk-dialog'),
    ('long-footer-top', True, False, True, 0, 'risk-footer'),
    ('long-footer-bottom', True, False, True, 1000000, 'risk-footer'),
]
for device, width, density in [('desktop', 800, 1), ('phone', 390, 2.625)]:
    for locale in ['en', 'zh-CN']:
        for name, checked, disabled, long_content, offset, target in profiles:
            actions = ([{'type': 'set-scroll', 'target': 'risk-content', 'offset': offset}]
                       if offset is not None else None)
            case = base_case(
                f'components.headed-dialogs.risk-{device}-{locale.split("-")[0]}-{name}',
                f'Risk confirmation {name}', 'headed-dialogs.risk',
                {'width': width, 'height': 320 if long_content else 900, 'density': density},
                [('default', name,
                  {'checked': checked, 'disabled': disabled, 'repeat': 6 if long_content else 1},
                  actions)],
                locale=locale, category='extension/headed-dialogs',
                react_hint='packages/client/ui-primitives/src/RiskConfirmation.tsx',
                flutter_hint='packages/dsh_ui/lib/src/dsh_risk_dialog.dart')
            case['capture'] = {'selector': f'[data-parity-id="{target}"]',
                               'flutterKey': target, 'crop': 'element'}
            cases += themed(case)
replace_cases('components.headed-dialogs.', cases)
