#!/usr/bin/env python3
"""Input, Tag, Pill and Switch atoms (dsh ui-primitives).

The React host renders the real atoms (host/atoms.tsx); dsh_ui has no Flutter widget for them yet, so these
cases are captured on the React side only and show up as `not covered` (ParityGap.noFlutterSurface in
tool/parity_flutter/test/parity/cases/uncovered.dart). They exist so a widget added to dsh_ui is
measured the day it lands: map its kind in a cases file and nothing else changes.
"""
from builders_api import base_case, replace_cases, themed

ORDER = 200
ROW = {'direction': 'row', 'gap': 12, 'align': 'center'}
COLUMN = {'direction': 'column', 'gap': 12, 'align': 'start'}
PRIM = 'packages/client/ui-primitives/src/'

inputs = {'layout': COLUMN, 'items': [
    {'id': 'in-empty', 'placeholder': 'Search sessions'},
    {'id': 'in-filled', 'value': 'deploy notes'},
    {'id': 'in-disabled', 'value': 'read only', 'disabled': True}]}
replace_cases('components.input.', themed(base_case(
    'components.input.field.states', 'Text input states', 'input.fields', {'width': 360, 'height': 176, 'density': 1},
    [('default', 'Default', inputs, None), ('focus', 'Keyboard focus on the first input', inputs, [{'type': 'tab'}])],
    category='extension/input', react_hint=PRIM + 'Input.tsx')))
replace_cases('components.tag.', themed(base_case(
    'components.tag.tones.all', 'Tag tones', 'tag.items', {'width': 420, 'height': 72, 'density': 1},
    [('default', 'Default', {'layout': {'direction': 'row', 'gap': 8, 'align': 'center'}, 'items': [
        {'id': 'tag-%s' % t, 'tone': t, 'label': t.capitalize()}
        for t in ('outline', 'solid', 'neutral', 'quiet', 'success', 'info', 'warning', 'danger')]}, None)],
    category='extension/tag', react_hint=PRIM + 'Tag.tsx')))
replace_cases('components.pill.', themed(base_case(
    'components.pill.states.all', 'Pill states', 'pill.items', {'width': 360, 'height': 64, 'density': 1},
    [('default', 'Default', {'layout': ROW, 'items': [
        {'id': 'pill-static', 'label': 'Static'}, {'id': 'pill-idle', 'label': 'Idle', 'interactive': True},
        {'id': 'pill-active', 'label': 'Active', 'interactive': True, 'active': True}]}, None)],
    category='extension/pill', react_hint=PRIM + 'Pill.tsx')))
replace_cases('components.switch.', themed(base_case(
    'components.switch.states.all', 'Switch states', 'switch.items', {'width': 280, 'height': 64, 'density': 1},
    [('default', 'Default', {'layout': ROW, 'items': [
        {'id': 'sw-off', 'checked': False, 'label': 'Off'}, {'id': 'sw-on', 'checked': True, 'label': 'On'},
        {'id': 'sw-disabled', 'checked': True, 'label': 'Disabled', 'disabled': True}]}, None)],
    category='extension/switch', react_hint=PRIM + 'Switch.tsx')))
