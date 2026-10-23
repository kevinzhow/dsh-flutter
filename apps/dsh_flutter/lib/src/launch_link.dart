import 'package:dsh_client/dsh_client.dart';

/// The host address and launch token a pairing form or QR code carries.
class LaunchLink {
  const LaunchLink(this.origin, this.token);

  final Uri origin;
  final String token;

  /// Parse the text of the pairing form.
  ///
  /// [text] is either the full launch URL `dsh web` prints
  /// (`http://host:port/?token=…`, also what its QR code encodes) or a bare
  /// host address (`host:port`, `http://host:port`) used together with [token].
  /// Throws [FormatException] for anything else.
  factory LaunchLink.parse(String text, {String token = ''}) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) throw const FormatException('empty');
    final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
    final uri = Uri.tryParse(withScheme);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      throw const FormatException('not a URL');
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const FormatException('unsupported scheme');
    }
    final fromLink = uri.queryParameters['token'];
    if (fromLink != null && fromLink.isNotEmpty) {
      final parsed = parseLaunchUrl(withScheme);
      return LaunchLink(parsed.origin, parsed.token);
    }
    final explicit = token.trim();
    if (explicit.isEmpty) throw const FormatException('no token');
    return LaunchLink(
      Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
      ),
      explicit,
    );
  }

  /// The origin without the token, safe to show and store.
  String get originText => origin.toString();
}

/// Reads a launch link from the camera. The phone build wires a real scanner
/// later (a camera plugin and its permissions); until then [scan] returns null
/// and the pairing screen offers the paste fallback only.
// TODO(whalee): implement with a camera scanning plugin on Android and iOS.
abstract interface class LaunchScanner {
  /// Whether this build can scan.
  bool get available;

  /// Open the camera and return the first decoded QR text, or null when the
  /// user backs out.
  Future<String?> scan();
}

/// The scanner of builds without camera support.
class NoScanner implements LaunchScanner {
  const NoScanner();
  @override
  bool get available => false;
  @override
  Future<String?> scan() async => null;
}
