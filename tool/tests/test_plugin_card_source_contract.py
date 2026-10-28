"""Loaded cards translate source fields and freeze every other source branch."""
import copy
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
def module(name):
    spec = importlib.util.spec_from_file_location('card_test_' + name, ROOT / 'tool/design-system' / (name + '.py'))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded

gen, published = module('generate'), module('published')
NEW = {'DshPluginCardListRecipe', 'DshPluginCardRecipe', 'DshPluginStatusTagRecipe'}
SHEET = 'PluginManagerPage.module.css'


class PluginCardSourceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lock, cls.sheets = gen.collect()
        cls.behavior = json.loads((ROOT / 'tool/design-system/upstream/ui-plugin-manager/loaded-card-behavior.json').read_text())

    def render(self, sheets=None):
        return json.loads(gen.render(self.lock, sheets or self.sheets)[1])['metrics']

    def change(self, selector, prop, raw):
        sheets = copy.deepcopy(self.sheets)
        next(r for r in sheets[SHEET] if r['selector'] == selector and not r['conditions'])['declarations'][prop] = raw
        return sheets

    def test_actual_content_box_and_natural_layout_values(self):
        metrics = self.render()
        self.assertTrue(NEW <= metrics.keys())
        card = metrics['DshPluginCardRecipe']
        self.assertEqual(metrics['DshPluginCardListRecipe']['gap'], 2)
        self.assertEqual((card['horizontalMargin'], card['headGap'], card['headPadding'], card['endGap']), (-8, 14, 8, 8))
        self.assertEqual((card['iconWidth'], card['iconHeight'], card['iconBorderWidth'], card['artworkSize']), (48, 48, .5, 36))
        self.assertEqual((card['titleFontSize'], card['titleLineHeight'], card['titleWeight'], card['titleMaxLines']), (14, 20, 500, 1))
        self.assertEqual((card['descriptionFontSize'], card['descriptionLineHeight'], card['descriptionMaxLines']), (13, 18, 1))
        self.assertEqual(card['experimentalPrefix'], '@deepseek-ai/dsh-experimental-')
        self.assertNotIn('height', card)
        self.assertEqual(metrics['DshPluginStatusTagRecipe'], {'contentHeight': 18, 'verticalPadding': 0,
            'horizontalPadding': 7, 'fontSize': 10, 'lineHeightFactor': 1})

    def test_unknown_card_conditions_generic_cascade_and_highlight_stay_closed(self):
        for rule in [
            {'selector': '.card:active', 'conditions': [], 'declarations': {'opacity': '.5'}},
            {'selector': '.cardHead', 'conditions': ['@media (max-width: 600px)'], 'declarations': {'gap': '8px'}},
            {'selector': 'button', 'conditions': [], 'declarations': {'min-width': '100px'}},
        ]:
            sheets = copy.deepcopy(self.sheets); sheets[SHEET].append(rule)
            with self.subTest(rule=rule), self.assertRaises(ValueError): self.render(sheets)
        for selector, prop, raw in [('.card[data-plugin-highlight]', 'animation', 'none'),
                                    ('.card', '--dsh-scrollbar-thumb', 'red')]:
            with self.subTest(selector=selector), self.assertRaises(ValueError): self.render(self.change(selector, prop, raw))

    def test_structural_ownership_wrapping_and_resets_cannot_drift(self):
        for selector, prop, raw in [
            ('.cardLink', 'position', 'static'), ('.cardOpen', 'padding', '1px'),
            ('.cardOpen', 'background', 'red'), ('.cardOpen:after', 'inset', '1px'),
            ('.titleRow', 'flex-wrap', 'nowrap'), ('.cardTitle', 'white-space', 'normal'),
            ('.cardEnd', 'z-index', '0'), ('.packageImage', 'object-fit', 'cover'),
            ('.reason', 'white-space', 'normal'),
        ]:
            with self.subTest(selector=selector, prop=prop), self.assertRaises(ValueError): self.render(self.change(selector, prop, raw))

    def test_duplicate_title_metrics_and_card_outline_radii_must_agree(self):
        for selector, prop, raw in [('.cardOpen', 'font-size', '15px'),
                                    ('.cardOpen', 'font-weight', '600'),
                                    ('.cardOpen:after', 'border-radius', 'var(--dsw-radius-lg)')]:
            with self.subTest(selector=selector, prop=prop), self.assertRaises(ValueError): self.render(self.change(selector, prop, raw))

    def test_invalid_card_numeric_and_token_roles_fail_before_dart(self):
        for selector, prop, raw in [('.cardIcon', 'width', '0px'), ('.cardIcon', 'height', '-1px'),
            ('.cardHead', 'gap', '-1px'), ('.statusTag', 'height', '0px'),
            ('.statusTag', 'line-height', '０.５'), ('.cardDesc', '-webkit-line-clamp', '1.5'),
            ('.card', 'border-radius', 'var(--dsw-alias-label-primary)'),
            ('.cardIcon', 'border', '.5px solid var(--dsw-radius-sm)')]:
            with self.subTest(selector=selector, prop=prop), self.assertRaises(ValueError): self.render(self.change(selector, prop, raw))

    def test_consumed_values_propagate_without_other_recipe_changes(self):
        before = self.render(); sheets = self.change('.cardHead', 'gap', '16px')
        for selector, values in {'.card': {'margin': '0 -10px'}, '.cards': {'gap': '3px'},
            '.cardIcon': {'width': '52px', 'height': '50px'}, '.statusTag': {'height': '20px', 'padding': '1px 8px'},
            '.cardOpen:focus-visible:after': {'outline-offset': '-2px'}}.items():
            next(r for r in sheets[SHEET] if r['selector'] == selector and not r['conditions'])['declarations'].update(values)
        sheets['PluginCardBehavior'] = copy.deepcopy(self.behavior)
        sheets['PluginCardBehavior']['region'] = self.behavior['region'].replace('const CARD_ARTWORK_SIZE = 36;', 'const CARD_ARTWORK_SIZE = 40;')
        after = self.render(sheets)
        self.assertTrue(NEW <= after.keys())
        self.assertEqual({k: v for k, v in before.items() if k not in NEW}, {k: v for k, v in after.items() if k not in NEW})
        card = after['DshPluginCardRecipe']
        self.assertEqual((card['headGap'], card['horizontalMargin'], card['artworkSize'], card['focusOffset']), (16, -10, 40, -2))
        self.assertEqual(after['DshPluginStatusTagRecipe']['verticalPadding'], 1)

    def test_complete_published_behavior_predicates_and_pending_context_fail_closed(self):
        for old, new in [
            ('disabled: busy || pkg.readOnlyReason !== void 0', 'disabled: busy'),
            ('return pkg.enabled ? "running" : "disabled";', 'return pkg.enabled ? "disabled" : "running";'),
            ('src === failedSource', 'false'),
            ('!pkg.installed || !pkg.removable', '!pkg.installed'),
            ('t("metadataError", { error })', 't("metadata Error", { error })'),
            ('onClick: onOpen', 'onClick: onSetEnabled'),
            ('const HIGHLIGHT_MS = 2400;', 'const HIGHLIGHT_MS = 2200;'),
        ]:
            self.assertIn(old, self.behavior['region'])
            sheets = copy.deepcopy(self.sheets); sheets['PluginCardBehavior'] = copy.deepcopy(self.behavior)
            sheets['PluginCardBehavior']['region'] = self.behavior['region'].replace(old, new, 1)
            with self.subTest(old=old), self.assertRaises(ValueError): self.render(sheets)

    def test_prefix_is_consumed_but_predicate_and_literal_boundaries_stay_closed(self):
        sheets = copy.deepcopy(self.sheets); sheets['PluginCardBehavior'] = copy.deepcopy(self.behavior)
        sheets['PluginCardBehavior']['presentationRegion'] = self.behavior['presentationRegion'].replace('beta: pkg.name.startsWith("@deepseek-ai/dsh-experimental-")', 'beta: pkg.name.startsWith("@deepseek-ai/dsh-preview-")', 1)
        metrics = self.render(sheets)
        self.assertTrue(NEW <= metrics.keys())
        self.assertEqual(metrics['DshPluginCardRecipe']['experimentalPrefix'], '@deepseek-ai/dsh-preview-')
        for old, new in [('const CARD_ARTWORK_SIZE = 36;', 'const CARD_ARTWORK_SIZE = ０３６;'),
                         ('const CARD_ARTWORK_SIZE = 36;', 'const CARD_ARTWORK_SIZE = 0;'),
                         ('"statusBeta"', '"status Beta"')]:
            sheets = copy.deepcopy(self.sheets); sheets['PluginCardBehavior'] = copy.deepcopy(self.behavior)
            sheets['PluginCardBehavior']['region'] = self.behavior['region'].replace(old, new, 1)
            with self.subTest(new=new), self.assertRaises(ValueError): self.render(sheets)

    def test_archive_decoder_retains_full_region_without_js_execution(self):
        body = '//#region lib/types/client/PluginManagerPage.js\nthrow new Error("never executed");\n//#endregion\n'
        css = '//#region lib/types/client/PluginManagerPage.module.css.mjs\nconst css = ".a{width:28px}";\nvar PluginManagerPage_module_css_default = {"a":"a"};\n//#endregion\n'
        with tempfile.TemporaryDirectory() as d:
            archive = Path(d) / 'package.tgz'
            with tarfile.open(archive, 'w:gz') as tar:
                for name, text in {'lib/client.js': css + body + '//#region lib/types/client/presentation.js\nthrow new Error("never executed");\n//#endregion\n', 'package.json': '{}', 'LICENSE': 'MIT'}.items():
                    raw = text.encode(); info = tarfile.TarInfo('package/' + name); info.size = len(raw); tar.addfile(info, io.BytesIO(raw))
            result = published.plugin_style_snapshot(archive)
            self.assertIn('behavior', result)
            self.assertEqual(result['behavior']['region'], body.split('//#endregion')[0])
            self.assertIn('never executed', result['behavior']['presentationRegion'])
            for mode in ('missing-manager', 'duplicate-manager', 'missing-presentation', 'duplicate-presentation'):
                presentation = '//#region lib/types/client/presentation.js\nthrow new Error("never executed");\n//#endregion\n'
                manager_body = '' if mode == 'missing-manager' else body * (2 if mode == 'duplicate-manager' else 1)
                presentation_body = '' if mode == 'missing-presentation' else presentation * (2 if mode == 'duplicate-presentation' else 1)
                with tarfile.open(archive, 'w:gz') as tar:
                    raw = (css + manager_body + presentation_body).encode()
                    info = tarfile.TarInfo('package/lib/client.js'); info.size = len(raw); tar.addfile(info, io.BytesIO(raw))
                with self.subTest(mode=mode), self.assertRaisesRegex(ValueError, 'missing/ambiguous'):
                    published.plugin_style_snapshot(archive)


if __name__ == '__main__': unittest.main()
