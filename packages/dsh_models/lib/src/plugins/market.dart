import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_plugin_market.dart';

import '../observable.dart';
import '../settings/host_remotes.dart';

class PluginDiscoverQuery {
  const PluginDiscoverQuery({
    this.text = '',
    this.category,
    this.labels = const [],
    this.sort = const MarketSortIndex(),
  });
  final String text;
  final String? category;
  final List<String> labels;
  final MarketSort sort;
  PluginDiscoverQuery withText(String value) => PluginDiscoverQuery(
    text: value,
    category: category,
    labels: labels,
    sort:
        text.trim().isEmpty &&
            value.trim().isNotEmpty &&
            sort is MarketSortIndex
        ? const MarketSortRelevance()
        : value.trim().isEmpty && sort is MarketSortRelevance
        ? const MarketSortIndex()
        : sort,
  );
  PluginDiscoverQuery declared(MarketIndexMetadata metadata) {
    final nextCategory = metadata.categories.containsKey(category)
        ? category
        : null;
    final nextLabels = labels.where(metadata.labels.containsKey).toList();
    final currentSort = sort;
    final nextSort =
        currentSort is MarketSortKey &&
            !metadata.sortKeys.containsKey(currentSort.id)
        ? const MarketSortIndex()
        : sort;
    return nextCategory == category &&
            nextLabels.length == labels.length &&
            identical(nextSort, sort)
        ? this
        : PluginDiscoverQuery(
            text: text,
            category: nextCategory,
            labels: nextLabels,
            sort: nextSort,
          );
  }
}

enum PluginDiscoverStatus { idle, loading, ready, error }

enum PluginListingStatus { loading, more, ready, error }

class PluginListing {
  const PluginListing({
    required this.url,
    required this.query,
    required this.status,
    this.value,
    this.answered,
    this.failure,
  });
  final String url;
  final PluginDiscoverQuery query;
  final PluginListingStatus status;
  final MarketSearchResult? value;
  final PluginDiscoverQuery? answered;
  final String? failure;
}

/// Marketplace pages pin the Host document's fetchedAt. A replacement restarts
/// from page one once; a second replacement fails and leaves the prior result.
class PluginMarketModel {
  PluginMarketModel(this.remotes) {
    _events = remotes.hostEvents.listen((event) {
      if (event is! EmitEvent) return;
      if (event.event == 'plugin-market/changed') {
        if (status != PluginDiscoverStatus.idle) unawaited(loadIndexes());
      } else if (event.event == 'plugin-manager/changed' &&
          listing?.status == PluginListingStatus.ready) {
        unawaited(refreshAnnotations());
      }
    });
    _generations = remotes.generations.listen((_) {
      _indexRead++;
      _listingRead++;
      if (status != PluginDiscoverStatus.idle) unawaited(loadIndexes());
    });
  }
  final HostRemotes remotes;
  StreamSubscription<HostEvent>? _events;
  StreamSubscription<ConnectionGeneration?>? _generations;
  final changed = Observable(0);
  PluginDiscoverStatus status = PluginDiscoverStatus.idle;
  List<MarketIndexSummary> indexes = const [];
  String? selected;
  PluginListing? listing;
  bool editing = false, saving = false;
  String draft = '';
  String? sourceFailure, sourceReason, indexError;
  int _indexRead = 0, _listingRead = 0;
  bool _disposed = false, _selectAdded = false;
  Future<void> Function()? _failed;
  void _publish() {
    if (!_disposed) changed.set(changed.value + 1);
  }

  bool get showSources => editing || indexes.isEmpty;
  void toggleSources() {
    editing = !editing;
    _publish();
  }

  void editDraft(String text) {
    draft = text;
    sourceFailure = null;
    _publish();
  }

  void ensure() {
    if (status == PluginDiscoverStatus.idle) unawaited(loadIndexes());
  }

