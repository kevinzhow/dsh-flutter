import 'dsh_code_language.g.dart';

/// The syntax-highlighting language of a file path, from its extension
/// (dsh `languageForPath`): the text after the last dot of the final path
/// segment, case-insensitive; null for an unlisted or absent suffix.
String? dshLanguageForPath(String path) {
  final slash = [
    path.lastIndexOf('/'),
    path.lastIndexOf(r'\'),
  ].reduce((a, b) => a > b ? a : b);
  final base = path.substring(slash + 1);
  final dot = base.lastIndexOf('.');
  if (dot < 0) return null;
  return dshLanguageByExtension[base.substring(dot + 1).toLowerCase()];
}

/// Whether a language hint resolves to a grammar of dsh's shared highlighter
/// (dsh `supportsHighlighting`). The label of a code card shows the hint only
/// then; otherwise it reads the generic "Code" label.
bool dshSupportsHighlighting(String? lang) =>
    lang != null && dshGrammarByHint.containsKey(lang.toLowerCase());
