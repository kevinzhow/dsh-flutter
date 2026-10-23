// vscode-textmate's rule compilation: Rule classes, RuleFactory, RegExpSource,
// RegExpSourceList and the scanner, ported to Dart.
library;

import 'compiled_pattern.dart';
import 'raw_grammar.dart';

// --- pattern cache -----------------------------------------------------------

/// Compiles Oniguruma sources once per (source, requested offsets) and counts
/// the ones that had to be degraded to "never matches".
class PatternCache {
  final Map<String, CompiledPattern?> _cache = {};

  /// Sources that could not be translated (source -> reason).
  final Map<String, String> failures = {};

  CompiledPattern? get(String source, Set<int> positionGroups) {
    final key = positionGroups.isEmpty
        ? source
        : '${(positionGroups.toList()..sort()).join(',')}\u0000$source';
    if (_cache.containsKey(key)) return _cache[key];
    final compiled = CompiledPattern.tryCompile(
      source,
      positionGroups: positionGroups,
      onError: (reason) => failures[source] = reason,
    );
    _cache[key] = compiled;
    return compiled;
  }
}

// --- scanner -----------------------------------------------------------------

class ScanResult {
  const ScanResult(this.ruleId, this.match);
  final int ruleId;
  final OnigMatch match;
}

/// shiki's JavaScriptScanner semantics: each pattern is searched separately; a
/// match at the search position wins at once, otherwise the leftmost match,
/// earliest pattern first. Per-line result reuse lives in
/// [CompiledPattern.searchCached].
class Scanner {
  Scanner(this._patterns, this._ruleIds);

  final List<CompiledPattern?> _patterns;
  final List<int> _ruleIds;

  ScanResult? find(String text, int start) {
    var bestIndex = -1;
    var bestStart = 0;
    OnigMatch? bestMatch;
    for (var i = 0; i < _patterns.length; i++) {
      final p = _patterns[i];
      if (p == null) continue;
      final m = p.searchCached(text, start);
      if (m == null) continue;
      final s = m.start(0);
      if (s == start) return ScanResult(_ruleIds[i], m);
      if (bestMatch == null || s < bestStart) {
        bestIndex = i;
        bestStart = s;
        bestMatch = m;
      }
    }
    if (bestMatch == null) return null;
    return ScanResult(_ruleIds[bestIndex], bestMatch);
  }
}

// --- regexp sources ------------------------------------------------------------

final RegExp _hasBackReferences = RegExp(r'\\(\d+)');
final RegExp _backReferencingEnd = RegExp(r'\\(\d+)');
final RegExp _escapeRegExpChars = RegExp(r'[\-\\{}*+?|^$.,\[\]()#\s]');

String escapeRegExpCharacters(String value) =>
    value.replaceAllMapped(_escapeRegExpChars, (m) => '\\${m[0]}');

/// One regex of a rule together with its textmate anchor handling.
class RegExpSource {
  RegExpSource(String source, this.ruleId, this.positionGroups)
    : _source = source,
      hasAnchor = false {
    var hasAnchor = false;
    var lastPushed = 0;
    final out = StringBuffer();
    final len = source.length;
    for (var pos = 0; pos < len; pos++) {
      if (source.codeUnitAt(pos) == 0x5c) {
        if (pos + 1 < len) {
          final next = source.codeUnitAt(pos + 1);
          if (next == 0x7a) {
            // \z
            out
              ..write(source.substring(lastPushed, pos))
              ..write(r'$(?!\n)(?<!\n)');
            lastPushed = pos + 2;
          } else if (next == 0x41 || next == 0x47) {
            hasAnchor = true;
          }
          pos++;
        }
      }
    }
    this.hasAnchor = hasAnchor;
    if (lastPushed != 0) {
      out.write(source.substring(lastPushed, len));
      _source = out.toString();
    }
    hasBackReferences = _hasBackReferences.hasMatch(_source);
  }

  String _source;
  bool hasAnchor;
  late final bool hasBackReferences;
  final int ruleId;

  /// Capture numbers whose offsets the owning rule's captures need.
  final Set<int> positionGroups;

  final List<String?> _variants = List<String?>.filled(4, null);

  String get source => _source;

