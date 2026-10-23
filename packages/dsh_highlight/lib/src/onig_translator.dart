// Oniguruma -> Dart RegExp pattern translator.
//
// TextMate grammars are written for Oniguruma; Dart's `RegExp` is a JS-like
// engine. This is a translator in the spirit of oniguruma-to-es (the engine
// shiki's JavaScript regex engine uses), producing a pattern for
// `RegExp(source, unicode: true)`. Where Oniguruma has a feature Dart lacks it
// is emulated (atomic groups and possessive quantifiers through a lookahead
// plus backreference, class intersections and negated nested classes through
// lookaheads, `\K` as a lookbehind, subroutine calls by inlining up to a depth
// limit, `\G` through a sticky/clipped search). A pattern that cannot be
// translated throws [TranslationException]; callers degrade such a pattern to
// "never matches" and count it. The translator never produces a RegExp itself,
// so it is unit-testable as pure string-to-string.
library;

/// Thrown when a pattern is invalid or uses a feature this translator cannot
/// reproduce.
class TranslationException implements Exception {
  const TranslationException(this.message);
  final String message;
  @override
  String toString() => 'TranslationException: $message';
}

/// Result of translating one Oniguruma pattern.
class TranslatedPattern {
  const TranslatedPattern({
    required this.source,
    required this.groupMap,
    required this.markerMap,
    required this.anchoredAtSearchStart,
    required this.clipSearch,
    required this.caseInsensitive,
  });

  /// Source for `RegExp(source, unicode: true)`.
  final String source;

  /// Oniguruma capture number -> Dart capture number (index 0 is the whole
  /// match). Dart has extra hidden groups where atomic groups are emulated.
  final List<int> groupMap;

  /// Dart's `Match` has no capture offsets, so a group whose position is
  /// needed gets a marker group `(?<=([\s\S]*))` as its first element; the
  /// marker's text length is the group's start offset. Oniguruma capture
  /// number -> Dart number of its marker (0: no marker; -1: the group starts
  /// where the whole match starts).
  final List<int> markerMap;

  /// The pattern starts with `\G` in every alternative: it can only match at
  /// the position the search started from (use `matchAsPrefix`).
  final bool anchoredAtSearchStart;

  /// Compile with `caseSensitive: false`. Dart's `(?i:...)` modifier groups
  /// are unreliable (alternations inside them can miss capitalised input), so
  /// a pattern that is case-insensitive throughout uses the flag, and one
  /// that mixes both gets its case-insensitive parts expanded by hand.
  final bool caseInsensitive;

  /// The pattern uses `\G` somewhere else: search the text clipped at the
  /// search start, so `\G` can be `^`.
  final bool clipSearch;
}

/// Maximum nesting when inlining subroutine calls (`\g<name>`), as in
/// oniguruma-to-es's `recursionLimit` rule used by shiki.
const int _recursionLimit = 5;

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

sealed class _Node {}

class _Lit extends _Node {
  _Lit(this.cp);
  final int cp;
}

/// A fragment that matches exactly one character and can take a quantifier.
class _Atom extends _Node {
  _Atom(this.text);
  final String text;
}

/// A bracket class (possibly with nesting / intersection).
class _ClassNode extends _Node {
  _ClassNode(this.negated, this.operands);
  final bool negated;
  // Intersection operands (a&&b&&c); each operand is a union of items.
  final List<List<_ClassItem>> operands;
}

class _Assertion extends _Node {
  _Assertion(this.text);
  final String text;
}

/// `\G`.
class _SearchStart extends _Node {}

/// `\K`.
class _Keep extends _Node {}

enum _GroupKind {
  capture,
  plain,
  ahead,
  notAhead,
  behind,
  notBehind,
  atomic,
  absence,
}

class _Group extends _Node {
  _Group(this.kind, this.alts, {this.index = 0});
  final _GroupKind kind;
  final List<List<_Node>> alts;
  // Capture number for [_GroupKind.capture].
  final int index;
}

/// `(?i:...)` / `(?-i:...)`; the only flag Dart needs to be told about (m and x
/// are resolved while parsing).
class _CaseGroup extends _Node {
  _CaseGroup(this.ignoreCase, this.alts);
  final bool ignoreCase;
  final List<List<_Node>> alts;
}

class _BackrefNum extends _Node {
  _BackrefNum(this.number);
  final int number;
}

/// `\10` and friends: a backreference when that many groups exist, else an
/// octal escape or identity escape.
class _AmbiguousNumber extends _Node {
  _AmbiguousNumber(this.digits);
  final String digits;
}

class _BackrefName extends _Node {
  _BackrefName(this.name);
  final String name;
}

class _Call extends _Node {
  _Call({this.number, this.name});
  final int? number;
  final String? name;
}

class _Quant extends _Node {
  _Quant(this.body, this.min, this.max, this.mode);
  final _Node body;
  final int min;
  final int max; // -1 = unbounded
  final _QMode mode;
}

enum _QMode { greedy, lazy, possessive }

sealed class _ClassItem {}

class _CChar extends _ClassItem {
  _CChar(this.lo, [int? hi]) : hi = hi ?? lo;
  final int lo;
  final int hi;
}

/// Raw fragment valid inside `[...]` (e.g. `\p{Nd}`).
class _CRaw extends _ClassItem {
  _CRaw(this.text);
  final String text;
}

class _CNested extends _ClassItem {
  _CNested(this.node);
  final _ClassNode node;
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

/// Translates [pattern] (Oniguruma syntax, as TextMate grammars use it with
/// ONIG_OPTION_CAPTURE_GROUP) to a Dart RegExp source.
///
/// Throws [TranslationException] for invalid or unsupported patterns.
///
/// [positionGroups] are the capture numbers whose offsets the caller needs
/// (see [TranslatedPattern.markerMap]).
TranslatedPattern translateOnigPattern(
  String pattern, {
  Set<int> positionGroups = const {},
}) {
  final parser = _Parser(pattern);
  final root = parser.parse();
  final emitter = _Emitter(parser, positionGroups);
  return emitter.emit(root);
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

bool _isDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isHex(int c) =>
    _isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66);
bool _isOctal(int c) => c >= 0x30 && c <= 0x37;
bool _isAlpha(int c) => (c >= 0x41 && c <= 0x5a) || (c >= 0x61 && c <= 0x7a);
bool _isWordAscii(int c) => _isAlpha(c) || _isDigit(c) || c == 0x5f;

class _Parser {
  _Parser(String pattern) : _s = pattern.runes.toList(growable: false);

  final List<int> _s;
  int _p = 0;

  bool _extended = false;
  bool _dotAll = false;
  bool _ci = false;

  int groupCount = 0;
  final Map<int, _Group> groupsByIndex = {};
  final Map<String, List<int>> groupsByName = {};
  late List<List<_Node>> rootAlts;

