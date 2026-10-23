// The theme half of shiki's css-variables setup, ported from vscode-textmate
// (Theme / ThemeTrieElement / ScopeStack) with the exact `tokenColors` of
// shiki's `createCssVariablesTheme({variablePrefix: '--shiki-', fontStyle:
// true})`. Colours are not hex values here but ids standing for the
// `--shiki-*` property each rule names.
library;

import 'api.dart';

/// vscode-textmate FontStyle bits.
const int fontNotSet = -1;
const int fontItalic = 1;
const int fontBold = 2;
const int fontUnderline = 4;

/// Colour ids: 0 = not set, otherwise an index into [colorTokens].
const int colorForeground = 1;

/// What each colour id means for the 9 token classes. Ids that name a
/// variable dsh's stylesheet does not define (`token-inserted`, ...) resolve to
/// the foreground, exactly as `color: var(--undefined)` inherits in CSS.
const List<HighlightToken?> colorTokens = [
  null, // 0: not set
  null, // 1: foreground
  HighlightToken.string, // 2
  HighlightToken.comment, // 3
  HighlightToken.constant, // 4
  HighlightToken.keyword, // 5
  HighlightToken.parameter, // 6
  HighlightToken.function, // 7
  HighlightToken.stringExpression, // 8
  HighlightToken.punctuation, // 9
  HighlightToken.link, // 10
  null, // 11: token-inserted (undefined in dsh)
  null, // 12: token-deleted
  null, // 13: token-changed
];

const Map<String, int> _colorIds = {
  'foreground': 1,
  'token-string': 2,
  'token-comment': 3,
  'token-constant': 4,
  'token-keyword': 5,
  'token-parameter': 6,
  'token-function': 7,
  'token-string-expression': 8,
  'token-punctuation': 9,
  'token-link': 10,
  'token-inserted': 11,
  'token-deleted': 12,
  'token-changed': 13,
};

class _RawRule {
  const _RawRule(this.scopes, {this.fontStyle, this.color});
  final List<String> scopes;
  final String? fontStyle;
  final String? color;
}

/// shiki's `createCssVariablesTheme` token colours, in its order.
const List<_RawRule> _tokenColors = [
  _RawRule([
    'keyword.operator.accessor',
    'meta.group.braces.round.function.arguments',
    'meta.template.expression',
    'markup.fenced_code meta.embedded.block',
  ], color: 'foreground'),
  _RawRule(['emphasis'], fontStyle: 'italic'),
  _RawRule([
    'strong',
    'markup.heading.markdown',
    'markup.bold.markdown',
  ], fontStyle: 'bold'),
  _RawRule(['markup.italic.markdown'], fontStyle: 'italic'),
  _RawRule(
    ['meta.link.inline.markdown'],
    fontStyle: 'underline',
    color: 'token-link',
  ),
  _RawRule([
    'string',
    'markup.fenced_code',
    'markup.inline',
  ], color: 'token-string'),
  _RawRule([
    'comment',
    'string.quoted.docstring.multi',
  ], color: 'token-comment'),
  _RawRule([
    'constant.numeric',
    'constant.language',
    'constant.other.placeholder',
    'constant.character.format.placeholder',
    'variable.language.this',
    'variable.other.object',
    'variable.other.class',
    'variable.other.constant',
    'meta.property-name',
    'meta.property-value',
    'support',
  ], color: 'token-constant'),
  _RawRule([
    'keyword',
    'storage.modifier',
    'storage.type',
    'storage.control.clojure',
    'entity.name.function.clojure',
    'entity.name.tag.yaml',
    'support.function.node',
    'support.type.property-name.json',
    'punctuation.separator.key-value',
    'punctuation.definition.template-expression',
  ], color: 'token-keyword'),
  _RawRule(['variable.parameter.function'], color: 'token-parameter'),
  _RawRule([
    'support.function',
    'entity.name.type',
    'entity.other.inherited-class',
    'meta.function-call',
    'meta.instance.constructor',
    'entity.other.attribute-name',
    'entity.name.function',
    'constant.keyword.clojure',
  ], color: 'token-function'),
  _RawRule([
    'entity.name.tag',
    'string.quoted',
    'string.regexp',
    'string.interpolated',
    'string.template',
    'string.unquoted.plain.out.yaml',
    'keyword.other.template',
  ], color: 'token-string-expression'),
  _RawRule([
    'punctuation.definition.arguments',
    'punctuation.definition.dict',
    'punctuation.separator',
    'meta.function-call.arguments',
  ], color: 'token-punctuation'),
  _RawRule([
    'markup.underline.link',
    'punctuation.definition.metadata.markdown',
  ], color: 'token-link'),
  _RawRule([
    'beginning.punctuation.definition.list.markdown',
  ], color: 'token-string'),
  _RawRule([
    'punctuation.definition.string.begin.markdown',
    'punctuation.definition.string.end.markdown',
    'string.other.link.title.markdown',
    'string.other.link.description.markdown',
  ], color: 'token-keyword'),
  _RawRule([
    'markup.inserted',
    'meta.diff.header.to-file',
    'punctuation.definition.inserted',
  ], color: 'token-inserted'),
  _RawRule([
    'markup.deleted',
    'meta.diff.header.from-file',
    'punctuation.definition.deleted',
  ], color: 'token-deleted'),
  _RawRule([
    'markup.changed',
    'punctuation.definition.changed',
  ], color: 'token-changed'),
];

