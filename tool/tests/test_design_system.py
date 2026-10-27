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
    def test_preset_archive_extraction_keeps_dollar_guide_literal_separate_from_roster(self):
        import io
        import tarfile
        published = module('published')
        bundle = '''//#region lib/types/client/PresetGuideDialog.module.css.mjs
const css$1 = ".g_guideDialog{width:640px}";
var PresetGuideDialog_module_css_default = {"guideDialog":"g_guideDialog"};
//#endregion
//#region lib/types/client/PresetGuideDialog.js
function PresetGuideDialog() { return null; }
//#endregion
//#region lib/types/client/AgentPresetSection.module.css.mjs
const css = ".r_section{width:720px}";
var AgentPresetSection_module_css_default = {"section":"r_section"};
//#endregion
'''
        with tempfile.TemporaryDirectory() as d:
            archive = pathlib.Path(d) / 'preset.tgz'
            with tarfile.open(archive, 'w:gz') as tar:
                for name, text in {'lib/client.js': bundle, 'package.json': '{}', 'LICENSE': 'MIT'}.items():
                    data = text.encode(); info = tarfile.TarInfo('package/' + name); info.size = len(data)
                    tar.addfile(info, io.BytesIO(data))
            snapshot = published.agent_preset_style_snapshot(archive)
            self.assertEqual(snapshot['css']['PresetGuideDialog.module.css'], '.g_guideDialog{width:640px}')
            self.assertEqual(snapshot['css']['styles.css'], '.r_section{width:720px}')
            self.assertEqual(snapshot['classes']['guide'], {'guideDialog': 'g_guideDialog'})
            self.assertNotIn('r_section', snapshot['css']['PresetGuideDialog.module.css'])
            with self.assertRaisesRegex(ValueError, 'missing/ambiguous'):
                published.bundle_region(bundle + bundle, 'PresetGuideDialog.module.css.mjs')

    def test_modal_and_guide_metrics_track_published_geometry(self):
        import copy
        lock, original = gen.collect()
        altered = copy.deepcopy(original)
        next(r for r in altered['Modal.module.css'] if r['selector'] == '.root')['declarations']['padding'] = 'max(28px, var(--dsh-frame-overlay-top, 28px)) 32px'
        next(r for r in altered['Modal.module.css'] if r['selector'] == '.dialog')['declarations']['width'] = 'min(420px, 100%)'
        next(r for r in altered['PresetGuideDialog.module.css'] if r['selector'] == '.guideDialog')['declarations'].update({'width': 'min(680px,100%)', 'height': 'min(620px,100%)'})
        next(r for r in altered['PresetGuideDialog.module.css'] if r['selector'] == '.guideHeader')['declarations']['padding'] = '26px 25px 21px 29px'
        next(r for r in altered['PresetGuideDialog.module.css'] if r['selector'] == '.guideClose')['declarations']['padding'] = '3px'
        next(r for r in altered['PresetGuideDialog.module.css'] if r['selector'] == '.guideTabs')['declarations']['margin'] = '4px 30px 24px'
        _, audit = gen.render(lock, altered)
        metrics = json.loads(audit)['metrics']
        self.assertEqual(metrics['DshModalRecipe']['rootMargin'], 28)
        self.assertEqual(metrics['DshModalRecipe']['rootHorizontalMargin'], 32)
        self.assertEqual(metrics['DshModalRecipe']['defaultWidth'], 420)
        self.assertEqual(metrics['DshGuideReaderRecipe']['width'], 680)
        self.assertEqual(metrics['DshGuideReaderRecipe']['height'], 620)
        self.assertEqual(metrics['DshGuideReaderRecipe']['headerLeft'], 29)
        self.assertEqual(metrics['DshGuideReaderRecipe']['closePadding'], 3)
        self.assertEqual(metrics['DshGuideReaderRecipe']['tabsTopMargin'], 4)
        self.assertEqual(metrics['DshGuideReaderRecipe']['tabsHorizontalMargin'], 30)
        self.assertEqual(metrics['DshGuideReaderRecipe']['tabsBottomMargin'], 24)

    def test_modal_timing_scrollbar_and_bundle_icon_inputs_are_consumed(self):
        import copy
        lock, original = gen.collect()
        altered = copy.deepcopy(original)
        context = altered['ModalContext']
        next(r for r in context['themeTokens'] if r['selector'] == ':root')['declarations'].update({
            '--ds-transition-duration': '.3s', '--ds-ease-in-out': 'cubic-bezier(.2, 0, .3, 1)'})
        next(r for r in context['scrollbarRules'] if r['selector'] == 'body')['declarations']['--dsh-scrollbar-width'] = '6px'
        context['modalBehavior']['modal'] = context['modalBehavior']['modal'].replace('IconCloseOutlineRegular, { size: 14 }', 'IconCloseOutlineRegular, { size: 16 }')
        context['readerBehavior']['region'] = context['readerBehavior']['region'].replace('IconCloseOutlineRegular, { size: 18 }', 'IconCloseOutlineRegular, { size: 20 }')
        context['readerBehavior']['region'] = context['readerBehavior']['region'].replace('IconListPenOutlineRegular, { size: 12 }', 'IconListPenOutlineRegular, { size: 16 }')
        _, audit = gen.render(lock, altered)
        metrics = json.loads(audit)['metrics']
        self.assertEqual(metrics['DshModalRecipe']['animationMs'], 300)
        self.assertEqual(metrics['DshModalRecipe']['curveX1'], .2)
        self.assertEqual(metrics['DshModalRecipe']['curveX2'], .3)
        self.assertEqual(metrics['DshModalRecipe']['closeIconSize'], 16)
        self.assertEqual(metrics['DshGuideReaderRecipe']['closeIconSize'], 20)
        self.assertEqual(metrics['DshGuideReaderRecipe']['exampleIconSize'], 16)
        self.assertEqual(metrics['DshGuideReaderRecipe']['scrollbarWidth'], 6)
        for change in ['missing', 'ambiguous']:
            altered = copy.deepcopy(original)
            if change == 'missing':
                altered['ModalContext']['readerBehavior']['region'] = altered['ModalContext']['readerBehavior']['region'].replace('IconListPenOutlineRegular', 'OtherIcon')
            else:
                altered['ModalContext']['readerBehavior']['region'] += '\nIconListPenOutlineRegular, { size: 12 }'
            with self.subTest(example_icon=change), self.assertRaisesRegex(ValueError, 'example icon declaration changed'):
                gen.render(lock, altered)

    def test_modal_guide_new_rules_and_untranslated_structures_fail_closed(self):
        import copy
        lock, original = gen.collect()
        mutations = [
            ('Modal.module.css', '.root', 'pointer-events', 'none'),
            ('Modal.module.css', '.mask', 'inset', '0'),
            ('Modal.module.css', '.dialog', 'animation', 'other 200ms ease'),
            ('PresetGuideDialog.module.css', '.guidePanel', 'overflow-y', 'visible'),
            ('PresetGuideDialog.module.css', '.guidePanel', 'scrollbar-gutter', 'auto'),
            ('PresetGuideDialog.module.css', '.guideExampleTag', 'flex-shrink', '1'),
        ]
        for sheet, selector, prop, changed in mutations:
            altered = copy.deepcopy(original)
            next(r for r in altered[sheet] if r['selector'] == selector)['declarations'][prop] = changed
            with self.subTest(sheet=sheet, selector=selector, prop=prop), self.assertRaisesRegex(ValueError, 'untranslated'):
                gen.render(lock, altered)
        for sheet, rule in [
            ('Modal.module.css', {'selector': 'from', 'conditions': ['@keyframes modalEnter'], 'declarations': {'opacity': '.5'}}),
            ('Modal.module.css', {'selector': '.dialog:hover', 'conditions': [], 'declarations': {'opacity': '.5'}}),
            ('PresetGuideDialog.module.css', {'selector': '.guidePanel', 'conditions': ['@media (prefers-color-scheme: dark)'], 'declarations': {'color': 'red'}}),
        ]:
            altered = copy.deepcopy(original)
            if rule['conditions'] == ['@keyframes modalEnter']:
                next(r for r in altered[sheet] if r['selector'] == 'from')['declarations'] = rule['declarations']
            else:
                altered[sheet].append(rule)
            with self.subTest(sheet=sheet, selector=rule['selector']), self.assertRaisesRegex(ValueError, 'untranslated'):
                gen.render(lock, altered)

    def test_modal_scoped_tokens_unknown_scrollbar_structure_and_blur_fail_closed(self):
        import copy
        lock, original = gen.collect()
        altered = copy.deepcopy(original)
        altered['ModalContext']['themeTokens'].append({'selector': 'body[data-ds-dark-theme]', 'conditions': [],
                                                      'declarations': {'--dsw-mask-blur': 'blur(2px)'}})
        with self.assertRaisesRegex(ValueError, 'untranslated modal theme token scope'):
            gen.render(lock, altered)
        altered = copy.deepcopy(original)
        next(r for r in altered['ModalContext']['themeTokens'] if r['selector'] == 'body')['declarations']['--dsw-mask-blur'] = 'blur(2px)'
        with self.assertRaisesRegex(ValueError, 'mask blur'):
            gen.render(lock, altered)
        altered = copy.deepcopy(original)
        next(r for r in altered['ModalContext']['scrollbarRules'] if r['selector'] == '::-webkit-scrollbar-thumb')['declarations']['background-clip'] = 'padding-box'
        with self.assertRaisesRegex(ValueError, 'untranslated modal scrollbar structure'):
            gen.render(lock, altered)

    def test_global_scrollbar_recipe_tracks_verified_geometry_and_l1_inheritance(self):
        import copy
        lock, original = gen.collect()
        _, audit = gen.render(lock, original)
        metrics = json.loads(audit)['metrics']
        self.assertEqual(metrics['DshScrollbarRecipe'], {
            'width': 5, 'radius': 999, 'thumbBorderWidth': 0, 'trackMargin': 0,
            'thumbToken': '--dsw-alias-scrollbar-bg-l1', 'hoverToken': '--dsw-alias-scrollbar-hover-l1',
        })
        self.assertEqual(metrics['DshGuideReaderRecipe']['scrollbarThumbToken'], '--dsw-alias-scrollbar-bg-l2')
        self.assertEqual(metrics['DshGuideReaderRecipe']['scrollbarHoverToken'], '--dsw-alias-scrollbar-hover-l2')
        changed = copy.deepcopy(original)
        rules = changed['ModalContext']['scrollbarRules']
        next(rule for rule in rules if rule['selector'] == 'body')['declarations'].update({
            '--dsh-scrollbar-width': '7px', '--dsh-scrollbar-thumb-border': '1px',
            '--dsh-scrollbar-track-margin': '3px',
        })
        next(rule for rule in rules if rule['selector'] == '::-webkit-scrollbar-thumb')['declarations']['border-radius'] = '40px'
        _, audit = gen.render(lock, changed)
        measured = json.loads(audit)['metrics']
        expected = {**metrics['DshScrollbarRecipe'], 'width': 7, 'radius': 40, 'thumbBorderWidth': 1, 'trackMargin': 3}
        self.assertEqual(measured['DshScrollbarRecipe'], expected)
        self.assertEqual(measured['DshGuideReaderRecipe']['scrollbarWidth'], 7)
        self.assertEqual(measured['DshGuideReaderRecipe']['scrollbarRadius'], 40)
        self.assertEqual(measured['DshGuideReaderRecipe']['scrollbarThumbBorderWidth'], 1)
        self.assertEqual(measured['DshGuideReaderRecipe']['scrollbarTrackMargin'], 3)
        for mode in ('unknown-state', 'unknown-property', 'unknown-condition', 'different-thumb', 'different-hover'):
            changed = copy.deepcopy(original)
            rules = changed['ModalContext']['scrollbarRules']
            if mode == 'unknown-state':
                rules.append({'selector': '::-webkit-scrollbar-thumb:active', 'conditions': [],
                              'declarations': {'background': 'red'}})
            elif mode == 'unknown-property':
                rules[0]['declarations']['--dsh-scrollbar-extra'] = '1px'
            elif mode == 'unknown-condition':
                rules.append({'selector': '::-webkit-scrollbar-thumb', 'conditions': ['@media (prefers-color-scheme: dark)'],
                              'declarations': {'background': 'red'}})
            else:
                prop = '--dsh-scrollbar-thumb' if mode == 'different-thumb' else '--dsh-scrollbar-thumb-hover'
                next(rule for rule in rules if rule['selector'] == 'body')['declarations'][prop] = 'var(--dsw-alias-scrollbar-bg-l2)'
            with self.subTest(mode=mode), self.assertRaisesRegex(ValueError, 'untranslated modal scrollbar'):
                gen.render(lock, changed)

    def test_guide_published_minifier_normalization_preserves_source_drift_detection(self):
        import copy
        _, sheets = gen.collect()
        modal = module('modal_recipes')
        original = copy.deepcopy(sheets['PresetGuideDialog.module.css'])
        for rule in original:
            rule['selector'] = rule['selector'].replace('[data-guide-page=usage]', "[data-guide-page='usage']").replace('+', ' + ')
            rule['declarations'] = dict(reversed(list(rule['declarations'].items())))
        modal.verify_guide_source(sheets['PresetGuideDialog.module.css'], original)
        next(r for r in original if r['selector'] == '.guideTabs')['declarations']['margin'] = '0 32px 22px'
        with self.assertRaisesRegex(ValueError, 'reference guide CSS differs'):
            modal.verify_guide_source(sheets['PresetGuideDialog.module.css'], original)

    def test_guide_primitive_consumer_dependency_is_verified(self):
        published = module('published')
        lock = json.loads((ROOT / 'tool/design-system/sources.lock.json').read_text())
        package = lock['packages'][0]
        declaration = next(d for d in package['referenceConsumers'] if d['path'] == 'packages/client/ui-agent-preset/package.json')
        with tempfile.TemporaryDirectory() as d:
            source = pathlib.Path(d)
            manifest = source / package['sourcePackage']; manifest.parent.mkdir(parents=True)
            manifest.write_text(json.dumps({'version': package['version']}))
            consumer = source / package['referenceConsumer']; consumer.parent.mkdir(parents=True)
            consumer.write_text(json.dumps({package['dependencyField']: {package['name']: package['dependencySpecifier']}}))
            guide = source / declaration['path']; guide.parent.mkdir(parents=True)
            guide.write_text(json.dumps({declaration['dependencyField']: {package['name']: '^0.3.0'}}))
            with self.assertRaisesRegex(ValueError, 'additional consumer drift'):
                published.verify_packages(source)

    def test_risk_dialog_metrics_follow_css_and_verified_bundle_without_changing_other_profiles(self):
        import copy
        lock, original = gen.collect()
        _, baseline = gen.render(lock, original)
        changed = copy.deepcopy(original)
        rules = changed['RiskConfirmation.module.css']
        def update(selector, **props):
            next(rule for rule in rules if rule['selector'] == selector and not rule['conditions'])['declarations'].update(props)
        update('.confirmation', width='min(480px, 100%)', **{'max-height': '80%'})
        next(rule for rule in rules if rule['conditions'])['declarations']['max-height'] = 'calc(100dvh - 64px)'
        update('.confirmationContent', **{'min-height': '2px'})
        update('.warning', gap='12px', color='var(--dsw-alias-label-primary)',
               **{'font-size': '16px', 'line-height': '24px'})
        update('.warningIcon', color='var(--dsw-alias-state-business-primary)', **{'margin-top': '3px'})
        update('.modalAction', **{'min-width': '80px'})
        update('.confirmAction', **{'min-width': '148px'})
        behavior = changed['ModalContext']['modalBehavior']
        behavior['risk'] = behavior['risk'].replace('size: 18,', 'size: 20,')
        _, audit = gen.render(lock, changed)
        metrics = json.loads(audit)['metrics']
        risk = metrics.pop('DshRiskDialogRecipe')
        self.assertEqual(risk, {
            'width': 480, 'maxHeightFactor': .8, 'dynamicViewportInset': 64, 'contentMinHeight': 2,
            'warningGap': 12, 'warningFontSize': 16, 'warningLineHeight': 24,
            'warningFontToken': gen.profile_font_token(16, 24), 'warningLabelToken': '--dsw-alias-label-primary',
            'warningIconTop': 3, 'warningIconSize': 20, 'errorIconToken': '--dsw-alias-state-business-primary',
            'actionMinWidth': 80, 'confirmMinWidth': 148,
        })
        baseline = json.loads(baseline)['metrics']
        del baseline['DshRiskDialogRecipe']
        self.assertEqual(metrics, baseline)

    def test_risk_dialog_rejects_unknown_rules_conditions_and_untranslated_structures(self):
        import copy
        lock, original = gen.collect()
        mutations = [
            ('.confirmation', 'overflow', 'visible'),
            ('.confirmationContent', 'overflow-y', 'visible'),
            ('.confirmationContent', 'overscroll-behavior', 'auto'),
            ('.warning', 'align-items', 'center'),
            ('.warning p', 'margin', '4px'),
            ('.warningIcon', 'flex', '1'),
            ('.confirmation', 'width', '440px'),
            ('.confirmation', 'max-height', '100dvh'),
        ]
        for selector, prop, value in mutations:
            changed = copy.deepcopy(original)
            next(rule for rule in changed['RiskConfirmation.module.css']
                 if rule['selector'] == selector and not rule['conditions'])['declarations'][prop] = value
            with self.subTest(selector=selector, prop=prop), self.assertRaisesRegex(ValueError, 'risk dialog'):
                gen.render(lock, changed)
        for mode in ('unknown-selector', 'unknown-property', 'unknown-condition', 'missing-cap',
                     'duplicate-cap', 'different-support', 'different-viewport-unit'):
            changed = copy.deepcopy(original)
            rules = changed['RiskConfirmation.module.css']
            cap = next(rule for rule in rules if rule['conditions'])
            if mode == 'unknown-selector':
                rules.append({'selector': '.confirmation:hover', 'conditions': [], 'declarations': {'opacity': '.5'}})
            elif mode == 'unknown-property':
                rules[0]['declarations']['padding'] = '2px'
            elif mode == 'unknown-condition':
                rules.append({'selector': '.confirmation', 'conditions': ['@media (prefers-color-scheme: dark)'],
                              'declarations': {'max-height': '100%'}})
            elif mode == 'missing-cap':
                rules.remove(cap)
            elif mode == 'duplicate-cap':
                rules.append(copy.deepcopy(cap))
            elif mode == 'different-support':
                cap['conditions'] = ['@supports (height: 100svh)']
            else:
                cap['declarations']['max-height'] = 'calc(100svh - 48px)'
            with self.subTest(mode=mode), self.assertRaisesRegex(ValueError, 'risk dialog'):
                gen.render(lock, changed)

    def test_risk_published_icon_and_control_structure_fail_closed(self):
        import copy
        lock, original = gen.collect()
        risk_recipe = module('risk_recipes')
        behavior = original['ModalContext']['modalBehavior']['risk']
        source = '<IconWarningOutlineRegular size={18} className={css.warningIcon} />'
        risk_recipe.verify_source_icon(behavior, source)
        for changed_source in (source.replace('18', '20'), source + source, source.replace('warningIcon', 'other')):
            with self.subTest(source=changed_source), self.assertRaisesRegex(ValueError, 'differs from its published bundle'):
                risk_recipe.verify_source_icon(behavior, changed_source)
        for old, replacement in [
            ('IconWarningOutlineRegular', 'OtherIcon'),
            ('contentClassName:', 'otherContentClassName:'),
            ('disabled || !acknowledged', 'disabled'),
            ('"data-modal-autofocus": true', '"data-modal-autofocus": false'),
            ('onAcknowledgedChange(event.currentTarget.checked)', 'onAcknowledgedChange(true)'),
        ]:
            changed = copy.deepcopy(original)
            behavior = changed['ModalContext']['modalBehavior']
            self.assertIn(old, behavior['risk'])
            behavior['risk'] = behavior['risk'].replace(old, replacement)
            with self.subTest(input=old), self.assertRaisesRegex(ValueError, 'risk'):
                gen.render(lock, changed)
        changed = copy.deepcopy(original)
        changed['ModalContext']['modalBehavior']['risk'] += '\nIconWarningOutlineRegular, { size: 18, className: css.warningIcon }'
        with self.assertRaisesRegex(ValueError, 'risk warning icon declaration changed'):
            gen.render(lock, changed)

    def test_published_modal_snapshot_keeps_risk_behavior_region_unique(self):
        import io
        import tarfile
        published = module('published')
        names = ('useModalLayer', 'Modal', 'RiskConfirmation')
        regions = {name: f'//#region lib/types/{name}.js\nfunction {name}() {{}}\n\n' for name in names}
        bundle = ''.join(region + '//#endregion\n' for region in regions.values())
        with tempfile.TemporaryDirectory() as d:
            archive = pathlib.Path(d) / 'primitive.tgz'
            with tarfile.open(archive, 'w:gz') as tar:
                data = bundle.encode(); info = tarfile.TarInfo('package/lib/index.js'); info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
            snapshot = published.modal_layer_snapshot(archive)
            self.assertEqual(snapshot['layer'], regions['useModalLayer'])
            self.assertEqual(snapshot['modal'], regions['Modal'])
            self.assertEqual(snapshot['risk'], regions['RiskConfirmation'])
            with self.assertRaisesRegex(ValueError, 'missing/ambiguous'):
                published.bundle_region(bundle + regions['RiskConfirmation'] + '//#endregion\n', 'RiskConfirmation.js')

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