  bool get _eof => _p >= _s.length;
  int get _peek => _s[_p];
  int? _peekAt(int offset) => _p + offset < _s.length ? _s[_p + offset] : null;

  List<List<_Node>> parse() {
    rootAlts = _parseAlts(topLevel: true);
    if (!_eof) throw const TranslationException('unmatched close parenthesis');
    return rootAlts;
  }

  /// Parses alternatives until `)` (not consumed) or the end.
  ///
  /// An inline flag directive `(?i)` stays in force to the end of the
  /// enclosing group, across the following alternatives, but the alternation
  /// itself is kept: `a(?i)b|c` is `a(?i:b)|(?i:c)` (what oniguruma-to-es,
  /// and so shiki, produces).
  List<List<_Node>> _parseAlts({required bool topLevel}) {
    final baseCi = _ci;
    final alts = <List<_Node>>[];
    var altNodes = <_Node>[];
    var cur = <_Node>[];
    var segCi = _ci;
    void flush() {
      if (segCi == baseCi) {
        altNodes.addAll(cur);
      } else if (cur.isNotEmpty) {
        altNodes.add(_CaseGroup(segCi, [cur]));
      }
      cur = <_Node>[];
    }

    while (!_eof) {
      final c = _peek;
      if (c == 0x29) {
        if (topLevel) {
          throw const TranslationException('unmatched close parenthesis');
        }
        break;
      }
      if (c == 0x7c) {
        _p++;
        flush();
        alts.add(altNodes);
        altNodes = <_Node>[];
        segCi = _ci;
        continue;
      }
      if (_extended && _skipExtended()) continue;
      final atom = _parseAtom();
      if (atom == null) continue;
      if (atom is _FlagDirective) {
        _applyDirective(atom);
        if (_ci != segCi) {
          flush();
          segCi = _ci;
        }
        continue;
      }
      cur.add(_parseQuantifiers(atom as _Node));
    }
    flush();
    alts.add(altNodes);
    return alts;
  }

  /// Skips whitespace and `#` comments in extended mode; true if it skipped.
  bool _skipExtended() {
    final c = _peek;
    if (c == 0x20 ||
        (c >= 0x09 && c <= 0x0d) ||
        c == 0x85 ||
        c == 0xa0 ||
        c == 0x2028 ||
        c == 0x2029 ||
        c == 0x1680 ||
        (c >= 0x2000 && c <= 0x200a) ||
        c == 0x202f ||
        c == 0x205f ||
        c == 0x3000) {
      _p++;
      return true;
    }
    if (c == 0x23) {
      while (!_eof && _peek != 0x0a) {
        _p++;
      }
      return true;
    }
    return false;
  }

  void _applyDirective(_FlagDirective d) {
    if (d.caseChange != null) _ci = d.caseChange!;
    if (d.extended != null) _extended = d.extended!;
    if (d.dotAll != null) _dotAll = d.dotAll!;
  }

  // Either a _Node, a _FlagDirective, or null (consumed with no output).
  Object? _parseAtom() {
    final c = _peek;
    switch (c) {
      case 0x5c: // backslash
        return _parseEscape();
      case 0x5b: // [
        _p++;
        return _parseClassBody();
      case 0x28: // (
        return _parseGroup();
      case 0x2e: // .
        _p++;
        return _Atom(_dotAll ? r'[\s\S]' : r'[^\n]');
      case 0x5e: // ^
        _p++;
        return _Assertion('^');
      case 0x24: // $
        _p++;
        return _Assertion(r'(?=\n?$)');
      case 0x2a:
      case 0x2b:
      case 0x3f:
        throw const TranslationException(
          'target of repeat operator is not specified',
        );
      default:
        _p++;
        return _Lit(c);
    }
  }

  // --- quantifiers ---------------------------------------------------------

  _Node _parseQuantifiers(_Node node) {
    while (true) {
      if (_extended) {
        while (!_eof && _skipExtended()) {}
      }
      if (_eof) return node;
      final c = _peek;
      int min;
      int max;
      var possessiveBraces = false;
      if (c == 0x2a) {
        min = 0;
        max = -1;
        _p++;
      } else if (c == 0x2b) {
        min = 1;
        max = -1;
        _p++;
      } else if (c == 0x3f) {
        min = 0;
        max = 1;
        _p++;
      } else if (c == 0x7b) {
        final q = _tryBraces();
        if (q == null) return node;
        min = q.$1;
        max = q.$2;
        possessiveBraces = q.$3;
      } else {
        return node;
      }
      var mode = _QMode.greedy;
      if (possessiveBraces) {
        mode = _QMode.possessive;
      } else if (!_eof) {
        final n = _peek;
        if (n == 0x3f) {
          mode = _QMode.lazy;
          _p++;
        } else if (n == 0x2b && (c != 0x7b)) {
          mode = _QMode.possessive;
          _p++;
        }
      }
      node = _Quant(node, min, max, mode);
    }
  }

  /// `{n}`, `{n,}`, `{n,m}`, `{,m}`; null when it is not a quantifier (then
  /// `{` is a literal). Third value: reversed range = possessive.
  (int, int, bool)? _tryBraces() {
    var i = _p + 1;
    int? readInt() {
      final start = i;
      while (i < _s.length && _isDigit(_s[i])) {
        i++;
      }
      if (i == start) return null;
      final v = int.parse(String.fromCharCodes(_s.sublist(start, i)));
      return v;
    }

    final a = readInt();
    int min;
    int max;
    if (i < _s.length && _s[i] == 0x7d) {
      if (a == null) return null;
      min = a;
      max = a;
      i++;
    } else if (i < _s.length && _s[i] == 0x2c) {
      i++;
      final b = readInt();
      if (i >= _s.length || _s[i] != 0x7d) return null;
      if (a == null && b == null) return null;
      min = a ?? 0;
      max = b ?? -1;
      i++;
    } else {
      return null;
    }
    if (min > 100000 || max > 100000) {
      throw const TranslationException('too big number for repeat range');
    }
    var possessive = false;
    if (max != -1 && min > max) {
      final t = min;
      min = max;
      max = t;
      possessive = true;
    }
    _p = i;
    return (min, max, possessive);
  }

  // --- groups --------------------------------------------------------------

