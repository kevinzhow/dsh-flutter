import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
import tempfile
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('theme_generator', ROOT / 'tool/theme-adapters/build_official_pack.py')
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)


class ThemeGeneratorTests(unittest.TestCase):
    def test_release_style_injection_order_cannot_be_reordered_or_executed(self):
        entries = [f'["{n.replace("_", "-")}.css", {n}_css_default]' for n in theme.PUBLISHED.THEME_SHEETS]
        source = 'const STYLES = [' + ',\n'.join(entries) + '];'
        self.assertEqual(theme.PUBLISHED.theme_injection_order(source), theme.SHEETS)
        for body in [list(reversed(entries)), entries + ['runCode()'], entries[:-1]]:
            with self.assertRaises(ValueError):
                theme.PUBLISHED.theme_injection_order('const STYLES = [' + ','.join(body) + '];')

    def test_snapshot_and_same_version_reference_drift_are_detected(self):
        with tempfile.TemporaryDirectory() as d:
            here = Path(d) / 'design'; folder = here / 'upstream/theme'; folder.mkdir(parents=True)
            source = Path(d) / 'reference'; source.mkdir()
            manifest = {'name': '@test/theme', 'version': '1'}
            (folder / 'package.json').write_text(json.dumps(manifest)); (folder / 'base.css').write_text('body{--x:1}')
            (source / 'package.json').write_text(json.dumps(manifest))
            (source / 'consumer.json').write_text(json.dumps({'dependencies': {'@test/theme': 'workspace:*'}}))
            (source / 'style.css').write_text('body{--x:1}')
            def git(*args):
                return subprocess.check_output(
                    ['git', '-C', str(source), '-c', 'user.name=Test',
                     '-c', 'user.email=test@example.invalid', *args],
                    text=True, stderr=subprocess.DEVNULL).strip()
            git('init', '-q')
            git('add', '.')
            git('commit', '-qm', 'Pinned reference')
            reference = git('rev-parse', 'HEAD')
            digest = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
            package = {'name': '@test/theme', 'version': '1', 'snapshotFolder': 'theme',
                       'sourcePackage': 'package.json', 'referenceConsumer': 'consumer.json',
                       'dependencyField': 'dependencies', 'dependencySpecifier': 'workspace:*',
                       'files': {p.name: digest(p) for p in folder.iterdir()},
                       'referenceSourceSha256': {'style.css': digest(source / 'style.css')}}
            (here / 'sources.lock.json').write_text(json.dumps({'referenceCommit': reference, 'packages': [package]}))
            with mock.patch.object(theme.PUBLISHED, '__file__', str(here / 'published.py')):
                theme.PUBLISHED.verify_packages(source)
                git('commit', '--allow-empty', '-qm', 'Same package bytes, different source revision')
                with self.assertRaisesRegex(ValueError, 'reference checkout differs'):
                    theme.PUBLISHED.verify_packages(source)
                git('checkout', '--detach', reference)
                (source / 'style.css').write_text('body{--x:2}')
                with self.assertRaisesRegex(ValueError, 'reference source drift'):
                    theme.PUBLISHED.verify_packages(source)
                (folder / 'base.css').write_text('body{--x:2}')
                with self.assertRaisesRegex(ValueError, 'snapshot hash mismatch'):
                    theme.PUBLISHED.verify_packages()

    def sheets(self):
        folder = ROOT / 'tool/design-system/upstream/ui-theme'
        return {name: (folder / name).read_text() for name in theme.SHEETS}

    def test_conditions_survive_and_known_scopes_stay_out_of_global_tokens(self):
        rep = theme.Report()
        layers = theme.read_sheets(None, rep, sheets=self.sheets())
        corner = rep.rules['corner-shape.css'][0]
        self.assertEqual(corner['conditions'], ['@supports (corner-shape:superellipse(1.5))'])
        self.assertEqual(layers['root']['--dsw-corner-shape'], 'superellipse(1.5)')
        self.assertEqual(len(rep.scopes), 4)
        self.assertNotIn('--dsw-focus-ring-color', layers['body'])
        self.assertNotEqual(layers['body']['--dsw-specific-menu'], '#f8f9faf0')
        self.assertNotEqual(layers['dark']['--dsw-specific-menu'], '#303136f0')

    def test_new_dark_or_conditional_syntax_fails_instead_of_being_flattened(self):
        for css in [
            '@media(prefers-color-scheme:dark){body{--dsw-alias-bg-base:#000}}',
            '@supports(color:oklch(0 0 0)){body{--dsw-alias-bg-base:#000}}',
            '@layer theme{body{--dsw-alias-bg-base:#000}}',
            'body[data-new-dark-theme]{--dsw-alias-bg-base:#000}',
            'body .new-scope{--dsw-alias-bg-base:#000}',
        ]:
            with self.subTest(css=css):
                sheets = self.sheets(); sheets['base.css'] += css
                with self.assertRaisesRegex(ValueError, 'unsupported'):
                    theme.read_sheets(None, theme.Report(), sheets=sheets)

    def test_known_browser_fallback_cannot_start_overriding_global_tokens(self):
        sheets = self.sheets()
        sheets['scrollbar.css'] += '@supports not selector(::-webkit-scrollbar){body{--dsw-alias-bg-base:#000}}'
        with self.assertRaisesRegex(ValueError, 'unsupported theme condition'):
            theme.read_sheets(None, theme.Report(), sheets=sheets)
        sheets = self.sheets()
        sheets['corner-shape.css'] = ':root{--dsw-corner-shape:superellipse(1.5)}'
        with self.assertRaisesRegex(ValueError, 'lost its support guard'):
            theme.read_sheets(None, theme.Report(), sheets=sheets)

    def test_published_hex_alpha_survives_exactly_and_fonts_have_release_provenance(self):
        pack, _, _ = theme.build(None)
        self.assertEqual(pack['modes']['light']['colors']['--dsw-alias-border-l1'], '#0000000a')
        self.assertEqual(pack['fonts']['terminal'], ['ui-monospace', 'SFMono-Regular', 'Menlo', 'Consolas', 'monospace'])
        self.assertEqual([p['name'] for p in pack['source']['packages']], [
            '@deepseek-ai/dsh-client-ui-theme', '@deepseek-ai/dsh-client-ui-sidebar-terminal'])
        self.assertTrue(all(p['version'] == '0.2.1-rc.2' and p['integrity'].startswith('sha512-') for p in pack['source']['packages']))

    def test_unresolved_token_cannot_silently_disappear_from_contract(self):
        with mock.patch.object(theme, 'classify_and_resolve', side_effect=theme.Unresolvable('unknown input')):
            with self.assertRaisesRegex(ValueError, 'unresolved published theme tokens'):
                theme.build(None)

    def test_css_literal_data_and_scope_are_not_destroyed_by_comment_stripping(self):
        rules = theme.parse_rules('body { --literal: "/* literal */;{value}"; /* comment */ --x: var(--a); }')
        self.assertEqual(rules[0]['declarations'], {'--literal': '"/* literal */;{value}"', '--x': 'var(--a)'})
        for css in ['body{--x:1;--x:2}', 'body{--x:var(--unclosed}', 'body{--x:1', 'body{ &:hover{--x:2}}']:
            with self.subTest(css=css), self.assertRaises(ValueError): theme.parse_rules(css)


if __name__ == '__main__': unittest.main()
