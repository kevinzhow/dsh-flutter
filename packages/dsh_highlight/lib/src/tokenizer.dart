// The TextMate tokenizer: vscode-textmate's Grammar, StateStack,
// AttributedScopeStack, LineTokens and _tokenizeString ported to Dart, with
// the css-variables theme applied while scopes are pushed (as the real
// tokenizer does), so a token's colour and font style are known without
// keeping its scope names.
library;

import 'compiled_pattern.dart';
import 'raw_grammar.dart';
import 'rules.dart';
import 'theme.dart';

// --- attributes (colour id + font style) -------------------------------------

int _mergeAttrs(int existing, StyleAttributes? style) {
  var font = (existing >> 8) & 0xf;
  var color = existing & 0xff;
  if (style != null) {
    if (style.fontStyle != fontNotSet) font = style.fontStyle;
    if (style.color != 0) color = style.color;
  }
  return (font << 8) | color;
}

int attrColor(int attrs) => attrs & 0xff;
int attrFontStyle(int attrs) => (attrs >> 8) & 0xf;

class AttributedScopeStack {
  AttributedScopeStack(this.parent, this.scopePath, this.attrs);

  final AttributedScopeStack? parent;
  final ScopeStack scopePath;
  final int attrs;
  List<String>? _names;

  static AttributedScopeStack createRootAndLookUp(
    String scopeName,
    int attrs,
    CssVariablesTheme theme,
  ) {
    final path = ScopeStack(null, scopeName);
    return AttributedScopeStack(
      null,
      path,
      _mergeAttrs(attrs, theme.match(path)),
    );
  }

  static AttributedScopeStack createRoot(String scopeName, int attrs) =>
      AttributedScopeStack(null, ScopeStack(null, scopeName), attrs);

  List<String> getScopeNames() => _names ??= scopePath.segments();

  AttributedScopeStack pushAttributed(
    String? scopePath,
    CssVariablesTheme theme,
  ) {
    if (scopePath == null) return this;
    if (!scopePath.contains(' ')) return _push(this, scopePath, theme);
    var result = this;
    for (final scope in scopePath.split(' ')) {
      result = _push(result, scope, theme);
    }
    return result;
  }

  static AttributedScopeStack _push(
    AttributedScopeStack target,
    String scopeName,
    CssVariablesTheme theme,
  ) {
    final newPath = target.scopePath.push(scopeName);
    final style = theme.match(newPath);
    return AttributedScopeStack(
      target,
      newPath,
      _mergeAttrs(target.attrs, style),
    );
  }
}

// --- rule stack ----------------------------------------------------------------

class StateStack {
  StateStack(
    this.parent,
    this.ruleId,
    this._enterPos,
    this._anchorPos,
    this.beginRuleCapturedEOL,
    this.endRule,
    this.nameScopesList,
    this.contentNameScopesList,
  ) : depth = parent == null ? 1 : parent.depth + 1;

  final StateStack? parent;
  final int ruleId;
  final bool beginRuleCapturedEOL;
  final String? endRule;
  final AttributedScopeStack nameScopesList;
  final AttributedScopeStack contentNameScopesList;
  final int depth;
  int _enterPos;
  int _anchorPos;

  int get enterPos => _enterPos;
  int get anchorPos => _anchorPos;

  void reset() {
    for (StateStack? el = this; el != null; el = el.parent) {
      el._enterPos = -1;
      el._anchorPos = -1;
    }
  }

  StateStack? pop() => parent;
  StateStack safePop() => parent ?? this;

  StateStack push(
    int ruleId,
    int enterPos,
    int anchorPos,
    bool beginRuleCapturedEOL,
    String? endRule,
    AttributedScopeStack nameScopesList,
    AttributedScopeStack contentNameScopesList,
  ) => StateStack(
    this,
    ruleId,
    enterPos,
    anchorPos,
    beginRuleCapturedEOL,
    endRule,
    nameScopesList,
    contentNameScopesList,
  );

  Rule getRule(Grammar grammar) => grammar.getRule(ruleId)!;

  StateStack withContentNameScopesList(AttributedScopeStack contentNames) {
    if (identical(contentNameScopesList, contentNames)) return this;
    return parent!.push(
      ruleId,
      _enterPos,
      _anchorPos,
      beginRuleCapturedEOL,
      endRule,
      nameScopesList,
      contentNames,
    );
  }

