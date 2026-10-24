import 'dart:async';

import 'package:dsh_client/dsh_client.dart';

import 'terminal_host.dart';

/// One window hold on a Host terminal (dsh `TerminalWindowHold`): while a tab is
/// open the Host does not reclaim its terminal as unattended, and an output
/// attachment only opens once the hold of the current connection generation
/// was acknowledged.
class TerminalWindowHold {
  TerminalWindowHold(TerminalHost host, String sessionId, String id) {
    _subscription = host
        .retain(sessionId, id)
        .listen(
          _onFrame,
          onError: (Object error) => _reject(error),
          onDone: () => _reject(
            RemoteException('terminal/unavailable', 'Terminal hold ended'),
          ),
        );
  }

  late final StreamSubscription<GenerationFrame> _subscription;
  final List<Completer<void>> _waiters = [];
  bool _acknowledged = false;
  Object? _failure;

  /// Whether a terminal-domain failure ended this hold.
  bool get failed => _failure != null;

  void _onFrame(GenerationFrame frame) {
    switch (frame) {
      case StreamOpened():
        _acknowledged = false;
      case StreamItem():
        _acknowledged = true;
        _failure = null;
        for (final waiter in _waiters) {
          if (!waiter.isCompleted) waiter.complete();
        }
        _waiters.clear();
      case StreamEnded(:final error):
        _acknowledged = false;
        // A lost connection reopens the hold on the next generation; a Host
        // answer (the terminal is gone) ends it.
        if (error == null) {
          _reject(
            RemoteException('terminal/unavailable', 'Terminal hold ended'),
          );
        } else if (error is! CarrierLost && error is! NotConnected) {
          _reject(error);
        }
    }
  }

  /// Resolves once the current generation's hold is acknowledged; rejects when
  /// the terminal is unavailable or the hold was released.
  Future<void> ready() {
    final failure = _failure;
    if (failure != null) return Future.error(failure);
    if (_acknowledged) return Future.value();
    final waiter = Completer<void>();
    _waiters.add(waiter);
    return waiter.future;
  }

  void _reject(Object error) {
    _failure = error;
    _acknowledged = false;
    for (final waiter in _waiters) {
      if (!waiter.isCompleted) waiter.completeError(error);
    }
    _waiters.clear();
  }

  /// Release the hold; waiting callers fail.
  Future<void> dispose() {
    _reject(StateError('Terminal window hold released'));
    return _subscription.cancel();
  }
}
