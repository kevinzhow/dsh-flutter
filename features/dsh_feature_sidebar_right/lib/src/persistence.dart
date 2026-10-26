import 'dart:convert';

import 'package:dsh_dockkit/dsh_dockkit.dart';
import 'package:dsh_slots/dsh_slots.dart';

/// Device storage, scoped to a Host origin and original Session. Implementations
/// keep writes ordered; storage refusal must not disable the live sidebar.
abstract interface class SidebarPersistence {
  String? read(String scope, String sessionId);
  void write(String scope, String sessionId, String value);
}

class RestoredSidebar {
  const RestoredSidebar(this.surface, this.extras);
  final SavedDockLayout surface;
  final Map<String, Map<String, Object?>> extras;
}

RestoredSidebar? restoreSidebar(String? raw, SidebarTabTypes types) {
  if (raw == null || raw.length > 512 * 1024) return null;
  try {
    final value = jsonDecode(raw);
    if (value is! Map<String, Object?> || value['version'] != 1) return null;
    final surface = SavedDockLayout.tryRead(value['surface']);
    if (surface == null) return null;
    final rawExtras = value['extras'];
    final extras = <String, Map<String, Object?>>{};
    final dock = DockController(
      DockControllerOptions(restored: surface, maxPanes: 2),
    );
    for (final record in surface.layout.tabs.values) {
      final type = types.typeOf(record.kind);
      final restorable =
          const ['guide', 'files', 'text'].contains(record.kind) ||
          type?.restorable == true;
      if (!restorable) {
        dock.closeTab(record.id);
        continue;
      }
      final rawExtra = rawExtras is Map<String, Object?>
          ? rawExtras[record.id]
          : null;
      final params =
          rawExtra is Map<String, Object?> &&
              rawExtra['params'] is Map<String, Object?>
          ? rawExtra['params'] as Map<String, Object?>
          : <String, Object?>{};
      final durable = type?.persistParams?.call(params);
      if (type?.persistParams != null && durable == null) {
        dock.closeTab(record.id);
        continue;
      }
      final line = rawExtra is Map<String, Object?> ? rawExtra['line'] : null;
      extras[record.id] = {
        'params': durable ?? <String, Object?>{},
        if (line is int && line > 0) 'line': line,
      };
    }
    if (dock.snapshot.state.tabs.isEmpty) dock.setExpanded(false);
    // Re-enter through the codec and a fresh controller: filtering does not
    // restore stale undo operations or retain an ephemeral tab in history.
    final filtered = SavedDockLayout.tryRead(dock.savedLayout.toJson());
    return filtered == null ? null : RestoredSidebar(filtered, extras);
  } on Object {
    return null;
  }
}