  StateStack withEndRule(String endRule) {
    if (this.endRule == endRule) return this;
    return StateStack(
      parent,
      ruleId,
      _enterPos,
      _anchorPos,
      beginRuleCapturedEOL,
      endRule,
      nameScopesList,
      contentNameScopesList,
    );
  }

  bool hasSameRuleAs(StateStack other) {
    StateStack? el = this;
    while (el != null && el._enterPos == other._enterPos) {
      if (el.ruleId == other.ruleId) return true;
      el = el.parent;
    }
    return false;
  }
}

// --- scope selectors (injections) -------------------------------------------------

typedef ScopeMatcher = bool Function(List<String> scopes);

class _SelectorMatcher {
  _SelectorMatcher(this.matcher, this.priority);
  final ScopeMatcher matcher;
  final int priority;
}

bool _scopesAreMatching(String thisScopeName, String scopeName) {
  if (thisScopeName == scopeName) return true;
  final len = scopeName.length;
  return thisScopeName.length > len &&
      thisScopeName.startsWith(scopeName) &&
      thisScopeName[len] == '.';
}

bool _nameMatcher(List<String> identifiers, List<String> scopes) {
  if (scopes.length < identifiers.length) return false;
  var lastIndex = 0;
  for (final identifier in identifiers) {
    var found = false;
    for (var i = lastIndex; i < scopes.length; i++) {
      if (_scopesAreMatching(scopes[i], identifier)) {
        lastIndex = i + 1;
        found = true;
        break;
      }
    }
    if (!found) return false;
  }
  return true;
}

final RegExp _selectorToken = RegExp(r'([LR]:|[\w\.:][\w\.:\-]*|[\,\|\-\(\)])');
final RegExp _isIdentifier = RegExp(r'[\w\.:]+');

List<_SelectorMatcher> _createMatchers(String selector) {
  final tokens = _selectorToken.allMatches(selector).map((m) => m[0]!).toList();
  var pos = 0;
  String? token = tokens.isEmpty ? null : tokens[0];
  void next() {
    pos++;
    token = pos < tokens.length ? tokens[pos] : null;
  }

  bool isIdentifier(String? t) => t != null && _isIdentifier.hasMatch(t);

  late ScopeMatcher? Function() parseOperand;
  late ScopeMatcher Function() parseConjunction;
  late ScopeMatcher Function() parseInnerExpression;

  parseOperand = () {
    if (token == '-') {
      next();
      final negate = parseOperand();
      return (scopes) => negate != null && !negate(scopes);
    }
    if (token == '(') {
      next();
      final inner = parseInnerExpression();
      if (token == ')') next();
      return inner;
    }
    if (isIdentifier(token)) {
      final identifiers = <String>[];
      do {
        identifiers.add(token!);
        next();
      } while (isIdentifier(token));
      return (scopes) => _nameMatcher(identifiers, scopes);
    }
    return null;
  };
  parseConjunction = () {
    final matchers = <ScopeMatcher>[];
    var m = parseOperand();
    while (m != null) {
      matchers.add(m);
      m = parseOperand();
    }
    return (scopes) => matchers.every((x) => x(scopes));
  };
  parseInnerExpression = () {
    final matchers = <ScopeMatcher>[];
    ScopeMatcher? m = parseConjunction();
    while (m != null) {
      matchers.add(m);
      if (token == '|' || token == ',') {
        do {
          next();
        } while (token == '|' || token == ',');
      } else {
        break;
      }
      m = parseConjunction();
    }
    return (scopes) => matchers.any((x) => x(scopes));
  };

  final results = <_SelectorMatcher>[];
  while (token != null) {
    var priority = 0;
    final t = token!;
    if (t.length == 2 && t[1] == ':') {
      if (t[0] == 'R') priority = 1;
      if (t[0] == 'L') priority = -1;
      next();
    }
    final matcher = parseConjunction();
    results.add(_SelectorMatcher(matcher, priority));
    if (token != ',') break;
    next();
  }
  return results;
}

class _Injection {
  _Injection(this.matcher, this.ruleId, this.priority);
  final ScopeMatcher matcher;
  final int ruleId;
  final int priority;
}

// --- line tokens ---------------------------------------------------------------------

class _LineTokens {
  // Flattened [start, attrs, start, attrs, ...].
  final List<int> binary = [];
  int _lastTokenEndIndex = 0;

  void produce(StateStack stack, int endIndex) =>
      produceFromScopes(stack.contentNameScopesList, endIndex);

