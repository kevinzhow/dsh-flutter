import importlib.util
import pathlib
import tempfile
import textwrap
import unittest

spec = importlib.util.spec_from_file_location(
    'check_deps', pathlib.Path(__file__).resolve().parents[1] / 'check_deps.py')
check_deps = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_deps)


def make(root, sub, name, deps=(), imports=()):
    d = root / sub / name
    (d / 'lib').mkdir(parents=True)
    body = 'name: %s\ndependencies:\n%s' % (name, ''.join('  %s: ^0.0.1\n' % x for x in deps))
    (d / 'pubspec.yaml').write_text(body)
    (d / 'lib' / 'a.dart').write_text(''.join("import 'package:%s/x.dart';\n" % x for x in imports))


class CheckDepsTest(unittest.TestCase):
    def run_check(self, build):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            build(root)
            return check_deps.check(root)[1]

    def test_real_workspace_is_clean(self):
        root = pathlib.Path(__file__).resolve().parents[2]
        self.assertEqual(check_deps.check(root)[1], [])

    def test_allowed_chain_passes(self):
        def build(r):
            make(r, 'packages', 'dsh_client')
            make(r, 'packages', 'dsh_models', ['dsh_client'], ['dsh_client'])
            make(r, 'packages', 'dsh_conversation', ['dsh_models'], ['dsh_models'])
            make(r, 'packages', 'dsh_slots', ['dsh_conversation'], ['dsh_conversation'])
            make(r, 'packages', 'dsh_theme')
            make(r, 'packages', 'dsh_ui', ['dsh_theme'], ['dsh_theme'])
            make(r, 'features', 'dsh_feature_one', ['dsh_slots', 'dsh_ui'], ['dsh_slots', 'dsh_ui'])
            make(r, 'apps', 'app', ['dsh_feature_one', 'dsh_client'], ['dsh_client'])
        self.assertEqual(self.run_check(build), [])

    def test_ui_importing_client_fails_in_pubspec_and_import(self):
        def build(r):
            make(r, 'packages', 'dsh_client')
            make(r, 'packages', 'dsh_theme')
            make(r, 'packages', 'dsh_ui', ['dsh_theme', 'dsh_client'], ['dsh_client'])
        v = self.run_check(build)
        self.assertEqual(len(v), 2)
        self.assertTrue(all('ui must never import client' in x for x in v))

    def test_theme_importing_client_fails(self):
        def build(r):
            make(r, 'packages', 'dsh_client')
            make(r, 'packages', 'dsh_theme', [], ['dsh_client'])
        self.assertTrue(any('theme must never import client' in x for x in self.run_check(build)))

    def test_models_importing_conversation_fails(self):
        def build2(r):
            make(r, 'packages', 'dsh_models', [], ['dsh_conversation'])
            make(r, 'packages', 'dsh_conversation', ['dsh_models'])
        v = self.run_check(build2)
        self.assertTrue(any('dsh_models (models) must not depend on dsh_conversation' in x for x in v))
        self.assertTrue(any('cycle' in x for x in v))

    def test_features_must_not_import_each_other(self):
        def build(r):
            make(r, 'features', 'dsh_feature_one')
            make(r, 'features', 'dsh_feature_two', ['dsh_feature_one'], ['dsh_feature_one'])
        v = self.run_check(build)
        self.assertEqual(len(v), 2)
        self.assertTrue(all('features never import each other' in x for x in v))

    def test_relative_import_leaving_the_package_fails(self):
        def build(r):
            make(r, 'packages', 'dsh_client')
            make(r, 'packages', 'dsh_theme')
            (r / 'packages' / 'dsh_theme' / 'lib' / 'b.dart').write_text("import '../../dsh_client/lib/x.dart';\n")
        self.assertTrue(any('relative import leaves the package' in x for x in self.run_check(build)))

    def test_unclassified_package_fails(self):
        def build(r):
            make(r, 'packages', 'dsh_mystery')
        self.assertTrue(any('not classified' in x for x in self.run_check(build)))


if __name__ == '__main__':
    unittest.main()
