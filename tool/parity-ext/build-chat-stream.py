#!/usr/bin/env python3
"""Stream controls of dsh's chat view (ui-chat): the back-to-bottom chevron, the "Loading history…" hint, the "Load earlier"
control (idle and reading a page) and the clock + copy actions of a message, at the density of a desktop window (1) and of
a phone (2.625).

React host: host/chat-stream.tsx (the real `ChatView.module.css` rules and the real MessageIconActions). Flutter:
features/dsh_feature_chat/test/parity/cases/stream.dart.

  chat.stream.control  {control: to-bottom | hint | load-earlier | load-earlier-loading}
  chat.stream.actions  {clock: start | end}
                       parity id: stream-el (the captured element)

Ids: components.chat-stream.<name>-<desktop|phone>.<theme>.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from builders_api import base_case, replace_cases, themed  # noqa: E402

ORDER = 450
HINT = 'packages/client/ui-chat/src/client/chat/ChatView.module.css'
FLUTTER = 'features/dsh_feature_chat/test/parity/cases/stream.dart chatStreamCases[%s]'
SURFACES = (
    ('to-bottom', 'chat.stream.control', {'control': 'to-bottom'}, 'The back-to-bottom chevron'),
    ('hint', 'chat.stream.control', {'control': 'hint'}, 'The "Loading history…" hint'),
    ('load-earlier', 'chat.stream.control', {'control': 'load-earlier'}, 'The "Load earlier" control'),
    ('load-earlier-loading', 'chat.stream.control', {'control': 'load-earlier-loading'}, 'The control while a page is read'),
    ('actions-user', 'chat.stream.actions', {'clock': 'start'}, 'Clock and copy under a user message'),
    ('actions-tail', 'chat.stream.actions', {'clock': 'end'}, 'Copy and clock of a turn tail'),
)

cases = []
for name, kind, props, title in SURFACES:
    for tag, density in (('desktop', 1), ('phone', 2.625)):
        case = base_case('components.chat-stream.%s-%s' % (name, tag), '%s (%s)' % (title, tag), kind,
                         {'width': 480, 'height': 120, 'density': density}, [('default', title, props, None)],
                         category='extension/chat-stream', react_hint=HINT, flutter_hint=FLUTTER % kind)
        case['capture'] = {'selector': '[data-parity-id="stream-el"]', 'flutterKey': 'stream-el', 'crop': 'element'}
        cases += themed(case)
replace_cases('components.chat-stream.', cases)