// --- vscode-textmate theme -------------------------------------------------

class _ParsedRule {
  _ParsedRule(
    this.scope,
    this.parentScopes,
    this.index,
    this.fontStyle,
    this.color,
  );
  final String scope;
  final List<String>? parentScopes;
  final int index;
  final int fontStyle;
  final int color;
}

int _strcmp(String a, String b) => a.compareTo(b).sign;

int _strArrCmp(List<String>? a, List<String>? b) {
  if (a == null && b == null) return 0;
  if (a == null) return -1;
  if (b == null) return 1;
  if (a.length == b.length) {
    for (var i = 0; i < a.length; i++) {
      final r = _strcmp(a[i], b[i]);
      if (r != 0) return r;
    }
    return 0;
  }
  return a.length - b.length;
}

/// The resolved style of a scope path.
class StyleAttributes {
  const StyleAttributes(this.fontStyle, this.color);
  final int fontStyle;
  final int color;
}

class _TrieRule {
  _TrieRule(
    this.scopeDepth,
    List<String>? parentScopes,
    this.fontStyle,
    this.color,
  ) : parentScopes = parentScopes ?? const [];

  int scopeDepth;
  final List<String> parentScopes;
  int fontStyle;
  int color;

  _TrieRule clone() => _TrieRule(scopeDepth, parentScopes, fontStyle, color);

  void acceptOverwrite(int depth, int fontStyle, int color) {
    if (scopeDepth <= depth) scopeDepth = depth;
    if (fontStyle != fontNotSet) this.fontStyle = fontStyle;
    if (color != 0) this.color = color;
  }
}

class _TrieElement {
  _TrieElement(this.mainRule, [List<_TrieRule>? rulesWithParents])
    : rulesWithParentScopes = rulesWithParents ?? [];

  final _TrieRule mainRule;
  final List<_TrieRule> rulesWithParentScopes;
  final Map<String, _TrieElement> children = {};

  static int _cmpBySpecificity(_TrieRule a, _TrieRule b) {
    if (a.scopeDepth != b.scopeDepth) return b.scopeDepth - a.scopeDepth;
    var ai = 0;
    var bi = 0;
    while (true) {
      if (ai < a.parentScopes.length && a.parentScopes[ai] == '>') ai++;
      if (bi < b.parentScopes.length && b.parentScopes[bi] == '>') bi++;
      if (ai >= a.parentScopes.length || bi >= b.parentScopes.length) break;
      final diff = b.parentScopes[bi].length - a.parentScopes[ai].length;
      if (diff != 0) return diff;
      ai++;
      bi++;
    }
    return b.parentScopes.length - a.parentScopes.length;
  }

  List<_TrieRule> match(String scope) {
    if (scope.isNotEmpty) {
      final dot = scope.indexOf('.');
      final head = dot == -1 ? scope : scope.substring(0, dot);
      final tail = dot == -1 ? '' : scope.substring(dot + 1);
      final child = children[head];
      if (child != null) return child.match(tail);
    }
    final rules = [...rulesWithParentScopes, mainRule];
    // Stable sort (insertion sort; the lists are tiny).
    for (var i = 1; i < rules.length; i++) {
      final x = rules[i];
      var j = i - 1;
      while (j >= 0 && _cmpBySpecificity(rules[j], x) > 0) {
        rules[j + 1] = rules[j];
        j--;
      }
      rules[j + 1] = x;
    }
    return rules;
  }

  void insert(
    int depth,
    String scope,
    List<String>? parentScopes,
    int fontStyle,
    int color,
  ) {
    if (scope.isEmpty) {
      _insertHere(depth, parentScopes, fontStyle, color);
      return;
    }
    final dot = scope.indexOf('.');
    final head = dot == -1 ? scope : scope.substring(0, dot);
    final tail = dot == -1 ? '' : scope.substring(dot + 1);
    var child = children[head];
    if (child == null) {
      child = _TrieElement(mainRule.clone(), [
        for (final r in rulesWithParentScopes) r.clone(),
      ]);
      children[head] = child;
    }
    child.insert(depth + 1, tail, parentScopes, fontStyle, color);
  }

