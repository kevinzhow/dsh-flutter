#!/usr/bin/env python3
"""ConnectionIndicator (dsh ui-primitives): the inline outage / retry / recovered control.

React host: host/connection.tsx mounts dsh's real ConnectionIndicator with the labels of dsh's `settings`
dictionary (connection.error / connection.connecting / connection.connected / connection.reconnect /
connection.restart). Flutter: DshConnectionIndicator (tool/parity_flutter/test/parity/cases/connection.dart).

  connection.indicator  {layout, labels: {disconnected, connecting, recovered, reconnectAction, restartAction},
                         items: [{id, state: disconnected|connecting|recovered}]}
                        parity ids: ind-disconnected, ind-connecting, ind-recovered

The default variant shows the three states side by side; `hover` and `press` act on the outage control.
Animations are off on both providers, so the connecting dots show all three.

Ids: components.connection-indicator.<name>.<theme>.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from builders_api import base_case, replace_cases, themed  # noqa: E402

ORDER = 430
HINT = 'packages/client/ui-primitives/src/ConnectionIndicator.tsx'
FLUTTER = 'tool/parity_flutter/test/parity/cases/connection.dart connectionCases[connection.indicator]'
LAYOUT = {'direction': 'row', 'gap': 12, 'align': 'center'}

# The text of dsh's `settings` dictionary (packages/client/ui-settings-general), en and zh.
EN = {'disconnected': 'Disconnected', 'connecting': 'Reconnecting', 'recovered': 'Connected',
      'reconnectAction': 'Disconnected, reconnect now', 'restartAction': 'Reconnecting, reconnect now'}
ZH = {'disconnected': '连接异常，刷新重试', 'connecting': '重新连接中', 'recovered': '连接成功',
      'reconnectAction': '连接异常，点击立即重连', 'restartAction': '连接中断，正在重试，点击立即重连'}


def items(*states):
    return [{'id': 'ind-%s' % s, 'state': s} for s in states]


cases = []
for name, locale, labels in (('states', 'en', EN), ('zh-cn', 'zh-CN', ZH)):
    props = {'layout': LAYOUT, 'labels': labels, 'items': items('disconnected', 'connecting', 'recovered')}
    variants = [('default', 'The three states', props, None),
                ('hover', 'Hover on the outage control', props, [{'type': 'hover', 'target': 'ind-disconnected'}]),
                ('press', 'Press on the outage control', props, [{'type': 'press', 'target': 'ind-disconnected'}])]
    cases += themed(base_case('components.connection-indicator.%s' % name, 'Connection indicator (%s)' % locale,
                              'connection.indicator', {'width': 640, 'height': 72, 'density': 2}, variants,
                              locale=locale, category='extension/connection-indicator', react_hint=HINT,
                              flutter_hint=FLUTTER))
replace_cases('components.connection-indicator.', cases)
