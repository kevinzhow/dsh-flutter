/// Put the account and official providers first, preserving every other
/// relative order (dsh `orderModelProviders`, ui-model-selection). Model order
/// within each group is unchanged.
List<T> orderModelProviders<T>(List<T> groups, String Function(T group) id) {
  int rank(T group) {
    final key = id(group);
    return key == 'deepseek-account' ? 0 : (key == 'deepseek-official' ? 1 : 2);
  }

  // A stable sort: the rank is the only key, ties keep the catalog order.
  final indexed = [for (var i = 0; i < groups.length; i++) (i, groups[i])];
  indexed.sort((a, b) {
    final byRank = rank(a.$2).compareTo(rank(b.$2));
    return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
  });
  return [for (final e in indexed) e.$2];
}
