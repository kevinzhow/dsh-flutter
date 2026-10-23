import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:flutter/foundation.dart';

/// One listed directory (dsh `DirLevel`), loading, or failed.
sealed class FilesLevel {
  const FilesLevel();
}

final class FilesLevelLoading extends FilesLevel {
  const FilesLevelLoading();
}

final class FilesLevelLoaded extends FilesLevel {
  const FilesLevelLoaded(this.entries, this.truncated, {this.failure});
  final List<WorkspaceDirectoryEntry> entries;
  final bool truncated;

  /// A failed reload that kept the previous listing under it.
  final Object? failure;
}

final class FilesLevelFailed extends FilesLevel {
  const FilesLevelFailed(this.failure);
  final Object failure;
}

/// `file2` before `file10`, case-insensitively (dsh's `Intl.Collator` with
/// `numeric` and base sensitivity).
int naturalCompare(String a, String b) {
  final left = RegExp(r'\d+|\D+').allMatches(a.toLowerCase()).map((m) => m[0]!);
  final right = RegExp(r'\d+|\D+')
      .allMatches(b.toLowerCase())
      .map((m) => m[0]!);
  final l = left.iterator;
  final r = right.iterator;
  while (true) {
    final hasL = l.moveNext();
    final hasR = r.moveNext();
    if (!hasL || !hasR) {
      return hasL == hasR ? 0 : (hasL ? 1 : -1);
    }
    final x = l.current;
    final y = r.current;
    final xn = int.tryParse(x);
    final yn = int.tryParse(y);
    final c = xn != null && yn != null ? xn.compareTo(yn) : x.compareTo(y);
    if (c != 0) return c;
  }
}

/// Directories first, then by name (dsh `orderEntries`).
List<WorkspaceDirectoryEntry> orderEntries(
  List<WorkspaceDirectoryEntry> entries,
) {
  final sorted = [...entries];
  sorted.sort((a, b) {
    final group =
        (b.type == WorkspaceEntryType.directory ? 1 : 0) -
        (a.type == WorkspaceEntryType.directory ? 1 : 0);
    return group != 0 ? group : naturalCompare(a.name, b.name);
  });
  return sorted;
}

/// The absolute path of a child entry (dsh `childPath`): joined with `/`
/// whatever the parent's separators.
String childPath(String parent, String name) =>
    '${parent.replaceAll(RegExp(r'[/\\]+$'), '')}/$name';

/// The tree of one sidebar tab: the levels, which directories are open, and a
/// directory watch per open directory that rereads it when it changes.
class FilesController extends ChangeNotifier {
  FilesController({
    required this.sessionId,
    required this.root,
    required this.files,
    this.debounce = const Duration(milliseconds: 150),
  }) {
    _open(root);
  }

  final String sessionId;
  final String root;
  final WorkspaceFilesRemote files;
  final Duration debounce;

  final Map<String, FilesLevel> levels = {};
  final Set<String> expanded = {};
  final Map<String, StreamSubscription<WorkspaceWatchEvent>> _watches = {};
  final Map<String, Timer> _timers = {};
  final Map<String, int> _generation = {};
  bool _disposed = false;

  void _open(String path) {
    _watch(path);
    unawaited(_load(path));
  }

  Future<void> _load(String path) async {
    final generation = (_generation[path] ?? 0) + 1;
    _generation[path] = generation;
    final previous = levels[path];
    if (previous is! FilesLevelLoaded) {
      levels[path] = const FilesLevelLoading();
      _changed();
    }
    try {
      final listing = await files.list(sessionId, path);
      if (_disposed || _generation[path] != generation) return;
      levels[path] = FilesLevelLoaded(listing.entries, listing.truncated);
      // A directory that vanished closes its open descendants.
      final names = {
        for (final e in listing.entries)
          if (e.type == WorkspaceEntryType.directory) childPath(path, e.name),
      };
      for (final open in expanded.toList()) {
        if (_parent(open) == path && !names.contains(open)) _close(open);
      }
    } on Object catch (e) {
      if (_disposed || _generation[path] != generation) return;
      final kept = levels[path];
      levels[path] = kept is FilesLevelLoaded
          ? FilesLevelLoaded(kept.entries, kept.truncated, failure: e)
          : FilesLevelFailed(e);
    }
    _changed();
  }

  String _parent(String path) {
    final cut = path.lastIndexOf('/');
    return cut <= 0 ? '/' : path.substring(0, cut);
  }

  void _watch(String path) {
    if (_watches.containsKey(path)) return;
    _watches[path] = files.changes(sessionId, path).listen(
      (event) {
        // `ready` only says the watcher is up; a change or a reopened
        // generation (the link dropped meanwhile) rereads the directory.
        if (event is WatchReady) return;
        _timers[path]?.cancel();
        _timers[path] = Timer(debounce, () => unawaited(_load(path)));
      },
      // A watch the host cannot start is not an error for the tree: the
      // listing was read once and Reload rereads it.
      onError: (Object _) {},
    );
  }

  /// Open or collapse one directory.
  void toggle(String path) {
    if (expanded.contains(path)) {
      _close(path);
    } else {
      expanded.add(path);
      _open(path);
    }
    _changed();
  }

  void _close(String path) {
    expanded.remove(path);
    for (final child
        in expanded.where((p) => p.startsWith('$path/')).toList()) {
      expanded.remove(child);
      _release(child);
    }
    _release(path);
  }

  void _release(String path) {
    unawaited(_watches.remove(path)?.cancel());
    _timers.remove(path)?.cancel();
    _generation.remove(path);
    levels.remove(path);
  }

  /// Reread the root and every open directory.
  void reload() {
    for (final path in [root, ...expanded]) {
      unawaited(_load(path));
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final w in _watches.values) {
      unawaited(w.cancel());
    }
    for (final t in _timers.values) {
      t.cancel();
    }
    super.dispose();
  }
}
