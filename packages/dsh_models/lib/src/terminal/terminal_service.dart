import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_terminal.dart';

import '../observable.dart';
import 'terminal_host.dart';
import 'terminal_inventory.dart';
import 'terminal_prefs.dart';
import 'terminal_view.dart';

/// The Host-discovered shell menu with the remembered available choice (dsh
/// `TerminalLaunchShells`).
class TerminalLaunchShells {
  const TerminalLaunchShells(this.shells, this.selectedShell);
  final List<TerminalShell> shells;

  /// The remembered shell if the Host still offers it, else the first.
  final String? selectedShell;
}

/// A background close the Host has not confirmed (dsh `TerminalCloseFailure`).
class TerminalCloseFailure {
  const TerminalCloseFailure(this.id, this.title, this.message);
  final String id;
  final String title;
  final String message;
}

/// The terminal views of every Session and their explicit cleanup (dsh
/// `ClientTerminals`): [view] returns the stable model of one sidebar tab,
/// [close] removes the tab at once and ends the process in the background.
class ClientTerminals {
  ClientTerminals({
    required TerminalHost host,
    TerminalPrefs? prefs,
    String Function()? newId,
  }) : _host = host,
       _prefs = prefs ?? MemoryTerminalPrefs(),
       _newId = newId ?? randomUuid {
    // A new connection lists terminals again; a close the Host has not
    // confirmed yet is tried again.
    _generations = _host.generations.listen((generation) {
      if (generation == null) return;
      resetInventories();
      for (final request in _prefs.pendingCloses) {
        _cleanup(request);
      }
    });
    for (final request in _prefs.pendingCloses) {
      _closed.add(request.id);
      _cleanup(request);
    }
  }

  late final StreamSubscription<ConnectionGeneration?> _generations;

  final TerminalHost _host;
  final TerminalPrefs _prefs;
  final String Function() _newId;
  final Map<String, Map<String, TerminalView>> _views = {};
  final Map<String, TerminalInventory> _inventories = {};
  final Map<String, Future<void>> _closing = {};
  final Set<String> _closed = {};
  bool _disposed = false;

  /// Cleanups that failed; in-progress and successful ones are not shown.
  final Observable<List<TerminalCloseFailure>> closeFailures = Observable(
    const [],
  );

  TerminalInventory _inventory(String sessionId) => _inventories.putIfAbsent(
    sessionId,
    () => TerminalInventory(() => _host.remote.list(sessionId)),
  );

  /// The stable model of one sidebar tab ([key] is the tab's identity). A
  /// known [terminalId] reattaches that Host terminal; otherwise a new
  /// identity is allocated on first use, with [shellPath] if the guide chose
  /// one.
  TerminalView view(
    String sessionId,
    String key, {
    String? terminalId,
    String? shellPath,
  }) {
    final views = _views.putIfAbsent(sessionId, () => {});
    return views.putIfAbsent(key, () {
      final view = TerminalView(
        sessionId: sessionId,
        id: terminalId ?? _newId(),
        host: _host,
        inventory: _inventory(sessionId),
        prefs: _prefs,
        createWhenMissing: terminalId == null,
        shellPath: shellPath,
      );
      return view;
    });
  }

  /// The view of tab [key] if one exists.
  TerminalView? existing(String sessionId, String key) =>
      _views[sessionId]?[key];

  /// Discover the installed shells without allocating a process.
  Future<TerminalLaunchShells> launchShells(String sessionId) async {
    final shells = await _host.remote.shells(sessionId);
    final previous = _prefs.preferredShell;
    return TerminalLaunchShells(
      shells,
      shells.where((s) => s.path == previous).firstOrNull?.path ??
          shells.firstOrNull?.path,
    );
  }

  /// Remember the guide's selection before its terminal tab opens.
  void selectShell(String path) => _prefs.rememberShell(path);

  /// Save a close intent and release the tab at once; the process is ended in
  /// the background and a failure shows in [closeFailures] for a retry.
  void close(String sessionId, String key) {
    final views = _views[sessionId];
    final view = views?[key];
    if (view == null) return;
    final request = TerminalCloseRequest(
      sessionId: sessionId,
      id: view.id,
      title: view.snapshot.title ?? key,
    );
    _closed.add(view.id);
    _prefs.saveClose(request);
    views!.remove(key);
    if (views.isEmpty) _views.remove(sessionId);
    _cleanup(request, view);
  }

  /// Retry a close the Host did not confirm.
  void retryClose(String id) {
    final request = _prefs.pendingCloses.where((r) => r.id == id).firstOrNull;
    if (request != null) _cleanup(request);
  }

  void _cleanup(TerminalCloseRequest request, [TerminalView? view]) {
    if (_closing.containsKey(request.id) || _disposed) return;
    closeFailures.set([
      for (final f in closeFailures.value)
        if (f.id != request.id) f,
    ]);
    final pending = (() async {
      try {
        if (view != null) {
          await view.close();
        } else {
          await _host.remote.close(request.sessionId, request.id);
        }
        _inventories[request.sessionId]?.remove(request.id);
        _prefs.removeClose(request.id);
      } on Object catch (error) {
        // A Session the Host no longer knows owns no process to clean up.
        if (error is RemoteException && error.code == 'session/not-found') {
          _prefs.removeClose(request.id);
        } else if (!_disposed) {
          closeFailures.set([
            ...closeFailures.value,
            TerminalCloseFailure(
              request.id,
              request.title,
              error is RemoteException
                  ? error.message
                  : describeTransportError(error),
            ),
          ]);
        }
      } finally {
        if (view != null) await view.dispose();
        unawaited(_closing.remove(request.id) ?? Future<void>.value());
      }
    })();
    _closing[request.id] = pending;
  }

  /// A new connection generation: lists are stale.
  void resetInventories() {
    for (final inventory in _inventories.values) {
      inventory.reset();
    }
  }

  /// Drop every view without ending any process: the host was left, and its
  /// terminals are reaped by the Host when nobody holds them.
  Future<void> detachAll() async {
    final views = [for (final map in _views.values) ...map.values];
    _views.clear();
    _inventories.clear();
    await Future.wait([for (final view in views) view.dispose()]);
  }

  /// Stop client work; Host terminals keep running.
  Future<void> dispose() async {
    _disposed = true;
    await _generations.cancel();
    final views = [for (final map in _views.values) ...map.values];
    _views.clear();
    await Future.wait([
      for (final view in views) view.dispose(),
      ..._closing.values,
    ]);
    unawaited(closeFailures.dispose());
  }
}
