/// Shared ranking for menu candidates (dsh `rankByName`, ui-primitives): the
/// query must be a case-insensitive ordered subsequence of the candidate name
/// or, when the candidate carries one, of its display label. Prefix hits rank
/// first, then the strongest alignment score over either key, then the source
/// order of the input.
library;

const double _noMatch = double.negativeInfinity;

int _boundaryBonus(String name, int index) =>
    index == 0 || name[index - 1] == '-' || name[index - 1] == '_' ? 8 : 0;

/// The strongest ordered-subsequence alignment of [query] in [name] in
/// O(name x query): boundary and adjacent matches earn weight, skipped and
/// leading characters cost weight. Null when [query] is not a subsequence.
/// Both arguments are compared as given (lower-case them first).
double? alignmentScore(String name, String query) {
  if (query.length > name.length) return null;
  var previous = List<double>.filled(name.length, _noMatch);
  for (var index = 0; index < name.length; index++) {
    if (name[index] == query[0]) {
      previous[index] = (1 + _boundaryBonus(name, index) - index).toDouble();
    }
  }
  for (var q = 1; q < query.length; q++) {
    final current = List<double>.filled(name.length, _noMatch);
    // Sweep the previous row once: `left` is its score one character back
    // (the adjacent continuation), `leftLeft` two back (the earliest gapped).
    var left = _noMatch;
    var leftLeft = _noMatch;
    var bestGapped = _noMatch;
    for (var index = 0; index < previous.length; index++) {
      final prior = previous[index];
      if (leftLeft != _noMatch) {
        bestGapped = _max(bestGapped, leftLeft + index - 2);
      }
      if (name[index] == query[q]) {
        final bonus = 1 + _boundaryBonus(name, index);
        var score = _noMatch;
        if (left != _noMatch) score = left + bonus + 4;
        if (bestGapped != _noMatch) {
          score = _max(score, bestGapped + bonus + 1 - index);
        }
        current[index] = score;
      }
      leftLeft = left;
      left = prior;
    }
    previous = current;
  }
  var best = _noMatch;
  for (final score in previous) {
    best = _max(best, score);
  }
  return best == _noMatch ? null : best;
}

double _max(double a, double b) => a > b ? a : b;

/// Rank [items] by a menu query. [name] is each item's search key, [label]
/// an optional second one (a localized title). Returns the input list itself
/// for an empty query, else the matching items: prefix hits first, then by
/// alignment score, then in source order.
List<T> rankByName<T>(
  List<T> items,
  String rawQuery, {
  required String Function(T item) name,
  String? Function(T item)? label,
}) {
  final query = rawQuery.toLowerCase();
  if (query.isEmpty) return items;
  final ranked = <({T item, int index, bool prefix, double score})>[];
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    final keys = [name(item), ?label?.call(item)];
    var prefix = false;
    double? score;
    for (final key in keys) {
      final lower = key.toLowerCase();
      final keyScore = alignmentScore(lower, query);
      if (keyScore == null) continue;
      prefix = prefix || lower.startsWith(query);
      score = score == null ? keyScore : _max(score, keyScore);
    }
    if (score != null) {
      ranked.add((item: item, index: index, prefix: prefix, score: score));
    }
  }
  ranked.sort((a, b) {
    final byPrefix = (b.prefix ? 1 : 0) - (a.prefix ? 1 : 0);
    if (byPrefix != 0) return byPrefix;
    final byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    return a.index - b.index;
  });
  return [for (final r in ranked) r.item];
}
