import pathlib
import sys
import tempfile
import unittest

TOOL = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL))
import parity_case_map as cm  # noqa: E402


class CaseMap(unittest.TestCase):
    def make(self, root, group, name, files):
        base = root / group / name / 'test' / 'parity'
        (base / 'cases').mkdir(parents=True)
        for fname, text in files.items():
            (base / 'cases' / fname).write_text(text)
        return base

    def test_collects_public_maps_of_both_kinds(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            base = self.make(root, 'tool', 'x', {
                'a.dart': "final Map<String, ParityCase> aCases = {};\nfinal Map<String, ParityUncovered> aGaps = {};\n",
                'b.dart': "final Map<String, ParityCase> _private = {};\nfinal Map<String, ParityCase> bCases = {};\n",
                'notes.txt': 'ignored',
            })
            self.make(root, 'apps', 'y', {'c.dart': "final Map<String, ParityCase> cCases = {};\n"})
            out = cm.generate(write=True, root=root)
            self.assertEqual(sorted(p.relative_to(root).as_posix() for p in out), [
                'apps/y/test/parity/case_map.g.dart', 'tool/x/test/parity/case_map.g.dart'])
            text = (base / 'case_map.g.dart').read_text()
            self.assertIn('[c0.aCases, c1.bCases]', text)
            self.assertIn('[c0.aGaps]', text)
            self.assertNotIn('_private', text)
            self.assertIn("throw StateError('duplicate parity", text)

    def test_second_run_is_stable(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            self.make(root, 'tool', 'x', {'a.dart': "final Map<String, ParityCase> aCases = {};\n"})
            first = cm.generate(write=True, root=root)
            second = cm.generate(write=False, root=root)
            self.assertEqual(first, second)


if __name__ == '__main__':
    unittest.main()
