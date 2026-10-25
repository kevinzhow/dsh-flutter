"""Explicit native component fixtures do not need host credentials."""
import importlib.util
import os
import pathlib
import tempfile
import unittest
from unittest.mock import patch

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
