import 'dart:async';

import 'package:dsh_client/generated_terminal.dart';

/// One Session's cached list of retained Host terminals (dsh
/// `TerminalInventory`), shared by every view of that Session. Confirmed
/// changes made while a list request is in flight win over its answer.
class TerminalInventory {
  TerminalInventory(this._load);

  final Future<List<WebTerminalInfo>> Function() _load;
  Future<Map<String, WebTerminalInfo>>? _loading;
  Map<String, WebTerminalInfo>? _items;
  Object? _failure;
  Map<String, WebTerminalInfo?>? _updates;

  /// The cached list, or the in-flight request. [refresh] replaces a settled
  /// result, including a failed one.
  Future<Map<String, WebTerminalInfo>> read({bool refresh = false}) {
    final loading = _loading;
    if (loading != null) return loading;
    if (!refresh && _items != null) return Future.value(_items);
    if (!refresh && _failure != null) return Future.error(_failure!);
    final updates = _updates = <String, WebTerminalInfo?>{};
    return _loading = (() async {
      try {
        final list = await _load();
        final items = {for (final info in list) info.id: info};
        for (final entry in updates.entries) {
          final info = entry.value;
          if (info == null) {
            items.remove(entry.key);
          } else {
            items[entry.key] = info;
          }
        }
        _items = items;
        _failure = null;
        return items;
      } on Object catch (error) {
        _failure = error;
        rethrow;
      } finally {
        _loading = null;
        _updates = null;
      }
    })();
  }

  /// Keep the latest confirmed metadata of one terminal.
  void update(WebTerminalInfo info) {
    (_items ??= {})[info.id] = info;
    _updates?[info.id] = info;
  }

  /// Forget a terminal after it was closed or found missing.
  void remove(String id) {
    _items?.remove(id);
    _updates?[id] = null;
  }

  /// Forget everything (a new connection): the next read lists again.
  void reset() {
    _items = null;
    _failure = null;
  }
}
