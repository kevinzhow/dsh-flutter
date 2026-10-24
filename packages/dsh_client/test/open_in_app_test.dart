import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

import 'support/fake_host.dart';

void main() {
  late FakeHost host;
  late DshConnection conn;
  late HttpOpenInAppClient client;

  setUp(() async {
    host = await FakeHost.start();
    conn = DshConnection(origin: host.origin);
    client = HttpOpenInAppClient(credential: () => conn.generation?.credential);
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

  test('lists the installed applications with the paired cookie', () async {
    late String cookie;
    host.raw['GET /open-in-app/apps'] = (req) async {
      cookie = req.headers.value(HttpHeaders.cookieHeader) ?? '';
      await answer(req, {
        'apps': ['vscode', 'terminal', 7],
      });
    };
    expect(await client.apps(), ['vscode', 'terminal']);
    expect(cookie, isNotEmpty);
  });

  test('an unusable answer reads as no applications', () async {
    host.raw['GET /open-in-app/apps'] = (req) => answer(req, 'x', status: 500);
    expect(await client.apps(), isEmpty);
    host.raw['GET /open-in-app/apps'] = (req) => answer(req, 'not json');
    expect(await client.apps(), isEmpty);
    host.raw.remove('GET /open-in-app/apps');
    expect(await client.apps(), isEmpty);
  });

  test('open posts the application and directory as JSON', () async {
    late Object? body;
    late String type;
    host.raw['POST /open-in-app/open'] = (req) async {
      type = req.headers.contentType?.mimeType ?? '';
      body = jsonDecode(await utf8.decodeStream(req));
      await answer(req, {'ok': true});
    };
    await client.open('vscode', '/work/project');
    expect(type, 'application/json');
    expect(body, {'app': 'vscode', 'path': '/work/project'});
  });

  test('a refused open throws with the status', () async {
    host.raw['POST /open-in-app/open'] = (req) => answer(req, '', status: 400);
    await expectLater(
      client.open('vscode', '/nope'),
      throwsA(
        isA<RemoteException>().having(
          (e) => e.code,
          'code',
          'transport/http-400',
        ),
      ),
    );
  });

  test('the icon is the PNG the host serves, or null', () async {
    final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
    host.raw['GET /open-in-app/icon/vscode'] = (req) async {
      req.response
        ..statusCode = 200
        ..headers.set(HttpHeaders.contentTypeHeader, 'image/png')
        ..add(png);
      await req.response.close();
    };
    host.raw['GET /open-in-app/icon/zed'] = (req) =>
        answer(req, '', status: 404);
    expect(await client.icon('vscode'), png);
    expect(await client.icon('zed'), isNull);
  });

  test('without a live generation every call reports it', () async {
    final idle = HttpOpenInAppClient(credential: () => null);
    expect(await idle.apps(), isEmpty);
    await expectLater(idle.open('a', '/b'), throwsA(isA<RemoteException>()));
    expect(await idle.icon('a'), isNull);
    idle.close();
  });
}
