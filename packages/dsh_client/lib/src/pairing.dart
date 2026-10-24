import 'dart:io';

import 'remote_caller.dart';

/// What dsh calls the connection's participation in forwarded human
/// interactions (`/connect?interactions=`). `answer` is required to receive and
/// answer approvals and user questions; the host default is `none`.
enum Interactions { answer, none }

/// The authority-bound API cookie issued by `GET /connect`.
///
/// The cookie name is derived from the host:port authority and the value is a
/// signed payload (version 2) naming one host-side API Peer. The Peer dies when
/// its mux socket closes or the host restarts, so a credential is good for
/// exactly one connection generation; the launch token is what survives until
/// the host restarts.
class PairedCredential {
  const PairedCredential({
    required this.origin,
    required this.cookieName,
    required this.cookieValue,
    required this.interactions,
  });

  final Uri origin;
  final String cookieName;
  final String cookieValue;
  final Interactions interactions;

  /// Value for a `Cookie:` request header.
  String get cookieHeader => '$cookieName=$cookieValue';

  /// The `/api/remote.mux` WebSocket URI for this origin.
  Uri get muxUri => origin.replace(
    scheme: origin.scheme == 'https' ? 'wss' : 'ws',
    path: '/api/remote.mux',
    query: null,
  );

  @override
  String toString() => 'PairedCredential($origin, ${interactions.name})';
}

/// The launch token was refused: wrong, or from a previous host process.
class PairingRejected extends RemoteException {
  PairingRejected(int status)
    : super(
        'pairing/rejected',
        'host refused the launch token (HTTP $status); host restarted or token is wrong',
      );
}

/// Performs `GET /connect?token=...&interactions=...` (docs: connection README,
/// "Only API callers use GET /connect").
class Pairing {
  /// A client handed in stays the caller's: [close] only closes a client this
  /// created.
  Pairing({HttpClient? httpClient})
    : _http = httpClient ?? HttpClient(),
      _owns = httpClient == null;

  final HttpClient _http;
  final bool _owns;

  /// Exchange [launchToken] for an API cookie. Never follows the redirect
  /// (it points at the mux destination); reads the signed cookie instead.
  /// [client] replaces this [Pairing]'s own client for this exchange (the
  /// connection asks its `HostTrust` per attempt, because a pin may have been
  /// added or forgotten since the last one).
  Future<PairedCredential> pair(
    Uri origin,
    String launchToken, {
    Interactions interactions = Interactions.answer,
    HttpClient? client,
  }) async {
    final uri = origin.replace(
      path: '/connect',
      queryParameters: {
        'token': launchToken,
        'interactions': interactions.name,
      },
    );
    // The launch token is in the request URL, and dart:io puts the URL into
    // the text of some of its exceptions: those are reduced to their message.
    final HttpClientResponse response;
    try {
      final request = await (client ?? _http).getUrl(uri);
      request.followRedirects = false;
      response = await request.close();
      await response.drain<void>();
    } on HttpException catch (e) {
      throw RemoteException('pairing/http', e.message);
    }
    if (response.statusCode == HttpStatus.unauthorized ||
        response.statusCode == HttpStatus.forbidden) {
      throw PairingRejected(response.statusCode);
    }
    if (response.statusCode != HttpStatus.found) {
      throw RemoteException(
        'pairing/unexpected-status',
        '/connect answered HTTP ${response.statusCode}',
      );
    }
    final raw = response.headers[HttpHeaders.setCookieHeader] ?? const [];
    if (raw.isEmpty) {
      throw RemoteException('pairing/no-cookie', '/connect set no cookie');
    }
    final pair = raw.first.split(';').first;
    final eq = pair.indexOf('=');
    if (eq <= 0) {
      throw RemoteException('pairing/bad-cookie', 'unparseable Set-Cookie');
    }
    return PairedCredential(
      origin: origin.replace(path: '', query: null),
      cookieName: pair.substring(0, eq).trim(),
      cookieValue: pair.substring(eq + 1).trim(),
      interactions: interactions,
    );
  }

  void close() {
    if (_owns) _http.close(force: true);
  }
}

/// Parse an `http://host:port/?token=...` URL as printed by `dsh web`
/// (also what a pairing QR code would carry). Returns `(origin, token)`.
({Uri origin, String token}) parseLaunchUrl(String text) {
  final uri = Uri.parse(text.trim());
  final token = uri.queryParameters['token'];
  if (!uri.hasAuthority || token == null || token.isEmpty) {
    throw const FormatException('expected http(s)://host:port/?token=...');
  }
  return (
    origin: Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    ),
    token: token,
  );
}
