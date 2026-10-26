"""Tooltips on the real DSH and Flutter message actions."""
from builders_api import base_case, replace_cases, themed

ORDER = 472
cases = []
for action in ['copy', 'branch']:
    for device, width, density in [('desktop', 800, 1), ('phone', 390, 2.625)]:
        for locale in ['en', 'zh-CN']:
            props = {'clock': 'start', 'branch': action == 'branch'}
            case = base_case(
                f'components.tooltip-family.message-{action}-{device}-{locale.split("-")[0]}',
                f'Message {action} tooltip', 'chat.stream.actions',
                {'width': width, 'height': 240, 'density': density},
                [('default', action, props, [{'type': 'hover', 'target': f'message-{action}'}])],
                locale=locale, category='extension/tooltip-family',
                react_hint='packages/client/ui-chat/src/client/chat/MessageIconActions.tsx',
                flutter_hint='features/dsh_feature_chat/test/parity/cases/stream.dart',
            )
            case['capture'] = {'selector': '[role="tooltip"]', 'flutterKey': 'dsh-tooltip-bubble', 'crop': 'element'}
            cases += themed(case)
replace_cases('components.tooltip-family.', cases)
