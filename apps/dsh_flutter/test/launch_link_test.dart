import 'package:dsh_flutter/src/launch_link.dart';
import 'package:flutter_test/flutter_test.dart';

// 43 base64url characters, the shape of a real launch token (made up).
const token = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNO_-';

void main() {
  group('LaunchLink.parse', () {
    test('the link dsh web prints', () {
      final l = LaunchLink.parse('http://192.0.2.10:8686/?token=$token');
      expect(l.origin, Uri.parse('http://192.0.2.10:8686'));
      expect(l.token, token);
    });

    test('https, IPv6 and a path of just a slash', () {
      expect(
        LaunchLink.parse('https://dsh.example:8443/?token=$token').origin,
        Uri.parse('https://dsh.example:8443'),
      );
      expect(
        LaunchLink.parse('http://[2001:db8::1]:8686/?token=$token').origin.host,
        '2001:db8::1',
      );
    });

    test('a bare host address takes the token from the second field', () {
      final l = LaunchLink.parse('192.0.2.10:8686', token: ' $token ');
      expect(l.origin, Uri.parse('http://192.0.2.10:8686'));
      expect(l.token, token);
    });

    test('the shape is checked before anything is sent', () {
      for (final bad in [
        '',
        '   ',
        'not a link at all',
        'ftp://192.0.2.10/?token=$token',
        'http://user:pass@192.0.2.10:8686/?token=$token',
        'http://192.0.2.10:8686/?token=$token#frag',
        'http://192.0.2.10:8686/some/path?token=$token',
        'http://192.0.2.10:8686/?token=$token&token=$token',
        'http://192.0.2.10:8686/?token=has space',
        'http://192.0.2.10:8686/?token=a%2Fb',
        'http://192.0.2.10:8686/?token=',
        'http://192.0.2.10:8686/',
        'http://192.0.2.10:99999/?token=$token',
        'http:///?token=$token',
      ]) {
        expect(() => LaunchLink.parse(bad), throwsFormatException, reason: bad);
      }
    });

    test('a failure never echoes the text (it holds the token)', () {
      try {
        LaunchLink.parse('ftp://192.0.2.10/?token=$token');
        fail('expected a FormatException');
      } on FormatException catch (e) {
        expect('$e', isNot(contains(token)));
      }
    });
  });
}
