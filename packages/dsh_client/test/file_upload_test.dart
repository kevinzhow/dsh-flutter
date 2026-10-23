import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

import 'support/fake_host.dart';

void main() {
  late FakeHost host;
  late DshConnection conn;
  late HttpFileUploadClient client;

  setUp(() async {
    host = await FakeHost.start();
    conn = DshConnection(origin: host.origin);
    client = HttpFileUploadClient(
      credential: () => conn.generation?.credential,
    );
    conn.start(host.token);
    await conn.untilConnected();
  });

  tearDown(() async {
    client.close();
    await conn.stop();
    await host.stop();
  });

  Future<void> answer(
    HttpRequest req,
    Object body, {
    int status = 200,
    String type = 'application/json; charset=utf-8',
  }) async {
    req.response
      ..statusCode = status
      ..headers.set(HttpHeaders.contentTypeHeader, type)
      ..write(body is String ? body : jsonEncode(body));
    await req.response.close();
  }

  test(
    'streams raw octet-stream bytes with the paired cookie and a receipt',
    () async {
      late Map<String, String> query;
      late String contentType;
      late String cookie;
      late int? declared;
      final received = BytesBuilder();
      host.raw['POST /api/session/uploadFileBinary'] = (req) async {
        query = req.uri.queryParameters;
        contentType = req.headers.contentType.toString();
        cookie = req.headers.value(HttpHeaders.cookieHeader) ?? '';
        declared = req.contentLength;
        await for (final c in req) {
          received.add(c);
        }
        await answer(req, {
          'ok': true,
          'value': {
            'receiptId': 'rcpt-1',
            'file': {
              'attachmentId': 'sha256:abc',
              'name': query['name'],
              'bytes': received.length,
            },
          },
        });
      };
      final chunks = [
        for (var i = 0; i < 5; i++) Uint8List(1000)..fillRange(0, 1000, i),
      ];
      final seen = <int>[];
      final receipt = await client.upload(
        sessionId: 'session-1',
        name: 'notes (1).txt',
        length: 5000,
        data: Stream.fromIterable(chunks),
        onProgress: (p) {
          seen.add(p.loaded);
          expect(p.total, 5000);
        },
      );
      expect(receipt.receiptId, 'rcpt-1');
      expect(receipt.attachmentId, 'sha256:abc');
      expect(receipt.bytes, 5000);
      expect(query, {'sessionId': 'session-1', 'name': 'notes (1).txt'});
      expect(contentType, 'application/octet-stream');
      expect(cookie, startsWith('dsh-fake='));
      expect(declared, 5000);
      expect(received.takeBytes(), [for (final c in chunks) ...c]);
      expect(seen.first, 0);
      expect(seen.last, 5000);
      expect(seen, orderedEquals([...seen]..sort()));
    },
  );

  test('omits the name query when none is given', () async {
    late Map<String, String> query;
    host.raw['POST /api/session/uploadFileBinary'] = (req) async {
      query = req.uri.queryParameters;
      await req.drain<void>();
      await answer(req, {
        'ok': true,
        'value': {
          'receiptId': 'r',
          'file': {'attachmentId': 'a', 'name': 'x', 'bytes': 0},
        },
      });
    };
    await client.upload(sessionId: 's', data: const Stream.empty());
    expect(query, {'sessionId': 's'});
  });

  test(
    'a host refusal in the 200 body becomes a RemoteException with details',
    () async {
      host.raw['POST /api/session/uploadFileBinary'] = (req) async {
        await req.drain<void>();
        await answer(req, {
          'ok': false,
          'error': {
            'code': 'session/not-found',
            'message': 'session "s" not found',
            'details': {'sessionId': 's'},
          },
        });
      };
      await expectLater(
        client.upload(sessionId: 's', data: const Stream.empty()),
        throwsA(
          isA<RemoteException>()
              .having((e) => e.code, 'code', 'session/not-found')
              .having((e) => e.details['sessionId'], 'details', 's'),
        ),
      );
    },
  );

  for (final status in [400, 401, 415, 500]) {
    test('HTTP $status is a transport failure', () async {
      host.raw['POST /api/session/uploadFileBinary'] = (req) async {
        await req.drain<void>();
        await answer(req, 'nope', status: status, type: 'text/plain');
      };
      await expectLater(
        client.upload(sessionId: 's', data: Stream.value([1, 2, 3])),
        throwsA(
          isA<UploadTransportFailure>().having(
            (e) => e.status,
            'status',
            status,
          ),
        ),
      );
    });
  }

  test('malformed receipts are refused', () async {
    host.raw['POST /api/session/uploadFileBinary'] = (req) async {
      await req.drain<void>();
      await answer(req, {
        'ok': true,
        'value': {
          'receiptId': 'r',
          'file': {'attachmentId': 'a'},
        },
      });
    };
    await expectLater(
      client.upload(sessionId: 's', data: Stream.value([1])),
      throwsA(
        isA<RemoteException>().having(
          (e) => e.code,
          'code',
          'transport/bad-envelope',
        ),
      ),
    );
  });

  test('cancel aborts an active upload and stops reading the source', () async {
    final started = Completer<void>();
    host.raw['POST /api/session/uploadFileBinary'] = (req) async {
      started.complete();
      try {
        await req.drain<void>();
      } on Object {
        // aborted by the client
      }
    };
    final source = StreamController<List<int>>();
    var cancelledSource = false;
    source.onCancel = () => cancelledSource = true;
    final token = UploadCancelToken();
    final progress = <int>[];
    final result = client.upload(
      sessionId: 's',
      data: source.stream,
      length: 1 << 20,
      cancel: token,
      onProgress: (p) => progress.add(p.loaded),
    );
    source.add(Uint8List(1024));
    await started.future;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    token.cancel();
    await expectLater(result, throwsA(isA<UploadCancelled>()));
    expect(token.isCancelled, isTrue);
    expect(cancelledSource, isTrue);
    expect(progress, isNotEmpty);
  });

  test('a token cancelled before the call never opens a request', () async {
    var hits = 0;
    host.raw['POST /api/session/uploadFileBinary'] = (req) async {
      hits++;
      await req.drain<void>();
      await answer(req, {});
    };
    final token = UploadCancelToken()..cancel();
    await expectLater(
      client.upload(sessionId: 's', data: const Stream.empty(), cancel: token),
      throwsA(isA<UploadCancelled>()),
    );
    expect(hits, 0);
  });

  test('without a live generation the upload refuses', () async {
    final offline = HttpFileUploadClient(credential: () => null);
    await expectLater(
      offline.upload(sessionId: 's', data: const Stream.empty()),
      throwsA(
        isA<RemoteException>().having(
          (e) => e.code,
          'code',
          'connection/not-connected',
        ),
      ),
    );
    offline.close();
  });
}
