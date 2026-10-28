"""Dispatch and transport controls; fake outputs are unit fixtures, not parity."""
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from parity_lib import env, manifest, published_toasts as provider, react


def entry(kind, key):
    return {'key': key, 'case': {'kind': kind, 'id': key}, 'variant': {'id': 'default'}}


class PublishedToastRoutingTest(unittest.TestCase):
    def test_existing_only_call_reaches_unchanged_provider_with_identical_arguments(self):
        entries = [entry('plugins-preview.manager', 'old-manager')]
        args = (entries, Path('out'), Path('results'), [Path('host')], 'fixtures', False, Path('cache'), 'native')
        result = {'old-manager': 'cache'}
        with mock.patch.object(react, '_capture_without_toasts', return_value=result) as generic, \
                mock.patch.object(provider, 'capture') as published:
            self.assertIs(react.capture(*args), result)
            generic.assert_called_once_with(*args)
            published.assert_not_called()

    def test_mixed_selection_splits_only_new_kind_and_keeps_result_order_and_modes(self):
        old, card = entry('plugins-preview.manager', 'existing'), entry(provider.KIND, 'published')
        entries = [card, old]
        args = (Path('out'), Path('results'), [Path('host')], 'fixture-hash', True, Path('cache'), 'emulated')
        with mock.patch.object(react, '_capture_without_toasts', return_value={'existing': 'cache'}) as generic, \
                mock.patch.object(provider, 'capture', return_value={'published': 'captured'}) as published:
            result = react.capture(entries, *args)
            self.assertEqual(list(result), ['published', 'existing'])
            generic.assert_called_once_with([old], *args)
            published.assert_called_once_with([card], args[0], args[1], 'emulated')
            self.assertEqual(result, {'published': 'captured', 'existing': 'cache'})

    def test_card_only_call_does_not_enter_generic_host_or_cache(self):
        rows = [entry(provider.KIND, 'card')]
        with mock.patch.object(react, '_capture_without_toasts') as generic, \
                mock.patch.object(provider, 'capture', return_value={'card': 'captured'}):
            self.assertEqual(react.capture(rows, Path('o'), Path('r'), [], '', False, Path('c')), {'card': 'captured'})
            generic.assert_not_called()

    def test_selected_variant_keys_follow_the_existing_tilde_contract(self):
        row = entry(provider.KIND, 'components.toast.selected.light')
        row['variant'] = {'id': 'hover', 'props': {'scenarioId': 'default'}}
        row['key'] = manifest.capture_key(row['case']['id'], 'hover')
        plan = provider.selected_manifest([row])
        self.assertEqual(plan['cases'][0]['variants'], [row['variant']])
        self.assertNotIn('sourceProvider', plan['cases'][0])
        row['key'] = row['case']['id'] + '__hover'
        with self.assertRaises(ValueError):
            provider.selected_manifest([row])


class PublishedToastTransportTest(unittest.TestCase):
    def run_provider(self, mode='native', corrupt=False):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        output, results = root / 'out', root / 'results'
        output.mkdir()
        (results / 'react').mkdir(parents=True)
        original = results / 'react/existing.png'
        original.write_bytes(b'unchanged old provider result')
        cache = root / 'cache'
        cache.mkdir()
        (cache / 'sentinel').write_text('unchanged cache')
        lock = root / 'tool/design-system/sources.lock.json'
        lock.parent.mkdir(parents=True)
        lock.write_text(json.dumps({'referenceCommit': 'pinned-source'}))
        rows = [entry(provider.KIND, 'components.toast.test.light')]
        calls = []

        def fake_source(command, cwd, log, extra_env):
            calls.append(command)
            source = Path(command[command.index('--out') + 1])
            destination = source / 'visual-testing-results/react'
            destination.mkdir(parents=True)
            key = rows[0]['key']
            image = destination / (key + '.png')
            Image.new('RGBA', (2, 2), (1, 2, 3, 255)).save(image)
            (destination / (key + '.metadata.json')).write_text(json.dumps({
                'provider': 'react', 'captureKey': key, 'caseId': rows[0]['case']['id'], 'variantId': 'default',
                'react': {'dshCommit': 'pinned-source'}, 'pixelModel': mode}))
            (source / 'source-trace.json').write_text(json.dumps({'passed': True, 'captures': 1, 'traces': [{
                'key': key, 'sha256': hashlib.sha256(image.read_bytes()).hexdigest(),
                'checks': [{'passed': not corrupt}]}]}))
            return 0

        with mock.patch.object(env, 'ROOT', root), mock.patch.object(react, 'check_dsh_checkout'), \
                mock.patch.object(react, 'setup'), mock.patch.object(provider, 'prepare_archive', return_value=root / 'archives'), \
                mock.patch.object(react, 'run_node', side_effect=fake_source):
            if corrupt:
                with self.assertRaises(ValueError):
                    provider.capture(rows, output, results, mode)
                self.assertFalse((results / 'react' / (rows[0]['key'] + '.png')).exists())
            else:
                self.assertEqual(provider.capture(rows, output, results, mode), {rows[0]['key']: 'captured'})
                self.assertTrue((results / 'react' / (rows[0]['key'] + '.png')).is_file())
        self.assertEqual(original.read_bytes(), b'unchanged old provider result')
        self.assertEqual((cache / 'sentinel').read_text(), 'unchanged cache')
        self.assertEqual(calls[0][calls[0].index('--reference') + 1], mode)
        self.assertEqual(len(list(output.glob('published-toasts-*'))), 1)
        return root

    def test_source_transport_preserves_existing_results_and_cache(self):
        self.run_provider()

    def test_reference_mode_is_forwarded_without_native_substitution(self):
        self.run_provider(mode='emulated')

    def test_failed_source_checks_never_copy_partial_new_results_or_fallback(self):
        self.run_provider(corrupt=True)


if __name__ == '__main__':
    unittest.main()
