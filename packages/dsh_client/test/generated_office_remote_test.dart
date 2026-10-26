import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_office_to_pdf.dart';
import 'package:test/test.dart';

void main() {
  test('generated Office result decodes native multipart bytes without a JSON array surrogate', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpRemoteCaller(
      PairedCredential(
        origin: Uri.parse('http://127.0.0.1:${server.port}'),
        cookieName: 'synthetic',
        cookieValue: 'synthetic',
        interactions: Interactions.none,
      ),
    );
    addTearDown(() async {
      client.close();
      await server.close(force: true);
    });
    final serving = server.first.then((request) async {
      final input = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, Object?>;
      expect((input['payload'] as Map)['args'], {
        'workspaceFileScopeId': 'original',
        'path': 'a.docx',
        'priority': 'foreground',
      });
      final metadata = jsonEncode({
        'type': 'server-response',
        'rpcId': input['rpcId'],
        'result': {
          'ok': true,
          'value': {
            'absolutePath': '/synthetic/a.docx',
            'version': 'v1',
            'offset': 0,
            'data': null,
            'eof': true,
            'generation': 'g1',
            'missingFonts': ['Synthetic Font'],
          },
        },
        'attachments': [
          {
            'path': ['data'],
            'codec': 'bytes',
            'part': 'pdf',
          },
        ],
      });
      request.response.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=OFFICE',
      );
      for (final part in [
        ('metadata', utf8.encode(metadata)),
        ('pdf', <int>[37, 80, 68, 70]),
      ]) {
        request.response.add(
          ascii.encode(
            '--OFFICE\r\nContent-Disposition: form-data; name="${part.$1}"\r\n\r\n',
          ),
        );
        request.response.add(part.$2);
        request.response.add([13, 10]);
      }
      request.response.add(ascii.encode('--OFFICE--\r\n'));
      await request.response.close();
    });
    final result = await OfficeToPdfRemote(client)
        .render('original', 'a.docx', OfficeToPdfPriority.foreground);
    expect(result.data, isA<Uint8List>());
    expect(result.data, [37, 80, 68, 70]);
    expect(result.missingFonts, ['Synthetic Font']);
    await serving;
  });
  test('cancelling a blocked HTTP response aborts the caller and leaves ordinary calls usable', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final arrived = Completer<void>();
    final client = HttpRemoteCaller(
      PairedCredential(
        origin: Uri.parse('http://127.0.0.1:${server.port}'),
        cookieName: 'synthetic',
        cookieValue: 'synthetic',
        interactions: Interactions.none,
      ),
    );
    final requests = <HttpRequest>[];
    final subscription = server.listen((request) async {
      requests.add(request);
      final input = jsonDecode(
        await utf8.decoder.bind(request).join(),
      ) as Map<String, Object?>;
      if (requests.length == 1) {
        arrived.complete();
        return;
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'type': 'server-response',
          'rpcId': input['rpcId'],
          'result': {'ok': true, 'value': 'generation'},
        }),
      );
      await request.response.close();
    });
    addTearDown(() async {
      client.close();
      await subscription.cancel();
      await server.close(force: true);
    });
    final cancellation = RemoteCancellation();
    final future = OfficeToPdfRemote(ScopedRemoteCaller(client, cancellation))
        .generation();
    final failure = expectLater(
      future,
      throwsA(
        isA<RemoteException>().having(
          (e) => e.code,
          'code',
          'transport/cancelled',
        ),
      ),
    );
    await arrived.future.timeout(const Duration(seconds: 5));
    cancellation.cancel();
    await failure.timeout(const Duration(seconds: 5));
    expect(await OfficeToPdfRemote(client).generation(), 'generation');
  });
}
