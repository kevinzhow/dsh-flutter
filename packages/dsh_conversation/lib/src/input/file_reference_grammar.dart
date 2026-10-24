/// The `@file` token grammar (dsh `file-reference/grammar`, shared by dsh's
/// terminal and web clients): which `@` token ends at the caret, and how a
/// chosen path is written back as prompt text.
library;

/// An `@path` or `@"path with spaces` token ending at the caret.
class ActiveAtToken {
  const ActiveAtToken({
    required this.prefix,
    required this.query,
    required this.quoted,
  });

  /// The complete token a completion replaces.
  final String prefix;

  /// The path text after `@` or `@"`.
  final String query;

  /// Whether the user opened a quoted path.
  final bool quoted;

  @override
  bool operator ==(Object other) =>
      other is ActiveAtToken &&
      other.prefix == prefix &&
      other.query == query &&
      other.quoted == quoted;

  @override
  int get hashCode => Object.hash(prefix, query, quoted);

  @override
  String toString() => 'ActiveAtToken($prefix, $query, quoted: $quoted)';
}

final RegExp _quotedAt = RegExp(r'(?:^|\s)(@"([^"]*))$', unicode: true);
final RegExp _plainAt = RegExp(r'(?:^|\s)(@([^\s]*))$', unicode: true);

/// The `@` token under the caret: an `@` inside another token (an email
/// address) does not trigger. [line] is the current editor line, [cursorCol]
/// the caret within it.
ActiveAtToken? activeAtToken(String line, int cursorCol) {
  final before = line.substring(0, cursorCol);
  final quoted = _quotedAt.firstMatch(before);
  if (quoted != null) {
    return ActiveAtToken(
      prefix: quoted.group(1)!,
      query: quoted.group(2)!,
      quoted: true,
    );
  }
  final plain = _plainAt.firstMatch(before);
  if (plain == null) return null;
  return ActiveAtToken(
    prefix: plain.group(1)!,
    query: plain.group(2)!,
    quoted: false,
  );
}

/// One path-only completion candidate (`fileReferences/list`).
class FileCandidate {
  const FileCandidate({required this.path, required this.isDirectory});
  final String path;
  final bool isDirectory;
}

final RegExp _unsafePath = RegExp(
  r'[\u0000-\u001f\u007f-\u009f"]',
  unicode: true,
);
final RegExp _whitespace = RegExp(r'\s', unicode: true);

/// A chosen path as prompt text (dsh `formatFileMention`): whitespace uses the
/// quoted `@"path"` form; a quoted directory keeps its quote open after the
/// trailing slash so completion can descend another level. Null for a path
/// the grammar cannot write safely.
String? formatFileMention(FileCandidate candidate, bool preserveQuote) {
  final path = candidate.isDirectory ? '${candidate.path}/' : candidate.path;
  if (_unsafePath.hasMatch(path)) return null;
  final quoted = preserveQuote || _whitespace.hasMatch(path);
  if (!quoted) return '@$path';
  if (candidate.isDirectory) return '@"$path';
  return '@"$path"';
}
