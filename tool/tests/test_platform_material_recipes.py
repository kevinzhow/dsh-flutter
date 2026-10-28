import copy
import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('platform_generate', ROOT / 'tool/design-system/generate.py')
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


class PlatformMaterialTests(unittest.TestCase):
    def test_platform_colours_are_generated_and_new_scopes_fail_closed(self):
        lock, sheets = gen.collect()
        _, audit = gen.render(lock, sheets)
        self.assertEqual(json.loads(audit)['metrics']['DshPlatformMaterialRecipe'], {
            'darwinLightMenuFill': '#f8f9faf0', 'darwinDarkMenuFill': '#303136f0',
        })
        changed = copy.deepcopy(sheets)
        changed['PlatformMenuMaterial'][0]['declarations']['--dsw-specific-menu'] = '#112233ee'
        _, audit = gen.render(lock, changed)
        self.assertEqual(json.loads(audit)['metrics']['DshPlatformMaterialRecipe']['darwinLightMenuFill'], '#112233ee')
        for mode in ('duplicate', 'missing', 'new-platform', 'new-condition', 'new-property'):
            changed = copy.deepcopy(sheets)
            rules = changed['PlatformMenuMaterial']
            if mode == 'duplicate':
                rules.append(copy.deepcopy(rules[0]))
            elif mode == 'missing':
                rules.pop()
            elif mode == 'new-platform':
                rules[0]['selector'] = 'html[data-platform=windows] body'
            elif mode == 'new-condition':
                rules[0]['conditions'] = ['@media (prefers-color-scheme: dark)']
            else:
                rules[0]['declarations']['--unknown-material'] = '#fff'
            with self.subTest(mode=mode), self.assertRaisesRegex(ValueError, 'platform menu material scope'):
                gen.render(lock, changed)