  void _insertHere(
    int depth,
    List<String>? parentScopes,
    int fontStyle,
    int color,
  ) {
    if (parentScopes == null) {
      mainRule.acceptOverwrite(depth, fontStyle, color);
      return;
    }
    for (final rule in rulesWithParentScopes) {
      if (_strArrCmp(rule.parentScopes, parentScopes) == 0) {
        rule.acceptOverwrite(depth, fontStyle, color);
        return;
      }
    }
    if (fontStyle == fontNotSet) fontStyle = mainRule.fontStyle;
    if (color == 0) color = mainRule.color;
    rulesWithParentScopes.add(_TrieRule(depth, parentScopes, fontStyle, color));
  }
}

/// A linked list of scope names (root first), as vscode-textmate's ScopeStack.
class ScopeStack {
  const ScopeStack(this.parent, this.scopeName);
  final ScopeStack? parent;
  final String scopeName;

  ScopeStack push(String name) => ScopeStack(this, name);

  List<String> segments() {
    final out = <String>[];
    for (ScopeStack? s = this; s != null; s = s.parent) {
      out.add(s.scopeName);
    }
    return out.reversed.toList(growable: false);
  }
}

bool _matchesScope(String scopeName, String pattern) =>
    pattern == scopeName ||
    (scopeName.startsWith(pattern) && scopeName[pattern.length] == '.');

bool _pathMatchesParents(ScopeStack? path, List<String> parents) {
  if (parents.isEmpty) return true;
  for (var index = 0; index < parents.length; index++) {
    var pattern = parents[index];
    var mustMatch = false;
    if (pattern == '>') {
      if (index == parents.length - 1) return false;
      pattern = parents[++index];
      mustMatch = true;
    }
    while (path != null) {
      if (_matchesScope(path.scopeName, pattern)) break;
      if (mustMatch) return false;
      path = path.parent;
    }
    if (path == null) return false;
    path = path.parent;
  }
  return true;
}

/// The css-variables theme as a vscode-textmate `Theme`.
class CssVariablesTheme {
  CssVariablesTheme._(this.defaults, this._root);

  /// The default style (foreground, no font style).
  final StyleAttributes defaults;
  final _TrieElement _root;
  final Map<String, List<_TrieRule>> _matchCache = {};

  static final CssVariablesTheme instance = _build();

  static CssVariablesTheme _build() {
    final parsed = <_ParsedRule>[];
    // shiki's normalizeTheme unshifts the default `{foreground, background}`.
    parsed.add(_ParsedRule('', null, 0, fontNotSet, colorForeground));
    for (var i = 0; i < _tokenColors.length; i++) {
      final raw = _tokenColors[i];
      var fontStyle = fontNotSet;
      final fs = raw.fontStyle;
      if (fs != null) {
        fontStyle = 0;
        for (final seg in fs.split(' ')) {
          switch (seg) {
            case 'italic':
              fontStyle |= fontItalic;
            case 'bold':
              fontStyle |= fontBold;
            case 'underline':
              fontStyle |= fontUnderline;
          }
        }
      }
      final color = raw.color == null ? 0 : _colorIds[raw.color]!;
      for (final scopeExpr in raw.scopes) {
        final segments = scopeExpr.trim().split(' ');
        final scope = segments.last;
        List<String>? parents;
        if (segments.length > 1) {
          parents = segments.sublist(0, segments.length - 1).reversed.toList();
        }
        parsed.add(_ParsedRule(scope, parents, i + 1, fontStyle, color));
      }
    }
    parsed.sort((a, b) {
      var r = _strcmp(a.scope, b.scope);
      if (r != 0) return r;
      r = _strArrCmp(a.parentScopes, b.parentScopes);
      if (r != 0) return r;
      return a.index - b.index;
    });
    var defaultFont = 0;
    var defaultColor = colorForeground;
    while (parsed.isNotEmpty && parsed.first.scope.isEmpty) {
      final d = parsed.removeAt(0);
      if (d.fontStyle != fontNotSet) defaultFont = d.fontStyle;
      if (d.color != 0) defaultColor = d.color;
    }
    final root = _TrieElement(_TrieRule(0, null, fontNotSet, 0));
    for (final r in parsed) {
      root.insert(0, r.scope, r.parentScopes, r.fontStyle, r.color);
    }
    return CssVariablesTheme._(
      StyleAttributes(defaultFont, defaultColor),
      root,
    );
  }

  /// Style of the innermost scope of [path] (null: no rule changes anything).
  StyleAttributes? match(ScopeStack path) {
    final rules = _matchCache.putIfAbsent(
      path.scopeName,
      () => _root.match(path.scopeName),
    );
    for (final rule in rules) {
      if (_pathMatchesParents(path.parent, rule.parentScopes)) {
        return StyleAttributes(rule.fontStyle, rule.color);
      }
    }
    return null;
  }
}
