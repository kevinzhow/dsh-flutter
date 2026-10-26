"""Effective bindings in the real DSH workspace session-action menu."""
from builders_api import base_case, replace_cases, themed

ORDER = 470
cases = []
for name in ['idle', 'archived']:
    for device, width, density in [('desktop', 800, 1), ('phone', 390, 2.625)]:
        for locale in ['en', 'zh-CN']:
            steps = [
                {'type': 'hover', 'target': 'session-row-s1'},
                {'type': 'click', 'target': 'session-row-menu-s1'},
            ]
            props = {'width': 256, 'name': name, 'long': False,
                     'archive': False, 'shortcuts': True}
            case = base_case(
                f'components.menu-shortcuts.session-{name}-{device}-{locale.split("-")[0]}',
                f'Session menu {name} with effective shortcuts',
                'workspace-management.row',
                {'width': width, 'height': 600, 'density': density},
                [('default', name, props, steps)],
                locale=locale,
                category='extension/menu-shortcuts',
                react_hint='packages/client/ui-workspace/src/client/session-actions',
                flutter_hint='apps/dsh_flutter/test/parity/cases/workspace_management.dart',
            )
            case['capture'] = {'selector': '[role="menu"]', 'flutterKey': 'dsh-menu', 'crop': 'element'}
            cases += themed(case)
replace_cases('components.menu-shortcuts.', cases)
