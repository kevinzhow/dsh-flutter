import copy
import json
import pathlib
import sys
import tempfile
import unittest

TOOL = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL))
from parity_lib import builders, manifest as mf, sampling  # noqa: E402


def good_case(**over):
    case = {
        'id': 'components.button.variants.md.light', 'title': 'Button variants', 'kind': 'button.items',
        'viewport': {'width': 420, 'height': 68, 'density': 1}, 'theme': 'light', 'locale': 'en',
        'variants': [{'id': 'default', 'name': 'Default', 'props': {}},
                     {'id': 'hover', 'name': 'Hover', 'props': {}, 'interactions': [{'type': 'hover', 'target': 'btn'}]}],
        'capture': {'selector': '[data-parity-target]', 'crop': 'element'},
    }
    case.update(over)
    return case


def manifest_of(*cases):
    return {'schema': mf.SCHEMA, 'name': 't', 'cases': list(cases)}


class ValidateCase(unittest.TestCase):
    def errors(self, **over):
        return mf.validate_case(good_case(**over))

    def test_valid_case(self):
        self.assertEqual(self.errors(), [])

    def test_id_shape(self):
        for bad in ('button.light', 'components.button.light', 'Components.Button.a.light', 'components.button..x.light',
                    'widgets.button.a.b.light'):
            self.assertTrue(self.errors(id=bad), bad)

    def test_theme_must_end_the_id(self):
        errs = self.errors(id='components.button.variants.md.dark')
        self.assertTrue(any('last id segment' in e for e in errs), errs)
        self.assertTrue(self.errors(theme='sepia'))

    def test_required_fields(self):
        for key in ('title', 'kind', 'viewport', 'theme', 'locale', 'variants'):
            case = good_case()
            del case[key]
            self.assertTrue(mf.validate_case(case), key)

    def test_viewport(self):
        self.assertTrue(self.errors(viewport={'width': 0, 'height': 10, 'density': 1}))
        self.assertTrue(self.errors(viewport={'width': 10, 'height': 10}))
        self.assertTrue(self.errors(viewport={'width': 10, 'height': 10, 'density': 'x'}))

    def test_locale(self):
        self.assertEqual(self.errors(locale='zh-CN'), [])
        self.assertTrue(self.errors(locale='fr'))

    def test_variants(self):
        self.assertTrue(self.errors(variants=[]))
        first = copy.deepcopy(good_case()['variants'])
        first[0]['id'] = 'hover'
        self.assertTrue(any('first variant' in e for e in self.errors(variants=first)))
        dup = good_case()['variants'] + [{'id': 'hover', 'name': 'again', 'props': {}}]
        self.assertTrue(any('duplicate variant' in e for e in self.errors(variants=dup)))
        self.assertTrue(self.errors(variants=[{'id': 'default', 'name': 'x', 'props': [] }]))

    def test_interactions(self):
        def with_steps(*steps):
            return self.errors(variants=[{'id': 'default', 'name': 'x', 'props': {}, 'interactions': list(steps)}])
        self.assertEqual(with_steps({'type': 'tab', 'count': 2}, {'type': 'wait', 'ms': 50}, {'type': 'type', 'target': 'a', 'text': 'x'}), [])
        self.assertTrue(with_steps({'type': 'dance', 'target': 'a'}))
        self.assertTrue(with_steps({'type': 'hover'}))                       # missing target
        self.assertTrue(with_steps({'type': 'hover', 'target': 'a', 'x': 1}))  # unknown key
        self.assertTrue(with_steps({'type': 'tab', 'count': 0}))
        self.assertEqual(with_steps({'type': 'set-scroll', 'target': 'list', 'offset': 14.5}), [])
        self.assertEqual(with_steps({'type': 'focus-by-tab', 'target': 'switch'}), [])
        self.assertTrue(with_steps({'type': 'focus-by-tab'}))
        self.assertTrue(with_steps({'type': 'set-scroll', 'target': 'list', 'offset': -1}))
        self.assertTrue(with_steps({'type': 'set-scroll', 'target': 'list', 'offset': float('nan')}))

    def test_capture_and_regions(self):
        self.assertTrue(self.errors(capture={'selector': 'x', 'bogus': 1}))
        self.assertTrue(self.errors(capture={'crop': 'sideways'}))
        ok = {'name': 'label', 'x': 0, 'y': 0, 'width': 10, 'height': 10}
        self.assertEqual(self.errors(regions=[ok]), [])
        self.assertTrue(self.errors(regions=[ok, ok]))                       # duplicate name
        self.assertTrue(self.errors(regions=[{'name': 'x', 'x': 0, 'y': 0, 'width': 0, 'height': 1}]))

    def test_capture_type_matches_prefix(self):
        self.assertEqual(self.errors(captureType='component-fixture'), [])
        self.assertTrue(self.errors(captureType='real-screen'))
        screen = good_case(id='screens.chat.main.empty.light', captureType='real-screen')
        self.assertEqual(mf.validate_case(screen), [])
        self.assertEqual(mf.capture_type(screen), 'real-screen')

    def test_fixture_is_a_plain_file_name(self):
        self.assertEqual(self.errors(fixture='chat.json'), [])
        self.assertTrue(self.errors(fixture='../chat.json'))

    def test_unknown_case_key(self):
        self.assertTrue(self.errors(colour='red'))