  RegExpSource clone() => RegExpSource(_source, ruleId, positionGroups);

  void setSource(String newSource) {
    if (_source == newSource) return;
    _source = newSource;
    for (var i = 0; i < 4; i++) {
      _variants[i] = null;
    }
  }

  String resolveBackReferences(String lineText, OnigMatch m) {
    return _source.replaceAllMapped(_backReferencingEnd, (mm) {
      final n = int.parse(mm[1]!);
      final text = n <= m.groupCount ? m.text(n) : '';
      return escapeRegExpCharacters(text);
    });
  }

  String resolveAnchors(bool allowA, bool allowG) {
    if (!hasAnchor) return _source;
    final key = (allowA ? 2 : 0) + (allowG ? 1 : 0);
    return _variants[key] ??= _buildVariant(allowA, allowG);
  }

  String _buildVariant(bool allowA, bool allowG) {
    final out = StringBuffer();
    final s = _source;
    for (var pos = 0; pos < s.length; pos++) {
      final ch = s[pos];
      out.write(ch);
      if (ch == r'\' && pos + 1 < s.length) {
        final next = s[pos + 1];
        if (next == 'A') {
          out.write(allowA ? 'A' : '\uFFFF');
        } else if (next == 'G') {
          out.write(allowG ? 'G' : '\uFFFF');
        } else {
          out.write(next);
        }
        pos++;
      }
    }
    return out.toString();
  }
}

class RegExpSourceList {
  final List<RegExpSource> _items = [];
  bool _hasAnchors = false;
  Scanner? _cached;
  final List<Scanner?> _anchorCache = List<Scanner?>.filled(4, null);

  void push(RegExpSource item) {
    _items.add(item);
    _hasAnchors = _hasAnchors || item.hasAnchor;
  }

  void unshift(RegExpSource item) {
    _items.insert(0, item);
    _hasAnchors = _hasAnchors || item.hasAnchor;
  }

  int get length => _items.length;

  void setSource(int index, String newSource) {
    if (_items[index].source != newSource) {
      _cached = null;
      for (var i = 0; i < 4; i++) {
        _anchorCache[i] = null;
      }
      _items[index].setSource(newSource);
    }
  }

  Scanner compile(PatternCache cache) {
    return _cached ??= Scanner(
      [for (final e in _items) cache.get(e.source, e.positionGroups)],
      [for (final e in _items) e.ruleId],
    );
  }

  Scanner compileAG(PatternCache cache, bool allowA, bool allowG) {
    if (!_hasAnchors) return compile(cache);
    final key = (allowA ? 2 : 0) + (allowG ? 1 : 0);
    return _anchorCache[key] ??= Scanner(
      [
        for (final e in _items)
          cache.get(e.resolveAnchors(allowA, allowG), e.positionGroups),
      ],
      [for (final e in _items) e.ruleId],
    );
  }
}

// --- rules ---------------------------------------------------------------------

const int endRuleId = -1;
const int whileRuleId = -2;

final RegExp _capturingRegexSource = RegExp(
  r'\$(\d+)|\$\{(\d+):\/(downcase|upcase)\}',
);

String _replaceCaptures(String source, OnigMatch m) {
  return source.replaceAllMapped(_capturingRegexSource, (mm) {
    final idx = int.parse(mm[1] ?? mm[2]!);
    if (idx > m.groupCount) return mm[0]!;
    var result = m.text(idx);
    while (result.startsWith('.')) {
      result = result.substring(1);
    }
    switch (mm[3]) {
      case 'downcase':
        return result.toLowerCase();
      case 'upcase':
        return result.toUpperCase();
      default:
        return result;
    }
  });
}

/// The grammar services rules need while compiling and scanning.
abstract interface class RuleHost {
  PatternCache get patternCache;
  int registerRule(Rule Function(int id) factory);
  Rule? getRule(int id);
  InitializedGrammar? getExternalGrammar(
    String scopeName,
    Map<String, RawRule>? repository,
  );
}

/// A raw grammar prepared for one grammar instance: `$self` / `$base` added to
/// its repository (vscode-textmate's initGrammar).
class InitializedGrammar {
  InitializedGrammar(this.raw, this.repository);
  final RawGrammar raw;
  final Map<String, RawRule> repository;

