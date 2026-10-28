"""Exercise the guard's CLI against an actual immutable Git base policy."""
import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    'design_guard_policy', ROOT / 'tool/design-system/check.py')
GUARD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GUARD)


class GuardPolicyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.here = self.root / 'tool/design-system'
        self.here.mkdir(parents=True)
        (self.root / 'features').mkdir()
        self.write('apps/demo/lib/view.dart',
                   'SizedBox(width: 12);\nColor(0xff123456);\n')
        self.write('packages/design/lib/canonical.dart', 'class Canonical {}\n')
        self.write('packages/design/lib/editor.dart', 'TextButton();\n')
        self.contract = {
            'schema': 'dsh-design-families/1',
            'families': [
                {'name': 'widgets',
                 'canonical': ['packages/design/lib/canonical.dart'],
                 'migrationStatus': 'Published source profile',
                 'pendingDuplicates': []},
                {'name': 'banners', 'canonical': [], 'status': 'pending',
                 'migrationStatus': 'Source profile still pending',
                 'pendingDuplicates': []},
            ],
            'patterns': {
                'platform-control': r'\bTextButton\s*\(',
                'manual-metric': r'\bwidth\s*:\s*\d+',
            },
            'remediation': {'platform-control': 'Use the shared control',
                            'manual-metric': 'Use the source recipe'},
            'wrapperAllowlist': {'platform-control': {
                'packages/design/lib/editor.dart': 'Canonical editing adapter'}},
            'baseline': {'apps/demo/lib/view.dart': {'manual-metric': 1}},
        }
        self.save()
        self.git('init', '--quiet')
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'Known source and guard policy')

    def git(self, *args):
        return subprocess.run([
            'git', '-c', 'core.hooksPath=/dev/null', '-c', 'commit.gpgSign=false',
            '-c', 'user.name=Guard policy test',
            '-c', 'user.email=guard-policy@example.invalid', *args,
        ], cwd=self.root, check=True, capture_output=True, text=True)

    def write(self, path, text):
        target = self.root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def save(self):
        (self.here / 'families.json').write_text(json.dumps(self.contract))

    def run_guard(self):
        output = io.StringIO()
        with (mock.patch.object(GUARD, 'ROOT', self.root),
              mock.patch.object(GUARD, 'HERE', self.here),
              mock.patch.dict(os.environ, {'GITHUB_EVENT_PATH': ''}),
              contextlib.redirect_stdout(output),
              contextlib.redirect_stderr(output)):
            result = GUARD.main()
        return result, output.getvalue()

    def rejected(self, expected):
        self.save()
        result, output = self.run_guard()
        self.assertEqual(result, 1, output)
        self.assertIn(expected, output)

    def test_existing_policy_and_explicit_pending_family_pass(self):
        result, output = self.run_guard()
        self.assertEqual(result, 0, output)

    def test_pattern_weakening_cannot_hide_existing_metric(self):
        self.contract['patterns']['manual-metric'] = '(?!)'
        self.rejected('pattern manual-metric changed')

    def test_pattern_deletion_cannot_remove_coverage(self):
        del self.contract['patterns']['manual-metric']
        del self.contract['remediation']['manual-metric']
        self.contract['baseline'].clear()
        self.rejected('pattern manual-metric removed')

    def test_new_whole_file_allowance_is_rejected(self):
        self.contract['wrapperAllowlist']['platform-control'][
            'apps/demo/lib/view.dart'] = 'Temporary adapter'
        self.write('apps/demo/lib/view.dart', 'SizedBox(width: 12);\nTextButton();')
        self.rejected('wrapper allowance added')

    def test_existing_wrapper_cannot_grow_its_exempt_occurrences(self):
        self.write('packages/design/lib/editor.dart', 'TextButton(); TextButton();')
        self.rejected('wrapper occurrences grew 1 -> 2')

    def test_family_deletion_is_rejected(self):
        self.contract['families'] = self.contract['families'][1:]
        self.rejected('family widgets removed')

    def test_pending_status_cannot_hide_removed_canonical(self):
        self.contract['families'][0].update(canonical=[], status='pending')
        self.rejected('canonical coverage removed')

    def test_empty_canonical_requires_explicit_pending_status(self):
        del self.contract['families'][1]['status']
        self.rejected('empty canonical requires pending status')

    def test_empty_family_inventory_is_rejected(self):
        self.contract['families'] = []
        self.rejected('families must be a nonempty list')

    def test_additive_rule_can_record_existing_source_debt(self):
        self.contract['patterns']['raw-color'] = r'\bColor\s*\('
        self.contract['remediation']['raw-color'] = 'Use the generated color'
        self.contract['baseline']['apps/demo/lib/view.dart']['raw-color'] = 1
        self.save()
        result, output = self.run_guard()
        self.assertEqual(result, 0, output)

    def test_additive_rule_cannot_bootstrap_new_debt(self):
        self.contract['patterns']['raw-color'] = r'\bColor\s*\('
        self.contract['remediation']['raw-color'] = 'Use the generated color'
        self.contract['baseline']['apps/demo/lib/view.dart']['raw-color'] = 2
        self.write('apps/demo/lib/view.dart',
                   'SizedBox(width: 12); Color(0xff123456); Color(0xff654321);')
        self.rejected('baseline raw-color increased 1 -> 2')

    def test_debt_and_allowance_reductions_pass(self):
        self.write('apps/demo/lib/view.dart', 'Color(0xff123456);')
        self.contract['baseline'].clear()
        self.write('packages/design/lib/editor.dart', 'class Editor {}')
        self.contract['wrapperAllowlist'].clear()
        self.save()
        result, output = self.run_guard()
        self.assertEqual(result, 0, output)

    def test_new_family_and_completed_pending_family_pass(self):
        self.write('packages/design/lib/banner.dart', 'class Banner {}')
        self.contract['families'][1].update(
            canonical=['packages/design/lib/banner.dart'], status='active')
        self.contract['families'].append({
            'name': 'new-family', 'canonical': ['packages/design/lib/banner.dart'],
            'migrationStatus': 'A separately registered source profile',
            'pendingDuplicates': [],
        })
        self.save()
        result, output = self.run_guard()
        self.assertEqual(result, 0, output)

    def test_malformed_contracts_fail_without_tracebacks(self):
        original = copy.deepcopy(self.contract)
        mutations = [
            lambda c: c.update(schema='unknown'),
            lambda c: c.update(unrecognizedPolicy=True),
            lambda c: c['patterns'].update({'manual-metric': '['}),
            lambda c: c['baseline']['apps/demo/lib/view.dart'].update(
                {'manual-metric': True}),
            lambda c: c['baseline'].update({'../outside.dart': {'manual-metric': 1}}),
            lambda c: c['families'][0].update(canonical='not-a-list'),
            lambda c: c['families'].append(copy.deepcopy(c['families'][0])),
            lambda c: c['wrapperAllowlist'].update({'missing-rule': {}}),
        ]
        for mutate in mutations:
            with self.subTest(mutation=mutate):
                self.contract = copy.deepcopy(original)
                mutate(self.contract)
                self.save()
                result, output = self.run_guard()
                self.assertEqual(result, 1, output)
                self.assertIn('invalid design-system contract', output)

    def test_duplicate_json_policy_keys_are_rejected(self):
        self.save()
        path = self.here / 'families.json'
        path.write_text(path.read_text().replace(
            '"schema":', '"schema":"dsh-design-families/1","schema":', 1))
        result, output = self.run_guard()
        self.assertEqual(result, 1, output)
        self.assertIn('duplicate key', output)


if __name__ == '__main__':
    unittest.main()
