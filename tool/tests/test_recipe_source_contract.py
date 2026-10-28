"""Changes to supported source declarations must translate or fail explicitly."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('recipe_contract_generator', ROOT / 'tool/design-system/generate.py')
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


class RecipeSourceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lock, cls.sheets = gen.collect()

    def test_untranslated_tab_declarations_cannot_silently_keep_old_renderer(self):
        changes = [
            ('.tabs', 'position', 'absolute'),
            ('.tabs', 'display', 'block'),
            ('.indicator', 'position', 'relative'),
            ('.indicator', 'inset', '5px auto 4px 4px'),
            ('.indicator', 'pointer-events', 'auto'),
            ('.tab', 'position', 'absolute'),
            ('.tab', 'justify-content', 'start'),
            ('.tab', 'border-radius', 'var(--dsw-radius-lg)'),
            ('.tab', 'background', 'var(--dsw-alias-bg-layer-3)'),
            (".tab:hover, .tab[aria-selected='true']", 'background', 'var(--dsw-alias-bg-layer-3)'),
            ('.tab:focus-visible', 'outline', '1px solid red'),
            ('.tab:focus-visible', 'text-decoration', 'none'),
        ]
        for selector, prop, value in changes:
            changed = copy.deepcopy(self.sheets)
            rule = next(r for r in changed['SegmentedTabs.module.css'] if r['selector'] == selector)
            rule['declarations'][prop] = value
            with self.subTest(selector=selector, prop=prop), self.assertRaisesRegex(ValueError, 'untranslated'):
                gen.render(self.lock, changed)

    def test_reduced_motion_has_required_exclusive_family_ownership(self):
        motion = next(r for r in self.sheets['SegmentedTabs.module.css'] if r['conditions'])
        for mode in ['missing', 'duplicate', 'wrong-family']:
            changed = copy.deepcopy(self.sheets)
            if mode == 'missing':
                changed['SegmentedTabs.module.css'] = [r for r in changed['SegmentedTabs.module.css'] if not r['conditions']]
            else:
                family = 'Button.module.css' if mode == 'wrong-family' else 'SegmentedTabs.module.css'
                changed[family].append(copy.deepcopy(motion))
            with self.subTest(mode=mode), self.assertRaisesRegex(ValueError, 'conditional'):
                gen.render(self.lock, changed)

    def test_unknown_theme_token_is_rejected_before_emitting_broken_lookup(self):
        changed = copy.deepcopy(self.sheets)
        next(r for r in changed['Button.module.css'] if r['selector'] == '.primary')['declarations']['background'] = 'var(--dsw-does-not-exist)'
        with self.assertRaisesRegex(ValueError, 'unknown.*token'):
            gen.render(self.lock, changed)

    def test_supported_source_geometry_still_changes_generated_recipe(self):
        changed = copy.deepcopy(self.sheets)
        next(r for r in changed['SegmentedTabs.module.css'] if r['selector'] == '.tab')['declarations']['height'] = '38px'
        next(r for r in changed['SegmentedTabs.module.css'] if r['selector'] == '.tabs')['declarations']['padding'] = '6px'
        next(r for r in changed['SegmentedTabs.module.css'] if r['selector'] == '.indicator')['declarations']['inset'] = '6px auto 6px 6px'
        _, audit = gen.render(self.lock, changed)
        recipe = json.loads(audit)['metrics']['DshSegmentedTabRecipe']
        self.assertEqual(recipe['height'], 38)
        self.assertEqual(recipe['padding'], 6)

    def test_nullable_separator_variable_keeps_source_css_inheritance(self):
        changed = copy.deepcopy(self.sheets)
        next(r for r in changed['StatsPills.module.css'] if r['selector'] == '.sep')['declarations']['color'] = 'var(--dsw-unset-separator-reference)'
        _, audit = gen.render(self.lock, changed)
        self.assertEqual(json.loads(audit)['metrics']['DshStatsPillRecipe']['separatorToken'],
                         '--dsw-unset-separator-reference')


if __name__ == '__main__':
    unittest.main()
