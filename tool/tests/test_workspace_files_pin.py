"""The hand-written `workspaceFiles` client (packages/dsh_client/lib/src/workspace_files.dart) and the upload client
(file_upload.dart) have no generator behind them (tool/codegen only extracts the `session` namespace), so this test pins
their method names, wire-argument names and route against the pinned dsh checkout. Skipped without the checkout."""
import os
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
DSH = pathlib.Path(os.environ.get('DSH_SRC', str(ROOT / '.local' / 'dsh-src')))
CLIENT = (ROOT / 'packages/dsh_client/lib/src/workspace_files.dart').read_text()
UPLOAD = (ROOT / 'packages/dsh_client/lib/src/file_upload.dart').read_text()


class Pin(unittest.TestCase):
    def has(self, haystack, needle):
        # Never put the haystack in the failure message (these are whole source files).
        self.assertTrue(needle in haystack, 'missing %r' % needle)


@unittest.skipUnless((DSH / 'package.json').exists(), 'pinned dsh checkout not found')
class WorkspaceFilesPin(Pin):
    def setUp(self):
        self.index = (DSH / 'packages/api/workspace-files/src/index.ts').read_text()
        self.types = (DSH / 'packages/api/workspace-files/src/types.ts').read_text()

    def test_methods_and_lookup_parameter(self):
        methods = set(re.findall(r'@Remote(?:\([^)]*\))?\s+(?:async\s+)?(\w+)\(', self.index))
        self.assertEqual(methods, {'read', 'readBytes', 'stat', 'list', 'changes'})
        for name in methods:
            self.has(CLIENT, "'%s'" % name if name != 'changes' else "/changes'")
        # The Session identity is a Typert lookup parameter: its wire name is "<parameter>Id".
        self.has(self.index, 'workspaceFileScope: WorkspaceFileScope')
        self.has(CLIENT, "'workspaceFileScopeId'")

    def test_wire_argument_names(self):
        read_bytes = re.search(r'async readBytes\((.*?)\): Promise', self.index, re.S).group(1)
        self.has(read_bytes, 'options: WorkspaceByteReadOptions')
        self.has(CLIENT, "'options'")
        read = re.search(r'async read\((.*?)\): Promise', self.index, re.S).group(1)
        self.has(read, 'range: WorkspaceFileRange')
        self.has(CLIENT, "'range'")

    def test_result_fields(self):
        for field in ('absolutePath', 'version', 'bytes', 'offset', 'text', 'lines', 'eof', 'data', 'entries',
                      'truncated', 'baseFile', 'range', 'length', 'absent'):
            self.has(self.types, field)
            self.has(CLIENT, field)


@unittest.skipUnless((DSH / 'package.json').exists(), 'pinned dsh checkout not found')
class UploadRoutePin(Pin):
    def test_upload_route(self):
        proto = (DSH / 'packages/client/file-upload/src/protocol.ts').read_text()
        self.has(proto, "'/api/session/uploadFileBinary'")
        self.has(UPLOAD, '/api/session/uploadFileBinary')
        route = (DSH / 'packages/client/file-upload/src/http-route.ts').read_text()
        for needle in ("'sessionId'", "'name'", 'application/octet-stream'):
            self.has(route, needle)
        self.has(UPLOAD, "'sessionId'")
        self.has(UPLOAD, 'application/octet-stream')


if __name__ == '__main__':
    unittest.main()
