import 'dart:io';

/// A throwaway self-signed certificate made with `openssl` for one test run
/// (nothing is committed): the TLS tests need a certificate no CA signed.
class TestCertificate {
  TestCertificate._(this.directory, this.context, this.fingerprint);

  final Directory directory;
  final SecurityContext context;

  /// SHA-256 as `openssl x509 -fingerprint -sha256` prints it: the independent
  /// reference the client's own fingerprint must equal.
  final String fingerprint;

  static Future<TestCertificate> create(String commonName) async {
    final dir = await Directory.systemTemp.createTemp('whalee-cert-');
    final key = '${dir.path}/key.pem';
    final cert = '${dir.path}/cert.pem';
    final made = await Process.run('openssl', [
      'req',
      '-x509',
      '-newkey',
      'ec',
      '-pkeyopt',
      'ec_paramgen_curve:prime256v1',
      '-nodes',
      '-keyout',
      key,
      '-out',
      cert,
      '-days',
      '2',
      '-subj',
      '/CN=$commonName',
      '-addext',
      'subjectAltName=IP:127.0.0.1',
    ]);
    if (made.exitCode != 0) {
      throw StateError('openssl req failed: ${made.stderr}');
    }
    final print = await Process.run('openssl', [
      'x509',
      '-in',
      cert,
      '-noout',
      '-fingerprint',
      '-sha256',
    ]);
    final fingerprint = (print.stdout as String).trim().split('=').last;
    final context = SecurityContext()
      ..useCertificateChain(cert)
      ..usePrivateKey(key);
    return TestCertificate._(dir, context, fingerprint);
  }

  Future<void> dispose() => directory.delete(recursive: true);
}