  Future<void> loadIndexes() async {
    if (_disposed) return;
    final read = ++_indexRead;
    if (status == PluginDiscoverStatus.idle) {
      status = PluginDiscoverStatus.loading;
      _publish();
    }
    try {
      final value = await remotes.pluginMarket.listIndexes();
      if (_disposed || read != _indexRead) return;
      indexes = value;
      indexError = null;
      status = PluginDiscoverStatus.ready;
      selected = _selectAdded && value.isNotEmpty
          ? value.last.url
          : value.any((i) => i.url == selected)
          ? selected
          : value.firstOrNull?.url;
      _selectAdded = false;
      if (value.isEmpty) editing = false;
      if (selected == null) {
        listing = null;
        _listingRead++;
      }
      _publish();
      if (selected != null && selected != listing?.url) {
        await _load(selected!, const PluginDiscoverQuery(), 50, false);
      } else if (selected != null &&
          listing != null &&
          listing!.status != PluginListingStatus.loading &&
          listing!.status != PluginListingStatus.more) {
        // Reconnect rereads the current document without forcing a network refresh.
        await _load(selected!, listing!.query, _shownCount, false);
      }
    } catch (e) {
      if (_disposed || read != _indexRead) return;
      status = PluginDiscoverStatus.error;
      indexError = '$e';
      _publish();
    }
  }

  int get _shownCount => (listing?.value?.entries.length ?? 0) < 50
      ? 50
      : listing!.value!.entries.length;
  Future<void> select(String url) async {
    if (_disposed || selected == url) return;
    selected = url;
    _publish();
    await _load(url, const PluginDiscoverQuery(), 50, false);
  }

  Future<void> search(PluginDiscoverQuery query) async {
    final url = listing?.url;
    if (!_disposed && url != null) await _load(url, query, 50, false);
  }

  Future<void> refresh() async {
    final current = listing;
    if (!_disposed && current != null) {
      await _load(current.url, current.query, _shownCount, true);
    }
  }

  Future<void> refreshAnnotations() async {
    final current = listing;
    if (!_disposed && current != null) {
      await _load(current.url, current.query, _shownCount, false);
    }
  }

  Future<void> retry() async {
    if (!_disposed) await _failed?.call();
  }

  Future<MarketSearchResult> _page(
    String url,
    PluginDiscoverQuery query,
    int offset,
    int limit,
    int? fetchedAt,
    bool refresh,
  ) => remotes.pluginMarket.search(
    url,
    MarketQuery(
      text: query.text.trim().isEmpty ? null : query.text,
      category: query.category,
      labels: query.labels.isEmpty ? null : query.labels,
      sort: query.sort,
      offset: offset,
      limit: limit,
      fetchedAt: fetchedAt,
      refresh: refresh ? true : null,
    ),
  );
  String _failure(Object e) =>
      e is RemoteException && e.code == 'plugin-market/invalid-index'
      ? 'invalid'
      : 'fetch';
  void _settle(String url, PluginListing value, {String? error}) {
    listing = value;
    indexes = [
      for (final index in indexes)
        if (index.url != url)
          index
        else
          MarketIndexSummary(
            url: url,
            title: error == null ? value.value?.title : index.title,
            description: error == null
                ? value.value?.description
                : index.description,
            error: error,
          ),
    ];
    _publish();
  }

  Future<void> _load(
    String url,
    PluginDiscoverQuery query,
    int count,
    bool refresh,
  ) async {
    final read = ++_listingRead;
    final previous = listing?.url == url ? listing : null;
    listing = PluginListing(
      url: url,
      query: query,
      status: PluginListingStatus.loading,
      value: previous?.value,
      answered: previous?.answered,
    );
    _publish();
    void fail(String kind, [String? reason]) {
      _failed = () => _load(url, query, count, refresh);
      _settle(
        url,
        PluginListing(
          url: url,
          query: query,
          status: PluginListingStatus.error,
          value: previous?.value,
          answered: previous?.answered,
          failure: kind,
        ),
        error: reason,
      );
    }

    MarketSearchResult? value;
    var restarted = false;
    while (value == null ||
        (value.entries.length < count && value.nextOffset != null)) {
      final offset = value?.entries.length ?? 0;
      final remaining = count - offset;
      MarketSearchResult page;
      try {
        page = await _page(
          url,
          query,
          offset,
          remaining < 100 ? remaining : 100,
          value?.fetchedAt,
          refresh && value == null && !restarted,
        );
      } catch (e) {
        if (!_disposed && read == _listingRead) fail(_failure(e), '$e');
        return;
      }
      if (_disposed || read != _listingRead) return;
      if (value == null || page.fetchedAt == value.fetchedAt) {
        if (page.entries.isEmpty && page.nextOffset != null) {
          fail('invalid', 'Empty page has a next offset');
          return;
        }
        value = value == null ? page : _joined(value, page);
      } else if (restarted) {
        fail('changed');
        return;
      } else {
        restarted = true;
        value = null;
      }
    }
    final declared = query.declared(value.metadata);
    if (!identical(declared, query)) {
      await _load(url, declared, count, false);
      return;
    }
    _settle(
      url,
      PluginListing(
        url: url,
        query: query,
        status: PluginListingStatus.ready,
        value: value,
        answered: query,
      ),
    );
  }

