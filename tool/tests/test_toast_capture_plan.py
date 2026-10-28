"""Additive Toast matrix and shared fixture-source schema checks."""
import ast
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tool'))
sys.path.insert(0,str(ROOT/'tool/parity-ext'))
from parity_lib import manifest
spec=importlib.util.spec_from_file_location('toast_capture_builder',ROOT/'tool/parity-ext/build-toasts.py')
builder=importlib.util.module_from_spec(spec);spec.loader.exec_module(builder)


class ToastCapturePlanTest(unittest.TestCase):
    def test_schema_and_full_normal_reduced_matrix(self):
        rows=builder.cases()
        self.assertEqual(len(rows),224)
        self.assertEqual(len({r['id'] for r in rows}),224)
        self.assertEqual([error for row in rows for error in manifest.validate_case(row)],[])
        for scenario in builder.fixture()['scenarios']:
            selected=[r for r in rows if r['variants'][0]['props']['scenarioId']==scenario['id']]
            self.assertEqual({(r['theme'],r['locale'],r['viewport']['width'],r['viewport']['density'],r['variants'][0]['props']['reducedMotion']) for r in selected},
                {(t,l,w,d,m) for t in ('light','dark') for l in ('en','zh-CN') for w in (390,800) for d in (1,2.625) for m in (False,True)})

    def test_case_data_is_shared_and_long_hold_is_an_explicit_input(self):
        data=builder.fixture();by_id={r['id']:r for r in data['scenarios']}
        for row in builder.cases():
            props=row['variants'][0]['props']
            self.assertEqual(props['scenario'],by_id[props['scenarioId']])
            self.assertEqual(props['holdMs'],data['stableHoldMs'])
            self.assertIn('published @deepseek-ai/dsh-client-ui-primitives@0.2.1-rc.2/',row['reactPathHint'])
        self.assertIn('\n',by_id['whitespace']['text']['en'])
        self.assertIn('\u00a0',by_id['whitespace']['text']['en'])
        self.assertIn('pending',by_id['unbroken-word'])

    def test_previous_generic_capture_body_is_identical(self):
        before=ast.parse(subprocess.check_output(['git','-C',str(ROOT),'show','af532b17:tool/parity_lib/react.py'],text=True))
        after=ast.parse((ROOT/'tool/parity_lib/react.py').read_text())
        original=next(n for n in before.body if isinstance(n,ast.FunctionDef) and n.name=='_capture_generic')
        current=next(n for n in after.body if isinstance(n,ast.FunctionDef) and n.name=='_capture_generic')
        self.assertEqual(ast.dump(original,include_attributes=False),ast.dump(current,include_attributes=False))

    def test_unknown_schema_is_rejected(self):
        original=builder.DATA
        try:
            with tempfile.TemporaryDirectory() as temporary:
                builder.DATA=Path(temporary)/'data.dart'
                builder.DATA.write_text("const toastScenarioJson = r'''\n{\"schema\":\"invalid\"}\n''';")
                with self.assertRaises(ValueError):builder.fixture()
        finally:builder.DATA=original

    def test_additive_builder_preserves_existing_manager_and_card_cases(self):
        with tempfile.TemporaryDirectory() as temporary:
            file=Path(temporary)/'cases.json'
            old=[{'id':'components.icon-actions.retained','sentinel':'manager'},
                 {'id':'components.plugin-card.retained','sentinel':'card'}]
            file.write_text(json.dumps({'cases':old}))
            subprocess.run([sys.executable,str(ROOT/'tool/parity-ext/build-toasts.py')],
                env=dict(os.environ,PARITY_EXT_MANIFEST=str(file)),check=True,capture_output=True)
            actual=json.loads(file.read_text())['cases']
            self.assertEqual(actual[:2],old)
            self.assertEqual(len(actual),226)


if __name__=='__main__':unittest.main()
