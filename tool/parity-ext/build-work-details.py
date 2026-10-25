#!/usr/bin/env python3
"""Actual upstream Turn disclosures, process groups and work-detail selectors."""
import pathlib
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from builders_api import base_case, replace_cases, themed
ORDER = 458
families = {
    'turn-process': [
        ('complete', {}), ('open', {'open': True}), ('partial', {'partial': True}),
        ('stopped', {'reason': 'aborted'}), ('failed', {'reason': 'error'}),
        ('verbose', {'mode': 'verbose'}), ('empty', {'empty': True}),
        ('hours', {'elapsed': 3661000}),
    ],
    'work-settings': [('detailed', {'mode': 'detailed'}), ('compact', {'mode': 'compact'}),
                      ('verbose-next', {'mode': 'verbose', 'nextInput': True}),
                      ('standard', {'mode': 'standard'})],
    'process-group': [('read', {'names': ['read'], 'closed': True}),
                      ('mixed', {'names': ['read', 'bash', 'read'], 'closed': True}),
                      ('running', {'names': ['read'], 'closed': False}),
                      ('preparing', {'names': ['bash'], 'closed': False, 'preparing': True}),
                      ('open', {'names': ['read'], 'closed': True, 'open': True})],
}
for family, variants in families.items():
    cases = []
    for label, props in variants:
        for device, width, density in [('desktop', 480, 1), ('phone', 240, 2.625)]:
            for locale, tag in [('en', 'en'), ('zh-CN', 'zh')]:
                name = f'{label}-{device}-{tag}'
                steps = [{'type': 'click', 'target': 'work-toggle'}] if props.get('open') or props.get('menu') else None
                c = base_case(f'components.{family}.{name}', f'{family}: {name}', f'chat.{family}',
                              {'width': 520, 'height': 600, 'density': density},
                              [('default', name, {'width': width, **props}, steps)], locale=locale,
                              category=f'extension/{family}',
                              react_hint='packages/client/ui-chat/src/client/chat/TurnProcessNodeView.tsx' if family == 'turn-process' else 'packages/client/ui-chat/src/client/' + ('settings/TranscriptViewRow.tsx' if family == 'work-settings' else 'chat/ChatGroupSeat.tsx'),
                              flutter_hint='features/dsh_feature_chat/test/parity/cases/work_details.dart')
                c['capture'] = {'selector': '[data-parity-id="work-el"]', 'flutterKey': 'work-el', 'crop': 'element'}
                cases += themed(c)
    replace_cases(f'components.{family}.', cases)