class ValidateManifest(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(mf.validate_manifest(manifest_of(good_case())), [])

    def test_schema_and_shape(self):
        self.assertTrue(mf.validate_manifest([]))
        self.assertTrue(mf.validate_manifest({'schema': 'other', 'name': 'x', 'cases': []}))
        self.assertTrue(mf.validate_manifest({'schema': mf.SCHEMA, 'name': 'x', 'cases': {}}))

    def test_duplicate_ids(self):
        errs = mf.validate_manifest(manifest_of(good_case(), good_case()))
        self.assertTrue(any('duplicate case id' in e for e in errs), errs)

    def test_load_reports_every_problem(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = pathlib.Path(tmp) / 'm.json'
            path.write_text(json.dumps(manifest_of(good_case(theme='x'), good_case(id='bad'))))
            with self.assertRaises(mf.ManifestError) as ctx:
                mf.load_manifest(path)
            self.assertGreaterEqual(len(ctx.exception.errors), 2)
            path.write_text('{not json')
            with self.assertRaises(mf.ManifestError):
                mf.load_manifest(path)

    def test_committed_core_manifest_is_valid(self):
        man = mf.load_manifest(TOOL / 'parity-shared' / 'cases.json')
        self.assertGreater(len(man['cases']), 0)


class Entries(unittest.TestCase):
    def test_capture_keys_and_selection(self):
        man = manifest_of(good_case(), good_case(id='components.input.field.states.dark', theme='dark', kind='input.fields'),
                          good_case(id='components.tag.tones.all.light', skip={'reason': 'pending'}))
        got = mf.entries(man)
        self.assertEqual([e['key'] for e in got], [
            'components.button.variants.md.light', 'components.button.variants.md.light~hover',
            'components.input.field.states.dark', 'components.input.field.states.dark~hover'])  # skipped: not capturable
        self.assertEqual(mf.capture_key('a.b.c.light', 'default'), 'a.b.c.light')
        self.assertEqual([e['key'] for e in mf.select(got, 'components.button.*')], [
            'components.button.variants.md.light', 'components.button.variants.md.light~hover'])
        self.assertEqual([e['key'] for e in mf.select(got, 'components.button.variants.md.light')],
                         ['components.button.variants.md.light', 'components.button.variants.md.light~hover'])
        self.assertEqual([e['key'] for e in mf.select(got, '*~hover')],
                         ['components.button.variants.md.light~hover', 'components.input.field.states.dark~hover'])
        self.assertEqual(len(mf.select(got, '')), 4)


class Sampling(unittest.TestCase):
    def cases(self, names, theme):
        return [good_case(id='components.button.matrix.%s.%s' % (n, theme), theme=theme) for n in names]

    def test_dark_keeps_first_and_dense_light_keeps_all(self):
        names = ['primary-md', 'ghost-md', 'outline-many', 'toolbar-sm']
        man = manifest_of(*self.cases(names, 'light'), *self.cases(names, 'dark'))
        out = sampling.sample_themes(man, {})
        ids = [c['id'] for c in out['cases']]
        self.assertEqual(sum(i.endswith('.light') for i in ids), 4)
        self.assertEqual([i for i in ids if i.endswith('.dark')],
                         ['components.button.matrix.primary-md.dark', 'components.button.matrix.outline-many.dark'])

    def test_last_case_is_dense_when_no_keyword(self):
        names = ['a', 'b', 'c']
        man = manifest_of(*self.cases(names, 'dark'))
        kept = [c['id'] for c in sampling.sample_themes(man, {})['cases']]
        self.assertEqual(kept, ['components.button.matrix.a.dark', 'components.button.matrix.c.dark'])

    def test_all_themes_switch(self):
        man = manifest_of(*self.cases(['a', 'b', 'c'], 'dark'))
        self.assertEqual(len(sampling.sample_themes(man, {'PARITY_EXT_ALL_THEMES': '1'})['cases']), 3)


class Builders(unittest.TestCase):
    def test_order_constant_and_first_builder(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = pathlib.Path(tmp)
            (d / 'build-b.py').write_text('ORDER = 10\n')
            (d / 'build-a.py').write_text('x = 1\n')
            (d / 'build-c.py').write_text('ORDER = -5\n')
            (d / 'build-cases.py').write_text('ORDER = 999\n')
            (d / 'builders_api.py').write_text('')
            self.assertEqual(builders.ordered_builders(d), ['build-cases.py', 'build-c.py', 'build-b.py', 'build-a.py'])


if __name__ == '__main__':
    unittest.main()
