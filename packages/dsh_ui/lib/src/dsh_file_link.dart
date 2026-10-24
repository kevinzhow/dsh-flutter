/// A local Markdown destination: a path and the optional first line of a
/// `#L24` or `#L24-L30` fragment.
typedef DshFileLink = ({String path, int? line});

/// Port of dsh `parseFileLink` (`ui-primitives` `markdown/file-link.ts`).
/// Decodes a file destination and its optional GitHub-style line fragment.
/// Literal `?` and `#` in file names must be percent-encoded.
///
/// Returns null for URLs, fragment-only links, queries, malformed escapes and
/// invalid line ranges.
DshFileLink? parseFileLink(String value) {
  final hash = value.indexOf('#');
  final destination = hash < 0 ? value : value.substring(0, hash);
  if (destination.contains('?')) return null;
  final String path;
  try {
    path = Uri.decodeComponent(destination);
  } on Object {
    return null;
  }
  if (path.isEmpty ||
      RegExp(r'[\u0000-\u001f\u007f]').hasMatch(path) ||
      RegExp(r'^[\\/]{2}').hasMatch(path) ||
      (RegExp(r'^[a-z][a-z\d+.-]*:', caseSensitive: false).hasMatch(path) &&
          !RegExp(r'^[a-z]:[\\/]', caseSensitive: false).hasMatch(path))) {
    return null;
  }
  if (hash < 0) return (path: path, line: null);
  final match = RegExp(r'^L([1-9]\d*)(?:-L([1-9]\d*))?$')
      .firstMatch(value.substring(hash + 1));
  if (match == null) return null;
  final line = int.tryParse(match.group(1)!);
  final end = match.group(2) == null ? line : int.tryParse(match.group(2)!);
  if (line == null || end == null || end < line) return null;
  return (path: path, line: line);
}
