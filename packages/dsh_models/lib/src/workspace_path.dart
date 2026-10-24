/// File addresses and path parts (dsh `util/workspace-path`): how a file is
/// named across the sidebar and its tabs.
library;

bool _isWindowsStyle(String value) =>
    RegExp(r'^[A-Za-z]:[/\\]').hasMatch(value) || value.startsWith(r'\\');

/// Whether a path is absolute in either spelling the host accepts.
bool isAbsoluteWorkspacePath(String path) =>
    path.startsWith('/') || _isWindowsStyle(path);

const String _prefix = 'dsh-resource://file/';

String _encodeSegment(String segment) =>
    Uri.encodeComponent(segment)
        .replaceAll(RegExp('%3A', caseSensitive: false), ':');

String _encodePath(String path) =>
    path.split('/').map(_encodeSegment).join('/');

/// `dsh-resource://file/session/<sessionId>/<path>` (dsh `sessionFileAddress`).
String sessionFileAddress(String sessionId, String path) {
  final normalized = path
      .replaceAll(r'\', '/')
      .replaceFirst(RegExp(r'^(?:\./)+'), '');
  return '${_prefix}session/${_encodeSegment(sessionId)}/${_encodePath(normalized)}';
}

/// The address for a path as a caller holds it (dsh `fileAddressFor`): a
/// relative path, or an absolute one inside the workspace, becomes a
/// workspace-relative session address; any other absolute path keeps its
/// absolute spelling in that session's address.
String fileAddressFor(String sessionId, String? cwd, String path) {
  final normalized = path.replaceAll(r'\', '/');
  if (!isAbsoluteWorkspacePath(normalized)) {
    return sessionFileAddress(sessionId, normalized);
  }
  final root = cwd == null
      ? ''
      : cwd.replaceAll(r'\', '/').replaceAll(RegExp(r'/+$'), '');
  if (root.isNotEmpty && normalized == root) {
    return sessionFileAddress(sessionId, '');
  }
  if (root.isNotEmpty && normalized.startsWith('$root/')) {
    return sessionFileAddress(sessionId, normalized.substring(root.length + 1));
  }
  return sessionFileAddress(sessionId, normalized);
}

/// A parsed session-scoped file address.
class FileAddress {
  const FileAddress(this.sessionId, this.path);
  final String sessionId;

  /// Workspace-relative or absolute, `/`-separated.
  final String path;
}

/// Read a `session`-scoped address back (dsh `parseFileAddress`); null for
/// anything else, including a malformed escape.
FileAddress? parseSessionFileAddress(String address) {
  if (!address.startsWith(_prefix)) return null;
  try {
    final end = address.indexOf(RegExp('[?#]'));
    final body = address.substring(_prefix.length, end == -1 ? null : end);
    final parts = body.split('/');
    if (parts.first != 'session') return null;
    final rest = parts.skip(1).toList();
    if (rest.isEmpty || rest.first.isEmpty || rest.length < 2) return null;
    return FileAddress(
      Uri.decodeComponent(rest.first),
      rest.skip(1).map(Uri.decodeComponent).join('/'),
    );
  } on FormatException {
    return null;
  } on ArgumentError {
    return null;
  }
}

/// A path split for display (dsh `pathPartsOf`): the directories through the
/// last separator, and the final segment.
({String directory, String name}) pathPartsOf(String path) {
  final trimmed = path.replaceAll(RegExp(r'[/\\]+$'), '');
  if (trimmed.isEmpty) return (directory: '', name: path);
  final cut =
      [
        trimmed.lastIndexOf('/'),
        trimmed.lastIndexOf(r'\'),
      ].reduce((a, b) => a > b ? a : b) +
      1;
  return (directory: trimmed.substring(0, cut), name: trimmed.substring(cut));
}

/// `~` for the POSIX home and `~/…` below it (dsh `abbreviateHomePath`); the
/// path unchanged for another location, a Windows-style path or no home.
String abbreviateHome(String path, String? home) {
  if (home == null || home.isEmpty) return path;
  if (_isWindowsStyle(path) || _isWindowsStyle(home)) return path;
  final root = home.replaceAll(RegExp(r'/+$'), '');
  if (root.isEmpty || root == '/') return path;
  if (path.replaceAll(RegExp(r'/+$'), '') == root) return '~';
  if (path.startsWith('$root/')) return '~${path.substring(root.length)}';
  return path;
}

/// The final non-empty segment of a workspace path, for display (dsh
/// `workspaceTitleOf`); empty for a separator-only path.
String workspaceTitleOf(String path) {
  final trimmed = path.replaceAll(RegExp(r'[/\\]+$'), '');
  final sep = trimmed.lastIndexOf('/') > trimmed.lastIndexOf(r'\')
      ? trimmed.lastIndexOf('/')
      : trimmed.lastIndexOf(r'\');
  return trimmed.substring(sep + 1);
}

/// Leaf directory name of the first-use workspace (dsh
/// `DEFAULT_WORKSPACE_DIRECTORY`); language-neutral, so one installation keeps
/// one on-disk path across language switches.
const String defaultWorkspaceDirectory = 'default-workspace';

/// The text one workspace is labelled with (dsh `workspaceDisplayTitle`): a
/// workspace still carrying the automatic first-use title reads as the
/// caller's localized default name, every other title verbatim.
String workspaceDisplayTitle(String title, String localizedDefault) =>
    title == defaultWorkspaceDirectory ? localizedDefault : title;
