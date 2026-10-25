import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'tree.dart';

/// Where the browser's viewing state is kept between runs (dsh persists it in
/// `localStorage` under `dsh.workspace.view.v5`).
abstract interface class WorkspaceViewStorage {
  String? read();
  void write(String json);
}

/// Keeps nothing past the process; tests.
class MemoryWorkspaceViewStorage implements WorkspaceViewStorage {
  MemoryWorkspaceViewStorage([this.json]);
  String? json;

  @override
  String? read() => json;

  @override
  void write(String next) => json = next;
}

/// The workspace browser's viewing state (dsh `createWorkspaceViewStore`): the
/// grouping and order, the archived choice, which groups are open and the
/// manual order of each account. Persisted as dsh persists it.
class WorkspaceViewState extends ChangeNotifier {
  WorkspaceViewState({WorkspaceViewStorage? storage}) : _storage = storage {
    _load();
  }

  final WorkspaceViewStorage? _storage;

  SessionGroupBy groupBy = SessionGroupBy.workspace;
  SessionOrderBy orderBy = SessionOrderBy.updated;
  ArchivedFilter archivedFilter = ArchivedFilter.hide;
  final Map<String, bool> groupExpansion = {};
  final Map<String, List<String>> sessionOrderByAccount = {};

  /// Counts requests to focus the search field (the `session.search`
  /// command); not persisted.
  int searchRequest = 0;

  /// Counts requests to open the add-workspace flow (the `workspace.add`
  /// command); not persisted.
  final ValueNotifier<int> addRequests = ValueNotifier<int>(0);

  void requestAdd() => addRequests.value++;

  void requestSearch() {
    searchRequest++;
    notifyListeners();
  }

  static const _groupByWire = {
    SessionGroupBy.workspace: 'workspace',
    SessionGroupBy.workspaceTree: 'workspace-tree',
    SessionGroupBy.flat: 'flat',
  };
  static const _filterWire = {
    ArchivedFilter.hide: 'default',
    ArchivedFilter.show: 'show',
    ArchivedFilter.only: 'only',
  };

  void _load() {
    final raw = _storage?.read();
    if (raw == null) return;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return;
      groupBy = _groupByWire.entries
          .firstWhere(
            (e) => e.value == j['groupBy'],
            orElse: () => const MapEntry(SessionGroupBy.workspace, ''),
          )
          .key;
      orderBy = j['orderBy'] == 'manual'
          ? SessionOrderBy.manual
          : SessionOrderBy.updated;
      archivedFilter = _filterWire.entries
          .firstWhere(
            (e) => e.value == j['archivedFilter'],
            orElse: () => const MapEntry(ArchivedFilter.hide, ''),
          )
          .key;
      final expansion = j['groupExpansion'];
      if (expansion is Map) {
        for (final e in expansion.entries) {
          if (e.value is bool) groupExpansion['${e.key}'] = e.value as bool;
        }
      }
      final orders = j['sessionOrderByAccount'];
      if (orders is Map) {
        for (final e in orders.entries) {
          if (e.value is List) {
            sessionOrderByAccount['${e.key}'] = [
              for (final id in e.value as List)
                if (id is String) id,
            ];
          }
        }
      }
    } on Object {
      // A damaged blob reads as the defaults.
    }
  }

  void _save() {
    _storage?.write(
      jsonEncode({
        'groupBy': _groupByWire[groupBy],
        'orderBy': orderBy.name,
        'archivedFilter': _filterWire[archivedFilter],
        'groupExpansion': groupExpansion,
        'sessionOrderByAccount': sessionOrderByAccount,
      }),
    );
  }

  void _changed() {
    _save();
    notifyListeners();
  }

  void setGroupBy(SessionGroupBy mode) {
    if (mode == groupBy) return;
    groupBy = mode;
    _changed();
  }

  /// Selecting Manual keeps today's order as the saved one; Updated forgets it.
  void setOrderBy(
    SessionOrderBy mode,
    Map<String, List<String>> initialOrders,
  ) {
    if (mode == orderBy) return;
    sessionOrderByAccount
      ..clear()
      ..addAll(
        mode == SessionOrderBy.manual
            ? {
                for (final e in initialOrders.entries) e.key: [...e.value],
              }
            : const {},
      );
    orderBy = mode;
    _changed();
  }

  /// A drag snapshots every account before selecting Manual, then changes
  /// only its own account. It never moves a Session to another Workspace.
  void setSessionOrder(
    String key,
    List<String> order,
    Map<String, List<String>> initialOrders,
  ) {
    if (orderBy == SessionOrderBy.updated) sessionOrderByAccount.clear();
    sessionOrderByAccount.addAll({
      for (final e in initialOrders.entries) e.key: [...e.value],
    });
    orderBy = SessionOrderBy.manual;
    sessionOrderByAccount[key] = [...order];
    _changed();
  }

  void setArchivedFilter(ArchivedFilter filter) {
    if (filter == archivedFilter) return;
    archivedFilter = filter;
    _changed();
  }

  void setGroupExpanded(String key, bool expanded) {
    if (groupExpansion[key] == expanded) return;
    groupExpansion[key] = expanded;
    _changed();
  }

  /// Forget accounts of Workspaces that no longer exist.
  void retainAccountKeys(Iterable<String> keys) {
    final keep = {...keys};
    final before = groupExpansion.length + sessionOrderByAccount.length;
    groupExpansion.removeWhere((k, _) => !keep.contains(k));
    sessionOrderByAccount.removeWhere((k, _) => !keep.contains(k));
    if (groupExpansion.length + sessionOrderByAccount.length != before) {
      _changed();
    }
  }
}
