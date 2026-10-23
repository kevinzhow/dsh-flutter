import 'dart:async';

import 'package:dsh_highlight/dsh_highlight.dart';
import 'package:dsh_highlight/dsh_highlight_flutter.dart';

import 'dsh_code_highlight.dart';
import 'dsh_code_language.dart';

/// dsh's one syntax highlighter over the TextMate engine of `dsh_highlight`
/// (the same grammars and colour classes as dsh web's shiki). The grammars of
/// TypeScript, shell and JSON load at start like dsh's boot set; every other
/// language loads the first time a surface asks for it, drawing plain text
/// until then. An unknown or absent language is plain text, never an error.
class DshSyntaxHighlighter implements DshCodeHighlighter {
  DshSyntaxHighlighter(this.engine) {
    for (final id in _boot) {
      unawaited(_load(id));
    }
  }

  /// A highlighter over the grammars bundled with the app.
  static Future<DshSyntaxHighlighter> assets() async =>
      DshSyntaxHighlighter(HighlightEngine(await AssetGrammarSource.create()));

  /// The grammars dsh loads at boot.
  static const List<String> _boot = ['typescript', 'shellscript', 'json'];

  final HighlightEngine engine;
  final StreamController<void> _loaded = StreamController<void>.broadcast();
  final Set<String> _loading = {};
  ({String id, String code, List<List<DshCodeSpan>> lines})? _memo;

  /// The grammar id a language hint resolves to (dsh `grammarForHint`), or null.
  static String? grammarOf(String? lang) =>
      lang == null ? null : dshGrammarByHintOf(lang.toLowerCase());

  Future<void> _load(String id) async {
    if (engine.isLoaded(id) || !_loading.add(id)) return;
    try {
      await engine.load(id);
    } finally {
      _loading.remove(id);
    }
    if (!_loaded.isClosed) _loaded.add(null);
  }

  @override
  void prepare(String? lang) {
    final id = grammarOf(lang);
    if (id != null && engine.available.contains(id)) unawaited(_load(id));
  }

  @override
  Stream<void> get loaded => _loaded.stream;

  @override
  List<List<DshCodeSpan>>? highlight(String code, String? lang) {
    final id = grammarOf(lang);
    if (id == null || !engine.isLoaded(id)) return null;
    final memo = _memo;
    if (memo != null && memo.id == id && memo.code == code) return memo.lines;
    final raw = engine.highlightLines(code, id);
    if (raw == null) return null;
    final lines = [
      for (final line in raw)
        [
          for (final s in line)
            DshCodeSpan(
              s.text,
              s.token == null ? null : DshCodeToken.values[s.token!.index],
              s.italic,
              s.bold,
              s.underline,
            ),
        ],
    ];
    // The engine drops the empty last line of a trailing newline; surfaces
    // index lines by the text's own split.
    final expected = '\n'.allMatches(code).length + 1;
    while (lines.length < expected) {
      lines.add(const [DshCodeSpan('')]);
    }
    _memo = (id: id, code: code, lines: lines);
    return lines;
  }
}