  Object? _parseGroup() {
    // at '('
    _p++;
    if (!_eof && _peek == 0x3f) {
      // (?...)
      _p++;
      if (_eof) throw const TranslationException('end pattern in group');
      final c = _peek;
      switch (c) {
        case 0x3a: // (?:
          _p++;
          return _finishGroup(_GroupKind.plain);
        case 0x3d: // (?=
          _p++;
          return _finishGroup(_GroupKind.ahead);
        case 0x21: // (?!
          _p++;
          return _finishGroup(_GroupKind.notAhead);
        case 0x3e: // (?>
          _p++;
          return _finishGroup(_GroupKind.atomic);
        case 0x7e: // (?~
          _p++;
          if (!_eof && _peek == 0x7c) {
            throw const TranslationException('absence function variants');
          }
          return _finishGroup(_GroupKind.absence);
        case 0x23: // (?# comment )
          _p++;
          while (!_eof && _peek != 0x29) {
            if (_peek == 0x5c) _p++;
            _p++;
          }
          if (_eof) throw const TranslationException('end pattern in group');
          _p++;
          return null;
        case 0x3c: // (?<
          final n = _peekAt(1);
          if (n == 0x3d) {
            _p += 2;
            return _finishGroup(_GroupKind.behind);
          }
          if (n == 0x21) {
            _p += 2;
            return _finishGroup(_GroupKind.notBehind);
          }
          _p++;
          return _namedGroup(0x3e);
        case 0x27: // (?'name'
          _p++;
          return _namedGroup(0x27);
        case 0x28:
          throw const TranslationException('conditional groups');
        case 0x7b:
          throw const TranslationException('callouts');
        default:
          return _flagGroup();
      }
    }
    if (!_eof && _peek == 0x2a) {
      // (*FAIL) and friends
      final start = _p;
      while (!_eof && _peek != 0x29) {
        _p++;
      }
      if (_eof) throw const TranslationException('end pattern in group');
      final name = String.fromCharCodes(_s.sublist(start + 1, _p));
      _p++;
      if (name == 'FAIL' || name == 'F') return _Assertion('(?!)');
      throw TranslationException('callout (*$name)');
    }
    return _finishGroup(_GroupKind.capture);
  }

  _Group _namedGroup(int close) {
    final start = _p;
    while (!_eof && _peek != close) {
      _p++;
    }
    if (_eof) throw const TranslationException('invalid group name');
    final name = String.fromCharCodes(_s.sublist(start, _p));
    _p++;
    if (name.isEmpty ||
        _isDigit(name.codeUnitAt(0)) ||
        name.runes.any((r) => !(_isWordAscii(r) || r > 0x7f))) {
      throw TranslationException('invalid group name <$name>');
    }
    final g = _finishGroup(_GroupKind.capture, name: name);
    return g;
  }

  _Group _finishGroup(_GroupKind kind, {String? name}) {
    var index = 0;
    if (kind == _GroupKind.capture) {
      index = ++groupCount;
      if (name != null) (groupsByName[name] ??= <int>[]).add(index);
    }
    final saved = (_extended, _dotAll, _ci);
    final alts = _parseAlts(topLevel: false);
    _extended = saved.$1;
    _dotAll = saved.$2;
    _ci = saved.$3;
    if (_eof || _peek != 0x29) {
      throw const TranslationException(
        'end pattern with unmatched parenthesis',
      );
    }
    _p++;
    final g = _Group(kind, alts, index: index);
    if (kind == _GroupKind.capture) groupsByIndex[index] = g;
    return g;
  }

  /// `(?imx-imx)` directive or `(?imx-imx:...)` group.
  Object _flagGroup() {
    var on = true;
    bool? ci;
    bool? x;
    bool? m;
    while (true) {
      if (_eof) throw const TranslationException('end pattern in group');
      final c = _peek;
      _p++;
      if (c == 0x2d) {
        on = false;
      } else if (c == 0x69) {
        ci = on;
      } else if (c == 0x78) {
        x = on;
      } else if (c == 0x6d) {
        m = on;
      } else if (c == 0x29) {
        return _FlagDirective(ci, x, m);
      } else if (c == 0x3a) {
        final saved = (_extended, _dotAll, _ci);
        _applyDirective(_FlagDirective(ci, x, m));
        final alts = _parseAlts(topLevel: false);
        _extended = saved.$1;
        _dotAll = saved.$2;
        _ci = saved.$3;
        if (_eof || _peek != 0x29) {
          throw const TranslationException(
            'end pattern with unmatched parenthesis',
          );
        }
        _p++;
        if (ci == null) return _Group(_GroupKind.plain, alts);
        return _CaseGroup(ci, alts);
      } else {
        throw TranslationException(
          'undefined group option (?${String.fromCharCode(c)}',
        );
      }
    }
  }

  // --- escapes -------------------------------------------------------------

  Object _parseEscape() {
    // at backslash
    _p++;
    if (_eof) throw const TranslationException('end pattern at escape');
    final c = _peek;
    _p++;
    switch (c) {
      case 0x64: // d
        return _Atom(r'\p{Nd}');
      case 0x44:
        return _Atom(r'\P{Nd}');
      case 0x77:
        return _Atom(_wordClass);
      case 0x57:
        return _Atom(_notWordClass);
      case 0x73:
        return _Atom(r'\p{space}');
      case 0x53:
        return _Atom(r'\P{space}');
      case 0x68:
        return _Atom(r'\p{AHex}');
      case 0x48:
        return _Atom(r'\P{AHex}');
      case 0x4f: // \O
        return _Atom(r'[\s\S]');
      case 0x4e: // \N
        return _Atom(r'[^\n]');
      case 0x52: // \R
        return _AtomicText(r'\r\n?|[\n\v\f\x85  ]');
      case 0x58: // \X (approximation, like oniguruma-to-es)
        return _AtomicText(r'\r\n|\P{M}\p{M}*');
      case 0x70:
      case 0x50:
        return _parseProperty(negated: c == 0x50);
      case 0x62:
        return _Assertion(r'\b');
      case 0x42:
        return _Assertion(r'\B');
      case 0x41:
        return _Assertion('^');
      case 0x7a:
        return _Assertion(r'$');
      case 0x5a:
        return _Assertion(r'(?=\n?$)');
      case 0x47:
        return _SearchStart();
      case 0x4b:
        return _Keep();
      case 0x79:
      case 0x59:
        throw const TranslationException('text segment boundary \\y');
      case 0x6b:
        return _parseNamedRef();
      case 0x67:
        return _parseCall();
      default:
        break;
    }
    if (c >= 0x31 && c <= 0x39) {
      // \1-\9: a backreference; longer numbers are ambiguous.
      final start = _p - 1;
      var end = _p;
      while (end < _s.length && _isDigit(_s[end])) {
        end++;
      }
      final digits = String.fromCharCodes(_s.sublist(start, end));
      if (digits.length == 1) return _BackrefNum(int.parse(digits));
      _p = end;
      return _AmbiguousNumber(digits);
    }
    _p--; // let the char-escape reader consume it
    return _Lit(_readCharEscape(inClass: false));
  }

