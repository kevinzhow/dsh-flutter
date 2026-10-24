/// What the terminal models remember on the device (dsh keeps both in
/// `localStorage`): the last shell the person chose, and close requests that
/// the Host has not confirmed yet.
abstract interface class TerminalPrefs {
  /// The last selected shell path, or null.
  String? get preferredShell;
  void rememberShell(String path);

  /// Close requests still waiting for the Host's confirmation.
  List<TerminalCloseRequest> get pendingCloses;
  void saveClose(TerminalCloseRequest request);
  void removeClose(String terminalId);
}

/// A saved intent to end one Host terminal; no process or tab metadata is
/// mirrored here.
class TerminalCloseRequest {
  const TerminalCloseRequest({
    required this.sessionId,
    required this.id,
    required this.title,
  });

  /// Reads `{sessionId, id, title}`, or null when [json] is not one.
  static TerminalCloseRequest? tryParse(Object? json) {
    if (json is! Map) return null;
    final sessionId = json['sessionId'];
    final id = json['id'];
    final title = json['title'];
    if (sessionId is! String ||
        sessionId.isEmpty ||
        id is! String ||
        !RegExp(r'^[\w-]{1,128}$').hasMatch(id) ||
        title is! String) {
      return null;
    }
    return TerminalCloseRequest(sessionId: sessionId, id: id, title: title);
  }

  final String sessionId;
  final String id;
  final String title;

  Map<String, Object?> toJson() => {
    'sessionId': sessionId,
    'id': id,
    'title': title,
  };
}

/// Keeps nothing past the process.
class MemoryTerminalPrefs implements TerminalPrefs {
  String? _shell;
  final Map<String, TerminalCloseRequest> _closes = {};

  @override
  String? get preferredShell => _shell;

  @override
  void rememberShell(String path) => _shell = path;

  @override
  List<TerminalCloseRequest> get pendingCloses => _closes.values.toList();

  @override
  void saveClose(TerminalCloseRequest request) => _closes[request.id] = request;

  @override
  void removeClose(String terminalId) => _closes.remove(terminalId);
}
