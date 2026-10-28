"""Source/plan identity checks for the additive actual-loaded-card cohort."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BUILDERS = ROOT / 'tool/parity-ext'
sys.path.insert(0, str(BUILDERS))
sys.path.insert(0, str(ROOT / 'tool'))
from parity_lib.manifest import validate_case
spec = importlib.util.spec_from_file_location('plugin_card_capture_builder', BUILDERS / 'build-plugin-cards.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class PluginCardCapturePlanTest(unittest.TestCase):
    def test_actual_pipeline_schema_accepts_every_new_case(self):
        errors = [error for row in builder.cases() for error in validate_case(row)]
        self.assertEqual(errors, [])

    def test_actual_matrix_is_complete_and_unique(self):
        rows = builder.cases()
        self.assertEqual(len(rows), 224)
        self.assertEqual(len({row['id'] for row in rows}), len(rows))
        expected = {(theme, locale, width, density) for theme in ('light', 'dark')
                    for locale in ('en', 'zh-CN') for width in (390, 800) for density in (1, 2.625)}
        for scenario in builder.scenarios():
            selected = [r for r in rows if r['variants'][0]['props']['scenarioId'] == scenario['id']]
            states = {'idle', 'hover', 'press', 'focus'} if scenario['id'] == 'default' else {'idle'}
            self.assertEqual({r['variants'][0]['name'] for r in selected}, states)
            for state in states:
                self.assertEqual({(r['theme'], r['locale'], r['viewport']['width'], r['viewport']['density'])
                                  for r in selected if r['variants'][0]['name'] == state}, expected)

    def test_plan_preserves_one_shared_data_source_and_actual_reference(self):
        data = {s['id']: s for s in builder.scenarios()}
        for row in builder.cases():
            props = row['variants'][0]['props']
            self.assertEqual(props['scenario'], data[props['scenarioId']])
            self.assertTrue(row['reactPathHint'].startswith('published @deepseek-ai/dsh-client-ui-plugin-manager@0.2.1-rc.2/'))
            self.assertEqual(row['capture']['crop'], 'viewport')
            self.assertEqual(set(props), {'scenario', 'scenarioId'})

    def test_additive_builder_does_not_mutate_existing_cohorts(self):
        with tempfile.TemporaryDirectory() as temporary:
            file = Path(temporary) / 'cases.json'
            original = [{'id': 'components.icon-actions.manager-existing', 'sentinel': 1},
                        {'id': 'components.reported-model.existing', 'sentinel': 2}]
            file.write_text(json.dumps({'cases': original}))
            subprocess.run([sys.executable, str(BUILDERS / 'build-plugin-cards.py')],
                           env=dict(os.environ, PARITY_EXT_MANIFEST=str(file)), check=True, capture_output=True)
            rows = json.loads(file.read_text())['cases']
            self.assertEqual(rows[:2], original)
            self.assertEqual(len(rows), 226)

    def test_duplicate_and_unknown_compiled_schema_are_rejected(self):
        original = builder.DATA
        try:
            with tempfile.TemporaryDirectory() as temporary:
                file = Path(temporary) / 'fixture.dart'
                builder.DATA = file
                for data in [{'schema': 'unrecognized', 'scenarios': []},
                             {'schema': 'dsh-plugin-card-scenarios/1', 'scenarios': [{'id': 'x'}, {'id': 'x'}]}]:
                    file.write_text("const pluginCardScenarioJson = r'''\n" + json.dumps(data) + "\n''';")
                    with self.assertRaises(ValueError):
                        builder.scenarios()
        finally:
            builder.DATA = original


if __name__ == '__main__':
    unittest.main()
