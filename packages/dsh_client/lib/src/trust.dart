import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;

import 'remote_caller.dart';

/// `host:port` of an origin: the key certificate pins are stored under. An
/// https origin without a port means 443.
String authorityOf(Uri origin) {
  final port = origin.hasPort
      ? origin.port
      : (origin.scheme == 'https' ? 443 : 80);
  final host = origin.host.toLowerCase();
  return host.contains(':') ? '[$host]:$port' : '$host:$port';
}

/// SHA-256 of a DER certificate as `AB:CD:...` uppercase hex pairs: the form
/// `openssl x509 -noout -fingerprint -sha256` prints, so a person can compare
/// it with what the host's owner sees.
String certificateFingerprint(List<int> der) {
  final digest = crypto.sha256.convert(der).bytes;
  return digest
      .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
      .join(':');
}

/// What a person needs to judge a certificate: its fingerprint, who it says it
/// is, and until when it is valid.
class CertificateInfo {
  const CertificateInfo({
    required this.sha256,
    required this.subject,
    required this.issuer,
    required this.notBefore,
    required this.notAfter,
  });

  factory CertificateInfo.fromX509(X509Certificate certificate) =>
      CertificateInfo(
        sha256: certificateFingerprint(certificate.der),
        subject: certificate.subject,
        issuer: certificate.issuer,
        notBefore: certificate.startValidity,
        notAfter: certificate.endValidity,
      );

  /// Fingerprint, see [certificateFingerprint].
  final String sha256;
  final String subject;
  final String issuer;
  final DateTime notBefore;
  final DateTime notAfter;

  /// Subject and issuer are the same name: the certificate vouches for itself.
  bool get selfSigned => subject == issuer;

  bool expiredAt(DateTime now) => now.isAfter(notAfter);
  bool notYetValidAt(DateTime now) => now.isBefore(notBefore);
}

/// Certificate fingerprints the user confirmed, per `host:port`.
abstract interface class PinStore {
  /// The pinned fingerprint of [authority], or null.
  String? pinFor(String authority);

  Future<void> pin(String authority, String fingerprint);
  Future<void> forget(String authority);
}

/// Keeps pins for the life of the process (tests, platforms without storage).
class MemoryPinStore implements PinStore {
  MemoryPinStore([Map<String, String>? initial]) : _pins = {...?initial};
  final Map<String, String> _pins;

  @override
  String? pinFor(String authority) => _pins[authority];
  @override
  Future<void> pin(String authority, String fingerprint) async =>
      _pins[authority] = fingerprint;
  @override
  Future<void> forget(String authority) async => _pins.remove(authority);
}

/// A TLS handshake the trust policy refused.
class CertificateRefusal {
  const CertificateRefusal({
    required this.authority,
    required this.presented,
    this.pinned,
  });

  final String authority;

  /// The certificate the host showed.
  final CertificateInfo presented;

  /// The fingerprint the user had confirmed for this host, or null when none
  /// was (the host is simply not trusted yet).
  final String? pinned;

  /// The host showed a different certificate than the one confirmed before.
  bool get changed => pinned != null;
}

/// The handshake failed because of [refusal] (the trust policy, not the
/// network).
class CertificateRefused extends RemoteException {
  CertificateRefused(this.refusal)
    : super(
        refusal.changed
            ? 'tls/certificate-changed'
            : 'tls/certificate-untrusted',
        refusal.changed
            ? 'the host presented a different certificate than the one trusted before'
            : 'the host presented a certificate nobody has vouched for',
      );

  final CertificateRefusal refusal;
}

/// How a host's certificate stands before any request (or token) is sent.
sealed class CertificateProbe {
  const CertificateProbe();
}

/// Plain http: nothing to check (the caller decides whether that is allowed).
final class ProbeNoTls extends CertificateProbe {
  const ProbeNoTls();
}

/// A certificate the system trusts (a CA signed it and the name matches).
final class ProbeSystemTrusted extends CertificateProbe {
  const ProbeSystemTrusted();
}

/// The certificate matches the pin the user confirmed earlier.
final class ProbePinned extends CertificateProbe {
  const ProbePinned(this.certificate);
  final CertificateInfo certificate;
}

/// Nobody vouched for this certificate yet; it is a candidate for a pin.
final class ProbeUntrusted extends CertificateProbe {
  const ProbeUntrusted(this.certificate);
  final CertificateInfo certificate;
}

/// The host shows a different certificate than the pinned one.
final class ProbeChanged extends CertificateProbe {
  const ProbeChanged(this.certificate, this.pinned);
  final CertificateInfo certificate;
  final String pinned;
}

/// No TLS handshake happened (refused, timed out, not TLS).
final class ProbeUnreachable extends CertificateProbe {
  const ProbeUnreachable(this.error);
  final Object error;
}

