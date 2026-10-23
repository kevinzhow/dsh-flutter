/// Workspace path helpers (dsh `util/workspace-path`).
library;

bool _isWindowsStyle(String value) =>
    RegExp(r'^[A-Za-z]:[/\\]').hasMatch(value) || value.startsWith(r'\\');

bool isAbsoluteWorkspacePath(String path) =>
    path.startsWith('/') || _isWindowsStyle(path);

String resolveWorkspacePath(String? cwd, String path) {
  if (isAbsoluteWorkspacePath(path)) return path;
  if (cwd == null || cwd.isEmpty) return path;
  final separator = _isWindowsStyle(cwd) && cwd.contains(r'\') ? r'\' : '/';
  final base = cwd.replaceAll(RegExp(r'[/\\]+$'), '');
  final relative = path.replaceAll(RegExp(r'^[/\\]+'), '');
  return '$base$separator$relative';
}

String abbreviateHomePath(String path, String? home) {
  if (home == null || home.isEmpty) return path;
  if (_isWindowsStyle(path) || _isWindowsStyle(home)) return path;
  final root = home.replaceAll(RegExp(r'/+$'), '');
  if (root.isEmpty || root == '/') return path;
  if (path.replaceAll(RegExp(r'/+$'), '') == root) return '~';
  if (path.startsWith('$root/')) return '~${path.substring(root.length)}';
  return path;
}

String relativizeToCwd(String text, String? cwd) {
  if (cwd == null || cwd.isEmpty) return text;
  final root = cwd.replaceAll(RegExp(r'[/\\]+$'), '');
  if (text.startsWith('$root/') || text.startsWith('$root\\')) {
    return text.substring(root.length + 1);
  }
  return text;
}
