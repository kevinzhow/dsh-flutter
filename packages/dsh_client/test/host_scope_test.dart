import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:test/test.dart';

void main() {
  group('classifyHost', () {
    test('loopback', () {
      for (final h in [
        '127.0.0.1',
        '127.9.9.9',
        '::1',
        'localhost',
        'a.localhost',
      ]) {
        expect(classifyHost(h), HostScope.loopback, reason: h);
      }
    });

    test('private IPv4 ranges, link local and Tailscale space', () {
      for (final h in [
        '10.0.0.1',
        '172.16.0.1',
        '172.31.255.254',
        '192.168.1.20',
        '169.254.10.1',
        '100.64.0.1',
        '100.127.255.254',
      ]) {
        expect(classifyHost(h), HostScope.privateNetwork, reason: h);
      }
    });

    test('public IPv4 including the edges of the private ranges', () {
      for (final h in [
        '203.0.113.7',
        '198.51.100.1',
        '8.8.8.8',
        '172.15.0.1',
        '172.32.0.1',
        '100.63.255.255',
        '100.128.0.1',
        '192.169.0.1',
      ]) {
        expect(classifyHost(h), HostScope.public, reason: h);
      }
    });

    test('IPv6: unique local and link local are private, global is public', () {
      expect(classifyHost('fd12:3456::1'), HostScope.privateNetwork);
      expect(classifyHost('fe80::1'), HostScope.privateNetwork);
      expect(classifyHost('2001:db8::1'), HostScope.public);
    });

    test('an IPv4-mapped IPv6 address takes the scope of the IPv4 address', () {
      expect(classifyHost('::ffff:192.168.1.5'), HostScope.privateNetwork);
      expect(classifyHost('::ffff:203.0.113.5'), HostScope.public);
      expect(classifyHost('::ffff:127.0.0.1'), HostScope.loopback);
    });

    test('names: local-network spellings are private, others need DNS', () {
      expect(classifyHost('mybox'), HostScope.privateNetwork);
      expect(classifyHost('printer.local'), HostScope.privateNetwork);
      expect(classifyHost('nas.lan'), HostScope.privateNetwork);
      expect(classifyHost('example.com'), HostScope.name);
      expect(classifyHost('host.example.ts.net'), HostScope.name);
    });
  });

  group('classifyAddresses', () {
    InternetAddress a(String s) => InternetAddress(s);

    test('private only when every address is private or loopback', () {
      expect(
        classifyAddresses([a('192.168.1.2'), a('127.0.0.1')]),
        HostScope.privateNetwork,
      );
      expect(classifyAddresses([a('127.0.0.1')]), HostScope.loopback);
      expect(
        classifyAddresses([a('192.168.1.2'), a('203.0.113.9')]),
        HostScope.public,
      );
    });

    test('no addresses is not private', () {
      expect(classifyAddresses(const []), HostScope.public);
    });
  });
}
