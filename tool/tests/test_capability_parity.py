import copy
import importlib.util
import json
import pathlib
import tempfile
import textwrap
import unittest

spec = importlib.util.spec_from_file_location(
    'capability_parity', pathlib.Path(__file__).resolve().parents[1] / 'capability_parity.py')
cp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cp)

COMMIT = 'a' * 40


def row(rid, status='missing', **extra):
    kind = rid.split(':')[0]
    r = {'id': rid, 'kind': kind, 'area': 'misc', 'dshSource': 'x/y.ts', 'description': 'Does a thing.', 'status': status}
    if kind == 'package' and status in ('missing', 'partial'):
        r['priority'] = 'P3'
    r.update(extra)
    return r


def table(*rows):
    return {'schemaVersion': 1, 'dsh': {'commit': COMMIT, 'npmVersion': '1'}, 'whalee': {'reviewedAt': 'abc'}, 'rows': list(rows)}


def write(root, rel, text):
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(textwrap.dedent(text))
    return p


def fake_dsh(root):
    write(root, 'packages/client/ui-alpha/package.json', json.dumps({'description': 'Alpha surface. More words.'}))
    write(root, 'packages/client/ui-beta/package.json', json.dumps({'description': 'Beta surface'}))
    write(root, 'packages/client/not-ui/package.json', json.dumps({'description': 'ignored'}))
    write(root, 'packages/api/thing/src/index.ts', """
        export class Thing extends TypertRemoteService {
          constructor(ctx: Context) { super(ctx, 'thingController', { namespace: 'thing' }) }
          /**
           * Read the thing. Second sentence.
           * @param id - the id
           */
          @Remote
          async read(id: string): Promise<string> { return id }
          @Remote('renamed')
          write(): void {}
          @Remote({ mode: 'stream' })
          async *watch(): AsyncIterable<string> {}
        }
        export class Other extends TypertRemoteService {
          constructor(ctx: Context) { super(ctx, 'other') }
          @Remote({ name: 'go', mode: 'unary' })
          run(): void {}
        }
        """)
    write(root, 'packages/api/thing/tests/x.spec.ts', "@Remote\nfoo() {}\n")
    write(root, 'packages/extensions/cordis-client-runner/src/client/slot-catalog.ts', """
        export const SLOTS = [
          {
            key: 'a.b.c',
            kind: 'list',
            scope: 'session',
            summary: 'First slot. It\\'s here.',
            doc: 'x',
            source: 'packages/client/ui-alpha/src/slots.ts:12',
          },
          {
            key: 'd.e',
            kind: 'single',
            scope: 'root',
            summary: 'Second slot.',
            doc: 'x',
            source: 'packages/client/ui-beta/src/slots.ts:3',
          },
        ]
        """)
    write(root, 'packages/client/ui-alpha/src/client/index.ts', """
        export const NS = 'alpha-ns'
        const a = ctx.configForms.get<Foo>(NS)
        const b = ctx.configForms.get('literal-ns')
        ctx.configForms.whileServed([NS, 'second'], () => {})
        ctx.remote.settings.mutate('mutated-ns', ops, rev)
        """)


