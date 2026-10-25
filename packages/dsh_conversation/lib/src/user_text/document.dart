/// Original-text reconciliation for references and display-only masks. Rules
/// offer ranges in the original UTF-16 string; earlier starts win, then order
/// and stable ID. The raw message never passes through a display transform.
library;

import 'package:dsh_models/dsh_models.dart' show Observable;

class UserTextNode {
  UserTextNode(this.id, this.start, this.end, Map<String, Object?> data)
    : data = Map.unmodifiable(data);
  final String id;
  final int start, end;
  final Map<String, Object?> data;
  String raw(String text) => text.substring(start, end);
}

class UserTextContext {
  UserTextContext._(this._facts, this._reads);
  final Map<String, Object?> _facts, _reads;
  bool _active = true;
  Object? read(String key) {
    if (!_active) {
      throw StateError('User text facts may only be read synchronously');
    }
    final value = _facts[key];
    _reads[key] = value;
    return value;
  }
}

class UserTextRule {
  const UserTextRule({
    required this.id,
    required this.order,
    required this.match,
  });
  final String id;
  final double order;
  final UserTextNode? Function(String text, int from, UserTextContext context)
  match;
}

class UserTextTransformException implements Exception {
  const UserTextTransformException(this.ruleId, this.cause);
  final String ruleId;
  final Object cause;
  @override
  String toString() => 'User text rule "$ruleId" failed: $cause';
}

/// The registry retains rules, never document text or evaluators. An evaluator
/// owns its own cache and reads a rule snapshot at each call; removal is
/// idempotent and immediately visible to existing evaluators.
class UserTextRegistry {
  final _definitions = <String, UserTextRule>{};
  List<UserTextRule> _rules = const [];
  final _revision = Observable<int>(0);
  int get revision => _revision.value;
  Stream<int> get changes => _revision.changes;
  Future<void> dispose() => _revision.dispose();
  void Function() register(UserTextRule rule) {
    if (rule.id.isEmpty || rule.id == 'text' || !rule.order.isFinite) {
      throw ArgumentError(
        'User text rules require a non-reserved ID and finite order',
      );
    }
    if (_definitions.containsKey(rule.id)) {
      throw StateError('User text rule "${rule.id}" is already registered');
    }
    _definitions[rule.id] = rule;
    _refresh();
    var removed = false;
    return () {
      if (removed) return;
      removed = true;
      _definitions.remove(rule.id);
      _refresh();
    };
  }

  void _refresh() {
    final next = _definitions.values.toList()
      ..sort((a, b) {
        final order = a.order.compareTo(b.order);
        return order == 0 ? a.id.compareTo(b.id) : order;
      });
    _rules = List.unmodifiable(next);
    _revision.set(revision + 1);
  }

  UserTextDocument createDocument() => UserTextDocument._(this);
}

class _Query {
  const _Query(this.from, this.node, this.error);
  final int from;
  final UserTextNode? node;
  final UserTextTransformException? error;
}

class _Matcher {
  _Matcher(this.rule);
  final UserTextRule rule;
  final reads = <String, Object?>{};
  final queries = <_Query>[];
}

class UserTextDocument {
  UserTextDocument._(this._registry);
  final UserTextRegistry _registry;
  final _matchers = <String, _Matcher>{};
  String? _text;
  List<UserTextRule>? _rules;
  List<UserTextNode> _output = const [];
  bool _complete = false, _evaluating = false;

