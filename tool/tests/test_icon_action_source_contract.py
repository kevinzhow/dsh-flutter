"""Upstream CSS drift must either reach a translated field or stop generation."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    'icon_action_contract_generate', ROOT / 'tool/design-system/generate.py')
gen = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gen)
SHEET = 'PluginManagerPage.module.css'


class IconActionSourceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lock, cls.sheets = gen.collect()
        cls.dart, cls.audit = gen.render(cls.lock, cls.sheets)
        cls.metrics = json.loads(cls.audit)['metrics']

    def changed(self, selector, prop, value):
        sheets = copy.deepcopy(self.sheets)
        next(r for r in sheets[SHEET] if r['selector'] == selector
             and not r['conditions'])['declarations'][prop] = value
        return sheets

    def assert_rejected(self, sheets):
        with self.assertRaises(ValueError):
            gen.render(self.lock, sheets)

    def rendered_metrics(self, sheets):
        return json.loads(gen.render(self.lock, sheets)[1])['metrics']

    def assert_only_recipe_changed(self, after, recipe):
        self.assertNotEqual(after[recipe], self.metrics[recipe])
        self.assertEqual({k: v for k, v in after.items() if k != recipe},
                         {k: v for k, v in self.metrics.items() if k != recipe})

    def test_real_inputs_preserve_both_generated_files_exactly(self):
        self.assertEqual(self.dart, gen.OUT.read_text())
        self.assertEqual(self.audit, gen.AUDIT.read_text())

    def test_generic_button_cascade_changes_cannot_escape_class_filter(self):
        for selector, declarations in [
            ('button:active', {'background': 'red'}),
            ('button', {'min-width': '100px'}),
            ('*', {'box-sizing': 'content-box'}),
            (':root', {'--dsw-alias-label-caption': 'red'}),
        ]:
            with self.subTest(selector=selector):
                sheets = copy.deepcopy(self.sheets)
                sheets[SHEET].append({'selector': selector, 'conditions': [],
                                      'declarations': declarations})
                self.assert_rejected(sheets)

    def test_generic_conditional_and_ancestor_overrides_are_not_ignored(self):
        for selector, conditions, declarations in [
            ('button', ['@media (prefers-color-scheme: dark)'], {'color': 'red'}),
            ('button:active', ['@supports (display: grid)'], {'background': 'red'}),
            ('.page', [], {'--dsw-alias-label-caption': 'red'}),
            ('.page .iconWrap button', [], {'opacity': '.2'}),
        ]:
            with self.subTest(selector=selector, conditions=conditions):
                sheets = copy.deepcopy(self.sheets)
                sheets[SHEET].append({'selector': selector, 'conditions': conditions,
                                      'declarations': declarations})
                self.assert_rejected(sheets)
        self.assert_rejected(self.changed('.page', '--dsw-alias-label-caption', 'red'))

    def test_pending_context_values_are_frozen_not_reported_as_implemented(self):
        for selector, prop, value in [
            ('.page', 'gap', '33px'),
            ('.danger', '--dsw-alias-interactive-bg-hover', 'red'),
            ('.subjectSpec', 'font-family', '"session. new"'),
            ('.subjectSpec', 'font-family', '"session.new"'),
            ('.subjectSpec', 'font-family', '"a, b"'),
            ('.subjectSpec', 'font-family', '"a,b"'),
        ]:
            with self.subTest(selector=selector, value=value):
                self.assert_rejected(self.changed(selector, prop, value))

    def test_rule_declaration_order_duplicates_and_missing_context_fail(self):
        for mode in ('rule-order', 'declaration-order', 'duplicate', 'missing',
                     'selector-literal', 'condition'):
            sheets = copy.deepcopy(self.sheets)
            rules = sheets[SHEET]
            if mode == 'rule-order':
                rules[0], rules[1] = rules[1], rules[0]
            elif mode == 'declaration-order':
                rules[0]['declarations'] = dict(reversed(list(rules[0]['declarations'].items())))
            elif mode == 'duplicate':
                rules.append(copy.deepcopy(rules[0]))
            elif mode == 'missing':
                rules.pop(0)
            elif mode == 'selector-literal':
                rules[0]['selector'] = '.pa ge'
            else:
                rules[0]['conditions'] = ['@media (max-width: 600px)']
            with self.subTest(mode=mode):
                self.assert_rejected(sheets)

    def test_actual_source_comparison_covers_generic_and_pending_rules(self):
        published = self.sheets[SHEET]
        source = [gen.normalized_rule(r) for r in published]
        gen.verify_feature_source(published, source)
        for amendment in [
            {'selector': 'button:active', 'conditions': [],
             'declarations': {'background': 'red'}},
            {'selector': 'button', 'conditions': ['@media (max-width: 600px)'],
             'declarations': {'min-width': '100px'}},
            {'selector': '.page', 'conditions': [],
             'declarations': {'--dsw-alias-label-caption': 'red'}},
        ]:
            changed = copy.deepcopy(source)
            changed.append(amendment)
            with self.subTest(selector=amendment['selector']), self.assertRaises(ValueError):
                gen.verify_feature_source(published, changed)
        changed = copy.deepcopy(source)
        changed[0]['declarations']['gap'] = '33px'
        with self.assertRaises(ValueError):
            gen.verify_feature_source(published, changed)

    def test_existing_icon_state_property_condition_and_structure_gates_remain(self):
        for amendment in [
            {'selector': '.iconButton:active', 'conditions': [],
             'declarations': {'opacity': '.2'}},
            {'selector': '.iconButton', 'conditions': ['@media (prefers-color-scheme: dark)'],
             'declarations': {'color': 'red'}},
        ]:
            sheets = copy.deepcopy(self.sheets)
            sheets[SHEET].append(amendment)
            self.assert_rejected(sheets)
        self.assert_rejected(self.changed('.iconButton', 'padding', '2px'))
        self.assert_rejected(self.changed('.iconButton', 'display', 'block'))

    def test_token_roles_and_unsupported_value_expressions_still_fail(self):
        for selector, prop, value in [
            ('.iconButton', 'color', 'var(--dsw-radius-sm)'),
            ('.iconButton', 'border-radius', 'var(--dsw-alias-label-caption)'),
            ('.iconButton', 'width', 'calc(28px + 1px)'),
            ('.iconButton:disabled', 'opacity', 'var(--unknown-opacity)'),
        ]:
            with self.subTest(prop=prop, value=value):
                self.assert_rejected(self.changed(selector, prop, value))

    def test_icon_and_info_geometry_must_be_strictly_positive(self):
        for selector in ('.iconButton', '.infoButton'):
            for prop in ('width', 'height'):
                for value in ('-1px', '0px'):
                    with self.subTest(selector=selector, prop=prop, value=value):
                        self.assert_rejected(self.changed(selector, prop, value))

    def test_opacity_outside_css_flutter_shared_domain_is_rejected(self):
        for value in ('-.1', '1.01', '2'):
            with self.subTest(value=value):
                self.assert_rejected(self.changed('.iconButton:disabled', 'opacity', value))

    def test_numeric_overflow_cannot_reach_generated_dart(self):
        overflow = '9' * 400
        self.assert_rejected(self.changed('.iconButton', 'width', overflow + 'px'))
        self.assert_rejected(self.changed('.iconButton:focus-visible', 'outline-offset', overflow + 'px'))

    def test_non_ascii_css_numbers_do_not_silently_preserve_dart(self):
        for selector, prop, value in [
            ('.iconButton', 'width', '２８px'),
            ('.infoButton', 'height', '２０px'),
            ('.iconButton:disabled', 'opacity', '０.５'),
        ]:
            with self.subTest(selector=selector, prop=prop, value=value):
                self.assert_rejected(self.changed(selector, prop, value))

    def test_other_translated_numeric_slots_reject_unicode_and_overflow(self):
        for selector, prop, value in [
            ('.addMore', 'border-left', '.５px solid color-mix(in srgb, var(--dsw-alias-label-primary-foreground) 30%, transparent)'),
            ('.addMore', 'border-left', '.5px solid color-mix(in srgb, var(--dsw-alias-label-primary-foreground) ３０%, transparent)'),
            ('.addMore', 'border-left', '.5px solid color-mix(in srgb, var(--dsw-alias-label-primary-foreground) ' + '9' * 400 + '%, transparent)'),
            ('.addMenu', 'max-width', 'calc(100vw - ２４px)'),
            ('.addMenu', 'max-width', 'calc(100vw - ' + '9' * 400 + 'px)'),
            ('.addButton, .addPrimary, .addMore', 'padding', '0 １２px'),
            ('.addMenuDescription', 'max-height', '３６px'),
            ('.iconButton:focus-visible', 'outline-offset', '-１px'),
        ]:
            with self.subTest(selector=selector, prop=prop, value=value):
                self.assert_rejected(self.changed(selector, prop, value))

    def test_ascii_css_number_grammar_keeps_sign_fraction_exponent_and_leading_zeros(self):
        for raw, unit, expected in [
            ('0', '', 0), ('-0', '', 0), ('+0', '', 0),
            ('00.50', '', .5), ('+.5', '', .5), ('-.5px', 'px', -.5),
            ('0028px', 'px', 28), ('+0028.00px', 'px', 28),
            ('01e+2px', 'px', 100), ('2.5E-1px', 'px', .25),
            ('000.5%', '%', .5), ('00180ms', 'ms', 180),
        ]:
            with self.subTest(raw=raw, unit=unit):
                self.assertEqual(gen.number(raw, unit), expected)

    def test_invalid_css_numeric_tokens_and_nonfinite_values_fail(self):
        for raw, unit in [
            ('٢٨px', 'px'), ('28pｘ', 'px'), ('28 px', 'px'),
            ('1.px', 'px'), ('.px', 'px'), ('--1px', 'px'),
            ('1_0px', 'px'), ('0x1px', 'px'), ('1e', ''),
            ('NaN', ''), ('Infinity', ''), ('-inf', ''),
            ('1e400px', 'px'), ('-1e400', ''), ('9' * 400, ''),
        ]:
            with self.subTest(raw=raw, unit=unit), self.assertRaises(ValueError):
                gen.number(raw, unit)

    def test_ascii_equivalent_icon_forms_propagate_without_other_recipe_changes(self):
        sheets = self.changed('.iconButton', 'width', '+0030.0px')
        for selector, values in {
            '.infoButton': {'height': '022.5px'},
            '.iconButton:disabled': {'opacity': '00.50'},
            '.iconButton:focus-visible': {'outline-offset': '-003.0px'},
        }.items():
            next(r for r in sheets[SHEET] if r['selector'] == selector)['declarations'].update(values)
        metrics = self.rendered_metrics(sheets)
        self.assert_only_recipe_changed(metrics, 'DshIconActionRecipe')
        icon = metrics['DshIconActionRecipe']
        self.assertEqual((icon['width'], icon['infoHeight'], icon['disabledOpacity'], icon['focusOffset']),
                         (30, 22.5, .5, -3))
        for opacity in ('+0', '-0', '+01.0'):
            metrics = self.rendered_metrics(self.changed('.iconButton:disabled', 'opacity', opacity))
            self.assertEqual(metrics['DshIconActionRecipe']['disabledOpacity'], float(opacity))

    def test_divider_ascii_tokens_and_viewport_literal_share_finite_number_validation(self):
        for percentage, expected in [('000', 0), ('+0030.5', .305), ('1e2', 1)]:
            sheets = self.changed('.addMore', 'border-left',
                '+00.5px solid color-mix(in srgb, var(--dsw-alias-label-primary-foreground) ' + percentage + '%, transparent)')
            metrics = self.rendered_metrics(sheets)
            self.assert_only_recipe_changed(metrics, 'DshAddButtonRecipe')
            self.assertEqual(metrics['DshAddButtonRecipe']['dividerWidth'], .5)
            self.assertEqual(metrics['DshAddButtonRecipe']['dividerAlpha'], expected)
        metrics = self.rendered_metrics(self.changed('.addMenu', 'max-width', 'calc(100vw - 0048px)'))
        self.assertEqual(metrics, self.metrics)
        for width, percentage in [('-1px', '30'), ('.5px', '-1'), ('.5px', '101')]:
            self.assert_rejected(self.changed('.addMore', 'border-left', width +
                ' solid color-mix(in srgb, var(--dsw-alias-label-primary-foreground) ' + percentage + '%, transparent)'))

    def test_shared_number_parser_preserves_valid_other_profiles_and_rejects_bad_ones(self):
        sheets = copy.deepcopy(self.sheets)
        next(r for r in sheets['Button.module.css'] if r['selector'] == '.md')['declarations']['height'] = '+0034px'
        metrics = self.rendered_metrics(sheets)
        self.assert_only_recipe_changed(metrics, 'DshButtonRecipe')
        self.assertEqual(metrics['DshButtonRecipe']['height'], 34)
        for value in ('０.５', '9' * 400):
            sheets = copy.deepcopy(self.sheets)
            next(r for r in sheets['Button.module.css'] if r['selector'] == '.button:disabled')['declarations']['opacity'] = value
            self.assert_rejected(sheets)

    def test_supported_icon_values_propagate_only_to_icon_recipe(self):
        sheets = self.changed('.iconButton', 'width', '30px')
        for selector, values in {
            '.iconButton': {'height': '32px', 'color': 'var(--dsw-alias-label-primary)',
                            'border-radius': 'var(--dsw-radius-md)'},
            '.infoButton': {'width': '22px', 'height': '24px',
                            'color': 'var(--dsw-alias-label-tertiary)'},
            '.iconButton:hover:not(:disabled)': {'color': 'var(--dsw-alias-label-caption)',
                                                'background': 'var(--dsw-alias-interactive-bg-hover-danger)'},
            '.iconButton:disabled': {'opacity': '.75'},
            '.iconButton:focus-visible': {
                'outline-offset': '-3px',
                'outline': 'var(--dsw-radius-md) solid var(--scoped-focus, var(--dsw-alias-label-caption))',
            },
        }.items():
            next(r for r in sheets[SHEET] if r['selector'] == selector)['declarations'].update(values)
        metrics = self.rendered_metrics(sheets)
        self.assert_only_recipe_changed(metrics, 'DshIconActionRecipe')
        icon = metrics['DshIconActionRecipe']
        self.assertEqual((icon['width'], icon['height'], icon['infoWidth'], icon['infoHeight']),
                         (30, 32, 22, 24))
        self.assertEqual((icon['disabledOpacity'], icon['focusOffset']), (.75, -3))
        self.assertEqual(icon['labelToken'], '--dsw-alias-label-primary')
        self.assertEqual(icon['radiusToken'], '--dsw-radius-md')
        self.assertEqual(icon['hoverToken'], '--dsw-alias-interactive-bg-hover-danger')
        self.assertEqual(icon['focusWidthToken'], '--dsw-radius-md')
        self.assertEqual(icon['focusToken'], '--scoped-focus')
        self.assertEqual(icon['focusFallbackToken'], '--dsw-alias-label-caption')

    def test_positive_fractional_geometry_and_opacity_endpoints_are_supported(self):
        for opacity in ('0', '1'):
            sheets = self.changed('.iconButton:disabled', 'opacity', opacity)
            for selector in ('.iconButton', '.infoButton'):
                next(r for r in sheets[SHEET] if r['selector'] == selector)['declarations'].update(
                    {'width': '.25px', 'height': '.5px'})
            metrics = self.rendered_metrics(sheets)
            self.assert_only_recipe_changed(metrics, 'DshIconActionRecipe')
            self.assertEqual(metrics['DshIconActionRecipe']['disabledOpacity'], float(opacity))
            self.assertEqual(metrics['DshIconActionRecipe']['infoWidth'], .25)

    def test_other_translated_plugin_profiles_keep_valid_metric_propagation(self):
        for selector, changes, recipe, expected in [
            ('.addMenu', {'width': '322px'}, 'DshPluginAddMenuRecipe', {'width': 322}),
            ('.addButton, .addPrimary, .addMore', {'height': '36px', 'padding': '0 14px'},
             'DshAddButtonRecipe', {'height': 36, 'padding': 14}),
        ]:
            sheets = copy.deepcopy(self.sheets)
            next(r for r in sheets[SHEET] if r['selector'] == selector)['declarations'].update(changes)
            metrics = self.rendered_metrics(sheets)
            self.assert_only_recipe_changed(metrics, recipe)
            for field, value in expected.items():
                self.assertEqual(metrics[recipe][field], value)

    def test_matching_source_and_release_supported_changes_remain_valid(self):
        published = copy.deepcopy(self.sheets[SHEET])
        next(r for r in published if r['selector'] == '.iconButton')['declarations']['width'] = '30px'
        source = [gen.normalized_rule(r) for r in published]
        gen.verify_feature_source(published, source)


if __name__ == '__main__':
    unittest.main()
