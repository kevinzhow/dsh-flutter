import copy
import importlib.util
import json
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('model_menu_generate', ROOT / 'tool/design-system/generate.py')
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


class ModelMenuRecipeTests(unittest.TestCase):
    def test_published_menu_bounds_and_above_anchor_placement_drive_recipe(self):
        lock, sheets = gen.collect()
        _, audit = gen.render(lock, sheets)
        recipe = json.loads(audit)['metrics']['DshModelMenuRecipe']
        self.assertEqual({key: recipe[key] for key in ('minWidth', 'maxWidth', 'maxHeight', 'viewportWidthInset', 'viewportHeightInset', 'anchorGap', 'portalMargin', 'rowHeight', 'cellHeight')},
                         {'minWidth': 240, 'maxWidth': 420, 'maxHeight': 360, 'viewportWidthInset': 32, 'viewportHeightInset': 96,
                          'anchorGap': 8, 'portalMargin': 12, 'rowHeight': 34, 'cellHeight': 34})
        altered = copy.deepcopy(sheets)
        next(r for r in altered['ModelSelect.module.css'] if r['selector'] == '.menu')['declarations']['max-width'] = 'min(460px,100vw - 32px)'
        altered['ModelSelectBehavior']['region'] = altered['ModelSelectBehavior']['region'].replace('rect.top - 8 - lh', 'rect.top - 10 - lh')
        _, audit = gen.render(lock, altered)
        recipe = json.loads(audit)['metrics']['DshModelMenuRecipe']
        self.assertEqual(recipe['maxWidth'], 460)
        self.assertEqual(recipe['anchorGap'], 10)

    def test_unknown_menu_state_and_a_bottom_sheet_reinterpretation_are_rejected(self):
        lock, sheets = gen.collect()
        altered = copy.deepcopy(sheets)
        altered['ModelSelect.module.css'].append({'selector': '.menu:active', 'conditions': [], 'declarations': {'padding': '20px'}})
        with self.assertRaisesRegex(ValueError, 'untranslated model menu'):
            gen.render(lock, altered)
        altered = copy.deepcopy(sheets)
        altered['ModelSelectBehavior']['region'] = altered['ModelSelectBehavior']['region'].replace('rect.top - 8 - lh', 'rect.bottom + 8')
        with self.assertRaisesRegex(ValueError, 'placement'):
            gen.render(lock, altered)


if __name__ == '__main__':
    unittest.main()
