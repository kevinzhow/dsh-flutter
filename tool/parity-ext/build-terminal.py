#!/usr/bin/env python3
"""Sidebar terminal panel (dsh ui-sidebar-terminal): the status strip, the error line, the missing-terminal panel and the screen.

React host: host/terminal.tsx mounts dsh's real TerminalBody (xterm.js) over a scripted model. Flutter: TerminalBody
(features/dsh_feature_sidebar_terminal/test/parity/cases/terminal.dart) over a scripted fake host and the xterm Flutter emulator.

  terminal.body   {state: {phase, info?, writable, error?, issue?}, screen?, width, height}

The window is 1120 CSS px wide, past the width where Whalee draws its phone key bar, which dsh web has no counterpart for.
Ids: components.terminal.<state>-<locale>.<theme>.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from builders_api import base_case, replace_cases, themed  # noqa: E402

ORDER = 450
HINT = 'packages/client/ui-sidebar-terminal/src/client/terminal.tsx'
FLUTTER = 'features/dsh_feature_sidebar_terminal/test/parity/cases/terminal.dart terminalCases[terminal.body]'
W, H = 1120, 300
SCREEN = 'build\\r\\nok'


def info(state='running', exit_code=None, error=None):
    out = {'id': 't1', 'title': 'bash', 'shell': {'path': '/bin/bash', 'args': ['-i'], 'name': 'bash'}, 'cwd': '/ws',
           'cols': 80, 'rows': 24, 'state': state, 'exitCode': exit_code}
    if error:
        out['error'] = error
    return out


def props(phase, *, writable=False, with_info=True, screen=None, error=None, issue=None, i=None):
    state = {'phase': phase, 'writable': writable}
    if with_info:
        state['info'] = i or info()
    if error:
        state['error'] = error
    if issue:
        state['issue'] = issue
    p = {'state': state, 'width': W, 'height': H}
    if screen is not None:
        p['screen'] = screen
    return p


STATES = (
    ('loading', 'Reading the terminal environment', props('loading', with_info=False)),
    ('connecting', 'Connecting to the Host terminal', props('connecting')),
    ('connected', 'Connected, writable, the Host screen drawn', props('connected', writable=True, screen='user@host:~$ ls\r\nREADME.md  src')),
    ('readonly', 'Another view holds input', props('connected', screen='user@host:~$', writable=False)),
    ('disconnected', 'The connection is gone; the screen stays', props('disconnected', screen='user@host:~$ make')),
    ('exited', 'The shell exited with code 3', props('connected', screen='user@host:~$ exit 3', i=info('exited', 3))),
    ('error', 'The terminal reported an error', props('failed', error='no shell could start', with_info=False)),
    ('limit', 'The session terminal limit', props('failed', with_info=False, issue='terminalLimit')),
    ('missing', 'The Host no longer has the terminal', props('failed', with_info=False, issue='missingTerminal')),
)

cases = []
for name, title, p in STATES:
    for locale, tag in (('en', 'en'), ('zh-CN', 'zh')):
        cases += themed(base_case('components.terminal.%s-%s' % (name, tag), '%s (%s)' % (title, locale), 'terminal.body',
                                  {'width': W + 32, 'height': H + 32, 'density': 2}, [('default', title, p, None)],
                                  locale=locale, category='extension/terminal', react_hint=HINT, flutter_hint=FLUTTER))
replace_cases('components.terminal.', cases)
