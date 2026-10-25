#!/usr/bin/env python3
"""Real command settlements and landed automatic/manual compaction markers."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from builders_api import base_case, replace_cases, themed  # noqa: E402

ORDER = 457
families = {
    'compaction': [
        ('available', {'summary': True, 'counts': True}),
        ('open', {'summary': True, 'counts': True, 'open': True}),
        ('unavailable', {'summary': False, 'counts': False}),
        ('counts-only', {'summary': False, 'counts': True}),
        ('manual-open', {'summary': True, 'counts': True, 'manual': True, 'open': True}),
        ('manual-fallback', {'summary': False, 'counts': False, 'manual': True}),
    ],
    'command': [
        ('running', {'state': 'running'}),
        ('success', {'state': 'success', 'text': 'Complete'}),
        ('success-open', {'state': 'success', 'text': 'First line\n<tag> **literal**', 'open': True}),
        ('error-open', {'state': 'error', 'text': 'First line\nSecond line', 'open': True}),
        ('orphan', {'state': 'error', 'orphan': True}),
        ('manual-running', {'state': 'running', 'manual': True}),
        ('manual-error-open', {'state': 'error', 'manual': True, 'text': 'Compaction failed\nTry again', 'open': True}),
    ],
}
for family, variants in families.items():
    cases = []
    for state, props in variants:
        for device, width, density in [('desktop', 480, 1), ('phone', 240, 2.625)]:
            for locale, tag in [('en', 'en'), ('zh-CN', 'zh')]:
                name = f'{state}-{device}-{tag}'
                steps = [{'type': 'hover', 'target': 'lifecycle-toggle'},
                         {'type': 'click', 'target': 'lifecycle-toggle'}] if props.get('open') else None
                c = base_case(f'components.{family}.{name}', f'{family}: {name}', f'chat.{family}',
                    {'width': 520, 'height': 320, 'density': density},
                    [('default', name, {'width': width, **props}, steps)], locale=locale,
                    category=f'extension/{family}',
                    react_hint='packages/client/ui-chat/src/client/chat/' + ('CompactionItem.tsx' if family == 'compaction' else 'GenericCommandCard.tsx'),
                    flutter_hint='features/dsh_feature_chat/test/parity/cases/compaction_command.dart')
                c['capture'] = {'selector': '[data-parity-id="lifecycle-el"]', 'flutterKey': 'lifecycle-el', 'crop': 'element'}
                cases += themed(c)
    replace_cases(f'components.{family}.', cases)