  /// Reads the escape char at [_p] (after the backslash), returns the code
  /// point it denotes.
  int _readCharEscape({required bool inClass}) {
    final c = _s[_p++];
    switch (c) {
      case 0x74:
        return 0x09;
      case 0x6e:
        return 0x0a;
      case 0x72:
        return 0x0d;
      case 0x66:
        return 0x0c;
      case 0x76:
        return 0x0b;
      case 0x61:
        return 0x07;
      case 0x65:
        return 0x1b;
      case 0x62:
        if (inClass) return 0x08;
        return 0x62;
      case 0x78: // \x
        if (!_eof && _peek == 0x7b) {
          _p++;
          final start = _p;
          while (!_eof && _isHex(_peek)) {
            _p++;
          }
          if (_eof || _peek != 0x7d || _p == start) {
            throw const TranslationException('invalid code point value');
          }
          final cp = int.parse(
            String.fromCharCodes(_s.sublist(start, _p)),
            radix: 16,
          );
          _p++;
          if (cp > 0x10ffff) {
            throw const TranslationException('too big wide-char value');
          }
          return cp;
        }
        final start = _p;
        while (!_eof && _p - start < 2 && _isHex(_peek)) {
          _p++;
        }
        if (_p == start) return 0x78; // \x without digits: identity
        final v = int.parse(
          String.fromCharCodes(_s.sublist(start, _p)),
          radix: 16,
        );
        if (v > 0x7f) {
          throw const TranslationException('encoded byte escape above \\x7F');
        }
        return v;
      case 0x75: // \uHHHH
        final start = _p;
        while (!_eof && _p - start < 4 && _isHex(_peek)) {
          _p++;
        }
        if (_p - start != 4) {
          throw const TranslationException('too short escape sequence');
        }
        return int.parse(
          String.fromCharCodes(_s.sublist(start, _p)),
          radix: 16,
        );
      case 0x63: // \cX
        if (_eof || !_isAlpha(_peek)) {
          throw const TranslationException('unsupported control character');
        }
        return _s[_p++] & 0x1f;
      case 0x43: // \C-X
        if (_peekAt(0) == 0x2d && _peekAt(1) != null && _isAlpha(_peekAt(1)!)) {
          _p++;
          return _s[_p++] & 0x1f;
        }
        throw const TranslationException('unsupported control character');
      case 0x4d: // \M-
        throw const TranslationException('unsupported meta character');
      case 0x6f: // \o{...}
        if (!_eof && _peek == 0x7b) {
          throw const TranslationException('octal code point');
        }
        return 0x6f;
      default:
        if (c >= 0x30 && c <= 0x37) {
          // \0, \0NN, octal (class context: \1..\7 too)
          var v = c - 0x30;
          var n = 1;
          while (!_eof && n < 3 && _isOctal(_peek)) {
            v = v * 8 + (_peek - 0x30);
            _p++;
            n++;
          }
          if (v > 0xff) {
            throw const TranslationException('too big number');
          }
          if (v > 0x7f) {
            throw const TranslationException('octal byte escape above \\177');
          }
          return v;
        }
        // Identity escape (also for non-ASCII, e.g. `\` + U+FFFF).
        return c;
    }
  }

  _Node _parseProperty({required bool negated}) {
    if (_eof || _peek != 0x7b) {
      // `\p` without `{` is an identity escape.
      return _Lit(negated ? 0x50 : 0x70);
    }
    _p++;
    var neg = negated;
    if (!_eof && _peek == 0x5e) {
      neg = !neg;
      _p++;
    }
    final start = _p;
    while (!_eof && _peek != 0x7d) {
      _p++;
    }
    if (_eof) {
      throw const TranslationException('invalid character property name');
    }
    final name = String.fromCharCodes(_s.sublist(start, _p));
    _p++;
    final items = _propertyItems(name);
    return _classFromItems(items, neg);
  }

  static final RegExp _singleProperty = RegExp(r'^\\[pP]\{[^}]*\}$');

  _Node _classFromItems(List<_ClassItem> items, bool negated) {
    if (items.length == 1 && items.first is _CRaw) {
      final t = (items.first as _CRaw).text;
      if (_singleProperty.hasMatch(t)) {
        if (!negated) return _Atom(t);
        return _Atom((t.startsWith(r'\p') ? r'\P' : r'\p') + t.substring(2));
      }
    }
    return _ClassNode(negated, [items]);
  }

  /// Items (valid inside a class) for a property / POSIX bracket name.
  List<_ClassItem> _propertyItems(String rawName) {
    final key = rawName.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
    switch (key) {
      case 'alnum':
        return [_CRaw(r'\p{Alpha}\p{Nd}')];
      case 'alpha':
        return [_CRaw(r'\p{Alpha}')];
      case 'ascii':
        return [_CRaw(r'\p{ASCII}')];
      case 'blank':
        return [_CRaw(r'\p{Zs}\t')];
      case 'cntrl':
        return [_CRaw(r'\p{Cc}')];
      case 'digit':
        return [_CRaw(r'\p{Nd}')];
      case 'graph':
        return [
          _CNested(
            _ClassNode(false, [
              [_CRaw(r'\P{space}')],
              [_CRaw(r'\P{Cc}')],
              [_CRaw(r'\P{Cn}')],
              [_CRaw(r'\P{Cs}')],
            ]),
          ),
        ];
      case 'print':
        return [
          _CNested(
            _ClassNode(false, [
              [_CRaw(r'\P{space}')],
              [_CRaw(r'\P{Cc}')],
              [_CRaw(r'\P{Cn}')],
              [_CRaw(r'\P{Cs}')],
            ]),
          ),
          _CRaw(r'\p{Zs}'),
        ];
      case 'lower':
        return [_CRaw(r'\p{Lower}')];
      case 'punct':
        return [_CRaw(r'\p{P}\p{S}')];
      case 'space':
        return [_CRaw(r'\p{space}')];
      case 'upper':
        return [_CRaw(r'\p{Upper}')];
      case 'xdigit':
        return [_CRaw(r'\p{AHex}')];
      case 'word':
        return [_CRaw(r'\p{Alpha}\p{M}\p{Nd}\p{Pc}')];
      case 'any':
        return [_CRaw(r'\p{Any}')];
    }
    final frag = _resolveProperty(rawName);
    if (frag == null) {
      throw TranslationException('invalid character property name {$rawName}');
    }
    return [_CRaw(frag)];
  }

  // --- named references / calls --------------------------------------------

  _Node _parseNamedRef() {
    if (_eof || (_peek != 0x3c && _peek != 0x27)) {
      return _Lit(0x6b); // identity escape
    }
    final close = _peek == 0x3c ? 0x3e : 0x27;
    _p++;
    final start = _p;
    while (!_eof && _peek != close) {
      _p++;
    }
    if (_eof) throw const TranslationException('invalid backref');
    final name = String.fromCharCodes(_s.sublist(start, _p));
    _p++;
    final numeric = int.tryParse(name);
    if (numeric != null) {
      if (name.startsWith('-') || name.startsWith('+')) {
        final n = name.startsWith('-')
            ? groupCount + 1 + numeric
            : groupCount + numeric;
        if (n < 1) throw const TranslationException('invalid backref number');
        return _BackrefNum(n);
      }
      if (numeric == 0) throw const TranslationException('invalid backref');
      return _BackrefNum(numeric);
    }
    // Strip a recursion level suffix (`name+0`).
    final plain = name.replaceFirst(RegExp(r'[+-]\d+$'), '');
    return _BackrefName(plain);
  }