class ScannerTest(unittest.TestCase):
    def test_scanners_on_a_synthetic_tree(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            fake_dsh(root)
            ids = {u['id']: u for u in cp.scan_all(root)}
        self.assertEqual({i for i in ids if i.startswith('package:')}, {'package:ui-alpha', 'package:ui-beta'})
        self.assertEqual(ids['package:ui-alpha']['description'], 'Alpha surface.')
        self.assertEqual({i for i in ids if i.startswith('remote:')},
                         {'remote:thing/read', 'remote:thing/renamed', 'remote:thing/watch', 'remote:other/go'})
        self.assertEqual(ids['remote:thing/read']['description'], 'Read the thing.')
        self.assertTrue(ids['remote:thing/watch']['stream'])
        self.assertEqual(ids['slot:a.b.c']['dshSource'], 'packages/client/ui-alpha/src/slots.ts')
        self.assertEqual(ids['slot:a.b.c']['description'], "First slot.")
        self.assertEqual({i for i in ids if i.startswith('settings:')},
                         {'settings:alpha-ns', 'settings:literal-ns', 'settings:second', 'settings:mutated-ns'})

    def test_real_pin_is_scanned_when_present(self):
        src = cp.dsh_src()
        if src is None:
            self.skipTest('no dsh checkout')
        kinds = {u['kind'] for u in cp.scan_all(src)}
        self.assertEqual(kinds, set(cp.KINDS))


class ValidateTest(unittest.TestCase):
    def errors(self, t, files=()):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            for f in files:
                write(root, f, 'x')
            return cp.validate(t, root)

    def test_minimal_table_is_valid(self):
        self.assertEqual(self.errors(table(row('slot:a.b'), row('remote:x/y', 'na', reason='why'))), [])

    def test_ported_needs_an_existing_whalee_path(self):
        self.assertTrue(self.errors(table(row('slot:a', 'ported'))))
        self.assertTrue(self.errors(table(row('slot:a', 'ported', whalee=['lib/a.dart']))))
        self.assertEqual(self.errors(table(row('slot:a', 'ported', whalee=['lib/a.dart'])), ['lib/a.dart']), [])

    def test_partial_needs_notes_and_na_needs_a_reason(self):
        self.assertTrue(self.errors(table(row('slot:a', 'partial', whalee=['lib/a.dart'])), ['lib/a.dart']))
        self.assertEqual(self.errors(table(row('slot:a', 'partial', whalee=['lib/a.dart'], notes='missing x')), ['lib/a.dart']), [])
        self.assertTrue(self.errors(table(row('slot:a', 'na'))))

    def test_missing_names_no_location_and_reason_is_for_na(self):
        self.assertTrue(self.errors(table(row('slot:a', 'missing', whalee=['lib/a.dart'])), ['lib/a.dart']))
        self.assertTrue(self.errors(table(row('slot:a', 'missing', reason='no'))))

    def test_vocabulary_and_shape(self):
        self.assertTrue(self.errors(table(row('slot:a', 'done'))))
        self.assertTrue(self.errors(table(row('slot:a', area='nowhere'))))
        self.assertTrue(self.errors(table(row('slot:a'), row('slot:a'))))
        self.assertTrue(self.errors(table(row('slot:a', bogus=1))))
        self.assertTrue(self.errors(table(dict(row('slot:a'), kind='remote'))))
        self.assertTrue(self.errors(table(row('slot:a', whalee=['../x']))))

    def test_missing_package_needs_a_priority_and_only_open_rows_have_one(self):
        r = row('package:ui-a')
        del r['priority']
        self.assertTrue(self.errors(table(r)))
        self.assertTrue(self.errors(table(row('slot:a', 'na', reason='r', priority='P1'))))
        self.assertTrue(self.errors(table(row('slot:a', priority='P9'))))

    def test_review_markers(self):
        t = table(row('slot:a'))
        t['dsh']['commit'] = 'short'
        self.assertTrue(self.errors(t))
        t = table(row('slot:a'))
        del t['whalee']
        self.assertTrue(self.errors(t))


class CoverageTest(unittest.TestCase):
    def test_new_and_stale_items(self):
        t = table(row('slot:a'), row('slot:gone'))
        upstream = [{'id': 'slot:a', 'kind': 'slot', 'dshSource': 's', 'description': 'd'},
                    {'id': 'remote:n/m', 'kind': 'remote', 'dshSource': 's', 'description': ''}]
        new, stale = cp.coverage(t, upstream)
        self.assertEqual([u['id'] for u in new], ['remote:n/m'])
        self.assertEqual(stale, ['slot:gone'])
        self.assertEqual(cp.stub(new[0])['status'], 'missing')
        self.assertTrue(cp.stub(new[0])['description'])


class CheckTest(unittest.TestCase):
    def build(self, root, t, md=True):
        write(root, 'docs/capability-parity.json', json.dumps(t))
        if md:
            write(root, 'docs/capability-parity.md', cp.render(t))

    def test_full_check_on_a_synthetic_tree(self):
        with tempfile.TemporaryDirectory() as tmp, tempfile.TemporaryDirectory() as dsh:
            root, src = pathlib.Path(tmp), pathlib.Path(dsh)
            fake_dsh(src)
            rows = [dict(u, area='misc', status='missing') for u in cp.scan_all(src)]
            rows = [{k: r[k] for k in ('id', 'kind', 'area', 'dshSource', 'description', 'status')} for r in rows]
            for r in rows:
                r['description'] = r['description'] or 'Does a thing.'
            for r in rows:
                if r['kind'] == 'package':
                    r['priority'] = 'P2'
            t = table(*rows)
            self.build(root, t)
            code, text = cp.check(root, src)
            self.assertEqual(code, 0, text)
            code, text = cp.check(root, None)  # offline only: skip, not failure
            self.assertEqual(code, 2, text)
            # a new upstream item turns the check red and names it
            write(src, 'packages/client/ui-gamma/package.json', json.dumps({'description': 'Gamma'}))
            code, text = cp.check(root, src)
            self.assertEqual(code, 1)
            self.assertIn('no row for package:ui-gamma', text)
            self.assertIn('"id": "package:ui-gamma"', text)
            # a removed upstream item leaves a stale row
            (src / 'packages/client/ui-gamma/package.json').unlink()
            (src / 'packages/client/ui-gamma').rmdir()
            (src / 'packages/client/ui-beta/package.json').unlink()
            code, text = cp.check(root, src)
            self.assertEqual(code, 1)
            self.assertIn('row package:ui-beta', text)

    def test_stale_markdown_fails_even_offline(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            t = table(row('slot:a'))
            self.build(root, t)
            write(root, 'docs/capability-parity.md', cp.render(t) + 'edited\n')
            code, text = cp.check(root, None)
            self.assertEqual(code, 1)
            self.assertIn('stale', text)

    def test_a_scanner_that_finds_nothing_is_an_error(self):
        with tempfile.TemporaryDirectory() as tmp, tempfile.TemporaryDirectory() as dsh:
            root, src = pathlib.Path(tmp), pathlib.Path(dsh)
            (src / 'packages' / 'client').mkdir(parents=True)
            self.build(root, table(row('slot:a')))
            code, text = cp.check(root, src)
            self.assertEqual(code, 1)
            self.assertIn('scanner found no', text)


class RenderTest(unittest.TestCase):
    def test_counts_and_priorities(self):
        t = table(row('package:ui-a'), row('slot:a', 'ported', whalee=['x']), row('slot:b', 'na', reason='r'))
        md = cp.render(t)
        self.assertIn('| **all** | 1 | 0 | 1 | 1 | 3 |', md)
        self.assertIn('**P3**', md)
        self.assertEqual(md, cp.render(copy.deepcopy(t)))


class RealTableTest(unittest.TestCase):
    def test_committed_table_is_valid_and_its_markdown_fresh(self):
        t = cp.load_table()
        self.assertEqual(cp.validate(t), [])
        self.assertEqual(cp.MARKDOWN.read_text(), cp.render(t))
        code, text = cp.check(cp.REPO, cp.dsh_src())
        self.assertIn(code, (0, 2), text)


if __name__ == '__main__':
    unittest.main()