  void produceFromScopes(AttributedScopeStack scopes, int endIndex) {
    if (_lastTokenEndIndex >= endIndex) return;
    final attrs = scopes.attrs;
    if (binary.isNotEmpty && binary[binary.length - 1] == attrs) {
      _lastTokenEndIndex = endIndex;
      return;
    }
    binary
      ..add(_lastTokenEndIndex)
      ..add(attrs);
    _lastTokenEndIndex = endIndex;
  }

  List<int> getBinaryResult(StateStack stack, int lineLength) {
    if (binary.isNotEmpty && binary[binary.length - 2] == lineLength - 1) {
      binary
        ..removeLast()
        ..removeLast();
    }
    if (binary.isEmpty) {
      _lastTokenEndIndex = -1;
      produce(stack, lineLength);
      binary[binary.length - 2] = 0;
    }
    return binary;
  }
}

class _LocalStackElement {
  _LocalStackElement(this.scopes, this.endPos);
  final AttributedScopeStack scopes;
  final int endPos;
}

class TokenizeLineResult {
  const TokenizeLineResult(this.tokens, this.ruleStack, this.stoppedEarly);

  /// [start, attrs, start, attrs, ...] over the line (without the newline).
  final List<int> tokens;
  final StateStack ruleStack;
  final bool stoppedEarly;
}

class _TokenizeStringResult {
  const _TokenizeStringResult(this.stack, this.stoppedEarly);
  final StateStack stack;
  final bool stoppedEarly;
}

class _MatchResult {
  const _MatchResult(this.match, this.ruleId, {this.priorityMatch = false});
  final OnigMatch match;
  final int ruleId;
  final bool priorityMatch;
}

// --- the grammar --------------------------------------------------------------------

/// Where a [Grammar] finds other grammars.
abstract interface class GrammarRepository {
  /// Decoded registration JSON for [scopeName], if loaded.
  Map<String, dynamic>? rawGrammarJson(String scopeName);

  /// Scope names of grammars that inject themselves into [targetScope].
  List<String> injectionScopeNames(String targetScope);
}

class Grammar implements RuleHost {
  Grammar(this.rootScopeName, this._repository, this.patternCache)
    : _grammar = InitializedGrammar.from(
        RawGrammar.fromJson(_repository.rawGrammarJson(rootScopeName)!),
        null,
      );

  final String rootScopeName;
  final GrammarRepository _repository;
  final InitializedGrammar _grammar;
  final CssVariablesTheme _theme = CssVariablesTheme.instance;

  @override
  final PatternCache patternCache;

  final List<Rule?> _rules = [null];
  final Map<String, InitializedGrammar> _included = {};
  int _rootId = -1;
  List<_Injection>? _injections;

  @override
  int registerRule(Rule Function(int id) factory) {
    final id = _rules.length;
    _rules.add(null);
    final rule = factory(id);
    _rules[id] = rule;
    return id;
  }

  @override
  Rule? getRule(int id) => id >= 0 && id < _rules.length ? _rules[id] : null;

  @override
  InitializedGrammar? getExternalGrammar(
    String scopeName,
    Map<String, RawRule>? repository,
  ) {
    final cached = _included[scopeName];
    if (cached != null) return cached;
    final json = _repository.rawGrammarJson(scopeName);
    if (json == null) return null;
    final g = InitializedGrammar.from(
      RawGrammar.fromJson(json),
      repository?[r'$base'],
    );
    _included[scopeName] = g;
    return g;
  }

  // --- injections ---

  List<_Injection> _getInjections() {
    final cached = _injections;
    if (cached != null) return cached;
    final result = <_Injection>[];
    void collect(String selector, RawRule rule, InitializedGrammar grammar) {
      final matchers = _createMatchers(selector);
      final ruleId = RuleFactory.getCompiledRuleId(
        rule,
        this,
        grammar.repository,
      );
      for (final m in matchers) {
        result.add(_Injection(m.matcher, ruleId, m.priority));
      }
    }

    for (final e in _grammar.raw.injections.entries) {
      collect(e.key, e.value, _grammar);
    }
    for (final injectorScope in _repository.injectionScopeNames(
      rootScopeName,
    )) {
      final g = getExternalGrammar(injectorScope, null);
      final selector = g?.raw.injectionSelector;
      if (g != null && selector != null) {
        final asRule = RawRule(patterns: g.raw.patterns, name: g.raw.scopeName);
        collect(selector, asRule, g);
      }
    }
    // Stable sort by priority.
    final indexed = [for (var i = 0; i < result.length; i++) (i, result[i])];
    indexed.sort((a, b) {
      final d = a.$2.priority - b.$2.priority;
      return d != 0 ? d : a.$1 - b.$1;
    });
    return _injections = [for (final e in indexed) e.$2];
  }

