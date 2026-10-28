"""Published Toast fields propagate; every other CSS/behavior branch stays closed."""
import copy
import base64
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / 'tool/design-system/upstream/ui-primitives'


def module(name):
    spec = importlib.util.spec_from_file_location('toast_test_' + name, ROOT / 'tool/design-system' / (name + '.py'))
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


gen, published = module('generate'), module('published')
SHEET, BEHAVIOR, RECIPE = 'Toast.module.css', 'ToastBehavior', 'DshToastRecipe'


class ToastSourceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.lock, cls.sheets = gen.collect()
        # Also permits running these negatives before the compiler is wired.
        cls.sheets.setdefault(SHEET, gen.css_rules((FOLDER / SHEET).read_text(), allow_keyframes=True))
        cls.sheets.setdefault(BEHAVIOR, json.loads((FOLDER / 'toast-behavior.json').read_text()))

    def render(self, sheets=None):
        return json.loads(gen.render(self.lock, self.sheets if sheets is None else sheets)[1])['metrics']

    def change(self, selector, prop, raw, conditions=()):
        sheets = copy.deepcopy(self.sheets)
        next(r for r in sheets[SHEET] if r['selector'] == selector and r['conditions'] == list(conditions))['declarations'][prop] = raw
        return sheets

    def test_actual_content_box_material_and_timing_fields(self):
        fields = self.render()
        self.assertIn(RECIPE, fields)
        toast = fields[RECIPE]
        self.assertEqual({k: toast[k] for k in ('top', 'maxContentWidth', 'viewportInset', 'horizontalPadding', 'verticalPadding', 'gap', 'fontSize', 'lineHeight')},
                         dict(top=40, maxContentWidth=640, viewportInset=48, horizontalPadding=16, verticalPadding=12, gap=10, fontSize=14, lineHeight=22))
        self.assertEqual({k: toast[k] for k in ('holdMs', 'fadeMs', 'enterMs', 'enterOffsetY', 'enterCurve', 'fadeCurve')},
                         dict(holdMs=3000, fadeMs=1000, enterMs=160, enterOffsetY=-6, enterCurve='ease-out', fadeCurve='ease'))
        self.assertEqual((toast['radiusToken'], toast['backgroundToken'], toast['labelToken'], toast['shadowToken']),
                         ('--dsw-radius-lg', '--dsw-alias-toast-bg', '--dsw-alias-toast-label', '--dsw-shadow-lv3'))
        self.assertEqual((toast['iconLabelToken'], toast['successIconLabelToken']),
                         ('--dsw-alias-state-warn-label', '--dsw-alias-state-success-primary'))
        self.assertFalse({'iconSize', 'fontWeight', 'actionColor', 'anchorLeft'} & toast.keys())

    def test_whole_sheet_closes_generic_ancestor_active_and_media_cascade(self):
        additions = [
            {'selector': 'div', 'conditions': [], 'declarations': {'min-width': '100px'}},
            {'selector': 'body', 'conditions': [], 'declarations': {'--dsw-alias-toast-bg': 'red'}},
            {'selector': '.toast:active', 'conditions': [], 'declarations': {'background': 'red'}},
            {'selector': '.toast', 'conditions': ['@media (max-width: 600px)'], 'declarations': {'top': '1px'}},
        ]
        for rule in additions:
            sheets = copy.deepcopy(self.sheets); sheets[SHEET].append(rule)
            with self.subTest(rule=rule), self.assertRaises(ValueError): self.render(sheets)

    def test_structure_and_pending_actions_cannot_silently_drift(self):
        for selector, prop, raw in [('.toast', 'position', 'absolute'), ('.toast', 'pointer-events', 'auto'),
            ('.toast', 'left', '40%'), ('.toast', 'transform', 'translateX(-40%)'),
            ('.toast', 'box-sizing', 'border-box'), ('.toast', 'z-index', '1200'),
            ('.icon', 'flex', '1'), ('.text', 'min-width', '1px'),
            ('.action', 'color', 'red'), ('.action:hover', 'opacity', '.7')]:
            with self.subTest(selector=selector, prop=prop), self.assertRaises(ValueError): self.render(self.change(selector, prop, raw))
        sheets = copy.deepcopy(self.sheets); sheets[SHEET].append(copy.deepcopy(sheets[SHEET][0]))
        with self.assertRaises(ValueError): self.render(sheets)

    def test_complete_behavior_closes_role_icon_lifetime_portal_anchor_and_actions(self):
        replacements = [('role: "alert"', 'role: "status"'), ('tone === "success"', 'tone !== "success"'),
            ('icon !== void 0', 'true'), ('IconCheckCircleOutlineRegular, {}', 'IconWarningOutlineRegular, {}'),
            ('latestOnDone.current()', 'onDone()'), ('}, [holdMs]);', '}, [holdMs, text]);'),
            ('clearTimeout(timer)', 'void timer'), ('document.body', 'document.documentElement'),
            ('rect.left + rect.width / 2', 'rect.left'), ('onClick: action.onClick', 'onClick: onDone')]
        body = self.sheets[BEHAVIOR]['region']
        for old, new in replacements:
            self.assertIn(old, body)
            sheets = copy.deepcopy(self.sheets); sheets[BEHAVIOR]['region'] = body.replace(old, new, 1)
            with self.subTest(old=old), self.assertRaises(ValueError): self.render(sheets)
        sheets = copy.deepcopy(self.sheets); sheets[BEHAVIOR]['region'] = body.replace('role: "alert"', 'role: "al ert"')
        with self.assertRaises(ValueError): self.render(sheets)

    def test_css_numbers_are_finite_ascii_and_have_supported_domains(self):
        for selector, prop, raw in [('.toast', 'top', '４０px'), ('.toast', 'gap', '-1px'),
            ('.toast', 'font-size', '0px'), ('.toast', 'line-height', '-1px'),
            ('.toast', 'padding', '1px -2px'), ('.toast', 'top', '1e999px'),
            ('.toast', 'max-width', 'min(0px, calc(100vw - 48px))'),
            ('.toast', 'max-width', 'min(640px, calc(100vw - -1px))'),
            ('.toast', 'max-width', 'min(０px, calc(100vw - 48px))'),
            ('.toast', 'max-width', 'min(640px, calc(100vh - 48px))')]:
            with self.subTest(raw=raw), self.assertRaises(ValueError): self.render(self.change(selector, prop, raw))

    def test_non_css_whitespace_cannot_be_erased_before_contract_validation(self):
        source = (FOLDER / SHEET).read_text()
        for altered in (source.replace('.toast {', '.toast\u00a0 {', 1), source.replace('40px;', '40px\u00a0;', 1)):
            with self.subTest(source=altered[:35]), self.assertRaises(ValueError):
                gen._toast.parse_css(altered, gen.css_rules)
        self.assertEqual(gen._toast.parse_css('/* literal\u00a0comment */\n' + source, gen.css_rules), self.sheets[SHEET])

    def test_js_numbers_reject_invalid_unicode_nonfinite_and_extra_expressions(self):
        body = self.sheets[BEHAVIOR]['region']
        for raw in ('３e３', '03e3', 'Infinity', 'NaN', '1e9999', '3000 + 1', '-1'):
            sheets = copy.deepcopy(self.sheets); sheets[BEHAVIOR]['region'] = body.replace('const HOLD_MS = 3e3;', 'const HOLD_MS = ' + raw + ';')
            with self.subTest(raw=raw), self.assertRaises(ValueError): self.render(sheets)

    def test_supported_geometry_tokens_and_curves_propagate_only_to_toast(self):
        before = self.render(); sheets = self.change('.toast', 'top', '-2.5px')
        next(r for r in sheets[SHEET] if r['selector'] == '.toast' and not r['conditions'])['declarations'].update({
            'gap': '00.5px', 'padding': '0px 18px', 'max-width': 'min(620px, calc(100vw - 32px))',
            'background': 'var(--dsw-alias-bg-base)', 'color': 'var(--dsw-alias-label-secondary)',
            'border-radius': 'var(--dsw-radius-md)', 'box-shadow': 'var(--dsw-shadow-lv2)',
            'font-size': '15px', 'line-height': '23px'})
        next(r for r in sheets[SHEET] if r['selector'] == '.icon')['declarations']['color'] = 'var(--dsw-alias-label-primary)'
        next(r for r in sheets[SHEET] if r['selector'] == '.icon.success')['declarations']['color'] = 'var(--dsw-alias-state-business-primary)'
        next(r for r in sheets[SHEET] if r['selector'] == 'from')['declarations']['transform'] = 'translate(-50%, +.5px)'
        next(r for r in sheets[SHEET] if r['selector'] == '.toast' and not r['conditions'])['declarations']['animation'] = next(r for r in sheets[SHEET] if r['selector'] == '.toast' and not r['conditions'])['declarations']['animation'].replace('160ms ease-out', '200ms linear')
        for rule in sheets[SHEET]:
            if 'animation' in rule['declarations']:
                rule['declarations']['animation'] = rule['declarations']['animation'].replace('1000ms ease ', '1000ms ease-in ')
        after = self.render(sheets)
        self.assertIn(RECIPE, after)
        self.assertEqual({k: v for k, v in before.items() if k != RECIPE}, {k: v for k, v in after.items() if k != RECIPE})
        self.assertEqual((after[RECIPE]['top'], after[RECIPE]['gap'], after[RECIPE]['horizontalPadding'], after[RECIPE]['enterOffsetY']), (-2.5, .5, 18, .5))
        self.assertEqual((after[RECIPE]['maxContentWidth'], after[RECIPE]['viewportInset'], after[RECIPE]['enterCurve']), (620, 32, 'linear'))
        self.assertEqual({k: after[RECIPE][k] for k in ('verticalPadding', 'fontSize', 'lineHeight', 'enterMs', 'fadeCurve')},
                         dict(verticalPadding=0, fontSize=15, lineHeight=23, enterMs=200, fadeCurve='ease-in'))
        self.assertEqual({k: after[RECIPE][k] for k in ('radiusToken', 'backgroundToken', 'labelToken', 'shadowToken', 'iconLabelToken', 'successIconLabelToken')},
                         dict(radiusToken='--dsw-radius-md', backgroundToken='--dsw-alias-bg-base', labelToken='--dsw-alias-label-secondary', shadowToken='--dsw-shadow-lv2', iconLabelToken='--dsw-alias-label-primary', successIconLabelToken='--dsw-alias-state-business-primary'))

    def timing(self, hold, fade):
        sheets = copy.deepcopy(self.sheets)
        sheets[BEHAVIOR]['region'] = sheets[BEHAVIOR]['region'].replace('const HOLD_MS = 3e3;', f'const HOLD_MS = {hold};').replace('const FADE_MS = 1e3;', f'const FADE_MS = {fade};')
        for rule in sheets[SHEET]:
            if 'animation' in rule['declarations']:
                rule['declarations']['animation'] = rule['declarations']['animation'].replace('1000ms', str(float(fade)) + 'ms').replace('3000ms', str(float(hold)) + 'ms')
        return sheets

    def test_matching_js_css_timing_allows_exponents_fractions_and_zero(self):
        for hold, fade in (('4e3', '2e3'), ('0', '.5'), ('0.5', '0')):
            result = self.render(self.timing(hold, fade)); self.assertIn(RECIPE, result)
            self.assertEqual((result[RECIPE]['holdMs'], result[RECIPE]['fadeMs']), (float(hold), float(fade)))

    def test_motion_duplicates_must_agree_and_unknown_curves_fail(self):
        for conditions, old, new in [((), '1000ms', '1100ms'),
            (('@media (prefers-reduced-motion: reduce)',), '3000ms', '3100ms'),
            ((), 'ease-out', 'steps(2)')]:
            sheets = copy.deepcopy(self.sheets)
            rule = next(r for r in sheets[SHEET] if r['selector'] == '.toast' and r['conditions'] == list(conditions))
            rule['declarations']['animation'] = rule['declarations']['animation'].replace(old, new)
            with self.subTest(conditions=conditions), self.assertRaises(ValueError): self.render(sheets)

    def test_token_kind_and_behavior_bundle_identity_fail_before_dart(self):
        for prop, raw in [('border-radius', 'var(--dsw-alias-label-primary)'), ('color', 'var(--dsw-radius-lg)'), ('box-shadow', 'var(--dsw-radius-lg)')]:
            with self.subTest(prop=prop), self.assertRaises(ValueError): self.render(self.change('.toast', prop, raw))
        sheets = copy.deepcopy(self.sheets); sheets[BEHAVIOR]['bundleSha256'] = '0' * 64
        with self.assertRaises(ValueError): self.render(sheets)

    def test_decoder_keeps_full_unique_region_without_executing_js(self):
        body = '//#region lib/types/Toast.js\nthrow new Error("never executed");\n//#endregion\n'
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / 'primitive.tgz'
            for source in (body, '', body + body, body.replace('//#endregion', '')):
                with tarfile.open(archive, 'w:gz') as tar:
                    raw = source.encode(); info = tarfile.TarInfo('package/lib/index.js'); info.size = len(raw); tar.addfile(info, io.BytesIO(raw))
                if source == body:
                    result = published.toast_snapshot(archive)
                    self.assertEqual(result, {'bundleSha256': hashlib.sha256(raw).hexdigest(), 'region': body.split('//#endregion')[0]})
                else:
                    with self.assertRaises(ValueError): published.toast_snapshot(archive)

    def test_primitive_expected_outputs_cannot_omit_toast_or_invent_files(self):
        self.assertIn('toast-behavior.json', published.PRIMITIVE_OUTPUTS)
        self.assertIn(SHEET, published.PRIMITIVE_OUTPUTS)
        with tempfile.TemporaryDirectory() as temp:
            archive = Path(temp) / 'primitive.tgz'
            with tarfile.open(archive, 'w:gz'): pass
            integrity = 'sha512-' + base64.b64encode(hashlib.sha512(archive.read_bytes()).digest()).decode()
            for mode in ('omitted-css', 'omitted-behavior', 'extra'):
                names = set(published.PRIMITIVE_OUTPUTS)
                if mode == 'extra': names.add('unverified.json')
                else: names.remove(SHEET if mode == 'omitted-css' else 'toast-behavior.json')
                package = {'files': dict.fromkeys(names), 'extractionKind': 'primitive-css', 'integrity': integrity}
                with self.subTest(mode=mode), self.assertRaisesRegex(ValueError, 'output coverage mismatch'):
                    published.verify_snapshot(archive, package, Path(temp))

    def test_rehashed_toast_snapshot_drift_cannot_replace_archive_bytes(self):
        # These are deliberately inert synthetic release bytes. They test
        # reconstruction, not visual or JS implementation equivalence.
        region = lambda name: f'//#region lib/types/{name}.js\nthrow new Error("never executed");\n//#endregion\n'
        bundle = ('throw new Error("never executed");\n'
                  'function Menu() { const MARGIN = 8; if (lh > 0) y = 12; }\n'
                  'function Tooltip() {\nsetPos({x: side === "right" ? 1 : 0});\n'
                  'const edgeMargin = 8; el.style.visibility = "visible";\n}\n'
                  + ''.join(region(name) for name in ('useModalLayer', 'Modal', 'RiskConfirmation', 'input-modality', 'Toast'))).encode()
        with tempfile.TemporaryDirectory() as temp:
            folder = Path(temp); archive = folder / 'primitive.tgz'
            with tarfile.open(archive, 'w:gz') as tar:
                members = {'package/lib/index.js': bundle}
                for name in published.PRIMITIVE_OUTPUTS:
                    if name.endswith('.json') and name != 'package.json': continue
                    members['package/' + ('' if name in ('package.json', 'LICENSE') else 'lib/') + name] = b'{}' if name == 'package.json' else b'fixture bytes\n'
                for name, raw in members.items():
                    info = tarfile.TarInfo(name); info.size = len(raw); tar.addfile(info, io.BytesIO(raw))
            decoders = {'menu-portal.json': published.menu_portal_snapshot,
                        'tooltip-placement.json': published.tooltip_placement_snapshot,
                        'modal-layer.json': published.modal_layer_snapshot,
                        'input-modality.json': published.input_modality_snapshot,
                        'toast-behavior.json': published.toast_snapshot}
            for name in published.PRIMITIVE_OUTPUTS:
                raw = json.dumps(decoders[name](archive)).encode() if name in decoders else members['package/' + ('' if name in ('package.json', 'LICENSE') else 'lib/') + name]
                (folder / name).write_bytes(raw)
            package = {'files': {name: hashlib.sha256((folder / name).read_bytes()).hexdigest() for name in published.PRIMITIVE_OUTPUTS},
                       'extractionKind': 'primitive-css', 'publishedBundleSha256': hashlib.sha256(bundle).hexdigest(),
                       'integrity': 'sha512-' + base64.b64encode(hashlib.sha512(archive.read_bytes()).digest()).decode()}
            self.assertEqual(published.verify_snapshot(archive, package, folder), published.PRIMITIVE_OUTPUTS)
            behavior = json.loads((folder / 'toast-behavior.json').read_text()); behavior['region'] += '\nfunction hiddenChange() {}\n'
            (folder / 'toast-behavior.json').write_text(json.dumps(behavior))
            package['files']['toast-behavior.json'] = hashlib.sha256((folder / 'toast-behavior.json').read_bytes()).hexdigest()
            with self.assertRaisesRegex(ValueError, 'Toast behavior snapshot mismatch'):
                published.verify_snapshot(archive, package, folder)


if __name__ == '__main__': unittest.main()
