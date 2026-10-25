import 'package:markdown/markdown.dart' as md;

/// Plain summaries use the renderer's GFM parser, retaining code, image alt
/// text and literal raw HTML while removing presentation markup.
String dshMarkdownPlainText(String markdown, {String mode = 'all'}) {
  final nodes = md.Document(
    extensionSet: md.ExtensionSet.gitHubFlavored,
    encodeHtml: false,
  ).parseLines(markdown.split('\n'));
  String inline(md.Node n) {
    if (n is md.Text) return n.text;
    final e = n as md.Element;
    if (e.tag == 'img') return e.attributes['alt'] ?? '';
    if (e.tag == 'br') return '\n';
    if (e.tag == 'input') return '';
    return (e.children ?? []).map(inline).join();
  }

  String compact(String text) => text.replaceAll(RegExp(r'\s+'), ' ').trim();
  String block(md.Node n) {
    if (n is md.Text) return n.text;
    final e = n as md.Element;
    final children = e.children ?? [];
    final values = children.map(block).where((s) => s.isNotEmpty);
    return switch (e.tag) {
      'blockquote' => values.join('\n\n'),
      'ul' || 'ol' || 'table' || 'thead' || 'tbody' => values.join('\n'),
      'li' => values.join(' '),
      'tr' => children.map(block).join('\t'),
      'pre' => inline(e).trim(),
      'hr' || 'input' => '',
      _ => compact(inline(e)),
    };
  }

  final all = nodes
      .map(block)
      .where((s) => s.isNotEmpty)
      .join('\n\n')
      .split('\n')
      .map((s) => s.trim())
      .join('\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  final first = all.split('\n').where((s) => s.isNotEmpty).firstOrNull ?? '';
  if (mode == 'first-line') return first;
  if (mode == 'first-paragraph') {
    String? paragraph(md.Node n) {
      if (n is! md.Element) return null;
      // Dart's GFM parser omits <p> inside a tight list; mdast retains
      // that semantic paragraph. Recover its leading inline children.
      if (n.tag == 'li' &&
          !(n.children ?? []).any((c) => c is md.Element && c.tag == 'p')) {
        final prefix = (n.children ?? []).takeWhile(
          (c) =>
              c is! md.Element ||
              !const ['ul', 'ol', 'blockquote'].contains(c.tag),
        );
        final text = compact(prefix.map(inline).join());
        if (text.isNotEmpty) return text;
      }
      if (n.tag == 'p') {
        final text = compact(inline(n));
        if (text.isNotEmpty) return text;
      }
      for (final child in n.children ?? <md.Node>[]) {
        final text = paragraph(child);
        if (text != null) return text;
      }
      return null;
    }

    for (final n in nodes) {
      final text = paragraph(n);
      if (text != null) return text;
    }
    return first;
  }
  return all;
}