  // --- tokenizing ---

  /// Tokenizes one [line] (no line terminator) given the state after the
  /// previous line ([prevState] null for the first line).
  TokenizeLineResult tokenizeLine(
    String line,
    StateStack? prevState,
    int timeLimitMs,
  ) {
    if (_rootId == -1) {
      _rootId = RuleFactory.getCompiledRuleId(
        _grammar.repository[r'$self']!,
        this,
        _grammar.repository,
      );
      _getInjections();
    }
    bool isFirstLine;
    StateStack state;
    if (prevState == null) {
      isFirstLine = true;
      final defaults = _theme.defaults;
      final defaultAttrs = (defaults.fontStyle << 8) | defaults.color;
      final rootName = getRule(_rootId)!.getName(null);
      final scopeList = rootName != null
          ? AttributedScopeStack.createRootAndLookUp(
              rootName,
              defaultAttrs,
              _theme,
            )
          : AttributedScopeStack.createRoot('unknown', defaultAttrs);
      state = StateStack(
        null,
        _rootId,
        -1,
        -1,
        false,
        null,
        scopeList,
        scopeList,
      );
    } else {
      isFirstLine = false;
      prevState.reset();
      state = prevState;
    }
    final lineText = '$line\n';
    final lineLength = lineText.length;
    final lineTokens = _LineTokens();
    final r = _tokenizeString(
      lineText,
      isFirstLine,
      0,
      state,
      lineTokens,
      true,
      timeLimitMs,
    );
    return TokenizeLineResult(
      lineTokens.getBinaryResult(r.stack, lineLength),
      r.stack,
      r.stoppedEarly,
    );
  }

  _TokenizeStringResult _tokenizeString(
    String lineText,
    bool isFirstLine,
    int linePos,
    StateStack stack,
    _LineTokens lineTokens,
    bool checkWhileConditions,
    int timeLimitMs,
  ) {
    final lineLength = lineText.length;
    var stop = false;
    var anchorPosition = -1;

    if (checkWhileConditions) {
      final w = _checkWhileConditions(
        lineText,
        isFirstLine,
        linePos,
        stack,
        lineTokens,
      );
      stack = w.stack;
      linePos = w.linePos;
      isFirstLine = w.isFirstLine;
      anchorPosition = w.anchorPosition;
    }

    final stopwatch = timeLimitMs != 0 ? (Stopwatch()..start()) : null;
    while (!stop) {
      if (stopwatch != null && stopwatch.elapsedMilliseconds > timeLimitMs) {
        return _TokenizeStringResult(stack, true);
      }
      final r = _matchRuleOrInjections(
        lineText,
        isFirstLine,
        linePos,
        stack,
        anchorPosition,
      );
      if (r == null) {
        lineTokens.produce(stack, lineLength);
        stop = true;
        break;
      }
      final m = r.match;
      final matchStart = m.start(0);
      final matchEnd = m.end(0);
      final hasAdvanced = matchEnd > linePos;

      if (r.ruleId == endRuleId) {
        final poppedRule = stack.getRule(this) as BeginEndRule;
        lineTokens.produce(stack, matchStart);
        stack = stack.withContentNameScopesList(stack.nameScopesList);
        _handleCaptures(
          lineText,
          isFirstLine,
          stack,
          lineTokens,
          poppedRule.endCaptures,
          m,
        );
        lineTokens.produce(stack, matchEnd);
        final popped = stack;
        stack = stack.parent!;
        anchorPosition = popped.anchorPos;
        if (!hasAdvanced && popped.enterPos == linePos) {
          // Grammar pushed & popped a rule without advancing: endless loop.
          stack = popped;
          lineTokens.produce(stack, lineLength);
          stop = true;
          break;
        }
      } else {
        final rule = getRule(r.ruleId)!;
        lineTokens.produce(stack, matchStart);
        final beforePush = stack;
        final scopeName = rule.getName(m);
        final nameScopesList = stack.contentNameScopesList.pushAttributed(
          scopeName,
          _theme,
        );
        stack = stack.push(
          r.ruleId,
          linePos,
          anchorPosition,
          matchEnd == lineLength,
          null,
          nameScopesList,
          nameScopesList,
        );
        if (rule is BeginEndRule) {
          _handleCaptures(
            lineText,
            isFirstLine,
            stack,
            lineTokens,
            rule.beginCaptures,
            m,
          );
          lineTokens.produce(stack, matchEnd);
          anchorPosition = matchEnd;
          final contentName = rule.getContentName(m);
          final contentList = nameScopesList.pushAttributed(
            contentName,
            _theme,
          );
          stack = stack.withContentNameScopesList(contentList);
          if (rule.endHasBackReferences) {
            stack = stack.withEndRule(
              rule.getEndWithResolvedBackReferences(lineText, m),
            );
          }
          if (!hasAdvanced && beforePush.hasSameRuleAs(stack)) {
            stack = stack.pop()!;
            lineTokens.produce(stack, lineLength);
            stop = true;
            break;
          }
        } else if (rule is BeginWhileRule) {
          _handleCaptures(
            lineText,
            isFirstLine,
            stack,
            lineTokens,
            rule.beginCaptures,
            m,
          );
          lineTokens.produce(stack, matchEnd);
          anchorPosition = matchEnd;
          final contentName = rule.getContentName(m);
          final contentList = nameScopesList.pushAttributed(
            contentName,
            _theme,
          );
          stack = stack.withContentNameScopesList(contentList);
          if (rule.whileHasBackReferences) {
            stack = stack.withEndRule(
              rule.getWhileWithResolvedBackReferences(lineText, m),
            );
          }
          if (!hasAdvanced && beforePush.hasSameRuleAs(stack)) {
            stack = stack.pop()!;
            lineTokens.produce(stack, lineLength);
            stop = true;
            break;
          }
        } else {
          final matching = rule as MatchRule;
          _handleCaptures(
            lineText,
            isFirstLine,
            stack,
            lineTokens,
            matching.captures,
            m,
          );
          lineTokens.produce(stack, matchEnd);
          stack = stack.pop()!;
          if (!hasAdvanced) {
            stack = stack.safePop();
            lineTokens.produce(stack, lineLength);
            stop = true;
            break;
          }
        }
      }
      if (matchEnd > linePos) {
        linePos = matchEnd;
        isFirstLine = false;
      }
    }
    return _TokenizeStringResult(stack, false);
  }