  factory InitializedGrammar.from(RawGrammar raw, RawRule? base) {
    final repo = Map<String, RawRule>.of(raw.repository);
    final self = RawRule(patterns: raw.patterns, name: raw.scopeName);
    repo[r'$self'] = self;
    repo[r'$base'] = base ?? self;
    return InitializedGrammar(raw, repo);
  }
}

abstract class Rule {
  Rule(this.id, String? name, String? contentName)
    : _name = name,
      _contentName = contentName,
      _nameIsCapturing = name != null && _capturingRegexSource.hasMatch(name),
      _contentNameIsCapturing =
          contentName != null && _capturingRegexSource.hasMatch(contentName);

  final int id;
  final String? _name;
  final String? _contentName;
  final bool _nameIsCapturing;
  final bool _contentNameIsCapturing;

  String? getName(OnigMatch? m) {
    if (!_nameIsCapturing || _name == null || m == null) return _name;
    return _replaceCaptures(_name, m);
  }

  String? getContentName(OnigMatch m) {
    if (!_contentNameIsCapturing || _contentName == null) return _contentName;
    return _replaceCaptures(_contentName, m);
  }

  void collectPatterns(RuleHost host, RegExpSourceList out);
  Scanner compileAG(
    RuleHost host,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  );
}

class CaptureRule extends Rule {
  CaptureRule(super.id, super.name, super.contentName, this.retokenizeWith);
  final int retokenizeWith;

  @override
  void collectPatterns(RuleHost host, RegExpSourceList out) =>
      throw UnsupportedError('capture rules have no patterns');

  @override
  Scanner compileAG(RuleHost host, String? e, bool a, bool g) =>
      throw UnsupportedError('capture rules cannot be compiled');
}

Set<int> _captureGroups(List<CaptureRule?> captures) => {
  for (var i = 0; i < captures.length; i++)
    if (captures[i] != null) i,
};

class MatchRule extends Rule {
  MatchRule(int id, String? name, String match, this.captures)
    : _match = RegExpSource(match, id, _captureGroups(captures)),
      super(id, name, null);

  final RegExpSource _match;
  final List<CaptureRule?> captures;
  RegExpSourceList? _list;

  @override
  void collectPatterns(RuleHost host, RegExpSourceList out) => out.push(_match);

  @override
  Scanner compileAG(RuleHost host, String? e, bool allowA, bool allowG) {
    var list = _list;
    if (list == null) {
      list = RegExpSourceList();
      collectPatterns(host, list);
      _list = list;
    }
    return list.compileAG(host.patternCache, allowA, allowG);
  }
}

class IncludeOnlyRule extends Rule {
  IncludeOnlyRule(
    super.id,
    super.name,
    super.contentName,
    this.patterns,
    this.hasMissingPatterns,
  );

  final List<int> patterns;
  final bool hasMissingPatterns;
  RegExpSourceList? _list;

  @override
  void collectPatterns(RuleHost host, RegExpSourceList out) {
    for (final p in patterns) {
      host.getRule(p)!.collectPatterns(host, out);
    }
  }

  @override
  Scanner compileAG(RuleHost host, String? e, bool allowA, bool allowG) {
    var list = _list;
    if (list == null) {
      list = RegExpSourceList();
      collectPatterns(host, list);
      _list = list;
    }
    return list.compileAG(host.patternCache, allowA, allowG);
  }
}

class BeginEndRule extends Rule {
  BeginEndRule(
    super.id,
    super.name,
    super.contentName,
    String begin,
    this.beginCaptures,
    String? end,
    this.endCaptures,
    this.applyEndPatternLast,
    this.patterns,
    this.hasMissingPatterns,
  ) : _begin = RegExpSource(begin, id, _captureGroups(beginCaptures)),
      _end = RegExpSource(
        end == null || end.isEmpty ? '\uFFFF' : end,
        endRuleId,
        _captureGroups(endCaptures),
      );

  final RegExpSource _begin;
  final RegExpSource _end;
  final List<CaptureRule?> beginCaptures;
  final List<CaptureRule?> endCaptures;
  final bool applyEndPatternLast;
  final List<int> patterns;
  final bool hasMissingPatterns;
  RegExpSourceList? _list;

