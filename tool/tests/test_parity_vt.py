import json
import pathlib
import sys
import unittest

TOOL = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL))
from parity_lib import manifest as mf, vt  # noqa: E402

try:
    from parity_lib import pipeline
    HAVE_PIPELINE = True
except ImportError:  # numpy / Pillow are optional tool dependencies
    HAVE_PIPELINE = False


def case(**over):
    base = {
        'id': 'components.button.variants.md.light', 'title': 'Button variants', 'kind': 'button.items',
        'viewport': {'width': 420, 'height': 68, 'density': 2}, 'theme': 'light', 'locale': 'en',
        'variants': [{'id': 'default', 'name': 'Default', 'props': {'a': 1}},
                     {'id': 'hover', 'name': 'Hover', 'props': {}, 'interactions': [{'type': 'hover', 'target': 'btn'}]}],
    }
    base.update(over)
    return base


class CliCases(unittest.TestCase):
    def flat(self, **over):
        return vt.cli_cases(mf.entries({'cases': [case(**over)]}))

    def test_one_cli_case_per_capture_key(self):
        cases = self.flat()
        self.assertEqual([c['id'] for c in cases],
                         ['components.button.variants.md.light', 'components.button.variants.md.light~hover'])
        self.assertEqual(cases[1]['title'], 'Button variants: Hover')
        self.assertEqual(cases[1]['variants'][0]['interactions'], [{'type': 'hover', 'target': 'btn'}])
        self.assertEqual(cases[0]['dshCaseId'], cases[1]['dshCaseId'])

    def test_fills_what_the_cli_validation_requires(self):
        c = self.flat()[0]
        self.assertEqual(c['viewport'], {'width': 420, 'height': 68, 'density': 2})
        self.assertTrue(c['fixture'])
        self.assertTrue(c['capture']['selector'])
        self.assertTrue(c['tolerance']['pixelRatio'])
        self.assertEqual(c['captureType'], 'component-fixture')

    def test_capture_selector_and_screens_prefix(self):
        c = self.flat(id='screens.chat.list.default.light', capture={'selector': '#x', 'crop': 'viewport'})[0]
        self.assertEqual(c['captureType'], 'real-screen')
        self.assertEqual(c['capture'], {'selector': '#x', 'crop': 'viewport'})

    def test_skipped_cases_are_not_flattened(self):
        self.assertEqual(self.flat(skip={'reason': 'x'}), [])

    def test_manifest_file_is_json(self):
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            path = vt.write_manifest(mf.entries({'cases': [case()]}), pathlib.Path(tmp) / 'sub' / 'cli.json')
            self.assertEqual(len(json.loads(path.read_text())['cases']), 2)


@unittest.skipUnless(HAVE_PIPELINE, 'numpy/Pillow not installed')
class Status(unittest.TestCase):
    def test_official_statuses_are_kept(self):
        for official in ('same', 'pass', 'basic-pass'):
            self.assertEqual(pipeline.status_of(official, 10.0, False), official)

    def test_geometry_pass_only_beyond_the_official_statuses(self):
        self.assertEqual(pipeline.status_of('different', 99.5, False), 'geometry-pass')
        self.assertEqual(pipeline.status_of('different', 99.4, False), 'fail')

    def test_size_mismatch_always_fails(self):
        for official in ('same', 'pass', 'basic-pass', 'different'):
            self.assertEqual(pipeline.status_of(official, 100.0, True), 'fail')


if __name__ == '__main__':
    unittest.main()
