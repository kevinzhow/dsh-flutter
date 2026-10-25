#!/usr/bin/env python3
"""Remaining chat node renderers, mounted against actual pinned upstream views."""
import json
import pathlib
from builders_api import base_case, replace_cases, themed

ORDER = 459
families = json.loads((pathlib.Path(__file__).parent / 'fixtures/extended-nodes.json').read_text())
paths = {'command-input': 'ui-goal/src/client/GoalCommandInputView.tsx',
         'question-reply': 'ui-user-questions/src/client/QuestionReplyView.tsx',
         'context-injection': 'ui-chat/src/client/chat/ContextInjectionRow.tsx',
         'workflow-run': 'ui-workflow-run/src/client/WorkflowRunPanel.tsx'}
packages = {'command-input': 'chat', 'context-injection': 'chat', 'question-reply': 'user_questions', 'workflow-run': 'workflow_run'}
for family, variants in families.items():
    cases = []
    for label, props in variants.items():
        for device, width, viewport, density in [('desktop', 480, 800, 1), ('phone', 240, 390, 2.625)]:
            for locale in ['en', 'zh-CN']:
                name = f'{label}-{device}-{locale.split("-")[0]}'
                steps = [{'type': 'click', 'target': 'node-toggle'}] if props.get('open') else None
                c = base_case(f'components.{family}.{name}', f'{family}: {name}', f'chat.{family}',
                              {'width': viewport, 'height': 1100, 'density': density},
                              [('default', name, {'width': width, **props}, steps)], locale=locale,
                              category=f'extension/{family}', react_hint='packages/client/' + paths[family],
                              flutter_hint=f'features/dsh_feature_{packages[family]}/test/parity/cases/extended_nodes.dart')
                c['capture'] = {'selector': '[data-parity-id="node-el"]', 'flutterKey': 'node-el', 'crop': 'element'}
                cases += themed(c)
    replace_cases(f'components.{family}.', cases)