  bool get endHasBackReferences => _end.hasBackReferences;

  String getEndWithResolvedBackReferences(String lineText, OnigMatch m) =>
      _end.resolveBackReferences(lineText, m);

  @override
  void collectPatterns(RuleHost host, RegExpSourceList out) => out.push(_begin);

  @override
  Scanner compileAG(
    RuleHost host,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    var list = _list;
    if (list == null) {
      list = RegExpSourceList();
      for (final p in patterns) {
        host.getRule(p)!.collectPatterns(host, list);
      }
      final end = _end.hasBackReferences ? _end.clone() : _end;
      if (applyEndPatternLast) {
        list.push(end);
      } else {
        list.unshift(end);
      }
      _list = list;
    }
    if (_end.hasBackReferences && endRegexSource != null) {
      list.setSource(applyEndPatternLast ? list.length - 1 : 0, endRegexSource);
    }
    return list.compileAG(host.patternCache, allowA, allowG);
  }
}

class BeginWhileRule extends Rule {
  BeginWhileRule(
    super.id,
    super.name,
    super.contentName,
    String begin,
    this.beginCaptures,
    String whileRe,
    this.whileCaptures,
    this.patterns,
    this.hasMissingPatterns,
  ) : _begin = RegExpSource(begin, id, _captureGroups(beginCaptures)),
      _while = RegExpSource(
        whileRe,
        whileRuleId,
        _captureGroups(whileCaptures),
      );

  final RegExpSource _begin;
  final RegExpSource _while;
  final List<CaptureRule?> beginCaptures;
  final List<CaptureRule?> whileCaptures;
  final List<int> patterns;
  final bool hasMissingPatterns;
  RegExpSourceList? _list;
  RegExpSourceList? _whileList;

  bool get whileHasBackReferences => _while.hasBackReferences;

  String getWhileWithResolvedBackReferences(String lineText, OnigMatch m) =>
      _while.resolveBackReferences(lineText, m);

  @override
  void collectPatterns(RuleHost host, RegExpSourceList out) => out.push(_begin);

  @override
  Scanner compileAG(RuleHost host, String? e, bool allowA, bool allowG) {
    var list = _list;
    if (list == null) {
      list = RegExpSourceList();
      for (final p in patterns) {
        host.getRule(p)!.collectPatterns(host, list);
      }
      _list = list;
    }
    return list.compileAG(host.patternCache, allowA, allowG);
  }

  Scanner compileWhileAG(
    RuleHost host,
    String? endRegexSource,
    bool allowA,
    bool allowG,
  ) {
    var list = _whileList;
    if (list == null) {
      list = RegExpSourceList();
      list.push(_while.hasBackReferences ? _while.clone() : _while);
      _whileList = list;
    }
    if (_while.hasBackReferences) {
      list.setSource(0, endRegexSource ?? '\uFFFF');
    }
    return list.compileAG(host.patternCache, allowA, allowG);
  }
}

// --- rule factory ----------------------------------------------------------------

class _CompiledPatterns {
  _CompiledPatterns(this.patterns, this.hasMissing);
  final List<int> patterns;
  final bool hasMissing;
}

class RuleFactory {
  static CaptureRule _createCaptureRule(
    RuleHost host,
    RawRule desc,
    int retokenizeWith,
  ) {
    late CaptureRule rule;
    host.registerRule((id) {
      rule = CaptureRule(id, desc.name, desc.contentName, retokenizeWith);
      return rule;
    });
    return rule;
  }

