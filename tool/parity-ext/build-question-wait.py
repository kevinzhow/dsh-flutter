#!/usr/bin/env python3
"""Question wait states (dsh ui-user-questions): the status and the Take time button of a timed question's card.

React host: host/question-wait.tsx mounts dsh's real QuestionComposer over the real PendingQuestion carrier and crops to the
header's action group with the icon buttons hidden. Flutter: QuestionWaitStrip
(features/dsh_feature_user_questions/test/parity/cases/question_wait.dart).

  question.wait   {state: counting|paused|held|continued, seconds}
                  parity id: wait-actions (the captured element)

Ids: components.question-wait.<state>-<locale>.<theme>.
"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from builders_api import base_case, replace_cases, themed  # noqa: E402

ORDER = 440
HINT = 'packages/client/ui-user-questions/src/client/QuestionComposer.tsx'
FLUTTER = 'features/dsh_feature_user_questions/test/parity/cases/question_wait.dart questionWaitCases[question.wait]'
STATES = (
    ('counting', 'A running countdown with Take time'),
    ('paused', 'The countdown paused by focus'),
    ('held', 'Waiting until the person answers'),
    ('continued', 'The agent continued; still answerable'),
)

cases = []
for state, title in STATES:
    for locale, tag in (('en', 'en'), ('zh-CN', 'zh')):
        case = base_case('components.question-wait.%s-%s' % (state, tag), '%s (%s)' % (title, locale), 'question.wait',
                         {'width': 640, 'height': 120, 'density': 2},
                         [('default', title, {'state': state, 'seconds': 20}, None)],
                         locale=locale, category='extension/question-wait', react_hint=HINT, flutter_hint=FLUTTER)
        case['capture'] = {'selector': '[data-parity-id="wait-actions"]', 'flutterKey': 'wait-actions', 'crop': 'element'}
        cases += themed(case)
replace_cases('components.question-wait.', cases)