  List<UserTextNode> evaluate(
    String text, {
    Map<String, Object?> facts = const {},
  }) {
    if (_evaluating) {
      throw StateError('User text evaluation cannot be reentrant');
    }
    _evaluating = true;
    try {
      final rules = _registry._rules;
      var changed = !identical(_rules, rules);
      if (_text != text) {
        _text = text;
        _matchers.clear();
        _output = text.isEmpty ? const [] : [_plain(text, 0, text.length)];
        changed = true;
      }
      final matchers = <_Matcher>[];
      for (final rule in rules) {
        var matcher = _matchers[rule.id];
        if (matcher == null ||
            !identical(matcher.rule, rule) ||
            matcher.reads.entries.any(
              (e) => !_sameValue(e.value, facts[e.key]),
            )) {
          matcher = _Matcher(rule);
          _matchers[rule.id] = matcher;
          changed = true;
        }
        matchers.add(matcher);
      }
      _matchers.removeWhere((id, _) => !rules.any((r) => r.id == id));
      _rules = rules;
      if (!changed && _complete) return _output;
      _complete = false;
      final nodes = <UserTextNode>[];
      var cursor = 0;
      while (true) {
        UserTextNode? winner;
        for (final matcher in matchers) {
          final node = _next(matcher, text, cursor, facts);
          if (node != null && (winner == null || node.start < winner.start)) {
            winner = node;
          }
        }
        if (winner == null) {
          if (cursor < text.length) {
            nodes.add(_plain(text, cursor, text.length));
          }
          break;
        }
        if (cursor < winner.start) {
          nodes.add(_plain(text, cursor, winner.start));
        }
        nodes.add(winner);
        cursor = winner.end;
      }
      final old = {for (final node in _output) node.start: node};
      final aligned = [
        for (final node in nodes)
          if (old[node.start] case final prior? when _equalNode(prior, node))
            prior
          else
            node,
      ];
      if (aligned.length != _output.length ||
          Iterable<int>.generate(aligned.length)
              .any((i) => !identical(aligned[i], _output[i]))) {
        _output = List.unmodifiable(aligned);
      }
      _complete = true;
      return _output;
    } finally {
      _evaluating = false;
    }
  }

  UserTextNode? _next(
    _Matcher matcher,
    String text,
    int cursor,
    Map<String, Object?> facts,
  ) {
    for (final query in matcher.queries.reversed) {
      if (query.from > cursor) continue;
      if (query.error != null) {
        if (query.from == cursor) throw query.error!;
      } else if (query.node == null || query.node!.start >= cursor) {
        return query.node;
      }
    }
    final context = UserTextContext._(facts, matcher.reads);
    try {
      final node = matcher.rule.match(text, cursor, context);
      if (node != null) {
        if (node.start < cursor ||
            node.end <= node.start ||
            node.end > text.length) {
          throw StateError('Invalid original-text candidate range');
        }
        if (node.id == 'text') {
          if (node.data['text'] != node.raw(text)) {
            throw StateError('Text candidates must preserve their source');
          }
        } else if (node.id != matcher.rule.id) {
          throw StateError('Candidate ID must be its rule ID or text');
        }
      }
      matcher.queries.add(_Query(cursor, node, null));
      return node;
    } on Object catch (e) {
      final error = UserTextTransformException(matcher.rule.id, e);
      matcher.queries.add(_Query(cursor, null, error));
      throw error;
    } finally {
      context._active = false;
    }
  }
}

UserTextNode _plain(String text, int start, int end) =>
    UserTextNode('text', start, end, {'text': text.substring(start, end)});
bool _sameValue(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is num && b is num) {
    if (a.isNaN && b.isNaN) return true;
    if (a == 0 && b == 0) return a.isNegative == b.isNegative;
    return a == b;
  }
  return (a is String || a is bool) && a == b;
}

bool _equalNode(UserTextNode a, UserTextNode b) =>
    a.id == b.id &&
    a.start == b.start &&
    a.end == b.end &&
    _equalJson(a.data, b.data);
bool _equalJson(Object? a, Object? b) {
  if (_sameValue(a, b)) return true;
  if (a is List && b is List) {
    return a.length == b.length &&
        Iterable<int>.generate(a.length).every((i) => _equalJson(a[i], b[i]));
  }
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((key) => b.containsKey(key) && _equalJson(a[key], b[key]));
  }
  return false;
}
