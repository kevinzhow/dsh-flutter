import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

void main() {
  late HttpServer server;
  late HttpDeliverablesClient client;
  late Future<void> Function(HttpRequest) handle;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    client = HttpDeliverablesClient(
      credential: () => PairedCredential(
        origin: Uri.parse('http://127.0.0.1:${server.port}'),
        cookieName: 'synthetic-peer',
        cookieValue: 'synthetic-cookie',
        interactions: Interactions.answer,
      ),
    );
    server.listen((request) => unawaited(handle(request)));
  });
  tearDown(() async {
    client.close();
    await server.close(force: true);
  });
  Future<void> answer(HttpRequest r, Object? value, {int status = 200}) async {
    r.response.statusCode = status;
    r.response.write(jsonEncode(value));
    await r.response.close();
  }

  test('paired coordinates and explicit gestures use fixed routes without redirects', () async {
    final requests = <(String, Uri)>[];
    handle = (r) async {
      expect(
        r.headers.value(HttpHeaders.cookieHeader),
        'synthetic-peer=synthetic-cookie',
      );
      requests.add((r.method, r.uri));
      switch (r.uri.path) {
        case '/api/changes.summary':
          await answer(r, {
            'turn': 1,
            'files': [
              {
                'path': '/synthetic/a.md',
                'display': 'a.md',
                'added': 2,
                'deleted': 1,
              },
            ],
            'total': 1,
            'added': 2,
            'deleted': 1,
          });
        case '/api/changes.diff':
          await answer(r, {
            'kind': 'binary',
            'path': '/synthetic/a.md',
            'display': 'a.md',
          });
        case '/api/present.host':
          await answer(r, {
            'name': 'Remote synthetic desktop',
            'available': true,
            'fileManager': 'finder',
          });
        default:
          await answer(r, null);
      }
    };
    expect(
      (await client.summary('session /?&', 7)).files.single.path,
      '/synthetic/a.md',
    );
    expect((await client.diff('session /?&', 7, 3)).kind, 'binary');
    expect((await client.host()).fileManager, 'finder');
    await client.open(
      const DeliveryFile('session /?&', 8, 2),
      action: NativeFileAction.reveal,
    );
    await client.open(
      const DeliveryFile('session /?&', 7, 3, kind: FileDeliveryKind.changed),
      application: 'synthetic app/?',
    );
    expect(requests[0].$2.queryParameters, {
      'sessionId': 'session /?&',
      'seq': '7',
    });
    expect(requests[3].$1, 'POST');
    expect(requests[3].$2.queryParameters, {
      'sessionId': 'session /?&',
      'seq': '8',
      'index': '2',
      'action': 'reveal',
    });
    expect(requests[4].$2.path, '/api/changes.open');
    expect(requests[4].$2.queryParameters['application'], 'synthetic app/?');
    var redirects = 0;
    handle = (r) async {
      if (r.uri.path == '/redirected') redirects++;
      r.response
        ..statusCode = 302
        ..headers.set(HttpHeaders.locationHeader, '/redirected');
      await r.response.close();
    };
    await expectLater(
      client.host(),
      throwsA(
        isA<DeliverablesHttpFailure>().having((e) => e.status, 'status', 302),
      ),
    );
    expect(redirects, 0);
  });
  test('association reads use exact authorized event coordinates', () async {
    handle = (r) async {
      expect(r.method, 'GET');
      expect(r.uri.path, '/api/present.open');
      expect(r.uri.queryParameters, {
        'sessionId': 's',
        'seq': '8',
        'index': '3',
      });
      await answer(r, [
        {
          'id': 'synthetic.app',
          'name': 'Synthetic editor',
          'default': true,
          'icon': null,
        },
      ]);
    };
    expect(
      (await client.applications(const DeliveryFile('s', 8, 3))).single.id,
      'synthetic.app',
    );
    handle = (r) => answer(r, [
      {
        'id': 'app',
        'name': 'Editor',
        'default': true,
        'icon': 'https://synthetic.invalid/icon',
      },
    ]);
    await expectLater(
      client.applications(const DeliveryFile('s', 8, 3)),
      throwsFormatException,
    );
  });
  test(
    'cancellation settles a waiting response and a partial response body',
    () async {
      for (final partial in [false, true]) {
        final received = Completer<void>();
        handle = (r) async {
          if (partial) {
            r.response.write('{');
            await r.response.flush();
          }
          received.complete();
        };
        final cancel = DeliverablesCancel();
        final result = client.host(cancel: cancel);
        final check = expectLater(
          result,
          throwsA(isA<DeliverablesCancelled>()),
        );
        await received.future;
        cancel.cancel();
        await check.timeout(const Duration(seconds: 2));
      }
    },
  );
  test(
    'malformed records and native refusal retain their distinct failure types',
    () async {
      handle = (r) => answer(r, {
        'turn': 0,
        'files': [],
        'total': 0,
        'added': 0,
        'deleted': 0,
      });
      await expectLater(client.summary('s', 1), throwsFormatException);
      handle = (r) => answer(r, null, status: 422);
      await expectLater(
        client.open(const DeliveryFile('s', 2, 0)),
        throwsA(
          isA<DeliverablesHttpFailure>().having((e) => e.status, 'status', 422),
        ),
      );
      expect(
        () => ChangedFile.fromJson({
          'path': 'a',
          'display': 'a',
          'added': 0,
          'deleted': 0,
          'binary': false,
        }),
        throwsFormatException,
      );
      expect(
        () => ChangesDiff.fromJson({
          'kind': 'text',
          'path': 'a',
          'display': 'a',
          'before': true,
          'after': true,
          'coarse': false,
          'hunks': [
            {
              'oldStart': 0,
              'oldLines': 0,
              'newStart': 0,
              'newLines': 1,
              'lines': ['invalid'],
            },
          ],
        }),
        throwsFormatException,
      );
    },
  );
}
