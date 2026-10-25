"""Device crops must preserve the enclosing raster, including fractional edges."""
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]


class PixelCropTest(unittest.TestCase):
    def check_js(self, script):
        result = subprocess.run(
            ['node', '--input-type=module', '-'], cwd=ROOT, text=True,
            input="import assert from 'node:assert/strict';\n"
                  "import { enclosingDeviceRect, cropRgba } from './tool/parity-web/pixel-crop.mjs';\n" + script,
            capture_output=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_fractional_size_origin_and_float_noise(self):
        self.check_js("""
          const view = {width: 520, height: 400};
          for (const [height, expected] of [[85, 224], [173, 455]]) {
            assert.deepEqual(enclosingDeviceRect({x:0,y:0,width:300,height}, view, 2.625),
              {x:0,y:0,width:788,height:expected});
          }
          assert.deepEqual(enclosingDeviceRect({x:10.4,y:296.5,width:39.8,height:23.6}, view, 3),
            {x:31,y:889,width:120,height:72});
          assert.deepEqual(enclosingDeviceRect({x:16+1e-10,y:16-1e-10,width:100,height:50}, view, 2.625),
            {x:42,y:42,width:263,height:132});
        """)

    def test_intersection_and_invalid_geometry(self):
        self.check_js("""
          const view = {width:10,height:10};
          assert.deepEqual(enclosingDeviceRect({x:-1,y:8,width:20,height:4}, view, 2.625),
            {x:0,y:21,width:27,height:6});
          for (const box of [{x:10,y:0,width:2,height:2}, {x:0,y:0,width:NaN,height:2}]) {
            assert.throws(() => enclosingDeviceRect(box, view, 2.625));
          }
          assert.throws(() => enclosingDeviceRect({x:0,y:0,width:2,height:2}, view, 0));
        """)

    def test_copy_preserves_every_channel_and_rejects_missing_pixels(self):
        self.check_js("""
          const image = {width:4,height:3,data:Buffer.from(Array.from({length:48}, (_,i) => i))};
          const cropped = cropRgba(image, {x:1,y:1,width:2,height:2});
          assert.deepEqual(cropped, {width:2,height:2,data:Buffer.from([
            ...image.data.subarray(20,28), ...image.data.subarray(36,44)])});
          assert.deepEqual([...image.data], Array.from({length:48}, (_,i) => i));
          for (const rect of [{x:3,y:0,width:2,height:1}, {x:0.5,y:0,width:1,height:1}]) {
            assert.throws(() => cropRgba(image, rect));
          }
        """)