  _Node _parseCall() {
    if (_eof || (_peek != 0x3c && _peek != 0x27)) {
      return _Lit(0x67);
    }
    final close = _peek == 0x3c ? 0x3e : 0x27;
    _p++;
    final start = _p;
    while (!_eof && _peek != close) {
      _p++;
    }
    if (_eof) throw const TranslationException('invalid group name');
    final name = String.fromCharCodes(_s.sublist(start, _p));
    _p++;
    final numeric = int.tryParse(name);
    if (numeric != null) {
      if (name.startsWith('-')) {
        final n = groupCount + 1 + numeric;
        if (n < 1) throw const TranslationException('invalid group number');
        return _Call(number: n);
      }
      if (name.startsWith('+')) return _Call(number: groupCount + numeric);
      return _Call(number: numeric);
    }
    return _Call(name: name);
  }

  // --- character classes ---------------------------------------------------

  /// Parses after `[`; returns the class (or an atom for a trivial one).
  _ClassNode _parseClassBody() {
    var negated = false;
    if (!_eof && _peek == 0x5e) {
      negated = true;
      _p++;
    }
    final operands = <List<_ClassItem>>[<_ClassItem>[]];
    var items = operands.last;
    var first = true;
    while (true) {
      if (_eof) throw const TranslationException('premature end of char-class');
      final c = _peek;
      if (c == 0x5d && !first) {
        _p++;
        break;
      }
      first = false;
      if (c == 0x26 && _peekAt(1) == 0x26) {
        _p += 2;
        items = <_ClassItem>[];
        operands.add(items);
        continue;
      }
      if (c == 0x5b) {
        // POSIX bracket or nested class.
        final posix = _tryPosixBracket();
        if (posix != null) {
          items.addAll(posix);
          continue;
        }
        _p++;
        final nested = _parseClassBody();
        items.add(_CNested(nested));
        continue;
      }
      final lo = _readClassAtom(items);
      if (lo == null) {
        // A set followed by `-` and something other than `]`/`&&` is an
        // invalid range in Oniguruma ([\d-z]).
        if (!_eof &&
            _peek == 0x2d &&
            _peekAt(1) != null &&
            _peekAt(1) != 0x5d &&
            !(_peekAt(1) == 0x26 && _peekAt(2) == 0x26)) {
          throw const TranslationException(
            'unmatched range specifier in char-class',
          );
        }
        continue;
      }
      // Range?
      if (!_eof && _peek == 0x2d && _peekAt(1) != null && _peekAt(1) != 0x5d) {
        final save = _p;
        _p++; // '-'
        if (_peek == 0x5b || (_peek == 0x26 && _peekAt(1) == 0x26)) {
          // `a-[` : '-' literal
          _p = save;
          items.add(_CChar(lo));
          continue;
        }
        final tmp = <_ClassItem>[];
        final hi = _readClassAtom(tmp);
        if (hi == null) {
          throw const TranslationException('char-class value at end of range');
        }
        if (hi < lo) {
          throw const TranslationException('empty range in char class');
        }
        items.add(_CChar(lo, hi));
      } else {
        items.add(_CChar(lo));
      }
    }
    return _ClassNode(negated, operands);
  }

  /// `[:name:]` / `[:^name:]` at [_p] (which is `[`).
  List<_ClassItem>? _tryPosixBracket() {
    if (_peekAt(1) != 0x3a) return null;
    var i = _p + 2;
    var neg = false;
    if (i < _s.length && _s[i] == 0x5e) {
      neg = true;
      i++;
    }
    final start = i;
    while (i < _s.length && _isAlpha(_s[i])) {
      i++;
    }
    if (i == start ||
        i + 1 >= _s.length ||
        _s[i] != 0x3a ||
        _s[i + 1] != 0x5d) {
      return null;
    }
    final name = String.fromCharCodes(_s.sublist(start, i));
    const known = {
      'alnum',
      'alpha',
      'ascii',
      'blank',
      'cntrl',
      'digit',
      'graph',
      'lower',
      'print',
      'punct',
      'space',
      'upper',
      'xdigit',
      'word',
    };
    if (!known.contains(name)) {
      throw TranslationException('invalid POSIX bracket type [:$name:]');
    }
    _p = i + 2;
    final items = _propertyItems(name);
    if (!neg) return items;
    return [
      _CNested(_ClassNode(true, [items])),
    ];
  }

  /// Reads one class element. Returns a code point, or null when it appended
  /// a set (`\d`, `\p{..}`) to [items].
  int? _readClassAtom(List<_ClassItem> items) {
    final c = _s[_p];
    if (c != 0x5c) {
      _p++;
      return c;
    }
    _p++;
    if (_eof) throw const TranslationException('end pattern at escape');
    final e = _peek;
    switch (e) {
      case 0x64:
        _p++;
        items.add(_CRaw(r'\p{Nd}'));
        return null;
      case 0x44:
        _p++;
        items.add(_CRaw(r'\P{Nd}'));
        return null;
      case 0x77:
        _p++;
        items.add(_CRaw(_wordItems));
        return null;
      case 0x57:
        _p++;
        items.add(
          _CNested(
            _ClassNode(true, [
              [_CRaw(_wordItems)],
            ]),
          ),
        );
        return null;
      case 0x73:
        _p++;
        items.add(_CRaw(r'\p{space}'));
        return null;
      case 0x53:
        _p++;
        items.add(_CRaw(r'\P{space}'));
        return null;
      case 0x68:
        _p++;
        items.add(_CRaw(r'\p{AHex}'));
        return null;
      case 0x48:
        _p++;
        items.add(_CRaw(r'\P{AHex}'));
        return null;
      case 0x70:
      case 0x50:
        if (_peekAt(1) == 0x7b) {
          _p++;
          final node = _parseProperty(negated: e == 0x50);
          if (node is _Atom) {
            items.add(_CRaw(node.text));
          } else {
            items.add(_CNested(node as _ClassNode));
          }
          return null;
        }
        _p++;
        return e;
      default:
        return _readCharEscape(inClass: true);
    }
  }
}

const String _wordItems = r'\p{L}\p{M}\p{N}\p{Pc}';
const String _wordClass = '[$_wordItems]';
const String _notWordClass = '[^$_wordItems]';

/// `\R`, `\X`: matched atomically.
class _AtomicText extends _Node {
  _AtomicText(this.body);
  final String body;
}

class _FlagDirective {
  _FlagDirective(this.caseChange, this.extended, this.dotAll);
  final bool? caseChange;
  final bool? extended;
  final bool? dotAll;
}

// Property resolution -------------------------------------------------------

final Map<String, String?> _propertyCache = {};

bool _dartAccepts(String fragment) {
  try {
    RegExp(fragment, unicode: true);
    return true;
  } on FormatException {
    return false;
  }
}

/// A Dart-valid `\p{...}` fragment for an Oniguruma property name, or null.
String? _resolveProperty(String name) {
  return _propertyCache.putIfAbsent(name, () {
    final words = name
        .split(RegExp(r'[\s_-]+'))
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
        .toList();
    final candidates = <String>[
      name,
      'sc=$name',
      if (words.isNotEmpty) words.join('_'),
      if (words.isNotEmpty) 'sc=${words.join('_')}',
    ];
    for (final c in candidates) {
      final frag = '\\p{$c}';
      if (_dartAccepts(frag)) return frag;
    }
    return null;
  });
}

// ---------------------------------------------------------------------------
// Emitter
// ---------------------------------------------------------------------------

class _Ref {
  _Ref(this.onigGroup);
  final int onigGroup;
}

class _Emitter {
  _Emitter(this._parser, this._positionGroups);

