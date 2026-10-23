import 'dart:async';
import 'dart:convert';

import 'api.dart';
import 'rules.dart';
import 'theme.dart';
import 'tokenizer.dart';

class _Registration {
  _Registration(this.name, this.scopeName, this.json, this.embeddedLangs);
  final String name;
  final String scopeName;
  final Map<String, dynamic> json;
  final List<String> embeddedLangs;
}

/// How many of a grammar's regexes were translated, and why the others were
/// degraded to "never matches".
class PatternStats {
  const PatternStats({
    required this.total,
    required this.unique,
    required this.degraded,
    required this.reasons,
  });

  /// Regex fields (match / begin / end / while) in the grammar.
  final int total;

  /// Distinct regex sources among them.
  final int unique;

  /// Distinct sources that could not be translated.
  final int degraded;

  /// Degradation reason -> distinct sources.
  final Map<String, int> reasons;

  int get translated => unique - degraded;
}

/// Colours code like dsh web: TextMate grammars (shiki's) tokenized by a Dart
/// port of vscode-textmate, scopes mapped to the nine `--shiki-token-*`
/// classes by shiki's css-variables theme.
///
/// The engine itself is pure Dart; grammars come from a [GrammarSource].
class HighlightEngine implements GrammarRepository {
  HighlightEngine(
    this._source, {
    this.maxLineLength = 1000,
    this.lineTimeLimit = const Duration(milliseconds: 500),
  });

  final GrammarSource _source;

  /// Lines at least this many UTF-16 units long are one uncoloured span (dsh:
  /// `TOKENIZE_MAX_LINE_LENGTH`).
  final int maxLineLength;

  /// Per-line tokenizing budget (shiki: `tokenizeTimeLimit`, 500 ms). A line
  /// that exceeds it keeps the tokens produced so far and the last token
  /// extends to the end of the line.
  final Duration lineTimeLimit;

  final Map<String, _Registration> _byName = {};
  final Map<String, _Registration> _byScope = {};
  final Map<String, List<String>> _injectTo = {};
  final Map<String, Future<void>> _inflight = {};
  final Set<String> _failed = {};
  final Map<String, Grammar> _grammars = {};
  final PatternCache _patterns = PatternCache();
  final StreamController<void> _loaded = StreamController<void>.broadcast();
  int _loadCount = 0;

  /// Grammar ids this engine's source can provide.
  Set<String> get available => _source.available;

  /// Whether [grammarId] is loaded (with the embedded grammars it needs).
  bool isLoaded(String grammarId) => _byName.containsKey(grammarId);

  /// Ids whose last load attempt failed (unreadable or invalid JSON).
  Set<String> get failedLoads => Set.unmodifiable(_failed);

  /// Number of completed loads; changes whenever [loaded] fires.
  int get loadCount => _loadCount;

  /// Fires after a [load] has registered a grammar (dsh: subscribeGrammarLoaded).
  Stream<void> get loaded => _loaded.stream;

  /// Loads [grammarId] and the grammars it embeds. Idempotent; concurrent calls
  /// share one load. An id the source does not provide, or one that fails to
  /// read, completes normally and stays unloaded (see [failedLoads]).
  Future<void> load(String grammarId) {
    if (_byName.containsKey(grammarId)) return Future<void>.value();
    if (!_source.available.contains(grammarId)) return Future<void>.value();
    return _inflight[grammarId] ??= _loadClosure(grammarId).whenComplete(() {
      _inflight.remove(grammarId);
    });
  }

  Future<void> _loadClosure(String grammarId) async {
    final fetched = <String, _Registration>{};
    final queue = <String>[grammarId];
    try {
      while (queue.isNotEmpty) {
        final id = queue.removeLast();
        if (_byName.containsKey(id) || fetched.containsKey(id)) continue;
        if (!_source.available.contains(id)) continue;
        final text = await _source.read(id);
        final json = jsonDecode(text) as Map<String, dynamic>;
        final reg = _Registration(
          json['name'] as String? ?? id,
          json['scopeName'] as String,
          json,
          [
            for (final e
                in (json['embeddedLangs'] as List<dynamic>? ?? const []))
              e as String,
          ],
        );
        fetched[id] = reg;
        queue.addAll(reg.embeddedLangs);
      }
    } on Object {
      _failed.add(grammarId);
      return;
    }
    _failed.remove(grammarId);
    for (final reg in fetched.values) {
      _byName[reg.name] = reg;
      _byScope[reg.scopeName] = reg;
      for (final target
          in (reg.json['injectTo'] as List<dynamic>? ?? const [])) {
        (_injectTo[target as String] ??= []).add(reg.scopeName);
      }
    }
    _grammars.clear();
    _loadCount++;
    _loaded.add(null);
  }

