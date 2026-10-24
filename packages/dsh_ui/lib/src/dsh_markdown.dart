import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import 'dsh_code_block.dart';
import 'dsh_code_toolbar.dart';
import 'dsh_pixel_snap.dart';
import 'dsh_file_link.dart';

import 'theme_access.dart';

/// Markdown body of an assistant answer, styled from dsh's markdown tokens
/// (`--dsw-font-markdown-*`, `--dsw-alias-markdown-*`, `--dsw-alias-link`).
/// Safe for partial text while it streams.
class DshMarkdown extends StatelessWidget {
  const DshMarkdown(
    this.data, {
    super.key,
    this.selectable = false,
    this.codeLabels,
    this.onOpenUrl,
    this.onOpenFile,
    this.streaming = false,
  });

  final String data;
  final bool selectable;

  /// Strings of the code card toolbar. With them a fenced block is dsh's code
  /// card (language, wrap and copy, coloured by the ambient highlighter);
  /// without, a plain padded block.
  final DshCodeToolbarLabels? codeLabels;

  /// An http(s) link was tapped (dsh `MarkdownDelegate.openExternalLink`).
  /// Without it links are styled but inert.
  final void Function(Uri url)? onOpenUrl;

  /// A local file link was tapped (dsh `MarkdownDelegate.openFile`), with the
  /// first line of a `#L24` fragment. Like dsh, local links are live only in
  /// settled text, not while [streaming].
  final void Function(String path, {int? line})? onOpenFile;

  /// The text is still arriving: file links are not yet actionable.
  final bool streaming;

  void _tap(String text, String? href, String title) {
    if (href == null) return;
    final uri = Uri.tryParse(href);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      onOpenUrl?.call(uri);
      return;
    }
    if (streaming) return;
    final file = parseFileLink(href);
    if (file != null) onOpenFile?.call(file.path, line: file.line);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final label = theme.labelPrimary;
    TextStyle t(String name, {Color? color}) =>
        theme.textStyle(name).copyWith(color: color ?? label);
    final codeBlock = theme.color('--dsw-alias-markdown-code-block');
    final sheet = MarkdownStyleSheet(
      p: t('--dsw-font-markdown-base'),
      pPadding: EdgeInsets.zero,
      a: t('--dsw-font-markdown-base', color: theme.color('--dsw-alias-link')),
      strong: t('--dsw-font-markdown-base-strong'),
      em: t('--dsw-font-markdown-base-italic'),
      h1: t('--dsw-font-markdown-h1'),
      h2: t('--dsw-font-markdown-h2'),
      h3: t('--dsw-font-markdown-h3'),
      h4: t('--dsw-font-markdown-h4'),
      h5: t('--dsw-font-markdown-h4'),
      h6: t('--dsw-font-markdown-h4'),
      listBullet: t('--dsw-font-markdown-base'),
      blockquote: t(
        '--dsw-font-markdown-base',
        color: theme.color('--dsw-alias-label-secondary'),
      ),
      code: theme
          .textStyle('--dsw-font-markdown-code')
          .copyWith(
            color: label,
            backgroundColor: theme.color('--dsw-alias-markdown-inline-code'),
          ),
      codeblockDecoration: BoxDecoration(
        color: codeBlock,
        borderRadius: BorderRadius.circular(theme.radiusMd),
      ),
      codeblockPadding: const EdgeInsets.all(DshSpace.md),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: theme.color('--dsw-alias-border-l2'),
            width: dshBorderWidthOf(context, 2),
          ),
        ),
      ),
      tableHead: t('--dsw-font-markdown-table-head'),
      tableBody: t('--dsw-font-markdown-table'),
      tableBorder: TableBorder.all(
        color: theme.color('--dsw-alias-border-l3'),
        width: dshHairlineOf(context),
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.color('--dsw-alias-border-l3'),
            width: dshHairlineOf(context),
          ),
        ),
      ),
      blockSpacing: DshSpace.sm,
    );
    return MarkdownBody(
      data: data,
      selectable: selectable,
      styleSheet: sheet,
      onTapLink: onOpenUrl == null && onOpenFile == null ? null : _tap,
      builders: {if (codeLabels != null) 'pre': _FenceBuilder(codeLabels!)},
    );
  }
}

/// Draws a fenced block as a [DshCodeBlock] (dsh's `CodeBlock` for markdown).
class _FenceBuilder extends MarkdownElementBuilder {
  _FenceBuilder(this.labels);

  final DshCodeToolbarLabels labels;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    String? lang;
    final first = element.children?.isNotEmpty ?? false
        ? element.children!.first
        : null;
    if (first is md.Element) {
      final cls = first.attributes['class'];
      if (cls != null && cls.startsWith('language-')) {
        lang = cls.substring('language-'.length);
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DshSpace.sm),
      child: DshCodeBlock(
        code: element.textContent,
        lang: lang,
        labels: labels,
      ),
    );
  }
}
