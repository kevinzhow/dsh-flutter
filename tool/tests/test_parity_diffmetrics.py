import pathlib
import sys
import tempfile
import unittest

TOOL = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL))

try:
    import numpy as np
    from PIL import Image
    from parity_lib import diffmetrics as dm
    HAVE = True
except ImportError:  # numpy / Pillow are optional tool dependencies (tool/parity-requirements.txt)
    HAVE = False


def canvas(h=60, w=120, colour=255):
    return np.full((h, w, 3), colour, np.int16)


def card():
    img = canvas()
    img[10:50, 10:110] = (30, 60, 200)   # a solid button-like block with straight edges
    return img


@unittest.skipUnless(HAVE, 'numpy/Pillow not installed')
class Metrics(unittest.TestCase):
    def compare(self, a, b, density=1.0, regions=()):
        return dm.compare_arrays(a, b, density, regions)[0]

    def test_identical_is_same(self):
        r = self.compare(card(), card())
        self.assertEqual((r['exactPct'], r['nonTextPct'], r['closePct'], r['verdict']), (100.0, 100.0, 100.0, 'same'))
        self.assertEqual(r['mismatched'], 0)

    def test_counts_are_exact(self):
        b = card()
        b[0, 0] = (0, 0, 0)
        b[0, 1] = (0, 0, 0)
        r = self.compare(card(), b)
        self.assertEqual(r['mismatched'], 2)
        self.assertAlmostEqual(r['exactPct'], 100.0 * (60 * 120 - 2) / (60 * 120), places=3)

    def test_close_ignores_rounding_noise(self):
        b = card()
        b[10:50, 10:110] = (30, 61, 200)   # 1/255 colour rounding over the whole fill
        r = self.compare(card(), b)
        self.assertEqual(r['closePct'], 100.0)
        self.assertLess(r['exactPct'], 100.0)
        self.assertGreater(r['buckets']['fill'], 0.9 * r['mismatched'])   # the interior; edge pixels are not flat
        self.assertEqual(r['buckets']['other'], 0)

    def test_whole_pixel_shift_is_not_text(self):
        r = self.compare(card(), np.roll(card(), 1, axis=0))
        self.assertEqual(r['buckets']['text'], 0)
        self.assertLess(r['nonTextPct'], 100.0)
        self.assertGreater(r['buckets']['hairline'] + r['buckets']['corner'] + r['buckets']['offset'], 0)

    def test_text_like_noise_counts_as_matching_in_non_text(self):
        rng = np.random.default_rng(7)
        a, b = canvas(), canvas()
        glyph = (rng.integers(0, 2, (14, 40)) * 255).astype(np.int16)
        a[20:34, 30:70] = glyph[..., None]
        b[20:34, 30:70] = np.clip(glyph[..., None] + rng.integers(-60, 60, (14, 40, 1)), 0, 255)
        r = self.compare(a, b)
        self.assertGreater(r['buckets']['text'], 0)
        self.assertGreater(r['nonTextPct'], r['exactPct'])
        self.assertGreater(r['nonTextPct'], 99.0)

    def test_wrong_colour_is_other_and_fails(self):
        b = card()
        b[10:50, 10:110] = (200, 30, 30)
        r = self.compare(card(), b)
        self.assertEqual(r['verdict'], 'fail')
        self.assertGreater(r['buckets']['other'], 0)
        self.assertLess(r['nonTextPct'], dm.GEOMETRY_PASS)

    def test_verdict_thresholds(self):
        self.assertEqual(dm.verdict(100.0, 100.0), 'same')
        self.assertEqual(dm.verdict(96.0, 96.0), 'pass')
        self.assertEqual(dm.verdict(95.9, 99.5), 'geometry-pass')
        self.assertEqual(dm.verdict(95.9, 99.4), 'fail')

    def test_size_mismatch_pads_with_white_and_fails(self):
        a, b = card(), card()[:, :100]
        r = self.compare(a, b)
        self.assertTrue(r['sizeMismatch'])
        self.assertEqual(r['verdict'], 'fail')
        self.assertEqual(r['sizeReact'], [120, 60])
        self.assertEqual(r['sizeFlutter'], [100, 60])

    def test_alpha_is_flattened_on_white(self):
        with tempfile.TemporaryDirectory() as tmp:
            p, q = pathlib.Path(tmp, 'a.png'), pathlib.Path(tmp, 'b.png')
            Image.new('RGBA', (4, 4), (0, 0, 0, 0)).save(p)
            Image.new('RGBA', (4, 4), (255, 255, 255, 255)).save(q)
            self.assertEqual(dm.compare_files(p, q)[0]['exactPct'], 100.0)

    def test_regions_are_scored_separately(self):
        b = card()
        b[12:20, 12:30] = (0, 0, 0)
        r = self.compare(card(), b, regions=[
            {'name': 'inside', 'x': 10, 'y': 10, 'width': 30, 'height': 20},
            {'name': 'elsewhere', 'x': 60, 'y': 30, 'width': 40, 'height': 20},
            {'name': 'off', 'x': 500, 'y': 500, 'width': 5, 'height': 5}])
        by = {g['name']: g for g in r['regions']}
        self.assertLess(by['inside']['exactPct'], 100.0)
        self.assertEqual(by['elsewhere']['exactPct'], 100.0)
        self.assertIn('error', by['off'])
        self.assertTrue(r['worstCells'])

    def test_density_scales_regions(self):
        a, b = canvas(120, 240), canvas(120, 240)
        b[20:30, 20:40] = 0
        r = self.compare(a, b, density=2.0, regions=[{'name': 'r', 'x': 10, 'y': 10, 'width': 10, 'height': 5}])
        self.assertEqual(r['regions'][0]['rect'], [20, 20, 20, 10])
        self.assertEqual(r['regions'][0]['mismatched'], 200)


if __name__ == '__main__':
    unittest.main()
