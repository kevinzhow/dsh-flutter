#!/usr/bin/env python3
"""Button matrix: every variant x size, each with a normal, a disabled and a long-label button.

Ids: components.button.matrix.<variant>-<size>.<theme>; kind button.items (the same renderer as the core
suite, so both providers already have it). Variants of each case: default and hover on the normal button.
"""
from builders_api import base_case, replace_cases, themed

ORDER = 100
HINT = 'packages/client/ui-primitives/src/Button.tsx'
FLUTTER = 'tool/parity_flutter/test/parity/cases/button.dart buttonCases[button.items]'

cases = []
for variant in ('primary', 'ghost', 'outline', 'toolbar'):
    for size in ('md', 'sm'):
        height = 16 + (36 if size == 'md' else 28) + 16
        items = [
            {'id': 'btn-normal', 'label': 'Continue', 'variant': variant, 'size': size},
            {'id': 'btn-disabled', 'label': 'Disabled', 'variant': variant, 'size': size, 'disabled': True},
            {'id': 'btn-long', 'label': 'A considerably longer label', 'variant': variant, 'size': size},
        ]
        props = {'layout': {'direction': 'row', 'gap': 12, 'align': 'start'}, 'items': items}
        variants = [
            ('default', 'Default', props, None),
            ('hover', 'Hover on the normal button', props, [{'type': 'hover', 'target': 'btn-normal'}]),
        ]
        cases += themed(base_case('components.button.matrix.%s-%s' % (variant, size), 'Button %s %s' % (variant, size),
                                  'button.items', {'width': 480, 'height': height, 'density': 1}, variants,
                                  category='extension/button', react_hint=HINT, flutter_hint=FLUTTER))
replace_cases('components.button.matrix.', cases)
