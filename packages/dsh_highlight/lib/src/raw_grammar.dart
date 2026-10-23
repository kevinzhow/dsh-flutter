// The parsed shape of a TextMate grammar registration (the JSON files under
// assets/grammars): vscode-textmate's IRawGrammar / IRawRule.
library;

/// A rule description. [id] is assigned when the rule is compiled for one
/// grammar instance (vscode-textmate stores it on the same object, so every
/// grammar instance works on its own copy; see [RawGrammar.fromJson]).
class RawRule {
  RawRule({
    this.name,
    this.contentName,
    this.match,
    this.begin,
    this.end,
    this.whileRe,
    this.include,
    this.captures,
    this.beginCaptures,
    this.endCaptures,
    this.whileCaptures,
    this.patterns,
    this.repository,
    this.applyEndPatternLast = false,
  });

  int id = 0;
  final String? name;
  final String? contentName;
  final String? match;
  final String? begin;
  final String? end;
  final String? whileRe;
  final String? include;
  final Map<String, RawRule>? captures;
  final Map<String, RawRule>? beginCaptures;
  final Map<String, RawRule>? endCaptures;
  final Map<String, RawRule>? whileCaptures;
  List<RawRule>? patterns;
  final Map<String, RawRule>? repository;
  final bool applyEndPatternLast;

  static RawRule fromJson(Map<String, dynamic> json) {
    Map<String, RawRule>? ruleMap(Object? v) {
      if (v is! Map) return null;
      return {
        for (final e in v.entries)
          if (e.value is Map)
            e.key as String: RawRule.fromJson(
              (e.value as Map).cast<String, dynamic>(),
            ),
      };
    }

    List<RawRule>? ruleList(Object? v) {
      if (v is! List) return null;
      return [
        for (final e in v)
          if (e is Map) RawRule.fromJson(e.cast<String, dynamic>()),
      ];
    }

    return RawRule(
      name: json['name'] as String?,
      contentName: json['contentName'] as String?,
      match: json['match'] as String?,
      begin: json['begin'] as String?,
      end: json['end'] as String?,
      whileRe: json['while'] as String?,
      include: json['include'] as String?,
      captures: ruleMap(json['captures']),
      beginCaptures: ruleMap(json['beginCaptures']),
      endCaptures: ruleMap(json['endCaptures']),
      whileCaptures: ruleMap(json['whileCaptures']),
      patterns: ruleList(json['patterns']),
      repository: ruleMap(json['repository']),
      applyEndPatternLast:
          json['applyEndPatternLast'] == 1 ||
          json['applyEndPatternLast'] == true,
    );
  }
}

/// One grammar registration.
class RawGrammar {
  RawGrammar({
    required this.name,
    required this.scopeName,
    required this.patterns,
    required this.repository,
    required this.injections,
    required this.injectionSelector,
    required this.injectTo,
    required this.embeddedLangs,
  });

  final String name;
  final String scopeName;
  final List<RawRule> patterns;
  final Map<String, RawRule> repository;
  final Map<String, RawRule> injections;
  final String? injectionSelector;
  final List<String> injectTo;
  final List<String> embeddedLangs;

  /// Builds a fresh object graph from decoded JSON. vscode-textmate clones a
  /// grammar for every grammar instance that includes it, because rule ids are
  /// stored on the rule objects; building anew each time is the same thing.
  static RawGrammar fromJson(Map<String, dynamic> json) {
    List<String> strings(Object? v) =>
        v is List ? [for (final e in v) e as String] : const [];
    final repo = <String, RawRule>{};
    final rawRepo = json['repository'];
    if (rawRepo is Map) {
      for (final e in rawRepo.entries) {
        if (e.value is Map) {
          repo[e.key as String] = RawRule.fromJson(
            (e.value as Map).cast<String, dynamic>(),
          );
        }
      }
    }
    final inj = <String, RawRule>{};
    final rawInj = json['injections'];
    if (rawInj is Map) {
      for (final e in rawInj.entries) {
        if (e.value is Map) {
          inj[e.key as String] = RawRule.fromJson(
            (e.value as Map).cast<String, dynamic>(),
          );
        }
      }
    }
    final pats = <RawRule>[];
    final rawPats = json['patterns'];
    if (rawPats is List) {
      for (final e in rawPats) {
        if (e is Map) pats.add(RawRule.fromJson(e.cast<String, dynamic>()));
      }
    }
    return RawGrammar(
      name: json['name'] as String? ?? json['scopeName'] as String,
      scopeName: json['scopeName'] as String,
      patterns: pats,
      repository: repo,
      injections: inj,
      injectionSelector: json['injectionSelector'] as String?,
      injectTo: strings(json['injectTo']),
      embeddedLangs: strings(json['embeddedLangs']),
    );
  }
}
