"""Bounded loaded-card plans; actual published source uses its separate runner.

No existing preview/Manager16/component cases are replaced. A stand-alone plan
can be prepared with --out PATH; the extension builder uses its usual manifest.
The only scenario data is the compiled Dart JSON literal shared with native.
"""
import argparse
import json
import os
from pathlib import Path
import re

from builders_api import base_case, replace_cases, themed

ORDER = 474
ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'apps/dsh_flutter/test/parity/helpers/plugin_card_fixture.dart'


def scenarios():
    matches = re.findall(r"const pluginCardScenarioJson = r'''\n(.*?)\n''';", DATA.read_text(), re.S)
    if len(matches) != 1:
        raise ValueError('one canonical compiled scenario JSON literal required')
    data = json.loads(matches[0])
    if data.get('schema') != 'dsh-plugin-card-scenarios/1':
        raise ValueError('unsupported card scenario schema')
    rows = data['scenarios']
    if len({r['id'] for r in rows}) != len(rows) or any(not re.fullmatch('[a-z-]+', r['id']) for r in rows):
        raise ValueError('duplicate or unsafe card scenario identity')
    return [{**r, 'package': {**data['basePackage'], **r['package']}} for r in rows]


def cases():
    result = []
    for scenario in scenarios():
        for state in (('idle', 'hover', 'press', 'focus') if scenario['id'] == 'default' else ('idle',)):
            for device, width in [('desktop', 800), ('phone', 390)]:
                for density in (1, 2.625):
                    for locale in ('en', 'zh-CN'):
                        interactions = None if state == 'idle' else [{
                            'type': 'focus-by-tab' if state == 'focus' else state,
                            'target': 'plugin-card-' + scenario['package']['name'],
                        }]
                        case = base_case(
                            f'components.plugin-card.{scenario["id"]}-{state}-{device}-dpr{density}-{locale.split("-")[0]}',
                            f'Actual loaded PluginManager card: {scenario["id"]} ({state})',
                            'plugin-cards.manager', {'width': width, 'height': 900, 'density': density},
                            [('default', state, {'scenarioId': scenario['id'], 'scenario': scenario}, interactions)],
                            locale=locale, category='extension/plugin-card',
                            react_hint='published @deepseek-ai/dsh-client-ui-plugin-manager@0.2.1-rc.2/lib/client.js',
                            flutter_hint='features/dsh_feature_plugins/lib/src/manager_page.dart')
                        case['capture'] = {'selector': '[data-plugin-cards-capture]',
                                           'flutterKey': 'plugin-cards-capture', 'crop': 'viewport'}
                        result.extend(themed(case))
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out', type=Path)
    args = parser.parse_args()
    rows = cases()
    if args.out is not None:
        if args.out.exists():
            raise SystemExit('Refusing to overwrite a card plan')
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps({'schema': 'dsh-parity-cases/1', 'name': 'plugin-cards', 'cases': rows},
                                      ensure_ascii=False, indent=2) + '\n')
    elif os.environ.get('PARITY_EXT_MANIFEST'):
        replace_cases('components.plugin-card.', rows)
    else:
        parser.error('--out or PARITY_EXT_MANIFEST is required')