  final _Parser _parser;
  final Set<int> _positionGroups;
  final Map<int, int> _markers = {};
  int _leadingGroup = -1;
  final List<Object> _parts = [];
  int _dartGroups = 0;
  final Map<int, int> _map = {0: 0};
  final Map<_Group, int> _active = {};
  final Set<_SearchStart> _stickyG = {};
  var _anchored = false;
  var _clip = false;
  // 0: no case-insensitive parts, 1: whole pattern (use the flag),
  // 2: mixed (expand by hand).
  var _caseMode = 0;
  var _ci = false;

  TranslatedPattern emit(List<List<_Node>> rootAlts) {
    // \G handling: leading in every alternative -> sticky.
    var allLeading = true;
    var anyLeading = false;
    final leading = <_SearchStart>[];
    for (final alt in rootAlts) {
      if (alt.length == 1 && alt.first is _SearchStart) {
        _stickyG.add(alt.first as _SearchStart);
        anyLeading = true;
        continue;
      }
      final g = _leadingG(alt);
      if (g == null) {
        allLeading = false;
      } else {
        leading.addAll(g);
        anyLeading = true;
      }
    }
    if (anyLeading && allLeading) {
      _stickyG.addAll(leading);
      _anchored = true;
    }
    _caseMode = _analyzeCase(rootAlts);
    var alts = rootAlts;
    // \K at top level.
    if (rootAlts.length == 1) {
      final seq = rootAlts.first;
      final k = seq.indexWhere((n) => n is _Keep);
      if (k >= 0) {
        if (seq.skip(k + 1).any((n) => n is _Keep)) {
          throw const TranslationException('multiple \\K');
        }
        final before = seq.sublist(0, k);
        final after = seq.sublist(k + 1);
        alts = [
          [
            _Group(_GroupKind.behind, [before]),
            ...after,
          ],
        ];
      }
    }
    if (alts.length == 1 &&
        alts.first.isNotEmpty &&
        alts.first.first is _Group &&
        (alts.first.first as _Group).kind == _GroupKind.capture) {
      _leadingGroup = (alts.first.first as _Group).index;
    }
    _emitAlts(alts, capture: true);
    final buf = StringBuffer();
    for (final p in _parts) {
      if (p is String) {
        buf.write(p);
      } else {
        final ref = p as _Ref;
        final n = ref.onigGroup;
        if (n > _parser.groupCount) {
          buf.write('(?:)'); // orphan backreference: matches empty
        } else {
          final d = _map[n];
          if (d == null) {
            throw const TranslationException(
              'backreference to a group never emitted',
            );
          }
          buf.write('(?:\\$d)');
        }
      }
    }
    final map = List<int>.filled(_parser.groupCount + 1, 0);
    for (var i = 0; i <= _parser.groupCount; i++) {
      map[i] = _map[i] ?? 0;
    }
    final markers = List<int>.filled(_parser.groupCount + 1, 0);
    for (final e in _markers.entries) {
      markers[e.key] = e.value;
    }
    // A group that opens the pattern starts at the match start: no marker.
    if (_leadingGroup > 0) markers[_leadingGroup] = -1;
    return TranslatedPattern(
      source: buf.toString(),
      groupMap: map,
      markerMap: markers,
      anchoredAtSearchStart: _anchored,
      clipSearch: _clip,
      caseInsensitive: _caseMode == 1,
    );
  }

  /// 0: nothing case-insensitive, 1: every cased leaf is, 2: mixed.
  int _analyzeCase(List<List<_Node>> alts) {
    var anyCi = false;
    var anyCs = false;
    void visitAlts(List<List<_Node>> a, bool ci) {
      for (final seq in a) {
        for (final n in seq) {
          visit(n, ci);
        }
      }
    }

    void leaf(bool cased, bool ci) {
      if (!cased) return;
      if (ci) {
        anyCi = true;
      } else {
        anyCs = true;
      }
    }

    void visitNode(_Node n, bool ci) {
      switch (n) {
        case _Lit():
          leaf(_isCased(n.cp), ci);
        case _ClassNode():
          leaf(_classHasCased(n), ci);
        case _Group():
          visitAlts(n.alts, ci);
        case _CaseGroup():
          visitAlts(n.alts, n.ignoreCase);
        case _Quant():
          visit(n.body, ci);
        default:
          break;
      }
    }

    visit = visitNode;
    visitAlts(alts, false);
    if (!anyCi) return 0;
    return anyCs ? 2 : 1;
  }

  late void Function(_Node, bool) visit;

  static bool _isCased(int cp) {
    final s = String.fromCharCode(cp);
    return s.toLowerCase() != s.toUpperCase();
  }

  static bool _classHasCased(_ClassNode c) {
    for (final operand in c.operands) {
      for (final item in operand) {
        switch (item) {
          case _CChar():
            if (item.hi - item.lo > 200) return true;
            for (var cp = item.lo; cp <= item.hi; cp++) {
              if (_isCased(cp)) return true;
            }
          case _CNested():
            if (_classHasCased(item.node)) return true;
          case _CRaw():
            break;
        }
      }
    }
    return false;
  }

  static List<int> _caseVariants(int cp) {
    final s = String.fromCharCode(cp);
    final out = <int>{};
    for (final v in [s.toLowerCase(), s.toUpperCase()]) {
      final runes = v.runes.toList();
      if (runes.length == 1 && runes.first != cp) out.add(runes.first);
    }
    return out.toList();
  }

