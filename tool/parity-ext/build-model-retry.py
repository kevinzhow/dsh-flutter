#!/usr/bin/env python3
"""The real DSH retry disclosure, at desktop and phone widths/densities."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from builders_api import base_case, replace_cases, themed  # noqa: E402

ORDER = 455
cases = []
for state, opened in [('scheduled', False), ('started', False), ('started', True), ('cancelled', True)]:
    for device, width, density in [('desktop', 480, 1), ('phone', 240, 2.625)]:
        for locale, tag in [('en', 'en'), ('zh-CN', 'zh')]:
            name = '%s-%s-%s-%s' % (state, 'open' if opened else 'closed', device, tag)
            props = {'state': state, 'open': opened, 'width': width}
            title = 'Model retry: ' + name
            c = base_case('components.model-retry.' + name, title, 'chat.model-retry',
                          {'width': 520, 'height': 300, 'density': density},
                          [('default', title, props, None)], locale=locale,
                          category='extension/model-retry',
                          react_hint='packages/client/ui-chat/src/client/chat/MessageItem.tsx RetryNodeView',
                          flutter_hint='features/dsh_feature_chat/test/parity/cases/model_retry.dart')
            c['capture'] = {'selector': '[data-parity-id="retry-el"]', 'flutterKey': 'retry-el', 'crop': 'element'}
            cases += themed(c)
replace_cases('components.model-retry.', cases)
