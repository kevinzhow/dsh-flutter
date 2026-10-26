import importlib.util
import json
import pathlib
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]

def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'tool/design-system' / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

gen, guard = module('generate'), module('check')

class DesignSystemTests(unittest.TestCase):
    def test_plugin_button_states_fail_closed_and_source_drift_is_detected(self):
        import copy
        _, sheets = gen.collect()
        original = sheets['PluginManagerPage.module.css']
        source = [gen.normalized_rule(r) for r in original]
        gen.verify_feature_source(original, source)
        for amendment in [
            {'selector': '.iconButton:active', 'conditions': [], 'declarations': {'opacity': '.2'}},
            {'selector': '.addMore', 'conditions': ['@media (prefers-color-scheme: dark)'], 'declarations': {'color': 'red'}},
        ]:
            altered = copy.deepcopy(sheets)
            altered['PluginManagerPage.module.css'].append(amendment)
            with self.assertRaisesRegex(ValueError, 'untranslated plugin'):
                gen.validate_supported(altered)
        altered = copy.deepcopy(source)
        next(r for r in altered if r['selector'] == '.iconButton')['declarations']['width'] = '29px'
        with self.assertRaisesRegex(ValueError, 'reference button CSS differs'):
            gen.verify_feature_source(original, altered)
        altered = copy.deepcopy(sheets)
        next(r for r in altered['PluginManagerPage.module.css'] if r['selector'] == '.iconButton')['declarations']['display'] = 'block'
        with self.assertRaisesRegex(ValueError, 'untranslated plugin button value'):
            gen.validate_supported(altered)

    def test_css_parser_preserves_literals_and_conditional_scope(self):
        css = '.x:is(.a, .b) { background: url("data:image/svg+xml;abc"); content: "a;{b}" } @media(max-width:600px) {.x {width:.5px}}'
        parsed = gen.css_rules(css)
        self.assertEqual(parsed[0]['selector'], '.x:is(.a, .b)')
        self.assertEqual(parsed[0]['declarations']['content'], '"a;{b}"')
        self.assertEqual(parsed[1]['conditions'], ['@media (max-width: 600px)'])
        self.assertEqual(gen.number(parsed[1]['declarations']['width']), .5)
        with self.assertRaises(ValueError): gen.css_rules('@keyframes spin {to {opacity:0}}')
        self.assertEqual(gen.css_rules('@keyframes spin {to {opacity:0}}', allow_keyframes=True)[0]['conditions'], ['@keyframes spin'])

    def test_conditional_rules_remain_in_recipe_audit(self):
        rules = gen.css_rules('.tab { color: var(--label); } @media (prefers-reduced-motion: reduce) { .tab { transition: none; } }')
        self.assertEqual(rules[1]['conditions'], ['@media (prefers-reduced-motion: reduce)'])
        self.assertEqual(rules[1]['declarations'], {'transition': 'none'})
        for css in ['@supports (a: b) {.tab {width: 1px}}', '.tab {width: 1px; width: 2px}', '.tab { &:hover {color: red} }', '.tab {width: 1px']:
            with self.subTest(css=css), self.assertRaises(ValueError):
                gen.css_rules(css)

    def test_new_dark_rules_and_untranslated_properties_fail_closed(self):
        _, original = gen.collect()
        import copy
        for amendment in [
            {'selector': '.tab', 'conditions': ['@media (prefers-color-scheme: dark)'], 'declarations': {'color': 'black'}},
            {'selector': '.new-tab-state', 'conditions': [], 'declarations': {'color': 'black'}},
        ]:
            altered = copy.deepcopy(original)
            altered['SegmentedTabs.module.css'].append(amendment)
            with self.assertRaisesRegex(ValueError, 'untranslated'):
                gen.validate_supported(altered)
        altered = copy.deepcopy(original)
        altered['Button.module.css'][0]['declarations']['box-shadow'] = 'none'
        with self.assertRaisesRegex(ValueError, 'untranslated'):
            gen.validate_supported(altered)

    def test_dependency_version_drift_is_rejected_even_with_matching_css(self):
        lock = json.loads((ROOT / 'tool/design-system/sources.lock.json').read_text())
        p = lock['packages'][0]
        with tempfile.TemporaryDirectory() as d:
            source = pathlib.Path(d)
            manifest = source / p['sourcePackage']; manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({'version': '0.3.0'}))
            consumer = source / p['referenceConsumer']; consumer.parent.mkdir(parents=True)
            consumer.write_text(json.dumps({p['dependencyField']: {p['name']: p['dependencySpecifier']}}))
            with self.assertRaisesRegex(ValueError, 'version drift'):
                gen.collect(source)

    def test_increasing_baseline_cannot_hide_a_new_bypass(self):
        previous = {'patterns': {'bypass': r'\bTextButton\s*\('}, 'baseline': {'old.dart': {'bypass': 1}}}
        changed = {'patterns': previous['patterns'], 'baseline': {'old.dart': {'bypass': 2}}}
        self.assertIn('baseline bypass increased 1 -> 2', guard.baseline_growth(changed, previous, lambda _: '')[0])
        # During bootstrap, counts cannot exceed violations in the actual base.
        self.assertTrue(guard.baseline_growth(changed, None, lambda _: 'TextButton();'))
        changed['baseline']['old.dart']['bypass'] = 1
        self.assertFalse(guard.baseline_growth(changed, None, lambda _: 'TextButton();'))

    def test_ratchets_are_per_file_and_ignore_comments_or_string_literals(self):
        contract = {'patterns': {'bypass': r'\bTextButton\s*\('}, 'wrapperAllowlist': {}, 'baseline': {'apps/a/lib/old.dart': {'bypass': 1}}, 'families': [], 'remediation': {'bypass': 'use DshButton'}}
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d)
            for name in ['apps/a/lib', 'features', 'packages']:
                (root / name).mkdir(parents=True)
            old = root / 'apps/a/lib/old.dart'; new = root / 'apps/a/lib/new.dart'
            old.write_text('TextButton(); // TextButton()\n const sample = "TextButton()";')
            counts, failures = guard.inspect(root, contract)
            self.assertFalse(failures)
            self.assertEqual(counts, {'apps/a/lib/old.dart': {'bypass': 1}})
            old.write_text('')
            new.write_text('TextButton();')
            _, failures = guard.inspect(root, contract)
            self.assertIn('new.dart: bypass grew 0 -> 1', failures[0])
            new.write_text('')
            _, failures = guard.inspect(root, contract)
            self.assertFalse(failures)

if __name__ == '__main__':
    unittest.main()