  ({StateStack stack, int linePos, int anchorPosition, bool isFirstLine})
  _checkWhileConditions(
    String lineText,
    bool isFirstLine,
    int linePos,
    StateStack stack,
    _LineTokens lineTokens,
  ) {
    var anchorPosition = stack.beginRuleCapturedEOL ? 0 : -1;
    final whileRules = <({BeginWhileRule rule, StateStack stack})>[];
    for (StateStack? node = stack; node != null; node = node.pop()) {
      final r = node.getRule(this);
      if (r is BeginWhileRule) whileRules.add((rule: r, stack: node));
    }
    while (whileRules.isNotEmpty) {
      final whileRule = whileRules.removeLast();
      final scanner = whileRule.rule.compileWhileAG(
        this,
        whileRule.stack.endRule,
        isFirstLine,
        linePos == anchorPosition,
      );
      final r = scanner.find(lineText, linePos);
      if (r != null) {
        if (r.ruleId != whileRuleId) {
          stack = whileRule.stack.pop()!;
          break;
        }
        final m = r.match;
        lineTokens.produce(whileRule.stack, m.start(0));
        _handleCaptures(
          lineText,
          isFirstLine,
          whileRule.stack,
          lineTokens,
          whileRule.rule.whileCaptures,
          m,
        );
        lineTokens.produce(whileRule.stack, m.end(0));
        anchorPosition = m.end(0);
        if (m.end(0) > linePos) {
          linePos = m.end(0);
          isFirstLine = false;
        }
      } else {
        stack = whileRule.stack.pop()!;
        break;
      }
    }
    return (
      stack: stack,
      linePos: linePos,
      anchorPosition: anchorPosition,
      isFirstLine: isFirstLine,
    );
  }

