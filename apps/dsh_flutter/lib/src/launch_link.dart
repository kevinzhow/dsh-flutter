/// The host address and launch token a pairing form or QR code carries.
class LaunchLink {
  const LaunchLink(this.origin, this.token);

  final Uri origin;
  final String token;

  /// What a launch token looks like: dsh mints 43 base64url characters; the
  /// check is the alphabet and a sane length, so a format change on the host
  /// does not lock the app out, while an arbitrary URL is still not a link.
  static final RegExp _tokenShape = RegExp(r'^[A-Za-z0-9_-]{1,512}$');

  /// Whether [token] has the shape of a launch token.
  static bool tokenLooksValid(String token) => _tokenShape.hasMatch(token);

  /// Parse the text of the pairing form.
  ///
  /// [text] is either the full launch URL `dsh web` prints
  /// (`http://host:port/?token=…`, also what a QR code of it encodes) or a bare
  /// host address (`host:port`, `http://host:port`) used together with [token].
  /// The shape is checked here, before anything is sent anywhere: http or
  /// https, a host, no user name or password, no fragment, the token only
  /// once and only in the token alphabet, no other path than `/`.
  /// Throws [FormatException] (without echoing [text]: it holds the token) for
  /// anything else.
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
    if (uri.userInfo.isNotEmpty) {
      throw const FormatException('credentials in the address');
    }
    if (uri.hasFragment) throw const FormatException('fragment');
    if (uri.path.isNotEmpty && uri.path != '/') {
      throw const FormatException('unexpected path');
    }
    if (uri.hasPort && (uri.port <= 0 || uri.port > 65535)) {
      throw const FormatException('bad port');
    }
    final tokens = uri.queryParametersAll['token'] ?? const <String>[];
    final String chosen;
    if (tokens.isNotEmpty) {
      if (tokens.length != 1) throw const FormatException('several tokens');
      chosen = tokens.single;
    } else {
      chosen = token.trim();
    }
    if (chosen.isEmpty) throw const FormatException('no token');
    if (!tokenLooksValid(chosen)) throw const FormatException('bad token');
    return LaunchLink(
      Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
      ),
      chosen,
    );
  }

  /// The origin without the token, safe to show and store.
  String get originText => origin.toString();
}

/// Reads a launch link from the camera.
abstract interface class LaunchScanner {
  /// Whether this build can scan.
  bool get available;

  /// Open the camera and return the first decoded QR text that is a launch
  /// link, or null when the user backs out.
  Future<String?> scan();
}

/// The scanner of builds without camera support (desktop).
class NoScanner implements LaunchScanner {
  const NoScanner();
  @override
  bool get available => false;
  @override
  Future<String?> scan() async => null;
}
