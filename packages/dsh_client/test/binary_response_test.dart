import 'dart:convert';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

import 'support/fake_host.dart';

void main() {
  group('decodeBinaryResponse', () {
    Uint8List body(String boundary, List<(String, List<int>)> parts) {
      final out = BytesBuilder();
      for (final (name, data) in parts) {
        out.add(ascii.encode('--$boundary\r\n'));
        out.add(
          ascii.encode('Content-Disposition: form-data; name="$name"\r\n\r\n'),
        );
        out.add(data);
        out.add(ascii.encode('\r\n'));
      }
      out.add(ascii.encode('--$boundary--\r\n'));
      return out.takeBytes();
    }

    Uint8List envelopeBody(
      Object? value,
      List<Map<String, Object?>> attachments,
      List<(String, List<int>)> parts, {
      String boundary = 'XX',
    }) => body(boundary, [
      for (final p in parts) p,
      (
        'metadata',
        utf8.encode(
          jsonEncode({
            'type': 'server-response',
            'rpcId': 'r',
            'result': {'ok': true, 'value': value},
            'attachments': attachments,
          }),
        ),
      ),
    ]);

    test('restores nested and array byte fields', () {
      final png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
      final decoded = decodeBinaryResponse(
        'multipart/form-data; boundary=XX',
        envelopeBody(
          {
            'data': null,
            'chunks': [null, 'x', null],
            'deep': {'a': null},
          },
          [
            {
              'path': ['data'],
              'codec': 'bytes',
              'part': 'bytes-0',
            },
            {
              'path': ['chunks', 0],
              'codec': 'bytes',
              'part': 'bytes-1',
            },
            {
              'path': ['chunks', 2],
              'codec': 'bytes',
              'part': 'bytes-2',
            },
            {
              'path': ['deep', 'a'],
              'codec': 'bytes',
              'part': 'bytes-3',
            },
          ],
          [
            ('bytes-0', png),
            ('bytes-1', [1, 2]),
            ('bytes-2', const <int>[]),
            ('bytes-3', [0x0d, 0x0a, 0x2d, 0x2d, 0x59, 0x59]),
          ],
        ),
      );
      final value =
          (decoded['result']! as Map)['value']! as Map<String, Object?>;
      expect(value['data'], png);
      expect((value['chunks']! as List)[0], [1, 2]);
      expect((value['chunks']! as List)[1], 'x');
      expect((value['chunks']! as List)[2], isEmpty);
      // A payload with CRLF and dashes that is not the delimiter is not split.
      expect((value['deep']! as Map)['a'], [
        0x0d,
        0x0a,
        0x2d,
        0x2d,
        0x59,
        0x59,
      ]);
    });

    test('a quoted boundary and a missing boundary', () {
      expect(multipartBoundary('multipart/form-data; boundary="a b"'), 'a b');
      expect(multipartBoundary('multipart/form-data'), isNull);
    });

    for (final (label, bad) in <(String, Uint8List Function())>[
      (
        'missing attachment part',
        () => envelopeBody(
          {'data': null},
          [
            {
              'path': ['data'],
              'codec': 'bytes',
              'part': 'bytes-0',
            },
          ],
          [],
        ),
      ),
      (
        'unreferenced part',
        () => envelopeBody(
          {'data': null},
          [
            {
              'path': ['data'],
              'codec': 'bytes',
              'part': 'bytes-0',
            },
          ],
          [
            ('bytes-0', [1]),
            ('stray', [2]),
          ],
        ),
      ),
      (
        'path outside the value',
        () => envelopeBody(
          {'data': null},
          [
            {
              'path': ['nope'],
              'codec': 'bytes',
              'part': 'bytes-0',
            },
          ],
          [
            ('bytes-0', [1]),
          ],
        ),
      ),
      (
        'placeholder that is not null',
        () => envelopeBody(
          {'data': 'text'},
          [
            {
              'path': ['data'],
              'codec': 'bytes',
              'part': 'bytes-0',
            },
          ],
          [
            ('bytes-0', [1]),
          ],
        ),
      ),
      (
        'unknown codec',
        () => envelopeBody(
          {'data': null},
          [
            {
              'path': ['data'],
              'codec': 'base64',
              'part': 'bytes-0',
            },
          ],
          [
            ('bytes-0', [1]),
          ],
        ),
      ),
      (
        'truncated body',
        () => Uint8List.fromList(
          ascii.encode(
            '--XX\r\nContent-Disposition: form-data; name="a"\r\n\r\nxx',
          ),
        ),
      ),
    ]) {
      test('rejects $label', () {
        expect(
          () => decodeBinaryResponse('multipart/form-data; boundary=XX', bad()),
          throwsA(
            isA<RemoteException>().having(
              (e) => e.code,
              'code',
              'transport/bad-envelope',
            ),
          ),
        );
      });
    }
  });

  test(
    'a unary call returns Uint8List values from a multipart answer',
    () async {
      final host = await FakeHost.start();
      final conn = DshConnection(origin: host.origin);
      addTearDown(() async {
        await conn.stop();
        await host.stop();
      });
      final bytes = List<int>.generate(70000, (i) => i % 251);
      host.unary['workspaceFiles/readBytes'] = (args) => FakeBinaryResult(
        {'absolutePath': '/w/a.bin', 'offset': 0, 'data': null, 'eof': true},
        [
          (path: ['data'], bytes: bytes),
        ],
      );
      conn.start(host.token);
      await conn.untilConnected();
      final value = await conn.caller.call('workspaceFiles', 'readBytes', {
        'path': 'a.bin',
      }) as Map<String, Object?>;
      expect(value['absolutePath'], '/w/a.bin');
      expect(value['data'], isA<Uint8List>());
      expect(value['data'], bytes);
    },
  );
}