  MarketSearchResult _joined(
    MarketSearchResult previous,
    MarketSearchResult next,
  ) => MarketSearchResult(
    url: next.url,
    title: next.title,
    description: next.description,
    metadata: next.metadata,
    fetchedAt: next.fetchedAt,
    entries: [...previous.entries, ...next.entries],
    total: next.total,
    nextOffset: next.nextOffset,
  );

  Future<void> more() async {
    final current = listing;
    if (_disposed ||
        current == null ||
        (current.status != PluginListingStatus.ready &&
            current.status != PluginListingStatus.error) ||
        !identical(current.query, current.answered) ||
        current.value?.nextOffset == null) {
      return;
    }
    final value = current.value!;
    final read = ++_listingRead;
    listing = PluginListing(
      url: current.url,
      query: current.query,
      status: PluginListingStatus.more,
      value: value,
      answered: current.answered,
    );
    _publish();
    try {
      final page = await _page(
        current.url,
        current.query,
        value.entries.length,
        50,
        value.fetchedAt,
        false,
      );
      if (_disposed || read != _listingRead) return;
      if (page.fetchedAt != value.fetchedAt) {
        await _load(
          current.url,
          current.query,
          value.entries.length + 50,
          false,
        );
        return;
      }
      _settle(
        current.url,
        PluginListing(
          url: current.url,
          query: current.query,
          status: PluginListingStatus.ready,
          value: _joined(value, page),
          answered: current.query,
        ),
      );
    } catch (e) {
      if (_disposed || read != _listingRead) return;
      _failed = more;
      _settle(
        current.url,
        PluginListing(
          url: current.url,
          query: current.query,
          status: PluginListingStatus.error,
          value: value,
          answered: current.answered,
          failure: _failure(e),
        ),
        error: '$e',
      );
    }
  }

  Future<void> addSource() async {
    if (saving || draft.trim().isEmpty || _disposed) return;
    _selectAdded = true;
    await _saveSources([
      ...indexes.map((i) => i.url),
      draft.trim(),
    ], adding: true);
  }

  Future<void> removeSource(String url) => _saveSources([
    for (final index in indexes)
      if (index.url != url) index.url,
  ]);
  Future<void> _saveSources(List<String> urls, {bool adding = false}) async {
    if (_disposed || saving) return;
    saving = true;
    sourceFailure = null;
    sourceReason = null;
    _publish();
    try {
      await remotes.pluginMarket.setIndexes(urls);
    } catch (e) {
      if (_disposed) return;
      _selectAdded = false;
      saving = false;
      sourceFailure =
          e is RemoteException && e.code == 'plugin-market/invalid-index-url'
          ? e.details['reason'] == 'duplicate'
                ? 'duplicate'
                : 'invalid'
          : e is RemoteException &&
                e.code == 'plugin-market/settings-unavailable'
          ? 'unavailable'
          : 'other';
      sourceReason = '$e';
      _publish();
      return;
    }
    if (_disposed) return;
    saving = false;
    if (adding) draft = '';
    _publish();
    await loadIndexes();
  }

  Future<void> dispose() async {
    _disposed = true;
    _indexRead++;
    _listingRead++;
    await _events?.cancel();
    await _generations?.cancel();
  }
}
