import 'dart:convert';

import 'package:dsh_highlight/dsh_highlight.dart';

/// A [GrammarSource] over in-memory grammar maps (for engine unit tests).
class MemorySource implements GrammarSource {
  MemorySource(Map<String, Map<String, Object?>> grammars)
    : _json = {for (final e in grammars.entries) e.key: jsonEncode(e.value)};

  final Map<String, String> _json;

  /// How many times each grammar was read.
  final Map<String, int> reads = {};

  @override
  Set<String> get available => _json.keys.toSet();

  @override
  Future<String> read(String grammarId) async {
    reads[grammarId] = (reads[grammarId] ?? 0) + 1;
    await Future<void>.delayed(Duration.zero);
    return _json[grammarId]!;
  }
}