  bool _zeroLength(_Node n) =>
      n is _Assertion ||
      n is _Keep ||
      (n is _Group &&
          (n.kind == _GroupKind.ahead ||
              n.kind == _GroupKind.notAhead ||
              n.kind == _GroupKind.behind ||
              n.kind == _GroupKind.notBehind));

  List<_SearchStart>? _leadingG(List<_Node> alt) {
    for (final n in alt) {
      if (n is _SearchStart) return [n];
      if (n is _Group && n.kind == _GroupKind.ahead) {
        if (n.alts.length == 1 &&
            n.alts.first.length == 1 &&
            n.alts.first.first is _SearchStart) {
          return [n.alts.first.first as _SearchStart];
        }
      }
      if (_zeroLength(n)) continue;
      if (n is _Group &&
          (n.kind == _GroupKind.capture || n.kind == _GroupKind.plain)) {
        final out = <_SearchStart>[];
        for (final a in n.alts) {
          final g = _leadingG(a);
          if (g == null) return null;
          out.addAll(g);
        }
        return out;
      }
      return null;
    }
    return null;
  }

  void _w(String s) => _parts.add(s);

  void _emitAlts(List<List<_Node>> alts, {required bool capture}) {
    for (var i = 0; i < alts.length; i++) {
      if (i > 0) _w('|');
      _emitSeq(alts[i], capture: capture);
    }
  }

  void _emitSeq(List<_Node> seq, {required bool capture}) {
    for (var i = 0; i < seq.length; i++) {
      _emitNode(seq[i], capture: capture, prev: i > 0 ? seq[i - 1] : null);
    }
  }

  bool _isAlwaysNonZero(_Node n) =>
      n is _Lit ||
      n is _Atom ||
      n is _ClassNode ||
      (n is _Quant && n.min > 0 && _isAlwaysNonZero(n.body));

  void _emitNode(_Node n, {required bool capture, _Node? prev}) {
    switch (n) {
      case _Lit():
        if (_caseMode == 2 && _ci) {
          final variants = _caseVariants(n.cp);
          if (variants.isNotEmpty) {
            _w(
              '[${_escapeInClass(n.cp)}${variants.map(_escapeInClass).join()}]',
            );
            break;
          }
        }
        _w(_escapeLiteral(n.cp));
      case _Atom():
        _w(n.text);
      case _AtomicText():
        final d = ++_dartGroups;
        _w('(?:(?=(${n.body}))\\$d)');
      case _ClassNode():
        _w(_emitClass(n, _caseMode == 2 && _ci));
      case _Assertion():
        _w(n.text);
      case _SearchStart():
        if (_stickyG.contains(n)) {
          break;
        }
        if (prev != null && _isAlwaysNonZero(prev)) {
          _w('(?!)');
        } else {
          _w('^');
          _clip = true;
        }
      case _Keep():
        throw const TranslationException('\\K in this position');
      case _Group():
        _emitGroup(n, capture: capture);
      case _CaseGroup():
        final saved = _ci;
        _ci = n.ignoreCase;
        _w('(?:');
        _emitAlts(n.alts, capture: capture);
        _w(')');
        _ci = saved;
      case _BackrefNum():
        _parts.add(_Ref(n.number));
      case _AmbiguousNumber():
        _emitAmbiguous(n);
      case _BackrefName():
        final nums = _parser.groupsByName[n.name];
        if (nums == null) {
          throw TranslationException('undefined name <${n.name}> reference');
        }
        if (nums.length == 1) {
          _parts.add(_Ref(nums.first));
        } else {
          _w('(?:');
          for (var i = nums.length - 1; i >= 0; i--) {
            if (i != nums.length - 1) _w('|');
            _parts.add(_Ref(nums[i]));
          }
          _w(')');
        }
      case _Call():
        _emitCall(n);
      case _Quant():
        _emitQuant(n, capture: capture);
    }
  }

  void _emitAmbiguous(_AmbiguousNumber n) {
    final num = int.parse(n.digits);
    if (num <= _parser.groupCount) {
      _parts.add(_Ref(num));
      return;
    }
    // Octal escape (first digit 0-7) followed by literal digits, else the
    // digits are literals.
    final d = n.digits;
    if (_isOctal(d.codeUnitAt(0))) {
      var v = 0;
      var used = 0;
      while (used < d.length && used < 3 && _isOctal(d.codeUnitAt(used))) {
        v = v * 8 + (d.codeUnitAt(used) - 0x30);
        used++;
      }
      if (v > 0x7f) {
        throw const TranslationException('octal byte escape above \\177');
      }
      _w(_escapeLiteral(v));
      for (var i = used; i < d.length; i++) {
        _w(d[i]);
      }
    } else {
      _w(d);
    }
  }

  void _emitGroup(_Group g, {required bool capture}) {
    switch (g.kind) {
      case _GroupKind.capture:
        if (capture) {
          _map[g.index] = ++_dartGroups;
          _w('(');
          if (_positionGroups.contains(g.index) && g.index != _leadingGroup) {
            _markers[g.index] = ++_dartGroups;
            _w(r'(?<=([\s\S]*))(?:');
            _emitAlts(g.alts, capture: capture);
            _w('))');
          } else {
            _emitAlts(g.alts, capture: capture);
            _w(')');
          }
        } else {
          _w('(?:');
          _emitAlts(g.alts, capture: capture);
          _w(')');
        }
      case _GroupKind.plain:
        _w('(?:');
        _emitAlts(g.alts, capture: capture);
        _w(')');
      case _GroupKind.ahead:
        _w('(?=');
        _emitAlts(g.alts, capture: capture);
        _w(')');
      case _GroupKind.notAhead:
        _w('(?!');
        _emitAlts(g.alts, capture: capture);
        _w(')');
      case _GroupKind.behind:
        _w('(?<=');
        _emitAlts(g.alts, capture: capture);
        _w(')');
      case _GroupKind.notBehind:
        _w('(?<!');
        _emitAlts(g.alts, capture: capture);
        _w(')');
      case _GroupKind.atomic:
        final d = ++_dartGroups;
        _w('(?:(?=(');
        _emitAlts(g.alts, capture: capture);
        _w('))\\$d)');
      case _GroupKind.absence:
        _w(r'(?:(?!');
        _emitAlts(g.alts, capture: capture);
        _w(r')[\s\S])*');
    }
  }

  void _emitCall(_Call c) {
    _Group? target;
    if (c.number != null) {
      if (c.number == 0) {
        // Whole-pattern recursion.
        target = _Group(_GroupKind.plain, _parser.rootAlts);
      } else {
        target = _parser.groupsByIndex[c.number];
      }
    } else {
      final nums = _parser.groupsByName[c.name];
      if (nums != null) {
        if (nums.length > 1) {
          throw const TranslationException('subroutine call to duplicate name');
        }
        target = _parser.groupsByIndex[nums.first];
      }
    }
    if (target == null) {
      throw const TranslationException('undefined group reference');
    }
    final key = c.number == 0 ? _wholeKey : target;
    final depth = _active[key] ?? 0;
    if (depth >= _recursionLimit) {
      _w('(?:)');
      return;
    }
    _active[key] = depth + 1;
    _w('(?:');
    _emitAlts(target.alts, capture: false);
    _w(')');
    _active[key] = depth;
  }

