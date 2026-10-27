import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:markdown/markdown.dart' as md;

import 'dsh_code_toolbar.dart';
import 'dsh_corners.dart';
import 'dsh_icon.dart';
import 'dsh_markdown.dart';
import 'dsh_recipes.g.dart';
import 'dsh_shell_icons.g.dart';
import 'dsh_snapped_box.dart';
import 'dsh_tag.dart';
import 'dsh_text_baseline.dart';
import 'theme_access.dart';

/// The published preset reader's prose profile of the canonical Markdown
/// engine. Content, links, inline formatting and code cards still go through
/// [DshMarkdown]; the reader supplies its generated typography and block flow.
class DshReaderMarkdown extends StatelessWidget {
  const DshReaderMarkdown(
    this.data, {
    super.key,
    this.usage = false,
    required this.exampleLabel,
    this.codeLabels,
    this.selectable = false,
    this.onOpenUrl,
    this.onOpenFile,
  });

  final String data;
  final bool usage;
  final String exampleLabel;
  final DshCodeToolbarLabels? codeLabels;
  final bool selectable;
  final void Function(Uri)? onOpenUrl;
  final void Function(String, {int? line})? onOpenFile;

  @override
  Widget build(BuildContext context) {
    Widget body(String text) => _ReaderMarkdownBody(
      text,
      usage: usage,
      codeLabels: codeLabels,
      selectable: selectable,
      onOpenUrl: onOpenUrl,
      onOpenFile: onOpenFile,
    );

    if (!usage) return body(data);
    // PresetGuideDialog.GuideUsage splits the real usage dictionary at its
    // level-three headings, then renders each example body as Markdown.
    final sections = data
        .split(RegExp(r'(?=^### )', multiLine: true))
        .where((section) => section.trim().isNotEmpty)
        .toList(growable: false);
    if (sections.any(
      (section) => !section.startsWith('### ') || !section.contains('\n'),
    )) {
      return body(data);
    }
    final theme = context.dsh;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++)
          Padding(
            padding: EdgeInsets.only(
              top: i == 0 ? 0 : DshGuideReaderRecipe.exampleGap,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    bottom: DshGuideReaderRecipe.exampleHeaderBottom,
                  ),
                  child: Wrap(
                    spacing: DshGuideReaderRecipe.exampleHeaderColumnGap,
                    runSpacing: DshGuideReaderRecipe.exampleHeaderRowGap,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      DshChromeText(
                        sections[i].substring(4, sections[i].indexOf('\n')),
                        style: _headingStyle(context),
                      ),
                      DshTag(
                        tone: DshTagTone.neutral,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DshIcon(
                              DshShellIcons.listPenOutline,
                              size: DshGuideReaderRecipe.exampleIconSize,
                              color: theme.color(
                                DshTagRecipe.neutralLabelToken,
                              ),
                            ),
                            const SizedBox(
                              width: DshGuideReaderRecipe.exampleTagGap,
                            ),
                            DshChromeText(
                              exampleLabel,
                              maxLines: 1,
                              softWrap: false,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                body(sections[i].substring(sections[i].indexOf('\n') + 1)),
              ],
            ),
          ),
      ],
    );
  }
}

TextStyle _headingStyle(BuildContext context) => context.dsh
    .fixedTextStyle(
      size: DshGuideReaderRecipe.headingFontSize,
      line: DshGuideReaderRecipe.headingLineHeight,
      weight: DshGuideReaderRecipe.headingWeight.round(),
    )
    .copyWith(color: context.dsh.color(DshGuideReaderRecipe.panelLabelToken));

TextStyle _paragraphStyle(BuildContext context, {required bool usage}) =>
    context.dsh
        .fixedTextStyle(
          size: usage
              ? DshGuideReaderRecipe.usageParagraphFontSize
              : DshGuideReaderRecipe.paragraphFontSize,
          line: usage
              ? DshGuideReaderRecipe.usageParagraphLineHeight
              : DshGuideReaderRecipe.paragraphLineHeight,
        )
        .copyWith(
          color: context.dsh.color(
            usage
                ? DshGuideReaderRecipe.usageParagraphLabelToken
                : DshGuideReaderRecipe.paragraphLabelToken,
          ),
        );

TextStyle _quoteStyle(BuildContext context, {required bool usage}) => context
    .dsh
    .fixedTextStyle(
      size: usage
          ? DshGuideReaderRecipe.usageQuoteFontSize
          : DshGuideReaderRecipe.paragraphFontSize,
      line: usage
          ? DshGuideReaderRecipe.usageQuoteLineHeight
          : DshGuideReaderRecipe.paragraphLineHeight,
    )
    .copyWith(
      color: context.dsh.color(
        usage
            ? DshGuideReaderRecipe.usageQuoteLabelToken
            : DshGuideReaderRecipe.quoteLabelToken,
      ),
    );

