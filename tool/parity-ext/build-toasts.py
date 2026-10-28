"""Additive actual-published Toast cohort with shared compiled fixture data."""
import argparse
import json
import os
from pathlib import Path
import re

from builders_api import base_case, replace_cases, themed

ORDER = 476
ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'apps/dsh_flutter/test/parity/helpers/toast_fixture.dart'


def fixture():
    literals = re.findall(r"const toastScenarioJson = r'''\n(.*?)\n''';", DATA.read_text(), re.S)
    if len(literals) != 1:
        raise ValueError('one compiled Toast JSON source required')
    data = json.loads(literals[0])
    rows = data.get('scenarios', [])
    if data.get('schema') != 'dsh-toast-scenarios/1' or len(rows) != len({r['id'] for r in rows}):
        raise ValueError('invalid or duplicate Toast scenario schema')
    for row in rows:
        if not re.fullmatch('[a-z-]+', row['id']) or set(row['text']) != {'en', 'zh'}:
            raise ValueError('invalid localized Toast data')
        if row['icon'] not in ('none', 'warning') or row['tone'] not in (None, 'success'):
            raise ValueError('unsupported fixture glyph/tone')
    return data


def cases():
    data, rows = fixture(), []
    for scenario in data['scenarios']:
        for reduced in (False, True):
            for device, width in [('desktop', 800), ('phone', 390)]:
                for density in (1, 2.625):
                    for locale in ('en', 'zh-CN'):
                        state = 'reduced' if reduced else 'normal'
                        case = base_case(
                            f'components.toast.{scenario["id"]}-{state}-{device}-dpr{density}-{locale.split("-")[0]}',
                            f'Actual published Toast {scenario["id"]} ({state})', 'toast.source',
                            {'width': width, 'height': 600, 'density': density},
                            [('default', state, {'scenarioId': scenario['id'], 'scenario': scenario,
                                                'holdMs': data['stableHoldMs'], 'reducedMotion': reduced}, None)],
                            locale=locale, category='extension/toast',
                            react_hint='published @deepseek-ai/dsh-client-ui-primitives@0.2.1-rc.2/lib/index.js Toast',
                            flutter_hint='packages/dsh_ui/lib/src/dsh_toast.dart')
                        case['capture'] = {'selector': 'body', 'flutterKey': 'toast-capture-root', 'crop': 'viewport'}
                        rows.extend(themed(case))
    return rows


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    rows = cases()
    if args.out:
        if args.out.exists():
            raise SystemExit('Refusing to overwrite a Toast plan')
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps({'schema': 'dsh-parity-cases/1', 'name': 'toasts', 'cases': rows}, indent=2, ensure_ascii=False) + '\n')
    elif os.environ.get('PARITY_EXT_MANIFEST'):
        replace_cases('components.toast.', rows)
    else:
        parser.error('--out or PARITY_EXT_MANIFEST required')