  /// One list of spans per line of [code], tokenized as a whole window so
  /// multi-line constructs keep their state.
  ///
  /// Lines are separated by `\n` (a `\r` before it is dropped, as shiki's line
  /// splitting does); like dsh's `highlightLines`, a final empty line produced
  /// by a trailing newline is not returned. An empty line is an empty list.
  /// Lines of [maxLineLength] or more units are one uncoloured span and leave
  /// the grammar state unchanged.
  ///
  /// Returns null when [grammarId] is unsupported or not loaded yet: show plain
  /// text and re-render on [loaded].
  List<List<HighlightSpan>>? highlightLines(String code, String grammarId) {
    final reg = _byName[grammarId];
    if (reg == null) return null;
    final grammar = _grammars[reg.scopeName] ??= Grammar(
      reg.scopeName,
      this,
      _patterns,
    );
    final lines = _splitLines(code);
    final out = <List<HighlightSpan>>[];
    StateStack? state;
    final limit = lineTimeLimit.inMilliseconds;
    for (final line in lines) {
      if (line.isEmpty) {
        out.add(const []);
        continue;
      }
      if (maxLineLength > 0 && line.length >= maxLineLength) {
        out.add([HighlightSpan(line)]);
        continue;
      }
      final r = grammar.tokenizeLine(line, state, limit);
      state = r.ruleStack;
      if (r.stoppedEarly) _timedOutLines++;
      out.add(_spans(line, r.tokens));
    }
    if (out.length > 1 && out.last.isEmpty && lines.last.isEmpty) {
      out.removeLast();
    }
    return out;
  }

  static List<String> _splitLines(String code) {
    if (code.isEmpty) return const [''];
    final parts = code.split('\n');
    return [
      for (final p in parts)
        if (p.endsWith('\r')) p.substring(0, p.length - 1) else p,
    ];
  }

  List<HighlightSpan> _spans(String line, List<int> tokens) {
    final spans = <HighlightSpan>[];
    final n = tokens.length ~/ 2;
    HighlightToken? lastToken;
    var lastFont = -1;
    var lastStart = 0;
    for (var j = 0; j < n; j++) {
      final start = tokens[2 * j];
      final end = j + 1 < n ? tokens[2 * j + 2] : line.length;
      if (start >= end || start >= line.length) continue;
      final attrs = tokens[2 * j + 1];
      final token = colorTokens[attrColor(attrs)];
      final font = attrFontStyle(attrs);
      if (lastFont != -1 && token == lastToken && font == lastFont) {
        continue; // extends the previous span; flushed below
      }
      if (lastFont != -1) {
        spans.add(_span(line.substring(lastStart, start), lastToken, lastFont));
      }
      lastToken = token;
      lastFont = font;
      lastStart = start;
    }
    if (lastFont != -1) {
      spans.add(_span(line.substring(lastStart), lastToken, lastFont));
    } else {
      spans.add(HighlightSpan(line));
    }
    return spans;
  }

  static HighlightSpan _span(String text, HighlightToken? token, int font) =>
      HighlightSpan(
        text,
        token,
        font & fontItalic != 0,
        font & fontBold != 0,
        font & fontUnderline != 0,
      );

  // --- statistics ---------------------------------------------------------------

  /// Translator coverage of one loaded grammar's own regexes (not those of the
  /// grammars it embeds).
  PatternStats? patternStats(String grammarId) {
    final reg = _byName[grammarId];
    if (reg == null) return null;
    final sources = <String>[];
    void walk(Object? node) {
      if (node is Map) {
        for (final key in const ['match', 'begin', 'end', 'while']) {
          final v = node[key];
          if (v is String && v.isNotEmpty) sources.add(v);
        }
        for (final v in node.values) {
          walk(v);
        }
      } else if (node is List) {
        for (final v in node) {
          walk(v);
        }
      }
    }

    walk(reg.json['patterns']);
    walk(reg.json['repository']);
    walk(reg.json['injections']);
    final unique = sources.toSet();
    final cache = PatternCache();
    final reasons = <String, int>{};
    var degraded = 0;
    for (final s in unique) {
      if (cache.get(s, const {}) == null) {
        degraded++;
        final why = cache.failures[s] ?? 'unknown';
        reasons[why] = (reasons[why] ?? 0) + 1;
      }
    }
    return PatternStats(
      total: sources.length,
      unique: unique.length,
      degraded: degraded,
      reasons: reasons,
    );
  }

  /// Lines that hit [lineTimeLimit] so far (their last token runs to the end of
  /// the line).
  int get timedOutLines => _timedOutLines;
  int _timedOutLines = 0;

  /// Distinct sources the engine degraded while tokenizing so far.
  int get degradedPatternCount => _patterns.failures.length;

  // --- GrammarRepository -----------------------------------------------------------

  @override
  Map<String, dynamic>? rawGrammarJson(String scopeName) =>
      _byScope[scopeName]?.json;

  @override
  List<String> injectionScopeNames(String targetScope) {
    final parts = targetScope.split('.');
    final out = <String>[];
    for (var i = 1; i <= parts.length; i++) {
      out.addAll(_injectTo[parts.sublist(0, i).join('.')] ?? const []);
    }
    return out;
  }
}
