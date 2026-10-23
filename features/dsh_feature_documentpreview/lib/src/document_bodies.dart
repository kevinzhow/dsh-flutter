import 'dart:async';
import 'dart:math' as math;

import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart';
import 'package:flutter/widgets.dart';

import 'document_controller.dart';
import 'renderers.dart';

/// The content of a preview in its selected viewer: highlighted source, plain
/// text, rendered Markdown or an image. [footer] is the load-more or failure
/// row of a paged read.
class DocumentBody extends StatelessWidget {
  const DocumentBody({
    super.key,
    required this.controller,
    required this.renderer,
    required this.i18n,
    required this.name,
    this.footer,
  });

  final DocumentController controller;
  final DocumentRenderer renderer;
  final DshI18n i18n;
  final String name;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => switch (renderer.id) {
    imageRendererId => ImageBody(
      controller: controller,
      i18n: i18n,
      name: name,
    ),
    markdownRendererId => MarkdownBody(
      controller: controller,
      i18n: i18n,
      footer: footer,
    ),
    codeRendererId => SourceBody(
      controller: controller,
      i18n: i18n,
      footer: footer,
      highlight: true,
    ),
    _ => SourceBody(
      controller: controller,
      i18n: i18n,
      footer: footer,
      highlight: false,
    ),
  };
}

/// Source or plain text: the loaded pages as lines in one scroller that asks
/// for the next page near its end, honours the wrap preference (off scrolls
/// sideways) and brings a navigated line into view.
class SourceBody extends StatefulWidget {
  const SourceBody({
    super.key,
    required this.controller,
    required this.i18n,
    required this.highlight,
    this.footer,
  });

  final DocumentController controller;
  final DshI18n i18n;

  /// Colour the source by its language and show a line-number gutter (the
  /// code viewer); plain text shows neither.
  final bool highlight;
  final Widget? footer;

  @override
  State<SourceBody> createState() => _SourceBodyState();
}

class _SourceBodyState extends State<SourceBody> with DshHighlightListener {
  final ScrollController _scroll = ScrollController();
  final GlobalKey _targetKey = GlobalKey();
  List<List<DshCodeSpan>>? _highlighted;
  String? _highlightedFor;
  int _targetAttempts = 0;

  @override
  String? get highlightLang =>
      widget.highlight ? dshLanguageForPath(widget.controller.path) : null;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _answerTarget());
  }

  @override
  void didUpdateWidget(SourceBody old) {
    super.didUpdateWidget(old);
    _targetAttempts = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) => _answerTarget());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final c = widget.controller;
    if (_scroll.position.extentAfter < 600 && !c.eof && !c.loading) {
      unawaited(c.loadNext());
    }
  }

  /// Bring the navigated line into view: jump near it by estimate (lazy
  /// lists build only what is visible), then align the built row.
  void _answerTarget() {
    final c = widget.controller;
    final line = c.targetLine;
    if (!mounted || line == null || !_scroll.hasClients) return;
    if (line > c.loadedThrough) return;
    final context = _targetKey.currentContext;
    if (context != null) {
      unawaited(
        Scrollable.ensureVisible(
          context,
          alignment: 0.15,
          duration: Duration.zero,
        ),
      );
      c.answeredTarget();
      setState(() {});
      return;
    }
    if (_targetAttempts++ > 6) {
      c.answeredTarget();
      return;
    }
    final estimate = (line - 1) * _lineHeight;
    _scroll.jumpTo(
      estimate.clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _answerTarget());
  }

  double _lineHeight = 20;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final c = widget.controller;
    final style = theme.textStyle('--dsw-font-markdown-code-block');
    _lineHeight = style.height! * style.fontSize!;
    final lines = c.lines;
    final lang = highlightLang;
    List<List<DshCodeSpan>> spans;
    if (widget.highlight) {
      // Whole-window highlighting over everything loaded (grammar state flows
      // across pages); recomputed only when the text or the grammar changed.
      final highlighter = DshCodeHighlighting.of(context);
      final key =
          '$lang:${lines.length}:$highlightRevision:'
          '${identityHashCode(highlighter)}';
      if (_highlightedFor != key) {
        _highlighted = dshCodeLines(lines.join('\n'), lang, highlighter);
        _highlightedFor = key;
      }
      spans = _highlighted!;
    } else {
      spans = [
        for (final l in lines) [DshCodeSpan(l)],
      ];
    }
    final digits = math.max(2, '${lines.length}'.length);
    final painter = TextPainter(
      text: TextSpan(text: '0', style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    final gutter = widget.highlight ? painter.width * digits : 0.0;
    final foreground = style.copyWith(color: theme.color('--shiki-foreground'));
    final number = style.copyWith(
      color: theme.color('--dsw-alias-label-tertiary'),
    );
    final target = c.targetLine;
    final maxChars = lines.fold<int>(0, (m, l) => math.max(m, l.length));
    final contentWidth =
        (widget.highlight ? gutter + 12 : 0) + maxChars * painter.width + 32;

    Widget row(int i) {
      final marked = target == i + 1;
      final text = Text.rich(
        TextSpan(children: dshStyledSpans(context, spans[i], foreground)),
        softWrap: c.wrap,
        style: foreground,
      );
      final line = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.highlight) ...[
            SizedBox(
              width: gutter,
              child: Text(
                '${i + 1}',
                textAlign: TextAlign.right,
                softWrap: false,
                style: number,
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (c.wrap) Expanded(child: text) else text,
        ],
      );
      return KeyedSubtree(
        key: marked ? _targetKey : ValueKey('line-${i + 1}'),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _lineHeight),
          child: marked
              ? ColoredBox(
                  color: theme.color('--dsw-alias-interactive-bg-hover'),
                  child: line,
                )
              : line,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = c.wrap
            ? constraints.maxWidth
            : math.max(constraints.maxWidth, contentWidth);
        final list = CustomScrollView(
          key: const ValueKey('document-scroll'),
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              sliver: SliverList.builder(
                itemCount: lines.length,
                itemBuilder: (_, i) => row(i),
              ),
            ),
            if (widget.footer != null) SliverToBoxAdapter(child: widget.footer),
            const SliverToBoxAdapter(child: SizedBox(height: DshSpace.xl)),
          ],
        );
        final body = ColoredBox(
          color: widget.highlight
              ? theme.color('--dsw-alias-markdown-code-block')
              : theme.bgBase,
          child: c.wrap
              ? list
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(width: width, child: list),
                ),
        );
        return body;
      },
    );
  }
}