  static final _Group _wholeKey = _Group(_GroupKind.plain, const []);

  void _emitQuant(_Quant q, {required bool capture}) {
    final possessive = q.mode == _QMode.possessive;
    // The hidden group's `(` comes before the body's groups textually.
    final hidden = possessive ? ++_dartGroups : 0;
    final start = _parts.length;
    _emitNode(q.body, capture: capture);
    final bodyParts = _parts.sublist(start);
    _parts.removeRange(start, _parts.length);
    final body = q.body;
    final simple =
        body is _Lit ||
        body is _Atom ||
        body is _ClassNode ||
        body is _CaseGroup ||
        (body is _Group &&
            (body.kind == _GroupKind.capture || body.kind == _GroupKind.plain));
    final suffix = _quantText(q);
    if (possessive) {
      _w('(?:(?=(');
      _wrapBody(bodyParts, simple);
      _w('$suffix))\\$hidden)');
      return;
    }
    _wrapBody(bodyParts, simple);
    _w(suffix);
  }

  void _wrapBody(List<Object> bodyParts, bool simple) {
    if (simple) {
      _parts.addAll(bodyParts);
    } else {
      _w('(?:');
      _parts.addAll(bodyParts);
      _w(')');
    }
  }

  String _quantText(_Quant q) {
    final lazy = q.mode == _QMode.lazy ? '?' : '';
    if (q.min == 0 && q.max == -1) return '*$lazy';
    if (q.min == 1 && q.max == -1) return '+$lazy';
    if (q.min == 0 && q.max == 1) return '?$lazy';
    if (q.max == -1) return '{${q.min},}$lazy';
    if (q.min == q.max) return '{${q.min}}$lazy';
    return '{${q.min},${q.max}}$lazy';
  }

  // --- literals ------------------------------------------------------------

  static String _escapeLiteral(int cp) {
    if (cp < 0x20 || cp == 0x7f) {
      return '\\x${cp.toRadixString(16).padLeft(2, '0')}';
    }
    switch (cp) {
      case 0x5c: // \
      case 0x5e: // ^
      case 0x24: // $
      case 0x2e: // .
      case 0x2a: // *
      case 0x2b: // +
      case 0x3f: // ?
      case 0x28: // (
      case 0x29: // )
      case 0x5b: // [
      case 0x5d: // ]
      case 0x7b: // {
      case 0x7d: // }
      case 0x7c: // |
      case 0x2f: // /
        return '\\${String.fromCharCode(cp)}';
      case 0x2028:
      case 0x2029:
        return '\\u${cp.toRadixString(16)}';
    }
    return String.fromCharCode(cp);
  }

  static String _escapeInClass(int cp) {
    if (cp < 0x20 || cp == 0x7f) {
      return '\\x${cp.toRadixString(16).padLeft(2, '0')}';
    }
    switch (cp) {
      case 0x5c:
      case 0x5d:
      case 0x5b:
      case 0x5e:
      case 0x2d:
        return '\\${String.fromCharCode(cp)}';
      case 0x2028:
      case 0x2029:
        return '\\u${cp.toRadixString(16)}';
    }
    return String.fromCharCode(cp);
  }

  // --- classes -------------------------------------------------------------

  /// Extra class items covering the other-case counterparts of lo..hi.
  static String _caseExpansion(int lo, int hi) {
    final out = StringBuffer();
    // ASCII letters by range arithmetic, the rest per character.
    void range(int a, int b, int delta) {
      final from = a > lo ? a : lo;
      final to = b < hi ? b : hi;
      if (from > to) return;
      out
        ..write(_escapeInClass(from + delta))
        ..write(from == to ? '' : '-${_escapeInClass(to + delta)}');
    }

    range(0x61, 0x7a, -32);
    range(0x41, 0x5a, 32);
    if (hi >= 0x80) {
      final start = lo < 0x80 ? 0x80 : lo;
      if (hi - start <= 256) {
        for (var cp = start; cp <= hi; cp++) {
          for (final v in _caseVariants(cp)) {
            out.write(_escapeInClass(v));
          }
        }
      }
    }
    return out.toString();
  }

  /// An atom matching one character.
  String _emitClass(_ClassNode c, bool ci) {
    final positive = _classPositive(c, ci);
    if (!c.negated) return positive.text;
    if (positive.simpleBody != null) return '[^${positive.simpleBody}]';
    return '(?:(?!${positive.text})[\\s\\S])';
  }

  /// Emits the non-negated meaning of [c]. [simpleBody] is non-null when the
  /// whole thing is one plain `[...]` whose body can be negated directly.
  _ClassText _classPositive(_ClassNode c, bool ci) {
    final operandTexts = <String>[];
    String? onlySimple;
    for (final operand in c.operands) {
      final simple = StringBuffer();
      final pieces = <String>[];
      for (final item in operand) {
        switch (item) {
          case _CChar():
            if (item.lo == item.hi) {
              simple.write(_escapeInClass(item.lo));
            } else {
              simple
                ..write(_escapeInClass(item.lo))
                ..write('-')
                ..write(_escapeInClass(item.hi));
            }
            if (ci) simple.write(_caseExpansion(item.lo, item.hi));
          case _CRaw():
            simple.write(item.text);
          case _CNested():
            pieces.add(_emitClass(item.node, ci));
        }
      }
      final s = simple.toString();
      if (pieces.isEmpty) {
        if (s.isEmpty) {
          operandTexts.add('(?!)');
        } else {
          operandTexts.add('[$s]');
          onlySimple = s;
        }
      } else {
        final all = <String>[if (s.isNotEmpty) '[$s]', ...pieces];
        operandTexts.add(all.length == 1 ? all.first : '(?:${all.join('|')})');
      }
    }
    if (operandTexts.length == 1) {
      final single = c.operands.first.every((i) => i is! _CNested);
      if (single && onlySimple != null) {
        return _ClassText(operandTexts.first, onlySimple);
      }
      return _ClassText(operandTexts.first, null);
    }
    final buf = StringBuffer();
    for (var i = 0; i < operandTexts.length - 1; i++) {
      buf.write('(?=${operandTexts[i]})');
    }
    buf.write(operandTexts.last);
    return _ClassText('(?:$buf)', null);
  }
}

class _ClassText {
  _ClassText(this.text, this.simpleBody);
  final String text;
  final String? simpleBody;
}
