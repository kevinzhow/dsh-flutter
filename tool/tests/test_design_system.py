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
    def test_segmented_tab_transition_tracks_each_source_duration_and_rejects_unknown_easing(self):
        import copy
        lock, sheets = gen.collect()
        altered = copy.deepcopy(sheets)
        next(r for r in altered['SegmentedTabs.module.css'] if r['selector'] == '.tab')['declarations']['transition'] = 'color 220ms ease'
        dart, _ = gen.render(lock, altered)
        self.assertIn('labelTransitionMs = 220.0;', dart)
        self.assertIn('transitionMs = 180.0;', dart)
        self.assertIn('focusLineOffset = 4.0;', dart)
        self.assertIn('labelPadding = 12.0;', dart)
        for selector, value in [('.indicator', 'transform 180ms linear'), ('.tab', 'color 180ms linear'), ('.tab', 'opacity 180ms ease')]:
            altered = copy.deepcopy(sheets)
            next(r for r in altered['SegmentedTabs.module.css'] if r['selector'] == selector)['declarations']['transition'] = value
            with self.subTest(selector=selector, value=value), self.assertRaisesRegex(ValueError, 'unsupported tab transition'):
                gen.render(lock, altered)

    def test_plugin_button_states_fail_closed_and_source_drift_is_detected(self):
        import copy
        _, sheets = gen.collect()
        original = sheets['PluginManagerPage.module.css']
        source = [gen.normalized_rule(r) for r in original]
        gen.verify_feature_source(original, source)
        menu_drift = copy.deepcopy(source)
        next(r for r in menu_drift if r['selector'] == '.addMenu')['declarations']['width'] = '322px'
        with self.assertRaisesRegex(ValueError, 'reference menu CSS differs'):
            gen.verify_feature_source(original, menu_drift)
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

    def test_menu_rejects_new_states_conditions_and_untranslated_values(self):
        import copy
        lock, sheets = gen.collect()
        mutations = [
            ('Menu.module.css', '.item', 'display', 'grid'),
            ('Menu.module.css', '.itemIcon svg, .check', 'height', '15px'),
            ('Menu.module.css', '.submenu', 'left', 'calc(100% + 12px)'),
            ('MenuSurface.module.css', '.material', 'pointer-events', 'auto'),
            ('MenuGroup.module.css', '.heading', 'position', 'relative'),
            ('PluginManagerPage.module.css', '.addMenuItem', 'display', 'block'),
        ]
        for sheet, selector, prop, change in mutations:
            altered = copy.deepcopy(sheets)
            next(r for r in altered[sheet] if r['selector'] == selector)['declarations'][prop] = change
            with self.subTest(sheet=sheet, selector=selector, prop=prop), self.assertRaisesRegex(ValueError, 'untranslated'):
                gen.render(lock, altered)
        for rule in [
            {'selector': '.item:active', 'conditions': [], 'declarations': {'opacity': '.2'}},
            {'selector': '.item', 'conditions': ['@media (prefers-color-scheme: dark)'], 'declarations': {'color': 'red'}},
        ]:
            altered = copy.deepcopy(sheets)
            altered['Menu.module.css'].append(rule)
            with self.assertRaisesRegex(ValueError, 'untranslated menu'):
                gen.render(lock, altered)

    def test_menu_generated_fields_follow_source_not_a_frozen_local_copy(self):
        import copy
        lock, sheets = gen.collect()
        altered = copy.deepcopy(sheets)
        next(r for r in altered['Menu.module.css'] if r['selector'] == '.compactList .item')['declarations']['min-height'] = '26px'
        dart, _ = gen.render(lock, altered)
        self.assertIn('compactHeight = 26.0;', dart)
        altered = copy.deepcopy(sheets)
        next(r for r in altered['PluginManagerPage.module.css'] if r['selector'] == '.addMenu')['declarations']['max-width'] = 'none'
        with self.assertRaisesRegex(ValueError, 'unsupported plugin menu viewport'):
            gen.render(lock, altered)

    def test_menu_group_recipe_tracks_published_values(self):
        import copy
        lock, sheets = gen.collect()
        altered = copy.deepcopy(sheets)
        next(r for r in altered['MenuGroup.module.css'] if r['selector'] == '.group + .group')['declarations']['margin-top'] = '5px'
        next(r for r in altered['MenuGroup.module.css'] if r['selector'] == '.heading')['declarations']['padding'] = '6px 8px 3px'
        dart, _ = gen.render(lock, altered)
        self.assertIn('gap = 5.0;', dart)
        self.assertIn('paddingTop = 6.0;', dart)
        self.assertIn('paddingHorizontal = 8.0;', dart)
        self.assertIn('paddingBottom = 3.0;', dart)

    def test_shortcut_recipe_tracks_published_values_and_rejects_unknown_rules(self):
        import copy
        lock, sheets = gen.collect()
        altered = copy.deepcopy(sheets)
        next(r for r in altered['ShortcutKeys.module.css'] if r['selector'] == '.keys')['declarations']['gap'] = '4px'
        next(r for r in altered['Menu.module.css'] if r['selector'] == '.shortcut .shortcutKeys')['declarations']['line-height'] = '17px'
        dart, _ = gen.render(lock, altered)
        self.assertIn('plainGap = 4.0;', dart)
        self.assertIn('shortcutLineHeight = 17.0;', dart)
        for rule in [
            {'selector': '.key:hover', 'conditions': [], 'declarations': {'color': 'red'}},
            {'selector': '.keys', 'conditions': ['@media (prefers-color-scheme: dark)'], 'declarations': {'color': 'red'}},
        ]:
            changed = copy.deepcopy(sheets)
            changed['ShortcutKeys.module.css'].append(rule)
            with self.assertRaisesRegex(ValueError, 'untranslated'):
                gen.render(lock, changed)
        changed = copy.deepcopy(sheets)
        next(r for r in changed['ShortcutKeys.module.css'] if r['selector'] == '.tooltip .key')['declarations']['padding'] = '0 3px'
        dart, _ = gen.render(lock, changed)
        self.assertIn('keyPadding = 3.0;', dart)

    def test_tooltip_recipe_follows_published_geometry_and_rejects_new_states(self):
        import copy
        lock, sheets = gen.collect()
        altered = copy.deepcopy(sheets)
        bubble = next(r for r in altered['Tooltip.module.css'] if r['selector'] == '.bubble' and not r['conditions'])
        bubble['declarations']['padding'] = '4px 9px'
        dart, _ = gen.render(lock, altered)
        self.assertIn('paddingVertical = 4.0;', dart)
        self.assertIn('paddingHorizontal = 9.0;', dart)
        changed = copy.deepcopy(sheets)
        next(r for r in changed['Tooltip.module.css'] if r['selector'] == '.bubble' and r['conditions'])['declarations']['animation'] = 'opacity 1s'
        with self.assertRaisesRegex(ValueError, 'untranslated tooltip'):
            gen.render(lock, changed)
        changed = copy.deepcopy(sheets)
        changed['Tooltip.module.css'].append({'selector': '.bubble:hover', 'conditions': [], 'declarations': {'opacity': '.5'}})
        with self.assertRaisesRegex(ValueError, 'untranslated tooltip'):
            gen.render(lock, changed)

    def test_input_recipe_follows_published_css_and_rejects_unknown_states(self):
        import copy
        lock, sheets = gen.collect()
        changed = copy.deepcopy(sheets)
        next(r for r in changed['Input.module.css'] if r['selector'] == '.wrap')['declarations']['padding'] = '0 10px'
        dart, _ = gen.render(lock, changed)
        self.assertIn('padding = 10.0;', dart)
        changed = copy.deepcopy(sheets)
        changed['Input.module.css'].append({'selector': '.wrap:disabled', 'conditions': [], 'declarations': {'opacity': '.5'}})
        with self.assertRaisesRegex(ValueError, 'untranslated input'):
            gen.render(lock, changed)
        changed = copy.deepcopy(sheets)
        next(r for r in changed['Input.module.css'] if r['selector'] == '.input')['declarations']['outline'] = 'auto'
        with self.assertRaisesRegex(ValueError, 'untranslated input'):
            gen.render(lock, changed)

    def test_switch_recipe_tracks_geometry_and_rejects_unknown_states(self):
        import copy
        lock, sheets = gen.collect()
        changed = copy.deepcopy(sheets)
        next(r for r in changed['Switch.module.css'] if r['selector'] == '.switch:disabled')['declarations']['opacity'] = '0.4'
        dart, _ = gen.render(lock, changed)
        self.assertIn('disabledOpacity = 0.4;', dart)
        changed = copy.deepcopy(sheets)
        changed['Switch.module.css'].append({'selector': '.switch:hover', 'conditions': [], 'declarations': {'background': 'red'}})
        with self.assertRaisesRegex(ValueError, 'untranslated switch'):
            gen.render(lock, changed)
        changed = copy.deepcopy(sheets)
        next(r for r in changed['Switch.module.css'] if r['selector'] == ".switch[aria-checked='true'] .thumb")['declarations']['transform'] = 'translateX(15px)'
        with self.assertRaisesRegex(ValueError, 'switch thumb geometry'):
            gen.render(lock, changed)

    def test_checkbox_profiles_track_source_and_reject_unknown_states(self):
        import copy
        lock, sheets = gen.collect()
        changed = copy.deepcopy(sheets)
        next(r for r in changed['Checkbox.module.css'] if r['selector'] == '.checkbox')['declarations']['gap'] = '8px'
        dart, _ = gen.render(lock, changed)
        self.assertIn('gap = 8.0;', dart)
        changed = copy.deepcopy(sheets)
        next(r for r in changed['RiskConfirmation.module.css'] if r['selector'] == '.acknowledgement input')['declarations']['margin'] = '4px 0 0'
        dart, _ = gen.render(lock, changed)
        self.assertIn('riskInputTop = 4.0;', dart)
        changed = copy.deepcopy(sheets)
        changed['Checkbox.module.css'].append({'selector': '.checkbox input:hover', 'conditions': [], 'declarations': {'opacity': '.4'}})
        with self.assertRaisesRegex(ValueError, 'untranslated checkbox'):
            gen.render(lock, changed)
        changed = copy.deepcopy(sheets)
        changed['ChromiumCheckbox']['geometry']['checkStrokeRatio'] = 0.18
        dart, _ = gen.render(lock, changed)
        self.assertIn('checkStrokeRatio = 0.18;', dart)
        changed['ChromiumCheckbox']['geometry']['newShape'] = 1.0
        with self.assertRaisesRegex(ValueError, 'unrecognized Chromium checkbox geometry'):
            gen.render(lock, changed)
        changed = copy.deepcopy(sheets)
        changed['ChromiumCheckbox']['palette']['light']['hover']['offFill'] = '#010203'
        with self.assertRaisesRegex(ValueError, 'unsupported Chromium checkbox hover'):
            gen.render(lock, changed)

    def test_pill_and_market_group_track_source_and_reject_unknown_states(self):
        import copy
        lock, sheets = gen.collect()
        changed = copy.deepcopy(sheets)
        next(r for r in changed['Pill.module.css'] if r['selector'] == '.pill')['declarations']['height'] = '26px'
        dart, _ = gen.render(lock, changed)
        self.assertIn('height = 26.0;', dart)
        changed = copy.deepcopy(sheets)
        next(r for r in changed['DiscoverSection.module.css'] if r['selector'] == '.categories')['declarations']['gap'] = '8px'
        dart, _ = gen.render(lock, changed)
        self.assertIn('categoryGap = 8.0;', dart)
        changed = copy.deepcopy(sheets)
        changed['Pill.module.css'].append({'selector': '.pill:focus', 'conditions': [], 'declarations': {'color': 'red'}})
        with self.assertRaisesRegex(ValueError, 'untranslated pill'):
            gen.render(lock, changed)

    def test_tag_tints_follow_source_and_unknown_tones_fail(self):
        import copy
        lock, sheets = gen.collect()
        changed = copy.deepcopy(sheets)
        rule = next(r for r in changed['Tag.module.css'] if r['selector'] == ".tag[data-tone='warning']")
        rule['declarations']['background'] = 'color-mix(in srgb, var(--dsw-alias-state-warn-primary) 15%, transparent)'
        dart, _ = gen.render(lock, changed)
        self.assertIn('warningAlpha = 0.15;', dart)
        changed = copy.deepcopy(sheets)
        changed['Tag.module.css'].append({'selector': ".tag[data-tone='new']", 'conditions': [], 'declarations': {'color': 'red'}})
        with self.assertRaisesRegex(ValueError, 'untranslated tag'):
            gen.render(lock, changed)

    def test_menu_viewport_limits_are_generated_and_unknown_expressions_fail(self):
        import copy
        lock, original = gen.collect()
        altered = copy.deepcopy(original)
        rule = next(r for r in altered['Menu.module.css'] if r['selector'] == '.scrollable')
        rule['declarations']['max-height'] = 'calc(100vh - 15px - max(14px, var(--dsh-frame-overlay-top, 13px)))'
        dart, _ = gen.render(lock, altered)
        for field, expected in [('viewportBottomMargin', 15), ('viewportTopMargin', 14), ('frameOverlayTopFallback', 13)]:
            self.assertIn(f'{field} = {expected}.0;', dart)
        for unknown in ['100vh', 'calc(100vh - 20px)', 'min(520px, 100vh)']:
            rule['declarations']['max-height'] = unknown
            with self.assertRaisesRegex(ValueError, 'unsupported menu viewport height'):
                gen.render(lock, altered)

    def test_published_menu_portal_structure_fails_closed(self):
        spec = importlib.util.spec_from_file_location('menu_recipes', ROOT / 'tool/design-system/menu_recipes.py')
        module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
        snapshot = json.loads((ROOT / 'tool/design-system/upstream/ui-primitives/menu-portal.json').read_text())
        contract = json.loads((ROOT / 'tool/design-system/menu-contract.json').read_text())['portalPlacement']
        self.assertEqual(module.portal_margin(snapshot['placement'], 4, contract), 12)
        self.assertEqual(module.portal_margin(snapshot['placement'].replace('MARGIN = 12', 'MARGIN = 16'), 4, contract), 16)
        for changed in [snapshot['placement'].replace('Math.min(Math.max(x, MARGIN)', 'Math.max(Math.min(x, MARGIN)'), snapshot['placement'].replace('r.right + 4', 'r.right + 5')]:
            with self.assertRaisesRegex(ValueError, 'untranslated menu portal placement'):
                module.portal_margin(changed, 4, contract)

    def test_dock_menu_rules_and_dynamic_fields_fail_closed(self):
        import copy
        lock, original = gen.collect()
        altered = copy.deepcopy(original)
        next(r for r in altered['dockkit.module.css'] if r['selector'] == '.menuItem')['declarations']['font-size'] = 'calc(var(--dsh-content-font-size-secondary, 13px) - 2px)'
        dart, _ = gen.render(lock, altered)
        self.assertIn('fontBase = 11.0;', dart)
        for change in [
          {'selector': '.menuItem:active', 'conditions': [], 'declarations': {'opacity': '.2'}},
          {'selector': '.menuItem', 'conditions': ['@media (prefers-color-scheme: dark)'], 'declarations': {'color': 'red'}},
        ]:
            altered = copy.deepcopy(original)
            altered['dockkit.module.css'].append(change)
            with self.assertRaisesRegex(ValueError, 'untranslated menu'):
                gen.render(lock, altered)
        altered = copy.deepcopy(original)
        next(r for r in altered['dockkit.module.css'] if r['selector'] == '.menu')['declarations']['display'] = 'grid'
        with self.assertRaisesRegex(ValueError, 'untranslated menu structural'):
            gen.render(lock, altered)

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
