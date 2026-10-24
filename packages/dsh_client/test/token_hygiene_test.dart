import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

void main() {
  const token = 'SECRET-launch-token_0123456789abcdefghijklmnopq';

  test('a pairing failure never carries the launch token in its text', () async {
    // A server that closes the socket without an answer makes dart:io throw an
    // HttpException whose text would name the request URL.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) => s.destroy());
    addTearDown(server.close);
    final pairing = Pairing();
    addTearDown(pairing.close);
    Object? caught;
    try {
      await pairing.pair(Uri.parse('http://127.0.0.1:${server.port}'), token);
    } on Object catch (e) {
      caught = e;
    }
    expect(caught, isNotNull);
    expect('$caught', isNot(contains(token)));
    expect(describeTransportError(caught), isNot(contains(token)));
    expect(describeTransportError(caught), isNotEmpty);
  });

  test('describeTransportError names the kind, never an unknown object', () {
    expect(describeTransportError(null), '');
    expect(
      describeTransportError(const SocketException('Connection refused')),
      'Connection refused',
    );
    expect(describeTransportError(Object()), 'Object');
  });
}
