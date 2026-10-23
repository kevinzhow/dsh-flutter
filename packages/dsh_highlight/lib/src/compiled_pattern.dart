import 'onig_translator.dart';

/// One match: capture ranges in Oniguruma numbering.
///
/// Dart's `Match` has no capture offsets. Texts come straight from the match;
/// offsets of captures other than the whole match are recovered on demand by
/// re-running a marker-instrumented twin of the pattern anchored at the match
/// start (see [TranslatedPattern.markerMap]), so searches that never need
/// offsets, and losing candidates, pay nothing for them.
class OnigMatch {
  OnigMatch(this._match, this._pattern, this._searchText, this._offset);

  final Match _match;
  final CompiledPattern _pattern;
  final String _searchText;
  final int _offset;
  Match? _marked;
  bool _markedTried = false;

  TranslatedPattern get _t => _pattern._translated;

  /// Number of Oniguruma capture groups (not counting group 0).
  int get groupCount => _t.groupMap.length - 1;

  /// Start of capture [i], or -1 when the group did not participate. Offsets of
  /// groups other than 0 are only available for groups named in
  /// `positionGroups` at compile time.
  int start(int i) {
    if (i == 0) return _match.start + _offset;
    if (i >= _t.groupMap.length) return -1;
    final g = _t.groupMap[i];
    if (g == 0) return -1;
    if (_match.group(g) == null) return -1;
    if (_t.markerMap[i] == -1) return _match.start + _offset;
    final marked = _markedMatch();
    if (marked == null) return -1;
    final mt = _pattern._markedTranslated!;
    final marker = mt.markerMap[i];
    if (marker <= 0) {
      throw StateError('offset of capture $i was not requested');
    }
    final text = marked.group(marker);
    if (text == null) return -1;
    return text.length + _offset;
  }

  /// End of capture [i], or -1 when the group did not participate.
  int end(int i) {
    if (i == 0) return _match.end + _offset;
    final s = start(i);
    if (s < 0) return -1;
    return s + _match.group(_t.groupMap[i])!.length;
  }

  /// Text of capture [i] ('' when the group did not participate).
  String text(int i) {
    if (i == 0) return _match.group(0)!;
    if (i >= _t.groupMap.length) return '';
    final g = _t.groupMap[i];
    if (g == 0) return '';
    return _match.group(g) ?? '';
  }

  Match? _markedMatch() {
    if (!_markedTried) {
      _markedTried = true;
      final re = _pattern._markedRegex();
      if (re != null) {
        _marked = re.matchAsPrefix(_searchText, _match.start);
      }
    }
    return _marked;
  }
}

/// An Oniguruma pattern compiled to a Dart RegExp.
class CompiledPattern {
  CompiledPattern._(
    this.regex,
    this._translated,
    this._source,
    this._positionGroups,
  );

  final RegExp regex;
  final TranslatedPattern _translated;
  final String _source;
  final Set<int> _positionGroups;
  TranslatedPattern? _markedTranslated;
  RegExp? _markedRe;
  bool _markedFailed = false;

  /// The result depends on the search start itself (`\G`), not only on the
  /// text: such results cannot be reused for a later start.
  bool get startDependent =>
      _translated.anchoredAtSearchStart || _translated.clipSearch;

  /// The Dart source (for diagnostics and tests).
  String get dartSource => _translated.source;

  /// Compiles [onigSource]. [positionGroups] are the capture numbers whose
  /// offsets will be asked of matches. Throws [TranslationException] /
  /// [FormatException] when the pattern cannot be translated.
  static CompiledPattern compile(
    String onigSource, {
    Set<int> positionGroups = const {},
  }) {
    final t = translateOnigPattern(onigSource);
    final re = RegExp(
      t.source,
      unicode: true,
      caseSensitive: !t.caseInsensitive,
    );
    return CompiledPattern._(re, t, onigSource, positionGroups);
  }

  /// Compiles, or returns null with [onError] told why.
  static CompiledPattern? tryCompile(
    String onigSource, {
    Set<int> positionGroups = const {},
    void Function(String reason)? onError,
  }) {
    try {
      return compile(onigSource, positionGroups: positionGroups);
    } on TranslationException catch (e) {
      onError?.call(e.message);
    } on FormatException catch (e) {
      onError?.call('dart regexp: ${e.message}');
    } on Object catch (e) {
      onError?.call('internal: $e');
    }
    return null;
  }

  RegExp? _markedRegex() {
    if (_markedRe != null || _markedFailed) return _markedRe;
    try {
      final t = translateOnigPattern(_source, positionGroups: _positionGroups);
      _markedTranslated = t;
      _markedRe = RegExp(
        t.source,
        unicode: true,
        caseSensitive: !t.caseInsensitive,
      );
    } on Object {
      _markedFailed = true;
    }
    return _markedRe;
  }

  // One-entry result cache. A match found from position p is still the answer
  // for any later start up to the match itself, and "no match" stays valid for
  // every later start; patterns are shared by all scanners that include them,
  // so this is where the per-line reuse pays off.
  String? _cacheText;
  int _cacheFrom = -1;
  OnigMatch? _cacheHit;

  /// [search] with the per-text result cache (not for `\G`-dependent patterns,
  /// which fall through to a plain search).
  OnigMatch? searchCached(String text, int start) {
    if (startDependent) return search(text, start);
    if (identical(text, _cacheText) &&
        start >= _cacheFrom &&
        (_cacheHit == null || start <= _cacheHit!.start(0))) {
      return _cacheHit;
    }
    final m = search(text, start);
    _cacheText = text;
    _cacheFrom = start;
    _cacheHit = m;
    return m;
  }

  /// The first match at or after [start] (only at [start] for `\G`-anchored
  /// patterns).
  OnigMatch? search(String text, int start) {
    final t = _translated;
    if (t.clipSearch && start > 0) {
      final clipped = text.substring(start);
      final m = t.anchoredAtSearchStart
          ? regex.matchAsPrefix(clipped, 0)
          : _first(clipped, 0);
      return m == null ? null : OnigMatch(m, this, clipped, start);
    }
    final Match? m;
    if (t.anchoredAtSearchStart) {
      m = regex.matchAsPrefix(text, start);
    } else {
      m = _first(text, start);
    }
    return m == null ? null : OnigMatch(m, this, text, 0);
  }

  Match? _first(String text, int start) {
    final it = regex.allMatches(text, start).iterator;
    return it.moveNext() ? it.current : null;
  }
}
