#!/usr/bin/env python3
"""Real upstream system-prompt cards, including bounded scrolling and empty text."""
import pathlib
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from builders_api import base_case, replace_cases, themed  # noqa: E402

ORDER = 456
cases = []
text = 'You are a helpful assistant.\nKeep <tags> and **markup** literal.\n保留原文和换行。'
for state in ['closed', 'open', 'update-open', 'long-open', 'empty-open']:
    for device, width, density in [('desktop', 480, 1), ('phone', 240, 2.625)]:
        for locale, tag in [('en', 'en'), ('zh-CN', 'zh')]:
            body = '' if state == 'empty-open' else '\n'.join('line %d: preserve original text' % i for i in range(40)) if state == 'long-open' else text
            props = {'width': width, 'text': body, 'update': state == 'update-open'}
            steps = [{'type': 'hover', 'target': 'prompt-toggle'}, {'type': 'click', 'target': 'prompt-toggle'}] if state != 'closed' else None
            name = '%s-%s-%s' % (state, device, tag)
            c = base_case('components.system-prompt.' + name, 'System prompt ' + name, 'chat.system-prompt',
                {'width': 520, 'height': 300, 'density': density},
                [('default', name, props, steps)], locale=locale, category='extension/system-prompt',
                react_hint='packages/client/ui-chat/src/client/chat/SystemPromptRow.tsx',
                flutter_hint='features/dsh_feature_chat/test/parity/cases/system_prompt.dart')
            c['capture'] = {'selector': '[data-parity-id="prompt-el"]', 'flutterKey': 'prompt-el', 'crop': 'element'}
            cases += themed(c)
replace_cases('components.system-prompt.', cases)
