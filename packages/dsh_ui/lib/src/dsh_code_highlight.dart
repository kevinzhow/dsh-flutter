import 'dart:async';

import 'package:flutter/widgets.dart';

import 'dsh_code_breaks.g.dart';
import 'theme_access.dart';

/// The colour classes of dsh's syntax highlighter (shiki's css-variables
/// theme): each resolves to a `--shiki-token-*` theme token.
enum DshCodeToken {
  constant('--shiki-token-constant'),
  string('--shiki-token-string'),
  comment('--shiki-token-comment'),
  keyword('--shiki-token-keyword'),
  parameter('--shiki-token-parameter'),
  function('--shiki-token-function'),
  stringExpression('--shiki-token-string-expression'),
  punctuation('--shiki-token-punctuation'),
  link('--shiki-token-link');

  const DshCodeToken(this.tokenName);
  final String tokenName;
}

/// A run of code in one colour class ([token] null is the foreground).
class DshCodeSpan {
  const DshCodeSpan(
    this.text, [
    this.token,
    this.italic = false,
    this.bold = false,
    this.underline = false,
  ]);

  final String text;
  final DshCodeToken? token;
  final bool italic;
  final bool bold;
  final bool underline;

  @override
  bool operator ==(Object other) =>
      other is DshCodeSpan &&
      other.text == text &&
      other.token == token &&
      other.italic == italic &&
      other.bold == bold &&
      other.underline == underline;

  @override
  int get hashCode => Object.hash(text, token, italic, bold, underline);

  @override
  String toString() => 'DshCodeSpan($text, $token)';
}

/// What a code surface needs from a syntax highlighter (dsh's one shared
/// shiki highlighter): a synchronous answer, plain text until the language's
/// grammar has loaded, and a signal to repaint when it has.
abstract interface class DshCodeHighlighter {
  /// One list of spans per line of [code] (split on `\n`; the span texts of a
  /// line concatenate to that line), or null when [lang] has no grammar or it
  /// has not loaded yet. Whole-window tokenization keeps multi-line state.
  List<List<DshCodeSpan>>? highlight(String code, String? lang);

  /// Starts loading the grammar of [lang] if it is not loaded.
  void prepare(String? lang);

  /// Fires when a grammar finished loading.
  Stream<void> get loaded;
}

/// Gives the code surfaces below it a [DshCodeHighlighter]; without one they
/// draw plain monospace (dsh: an unknown language is plain text, never an
/// error).
class DshCodeHighlighting extends InheritedWidget {
  const DshCodeHighlighting({
    super.key,
    required this.highlighter,
    required super.child,
  });

  final DshCodeHighlighter? highlighter;

  static DshCodeHighlighter? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DshCodeHighlighting>()
      ?.highlighter;

  @override
  bool updateShouldNotify(DshCodeHighlighting old) =>
      old.highlighter != highlighter;
}

/// Marks the line-break opportunities of dsh's wrapped code the way Chromium
/// has them (CSS `white-space: pre-wrap`): a zero-width space between two
/// printable ASCII characters where Chromium may break, a word joiner where it
/// may not ([dshCodeBreakTable], measured by tool/linebreak/gen-code-breaks.mjs).
/// Flutter's breaker follows other rules in the details that matter for source
/// code (it keeps `{ name` together, it may break between `}` and a backtick).
/// Other characters keep the engine's own rules (ideographs break anywhere in
/// both).
bool _printable(int c) => c >= 0x20 && c <= 0x7e;

bool _word(int c) =>
    (c >= 0x30 && c <= 0x39) ||
    (c >= 0x41 && c <= 0x5a) ||
    (c >= 0x61 && c <= 0x7a);

String dshWrapBreaks(String text, {String? next}) {
  if (text.isEmpty) return text;
  final out = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final a = text.codeUnitAt(i);
    out.writeCharCode(a);
    // The last character looks at the first of the following run (if any).
    final int b;
    if (i + 1 < text.length) {
      b = text.codeUnitAt(i + 1);
    } else if (next != null && next.isNotEmpty) {
      b = next.codeUnitAt(0);
    } else {
      break;
    }
    // Only the pairs the two breakers can disagree on get a marker: after a
    // space, and between two punctuation marks (letters, digits and the
    // spaces after them are the same for both).
    if (_printable(a) && _printable(b) && b != 0x20 && !_word(a)) {
      final allowed = dshCodeBreakTable[a - 0x20].codeUnitAt(b - 0x20) == 0x31;
      out.writeCharCode(allowed ? 0x200B : 0x2060);
    }
  }
  return out.toString();
}

/// Spans coloured for the ambient theme. [wrap] adds the `pre-wrap` break
/// opportunities of [dshWrapBreaks].
List<InlineSpan> dshStyledSpans(
  BuildContext context,
  List<DshCodeSpan> spans,
  TextStyle base, {
  bool wrap = false,
}) {
  final theme = context.dsh;
  Color color(DshCodeSpan s) => s.token == null
      ? theme.color('--shiki-foreground')
      : theme.color(s.token!.tokenName);
  return [
    for (var i = 0; i < spans.length; i++)
      TextSpan(
        text: wrap
            ? dshWrapBreaks(
                spans[i].text,
                next: i + 1 < spans.length ? spans[i + 1].text : null,
              )
            : spans[i].text,
        style: base.copyWith(
          color: color(spans[i]),
          fontStyle: spans[i].italic ? FontStyle.italic : null,
          fontWeight: spans[i].bold ? FontWeight.bold : null,
          decoration: spans[i].underline ? TextDecoration.underline : null,
          // CSS draws the underline in the colour of its span.
          decorationColor: spans[i].underline ? color(spans[i]) : null,
        ),
      ),
  ];
}

/// Keeps a widget in step with a [DshCodeHighlighter]: asks for the grammar of
/// the current language and rebuilds when any grammar loads.
mixin DshHighlightListener<T extends StatefulWidget> on State<T> {
  DshCodeHighlighter? _bound;
  StreamSubscription<void>? _sub;

  /// Counts grammar loads seen; a cache of highlighted text is stale when it
  /// changes.
  int highlightRevision = 0;

  /// The language this surface highlights; read on every dependency change.
  String? get highlightLang;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final h = DshCodeHighlighting.of(context);
    if (!identical(h, _bound)) {
      _sub?.cancel();
      _bound = h;
      _sub = h?.loaded.listen((_) {
        if (!mounted) return;
        highlightRevision++;
        setState(() {});
      });
    }
    h?.prepare(highlightLang);
  }

  @override
  void didUpdateWidget(T oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bound?.prepare(highlightLang);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// The body of a code card: the source inside dsh's `6 22 20` padding, wrapped
/// to the card or, unwrapped, scrolling sideways. The scroller spans the whole
/// card and the padding scrolls with the source (CSS `overflow-x: auto` on the
/// padded `pre`), so unwrapped text runs through the side padding up to the
/// card's edge.
class DshCodeBody extends StatelessWidget {
  const DshCodeBody({super.key, required this.wrapped, required this.child});

  final bool wrapped;
  final Widget child;

  static const EdgeInsets padding = EdgeInsets.fromLTRB(22, 6, 22, 20);

  @override
  Widget build(BuildContext context) {
    if (wrapped) return Padding(padding: padding, child: child);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: constraints.maxWidth),
          child: IntrinsicWidth(
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}