  static int getCompiledRuleId(
    RawRule desc,
    RuleHost host,
    Map<String, RawRule> repository,
  ) {
    if (desc.id == 0) {
      host.registerRule((id) {
        desc.id = id;
        final match = desc.match;
        if (match != null && match.isNotEmpty) {
          return MatchRule(
            id,
            desc.name,
            match,
            _compileCaptures(desc.captures, host, repository),
          );
        }
        if (desc.begin == null) {
          var repo = repository;
          if (desc.repository != null) {
            repo = {...repository, ...desc.repository!};
          }
          var patterns = desc.patterns;
          if (patterns == null &&
              desc.include != null &&
              desc.include!.isNotEmpty) {
            patterns = [RawRule(include: desc.include)];
          }
          final compiled = _compilePatterns(patterns, host, repo);
          return IncludeOnlyRule(
            id,
            desc.name,
            desc.contentName,
            compiled.patterns,
            compiled.hasMissing,
          );
        }
        final whileRe = desc.whileRe;
        if (whileRe != null && whileRe.isNotEmpty) {
          final compiled = _compilePatterns(desc.patterns, host, repository);
          return BeginWhileRule(
            id,
            desc.name,
            desc.contentName,
            desc.begin!,
            _compileCaptures(
              desc.beginCaptures ?? desc.captures,
              host,
              repository,
            ),
            whileRe,
            _compileCaptures(
              desc.whileCaptures ?? desc.captures,
              host,
              repository,
            ),
            compiled.patterns,
            compiled.hasMissing,
          );
        }
        final compiled = _compilePatterns(desc.patterns, host, repository);
        return BeginEndRule(
          id,
          desc.name,
          desc.contentName,
          desc.begin!,
          _compileCaptures(
            desc.beginCaptures ?? desc.captures,
            host,
            repository,
          ),
          desc.end,
          _compileCaptures(desc.endCaptures ?? desc.captures, host, repository),
          desc.applyEndPatternLast,
          compiled.patterns,
          compiled.hasMissing,
        );
      });
    }
    return desc.id;
  }

  static List<CaptureRule?> _compileCaptures(
    Map<String, RawRule>? captures,
    RuleHost host,
    Map<String, RawRule> repository,
  ) {
    if (captures == null) return const [];
    var maxId = 0;
    for (final key in captures.keys) {
      final n = int.tryParse(key);
      if (n != null && n > maxId) maxId = n;
    }
    final out = List<CaptureRule?>.filled(maxId + 1, null);
    for (final e in captures.entries) {
      final n = int.tryParse(e.key);
      if (n == null) continue;
      var retokenize = 0;
      if (e.value.patterns != null) {
        retokenize = getCompiledRuleId(e.value, host, repository);
      }
      out[n] = _createCaptureRule(host, e.value, retokenize);
    }
    return out;
  }

  static _CompiledPatterns _compilePatterns(
    List<RawRule>? patterns,
    RuleHost host,
    Map<String, RawRule> repository,
  ) {
    final out = <int>[];
    if (patterns != null) {
      for (final pattern in patterns) {
        var ruleId = -1;
        final include = pattern.include;
        if (include != null && include.isNotEmpty) {
          if (include == r'$base' || include == r'$self') {
            final target = repository[include];
            if (target != null) {
              ruleId = getCompiledRuleId(target, host, repository);
            }
          } else {
            final hash = include.indexOf('#');
            if (hash == 0) {
              final local = repository[include.substring(1)];
              if (local != null) {
                ruleId = getCompiledRuleId(local, host, repository);
              }
            } else {
              final scope = hash == -1 ? include : include.substring(0, hash);
              final ruleName = hash == -1 ? null : include.substring(hash + 1);
              final external = host.getExternalGrammar(scope, repository);
              if (external != null) {
                if (ruleName != null) {
                  final rule = external.repository[ruleName];
                  if (rule != null) {
                    ruleId = getCompiledRuleId(rule, host, external.repository);
                  }
                } else {
                  ruleId = getCompiledRuleId(
                    external.repository[r'$self']!,
                    host,
                    external.repository,
                  );
                }
              }
            }
          }
        } else {
          ruleId = getCompiledRuleId(pattern, host, repository);
        }
        if (ruleId != -1) {
          final rule = host.getRule(ruleId);
          var skip = false;
          if (rule is IncludeOnlyRule) {
            skip = rule.hasMissingPatterns && rule.patterns.isEmpty;
          } else if (rule is BeginEndRule) {
            skip = rule.hasMissingPatterns && rule.patterns.isEmpty;
          } else if (rule is BeginWhileRule) {
            skip = rule.hasMissingPatterns && rule.patterns.isEmpty;
          }
          if (skip) continue;
          out.add(ruleId);
        }
      }
    }
    return _CompiledPatterns(
      out,
      (patterns == null ? 0 : patterns.length) != out.length,
    );
  }
}
