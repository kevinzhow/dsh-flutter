"""Explicit native component fixtures do not need host credentials."""
import importlib.util
import os
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch
from PIL import Image

PATH = pathlib.Path(__file__).resolve().parents[1] / 'parity-desktop/gpu_capture.py'
SPEC = importlib.util.spec_from_file_location('gpu_capture_component', PATH)
GPU = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GPU)


class ComponentHostTest(unittest.TestCase):
    def test_explicit_standalone_cases_require_no_host(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertIsNone(GPU.host_link([{'pairHost': False}]))

    def test_default_and_mixed_cases_still_require_host(self):
        with patch.dict(os.environ, {}, clear=True):
            for cases in [[{}], [{'pairHost': False}, {}]]:
                with self.subTest(cases=cases), self.assertRaises(SystemExit):
                    GPU.host_link(cases)

    def test_normal_pairing_keeps_the_private_link_requirement(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = pathlib.Path(tmp) / 'host.log'
            log.write_text('no launch link')
            with patch.dict(os.environ, {'PARITY_DESKTOP_HOST_LOG': str(log)}):
                with self.assertRaises(SystemExit):
                    GPU.host_link([{}])
                link = 'http://127.0.0.1:18788/?token=synthetic-test'
                log.write_text(link)
                self.assertEqual(GPU.host_link([{}]), link)


class CursorCaptureTest(unittest.TestCase):
    def test_capture_restores_cursor_and_preserves_private_output(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            screen = Mock()

            def screenshot(*args, **kwargs):
                self.assertEqual(screen.send.call_args_list[-1].args, ('cursor 0',))
                (kwargs['cwd'] / 'wayland.png').write_bytes(b'png-raster')

            with patch.object(GPU.subprocess, 'run', side_effect=screenshot), patch.object(GPU.time, 'sleep'):
                GPU.capture({}, root / 'capture', root / 'result.png', screen)
            self.assertEqual([c.args for c in screen.send.call_args_list], [('cursor 0',), ('cursor 1',)])
            self.assertEqual((root / 'result.png').read_bytes(), b'png-raster')
            self.assertEqual((root / 'result.png').stat().st_mode & 0o777, 0o600)
            self.assertFalse((root / 'capture').exists())

    def test_failed_screenshooter_still_restores_cursor(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            screen = Mock()
            with patch.object(GPU.subprocess, 'run', side_effect=subprocess.TimeoutExpired('screenshooter', 15)), \
                    patch.object(GPU.time, 'sleep'), self.assertRaises(subprocess.TimeoutExpired):
                GPU.capture({}, root / 'capture', root / 'result.png', screen)
            self.assertEqual([c.args for c in screen.send.call_args_list], [('cursor 0',), ('cursor 1',)])
            self.assertFalse((root / 'result.png').exists())


class CaptureConditionTest(unittest.TestCase):
    def test_waits_for_changed_rgb_even_when_alpha_is_identical(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            Image.new('RGBA', (4, 4), (0, 0, 0, 255)).save(root / 'closed.png')
            attempts = []

            def screenshot(env, directory, output, screen):
                attempts.append(1)
                image = Image.new('RGBA', (4, 4), (0, 0, 0, 255))
                if len(attempts) == 3:
                    image.putpixel((1, 1), (255, 0, 0, 255))
                image.save(output)

            with patch.object(GPU, 'capture', side_effect=screenshot), patch.object(GPU.time, 'sleep'):
                result = GPU.expect_capture({}, root, Mock(),
                    {'reference': 'closed', 'rect': [0, 0, 3, 3], 'changed': True})
            self.assertEqual(result['attempts'], 3)
            self.assertTrue(result['passed'])
            self.assertFalse((root / 'assert-current.png').exists())

    def test_unchanged_scene_can_be_required_and_timeout_is_not_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            Image.new('RGB', (4, 4)).save(root / 'closed.png')

            def screenshot(env, directory, output, screen):
                Image.new('RGB', (4, 4)).save(output)

            spec = {'reference': 'closed', 'rect': [0, 0, 4, 4], 'changed': False}
            with patch.object(GPU, 'capture', side_effect=screenshot):
                self.assertTrue(GPU.expect_capture({}, root, Mock(), spec)['passed'])
                with self.assertRaisesRegex(RuntimeError, 'timed out'):
                    GPU.expect_capture({}, root, Mock(), {**spec, 'changed': True}, timeout=0)
            self.assertFalse((root / 'assert-current.png').exists())

    def test_invalid_reference_and_out_of_bounds_region_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = pathlib.Path(tmp)
            Image.new('RGB', (4, 4)).save(root / 'closed.png')
            for spec in [
                {'reference': '../closed', 'rect': [0, 0, 4, 4], 'changed': True},
                {'reference': 'closed', 'rect': [0, 0, 5, 4], 'changed': True},
                {'reference': 'closed', 'rect': [0, 0, 4, 4], 'changed': 1},
            ]:
                with self.subTest(spec=spec), self.assertRaises(ValueError):
                    GPU.expect_capture({}, root, Mock(), spec)
