import 'dart:async';

import 'package:flutter/widgets.dart';

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

/// Spans coloured for the ambient theme.
List<InlineSpan> dshStyledSpans(
  BuildContext context,
  List<DshCodeSpan> spans,
  TextStyle base,
) {
  final theme = context.dsh;
  return [
    for (final s in spans)
      TextSpan(
        text: s.text,
        style: base.copyWith(
          color: s.token == null
              ? theme.color('--shiki-foreground')
              : theme.color(s.token!.tokenName),
          fontStyle: s.italic ? FontStyle.italic : null,
          fontWeight: s.bold ? FontWeight.bold : null,
          decoration: s.underline ? TextDecoration.underline : null,
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
