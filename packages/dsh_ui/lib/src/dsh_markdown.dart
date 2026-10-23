import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'theme_access.dart';

/// Markdown body of an assistant answer, styled from dsh's markdown tokens
/// (`--dsw-font-markdown-*`, `--dsw-alias-markdown-*`, `--dsw-alias-link`).
/// Safe for partial text while it streams.
class DshMarkdown extends StatelessWidget {
  const DshMarkdown(this.data, {super.key, this.selectable = false});

  final String data;
  final bool selectable;

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
            width: 2,
          ),
        ),
      ),
      tableHead: t('--dsw-font-markdown-table-head'),
      tableBody: t('--dsw-font-markdown-table'),
      tableBorder: TableBorder.all(
        color: theme.color('--dsw-alias-border-l3'),
        width: 0.5,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.color('--dsw-alias-border-l3'),
            width: 0.5,
          ),
        ),
      ),
      blockSpacing: DshSpace.sm,
    );
    return MarkdownBody(data: data, selectable: selectable, styleSheet: sheet);
  }
}
