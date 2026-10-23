/// The nine colour classes of dsh's `--shiki-token-*` custom properties.
///
/// A span without a token uses the foreground colour (`--shiki-foreground`).
enum HighlightToken {
  constant,
  string,
  comment,
  keyword,
  parameter,
  function,
  stringExpression,
  punctuation,
  link,
}

/// A run of text sharing one colour class and font style.
class HighlightSpan {
  const HighlightSpan(
    this.text, [
    this.token,
    this.italic = false,
    this.bold = false,
    this.underline = false,
  ]);

  final String text;

  /// The colour class; null means the foreground colour.
  final HighlightToken? token;
  final bool italic;
  final bool bold;
  final bool underline;

  @override
  bool operator ==(Object other) =>
      other is HighlightSpan &&
      other.text == text &&
      other.token == token &&
      other.italic == italic &&
      other.bold == bold &&
      other.underline == underline;

  @override
  int get hashCode => Object.hash(text, token, italic, bold, underline);

  @override
  String toString() {
    final flags = [
      if (italic) 'italic',
      if (bold) 'bold',
      if (underline) 'underline',
    ];
    return 'HighlightSpan(${_quote(text)}, ${token?.name ?? 'fg'}'
        '${flags.isEmpty ? '' : ', ${flags.join('+')}'})';
  }

  static String _quote(String s) =>
      "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll('\n', r'\n')}'";
}

/// Where grammar JSON comes from (assets in the app, files in tests).
abstract interface class GrammarSource {
  /// Grammar ids this source can provide (shiki names: `typescript`,
  /// `shellscript`, ...), including grammars that only exist as embedded
  /// dependencies of others (`javascript`, `css`, ...).
  Set<String> get available;

  /// The JSON text of one grammar registration.
  Future<String> read(String grammarId);
}
