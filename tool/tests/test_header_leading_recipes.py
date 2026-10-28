"""Header's real release inputs must reach the generated profile or fail."""
import copy
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / 'tool/design-system'


def module(name):
    spec = importlib.util.spec_from_file_location(name, HERE / (name + '.py'))
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


gen = module('generate')
header = module('header_leading_recipes')


class HeaderLeadingRecipesTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lock, cls.sheets = gen.collect()

    def recipe(self, sheets):
        return header.build(sheets['HeaderLeadingControls.module.css'],
                            sheets['HeaderLeadingControlsBehavior'],
                            focus_context=sheets['HeaderLeadingFocusContext'],
                            number=gen.number, token=gen.token)['DshHeaderLeadingRecipe']

    def test_actual_release_geometry_and_behavior_are_generated(self):
        recipe = self.recipe(self.sheets)
        self.assertEqual((recipe['width'], recipe['height'], recipe['controlsGap'],
                          recipe['iconSize'], recipe['tooltipDelayMs']), (28, 28, 8, 16, 500))
        self.assertEqual(recipe['labelToken'], '--dsw-alias-label-secondary')
        self.assertEqual(recipe['radiusToken'], '--dsw-radius-sm')
        self.assertEqual(recipe['hoverToken'], '--dsw-alias-interactive-bg-hover')
        _, audit = gen.render(self.lock, self.sheets)
        self.assertEqual(json.loads(audit)['metrics']['DshHeaderLeadingRecipe'], recipe)

    def test_source_mutations_propagate_without_changing_other_profiles(self):
        changed = copy.deepcopy(self.sheets)
        controls, button, hover = changed['HeaderLeadingControls.module.css']
        controls['declarations']['gap'] = '9px'
        button['declarations'].update(width='31px', height='29px',
                                      color='var(--dsw-alias-label-caption)',
                                      **{'border-radius': 'var(--dsw-radius-md)'})
        hover['declarations']['background'] = 'var(--dsw-alias-interactive-bg-active)'
        changed['HeaderLeadingControlsBehavior']['region'] = changed['HeaderLeadingControlsBehavior']['region'].replace(
            'delayMs: 500', 'delayMs: 640').replace('size: 16', 'size: 18')
        _, before = gen.render(self.lock, self.sheets)
        _, after = gen.render(self.lock, changed)
        before, after = json.loads(before)['metrics'], json.loads(after)['metrics']
        recipe = after.pop('DshHeaderLeadingRecipe')
        before.pop('DshHeaderLeadingRecipe')
        self.assertEqual(before, after)
        self.assertEqual(recipe, dict(width=31, height=29, controlsGap=9, iconSize=18,
                                     tooltipDelayMs=640, labelToken='--dsw-alias-label-caption',
                                     radiusToken='--dsw-radius-md', hoverToken='--dsw-alias-interactive-bg-active',
                                     focusWidthToken='--dsw-focus-ring-width', focusToken='--dsw-focus-ring-color',
                                     focusFallbackToken='--dsw-alias-state-business-primary'))

    def test_unknown_states_properties_conditions_and_structure_fail_closed(self):
        for mode in ('active', 'focus', 'property', 'condition', 'structure', 'token'):
            changed = copy.deepcopy(self.sheets)
            sheet = changed['HeaderLeadingControls.module.css']
            if mode in ('active', 'focus'):
                sheet.append({'selector': '.iconButton:' + mode, 'conditions': [],
                              'declarations': {'background': 'red'}})
            elif mode == 'property':
                sheet[1]['declarations']['box-shadow'] = 'none'
            elif mode == 'condition':
                sheet[2]['conditions'] = ['@media (hover: hover)']
            elif mode == 'structure':
                sheet[1]['declarations']['padding'] = '1px'
            else:
                sheet[1]['declarations']['color'] = 'var(--untranslated-header-color)'
            with self.subTest(mode=mode), self.assertRaisesRegex(ValueError, 'untranslated|unknown source theme token'):
                self.recipe(changed)

    def test_changed_or_ambiguous_behavior_is_rejected(self):
        original = self.sheets['HeaderLeadingControlsBehavior']['region']
        for value in (original.replace('delayMs: 500', 'delayMs: sourceDelay'),
                      original.replace('delayMs: 500', 'delayMs: 600', 1),
                      original.replace('size: 16', 'size: 17', 1),
                      original.replace('size: 16', 'size: 0'),
                      original.replace('toggleSidebar();', 'startSession();'),
                      original.replace('IconNewChatOutlineRegular', 'IconCloseOutlineRegular'),
                      original + original):
            with self.subTest(value=value), self.assertRaisesRegex(ValueError, 'untranslated HeaderLeadingControls'):
                header.behavior_values(value)

    def test_semantic_whitespace_cannot_disappear_from_behavior_fingerprint(self):
        # Whitespace inside a string changes an actual shortcut/label/key.
        # Removing all whitespace also accepts an invalid split identifier.
        for before, after in [('"session.new"', '"session. new"'),
                              ('"toggle.open"', '"toggle. open"'),
                              ('toggleSidebar', 'toggle Sidebar')]:
            original = self.sheets['HeaderLeadingControlsBehavior']['region']
            self.assertIn(before, original)
            with self.subTest(after=after), self.assertRaisesRegex(
                    ValueError, 'untranslated HeaderLeadingControls'):
                header.behavior_values(original.replace(before, after))
        changed = copy.deepcopy(self.sheets)
        context = changed['HeaderLeadingFocusContext']
        original = context['inputModality']['region']
        self.assertIn('"PageDown"', original)
        context['inputModality']['region'] = original.replace('"PageDown"', '"Page Down"')
        with self.assertRaisesRegex(ValueError, 'untranslated HeaderLeadingControls'):
            self.recipe(changed)

    def test_only_supported_complete_ascii_decimal_literals_are_translated(self):
        original = self.sheets['HeaderLeadingControlsBehavior']['region']
        for before, after in [('delayMs: 500', 'delayMs: 0500'),
                              ('size: 16', 'size: 016'),
                              ('delayMs: 500', 'delayMs: ５００'),
                              ('size: 16', 'size: １６'),
                              ('delayMs: 500', 'delayMs: 500e0'),
                              ('size: 16', 'size: 16.0'),
                              ('delayMs: 500', 'delayMs: 500n'),
                              ('size: 16', 'size: +16')]:
            self.assertIn(before, original)
            with self.subTest(after=after), self.assertRaisesRegex(
                    ValueError, 'untranslated HeaderLeadingControls'):
                header.behavior_values(original.replace(before, after))

    def test_behavior_is_extracted_from_the_same_named_published_bundle(self):
        published = module('published')
        behavior = self.sheets['HeaderLeadingControlsBehavior']
        css = (HERE / 'upstream/ui-sidebar/HeaderLeadingControls.module.css').read_text()
        classes = json.loads((HERE / 'upstream/ui-sidebar/HeaderLeadingControls-classes.json').read_text())
        bundle = ('//#region lib/types/client/HeaderLeadingControls.module.css.mjs\nconst css = ' +
                  json.dumps(css) + ';\nvar HeaderLeadingControls_module_css_default = ' +
                  json.dumps(classes) + ';\n//#endregion\n' + behavior['region'] + '//#endregion\n')
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'sidebar.tgz'
            with tarfile.open(archive, 'w:gz') as tar:
                for name, text in {'lib/client.js': bundle, 'package.json': '{}', 'LICENSE': 'MIT'}.items():
                    data = text.encode()
                    info = tarfile.TarInfo('package/' + name)
                    info.size = len(data)
                    tar.addfile(info, io.BytesIO(data))
            snapshot = published.sidebar_component_snapshot(archive, ['HeaderLeadingControls'])
        self.assertEqual(snapshot['behavior']['HeaderLeadingControls-behavior.json'], {
            'bundleSha256': hashlib.sha256(bundle.encode()).hexdigest(), 'region': behavior['region']})
        with self.assertRaisesRegex(ValueError, 'missing/ambiguous'):
            published.bundle_region(bundle + behavior['region'] + '//#endregion', 'HeaderLeadingControls.js')

    def test_global_focus_source_has_no_header_specific_outline(self):
        # Header has no local :focus-visible rule. Its canonical button uses
        # the theme's generated global focus width/color and pointer modality.
        focus = (HERE / 'upstream/ui-theme/focus.css').read_text()
        self.assertIn('--dsw-focus-ring-width:2px', focus)
        self.assertIn('outline-width:var(--dsw-focus-ring-width)', focus)
        self.assertIn('html[data-input-modality=pointer]', focus)
        self.assertNotIn('outline-offset', focus)
        for mode in ('outline-offset', 'modality'):
            changed = copy.deepcopy(self.sheets)
            if mode == 'outline-offset':
                changed['HeaderLeadingFocusContext']['focus'][1]['declarations']['outline-offset'] = '1px'
            else:
                changed['HeaderLeadingFocusContext']['inputModality']['region'] = changed['HeaderLeadingFocusContext']['inputModality']['region'].replace('"PageDown"', '"Enter"')
            with self.subTest(mode=mode), self.assertRaisesRegex(ValueError, 'untranslated HeaderLeadingControls'):
                self.recipe(changed)


if __name__ == '__main__':
    unittest.main()