  _MatchResult? _matchRuleOrInjections(
    String lineText,
    bool isFirstLine,
    int linePos,
    StateStack stack,
    int anchorPosition,
  ) {
    final matchResult = _matchRule(
      lineText,
      isFirstLine,
      linePos,
      stack,
      anchorPosition,
    );
    final injections = _getInjections();
    if (injections.isEmpty) return matchResult;
    final injectionResult = _matchInjections(
      injections,
      lineText,
      isFirstLine,
      linePos,
      stack,
      anchorPosition,
    );
    if (injectionResult == null) return matchResult;
    if (matchResult == null) return injectionResult;
    final matchScore = matchResult.match.start(0);
    final injectionScore = injectionResult.match.start(0);
    if (injectionScore < matchScore ||
        (injectionResult.priorityMatch && injectionScore == matchScore)) {
      return injectionResult;
    }
    return matchResult;
  }

  _MatchResult? _matchRule(
    String lineText,
    bool isFirstLine,
    int linePos,
    StateStack stack,
    int anchorPosition,
  ) {
    final rule = stack.getRule(this);
    final scanner = rule.compileAG(
      this,
      stack.endRule,
      isFirstLine,
      linePos == anchorPosition,
    );
    final r = scanner.find(lineText, linePos);
    return r == null ? null : _MatchResult(r.match, r.ruleId);
  }

  _MatchResult? _matchInjections(
    List<_Injection> injections,
    String lineText,
    bool isFirstLine,
    int linePos,
    StateStack stack,
    int anchorPosition,
  ) {
    var bestRating = 1 << 62;
    OnigMatch? bestMatch;
    var bestRuleId = 0;
    var bestPriority = 0;
    final scopes = stack.contentNameScopesList.getScopeNames();
    for (final injection in injections) {
      if (!injection.matcher(scopes)) continue;
      final rule = getRule(injection.ruleId)!;
      final scanner = rule.compileAG(
        this,
        null,
        isFirstLine,
        linePos == anchorPosition,
      );
      final r = scanner.find(lineText, linePos);
      if (r == null) continue;
      final rating = r.match.start(0);
      if (rating >= bestRating) continue;
      bestRating = rating;
      bestMatch = r.match;
      bestRuleId = r.ruleId;
      bestPriority = injection.priority;
      if (bestRating == linePos) break;
    }
    if (bestMatch == null) return null;
    return _MatchResult(
      bestMatch,
      bestRuleId,
      priorityMatch: bestPriority == -1,
    );
  }

  void _handleCaptures(
    String lineText,
    bool isFirstLine,
    StateStack stack,
    _LineTokens lineTokens,
    List<CaptureRule?> captures,
    OnigMatch m,
  ) {
    if (captures.isEmpty) return;
    final len = captures.length < m.groupCount + 1
        ? captures.length
        : m.groupCount + 1;
    final localStack = <_LocalStackElement>[];
    final maxEnd = m.end(0);
    for (var i = 0; i < len; i++) {
      final captureRule = captures[i];
      if (captureRule == null) continue;
      final start = m.start(i);
      if (start < 0) continue;
      final end = m.end(i);
      if (end - start == 0) continue;
      if (start > maxEnd) break;
      while (localStack.isNotEmpty && localStack.last.endPos <= start) {
        lineTokens.produceFromScopes(
          localStack.last.scopes,
          localStack.last.endPos,
        );
        localStack.removeLast();
      }
      if (localStack.isNotEmpty) {
        lineTokens.produceFromScopes(localStack.last.scopes, start);
      } else {
        lineTokens.produce(stack, start);
      }
      if (captureRule.retokenizeWith != 0) {
        final scopeName = captureRule.getName(m);
        final nameScopesList = stack.contentNameScopesList.pushAttributed(
          scopeName,
          _theme,
        );
        final contentName = captureRule.getContentName(m);
        final contentList = nameScopesList.pushAttributed(contentName, _theme);
        final stackClone = stack.push(
          captureRule.retokenizeWith,
          start,
          -1,
          false,
          null,
          nameScopesList,
          contentList,
        );
        _tokenizeString(
          lineText.substring(0, end),
          isFirstLine && start == 0,
          start,
          stackClone,
          lineTokens,
          false,
          0,
        );
        continue;
      }
      final scopeName = captureRule.getName(m);
      if (scopeName != null) {
        final base = localStack.isNotEmpty
            ? localStack.last.scopes
            : stack.contentNameScopesList;
        localStack.add(
          _LocalStackElement(base.pushAttributed(scopeName, _theme), end),
        );
      }
    }
    while (localStack.isNotEmpty) {
      lineTokens.produceFromScopes(
        localStack.last.scopes,
        localStack.last.endPos,
      );
      localStack.removeLast();
    }
  }
}