class _ReaderMarkdownBody extends StatelessWidget {
  const _ReaderMarkdownBody(
    this.data, {
    required this.usage,
    required this.codeLabels,
    required this.selectable,
    required this.onOpenUrl,
    required this.onOpenFile,
  });

  final String data;
  final bool usage;
  final DshCodeToolbarLabels? codeLabels;
  final bool selectable;
  final void Function(Uri)? onOpenUrl;
  final void Function(String, {int? line})? onOpenFile;

  @override
  Widget build(BuildContext context) {
    // This second parse supplies block tags only. Rendering remains entirely
    // in the canonical engine, including GFM, links and all inline spans.
    final nodes = md.Document(
      extensionSet: md.ExtensionSet.gitHubFlavored,
      encodeHtml: false,
    ).parseLines(const LineSplitter().convert(data));
    return DshMarkdown(
      data,
      selectable: selectable,
      codeLabels: codeLabels,
      onOpenUrl: onOpenUrl,
      onOpenFile: onOpenFile,
      styleBuilder: (context, standard) => standard.copyWith(
        p: _paragraphStyle(context, usage: usage),
        h3: _headingStyle(context),
        h3Padding: EdgeInsets.zero,
        // Partial styles inherit the reader paragraph/quote's size and colour.
        strong: TextStyle(fontWeight: _headingStyle(context).fontWeight),
        em: const TextStyle(fontStyle: FontStyle.italic),
        a: TextStyle(color: standard.a?.color),
        listBullet: _paragraphStyle(context, usage: usage),
        blockquote: _quoteStyle(context, usage: usage),
        blockquotePadding: EdgeInsets.zero,
        blockquoteDecoration: const BoxDecoration(),
        blockSpacing: 0,
      ),
      blockBuilder: (context, rendered) {
        // MarkdownBody inserts these between its top-level blocks. The source
        // uses CSS margins instead; adjoining margins collapse to their max.
        final blocks = rendered
            .where(
              (widget) =>
                  !(widget is SizedBox &&
                      widget.height == 0 &&
                      widget.child == null),
            )
            .toList(growable: false);
        if (blocks.length != nodes.length) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rendered,
          );
        }
        final children = <Widget>[];
        var previousBottom = 0.0;
        for (var i = 0; i < blocks.length; i++) {
          final tag = nodes[i] is md.Element
              ? (nodes[i] as md.Element).tag
              : null;
          final (top, bottom) = _margins(tag);
          final gap = i == 0 ? 0.0 : math.max(previousBottom, top);
          if (gap > 0) children.add(SizedBox(height: gap));
          final block = switch (tag) {
            'p' => DshChromeBaseline(
              style: _paragraphStyle(context, usage: usage),
              child: blocks[i],
            ),
            'h3' => DshChromeBaseline(
              style: _headingStyle(context),
              child: blocks[i],
            ),
            'blockquote' => _quote(context, blocks[i]),
            _ => blocks[i],
          };
          children.add(block);
          previousBottom = bottom;
        }
        // MarkdownText removes its final child's bottom margin.
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        );
      },
    );
  }

  (double, double) _margins(String? tag) => switch (tag) {
    'h3' =>
      usage
          ? (0, 0)
          : (
              DshGuideReaderRecipe.headingTop,
              DshGuideReaderRecipe.headingBottom,
            ),
    'p' => (
      0,
      usage
          ? DshGuideReaderRecipe.usageParagraphBottom
          : DshGuideReaderRecipe.paragraphBottom,
    ),
    'blockquote' =>
      usage
          ? (
              DshGuideReaderRecipe.usageQuoteVerticalMargin,
              DshGuideReaderRecipe.usageQuoteVerticalMargin,
            )
          : (DshGuideReaderRecipe.quoteTop, DshGuideReaderRecipe.quoteBottom),
    // Other GFM structures keep the canonical engine's rendering.
    _ => (0, 0),
  };

  Widget _quote(BuildContext context, Widget block) {
    final theme = context.dsh;
    // Retain the engine's actual rich content, replacing only the generic
    // assistant quote frame. Baseline correction belongs inside the fill.
    final content = switch (block) {
      DecoratedBox(child: Padding(child: final Widget child)) => child,
      _ => block,
    };
    final fill = DshSurface.paint(
      context,
      theme.color(DshGuideReaderRecipe.quoteBackgroundToken),
    );
    return DshSurface(
      color: fill,
      child: DshDecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(
            theme.number(DshGuideReaderRecipe.quoteRadiusToken),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: usage
                ? DshGuideReaderRecipe.usageQuoteVerticalPadding
                : DshGuideReaderRecipe.quoteVerticalPadding,
            horizontal: usage
                ? DshGuideReaderRecipe.usageQuoteHorizontalPadding
                : DshGuideReaderRecipe.quoteHorizontalPadding,
          ),
          child: DshChromeBaseline(
            style: _quoteStyle(context, usage: usage),
            child: content,
          ),
        ),
      ),
    );
  }
}