/// Rendered Markdown of the loaded text, loading the rest as the reader
/// scrolls. A leading YAML frontmatter block is shown verbatim in a bordered
/// box above the body (dsh's fallback for it; its field list is not ported).
class MarkdownBody extends StatefulWidget {
  const MarkdownBody({
    super.key,
    required this.controller,
    required this.i18n,
    this.footer,
  });

  final DocumentController controller;
  final DshI18n i18n;
  final Widget? footer;

  @override
  State<MarkdownBody> createState() => _MarkdownBodyState();
}

/// Leading YAML frontmatter split from a Markdown document (dsh
/// `splitFrontmatter`): only an opening `---` on the first line counts, the
/// block ends at the first closing `---` or `...` line.
({String source, String body})? splitFrontmatter(String text) {
  final match = RegExp(
    r'^﻿?---[ \t]*\r?\n(?:([\s\S]*?)\r?\n)??(?:---|\.\.\.)[ \t]*(?:\r?\n|$)',
  ).firstMatch(text);
  if (match == null) return null;
  return (source: match.group(1) ?? '', body: text.substring(match.end));
}

class _MarkdownBodyState extends State<MarkdownBody> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final c = widget.controller;
      if (_scroll.hasClients &&
          _scroll.position.extentAfter < 600 &&
          !c.eof &&
          !c.loading) {
        unawaited(c.loadNext());
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final text = widget.controller.lines.join('\n');
    final split = splitFrontmatter(text);
    return SingleChildScrollView(
      key: const ValueKey('document-scroll'),
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, DshSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (split != null && split.source.isNotEmpty)
            Container(
              key: const ValueKey('document-frontmatter'),
              margin: const EdgeInsets.only(bottom: DshSpace.lg),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: theme.color('--dsw-alias-bg-layer-1'),
                borderRadius: BorderRadius.circular(theme.radiusMd),
                border: Border.all(
                  color: theme.color('--dsw-alias-border-l2'),
                  width: dshHairline,
                ),
              ),
              child: Text(
                split.source,
                style: theme
                    .textStyle('--dsw-font-markdown-code-block-small')
                    .copyWith(color: theme.labelPrimary),
              ),
            ),
          DshMarkdown(
            split?.body ?? text,
            selectable: true,
            codeLabels: DshCodeToolbarLabels(
              codeLabel: widget.i18n.t('conversation', 'codeBlock.title'),
              wrapLabel: widget.i18n.t('conversation', 'codeBlock.wrap'),
              unwrapLabel: widget.i18n.t('conversation', 'codeBlock.unwrap'),
              copy: widget.i18n.t('documentMarkdown', 'code.copy'),
              copied: widget.i18n.t('documentMarkdown', 'code.copied'),
            ),
          ),
          ?widget.footer,
        ],
      ),
    );
  }
}

/// A complete image in a pinch-zoom viewport (dsh's `ZoomViewport`, whose
/// fit-width and fixed-scale controls a phone replaces with the gesture).
class ImageBody extends StatelessWidget {
  const ImageBody({
    super.key,
    required this.controller,
    required this.i18n,
    required this.name,
  });

  final DocumentController controller;
  final DshI18n i18n;
  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = context.dsh;
    final bytes = controller.bytes;
    final failed = i18n.t('sidebarImage', 'failed');
    if (bytes == null) {
      return Center(
        child: Text(
          i18n.t('sidebarImage', 'unsupported'),
          style: theme
              .textStyle('--dsw-font-s-14')
              .copyWith(color: theme.labelSecondary),
        ),
      );
    }
    return InteractiveViewer(
      key: const ValueKey('document-image'),
      minScale: 1,
      maxScale: 8,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(theme.radiusMd),
            child: Image.memory(
              bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              semanticLabel: i18n.t(
                'sidebarImage',
                'preview',
                params: {'name': name},
              ),
              errorBuilder: (_, _, _) => Text(
                failed,
                style: theme
                    .textStyle('--dsw-font-s-14')
                    .copyWith(color: theme.labelSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