/// Certificate trust for dsh hosts: the system's roots, plus certificates the
/// user explicitly confirmed (pinned per `host:port` by SHA-256 of the leaf).
///
/// There is no way to accept every certificate. A host with a pin is held to
/// it strictly: the system roots no longer apply to that host, only the exact
/// certificate the user confirmed does, so a swapped certificate (even one a
/// CA signed) is refused until the user forgets the pin and confirms again.
/// A host without a pin must present a certificate the system trusts.
class HostTrust {
  HostTrust({PinStore? pins}) : pins = pins ?? MemoryPinStore();

  final PinStore pins;
  final Map<String, HttpClient> _clients = {};
  final Map<String, CertificateRefusal> _refusals = {};

  /// The fingerprint the user confirmed for [origin], if any.
  String? pinnedFingerprint(Uri origin) => pins.pinFor(authorityOf(origin));

  /// Trust [certificate] for [origin] from now on. Call only after the person
  /// compared the fingerprint.
  Future<void> pin(Uri origin, CertificateInfo certificate) async {
    final key = authorityOf(origin);
    await pins.pin(key, certificate.sha256);
    _refusals.remove(key);
    _evict(key);
  }

  /// Drop the pin of [origin]; the host must then present a system-trusted
  /// certificate or be confirmed again.
  Future<void> forget(Uri origin) async {
    final key = authorityOf(origin);
    await pins.forget(key);
    _refusals.remove(key);
    _evict(key);
  }

  /// The last handshake refusal recorded for [origin] by a client of this
  /// trust, if any.
  CertificateRefusal? refusalFor(Uri origin) => _refusals[authorityOf(origin)];

  void clearRefusal(Uri origin) => _refusals.remove(authorityOf(origin));

  /// Turn a transport [error] into the refusal behind it, when the trust
  /// policy was why the handshake failed.
  CertificateRefusal? refusalBehind(Uri origin, Object error) {
    if (error is CertificateRefused) return error.refusal;
    if (error is TlsException) return refusalFor(origin);
    return null;
  }

  /// An [HttpClient] for requests to [origin] that applies this trust policy.
  /// Clients are shared per host; [HostTrust] owns them (see [dispose]).
  HttpClient clientFor(Uri origin) {
    if (origin.scheme != 'https') return _plain;
    final key = authorityOf(origin);
    final pinned = pins.pinFor(key);
    return _clients.putIfAbsent('$key|${pinned ?? ''}', () {
      final context = pinned == null
          ? SecurityContext()
          : SecurityContext(withTrustedRoots: false);
      return HttpClient(context: context)
        ..badCertificateCallback = (certificate, host, port) {
          final info = CertificateInfo.fromX509(certificate);
          final authority = authorityOf(
            Uri(scheme: 'https', host: host, port: port),
          );
          if (pinned != null && info.sha256 == pinned) return true;
          _refusals[authority] = CertificateRefusal(
            authority: authority,
            presented: info,
            pinned: pinned,
          );
          return false;
        };
    });
  }

  late final HttpClient _plain = HttpClient();

  void _evict(String authority) {
    for (final key in _clients.keys.toList()) {
      if (key.startsWith('$authority|')) _clients.remove(key)?.close();
    }
  }

  /// Look at the certificate [origin] shows, without sending anything (no
  /// request, no token): a TLS handshake that is closed right after.
  Future<CertificateProbe> probe(
    Uri origin, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (origin.scheme != 'https') return const ProbeNoTls();
    final key = authorityOf(origin);
    final pinned = pins.pinFor(key);
    final seen = <X509Certificate>[];
    var verified = true;
    SecureSocket socket;
    try {
      socket = await SecureSocket.connect(
        origin.host,
        origin.hasPort ? origin.port : 443,
        context: pinned == null
            ? SecurityContext()
            : SecurityContext(withTrustedRoots: false),
        onBadCertificate: (certificate) {
          verified = false;
          seen.add(certificate);
          return true;
        },
        timeout: timeout,
      );
    } on Object catch (e) {
      return ProbeUnreachable(e);
    }
    final leaf = seen.isNotEmpty ? seen.first : socket.peerCertificate;
    socket.destroy();
    if (leaf == null) return const ProbeUnreachable('no certificate');
    final info = CertificateInfo.fromX509(leaf);
    if (pinned != null) {
      return info.sha256 == pinned
          ? ProbePinned(info)
          : ProbeChanged(info, pinned);
    }
    return verified ? const ProbeSystemTrusted() : ProbeUntrusted(info);
  }

  Future<void> dispose() async {
    for (final client in _clients.values) {
      client.close(force: true);
    }
    _clients.clear();
    _plain.close(force: true);
  }
}
