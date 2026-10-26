import 'dart:async';

/// The one seam generated Remote namespaces (and tests) use to reach a host.
///
/// Mirrors dsh's `connection.rpc.call('/api', '<namespace>/<method>', {args})`.
/// `args` is the named-parameter object of the Typert wire (for a Host method
/// `list(request)` it is `{'request': {...}}`; a trailing `AbortSignal` never
/// enters `args`).
abstract interface class RemoteCaller {
  /// Unary call: `POST /api/<namespace>/<method>`; returns the decoded `value`
  /// of a successful result envelope and throws [RemoteException] otherwise.
  Future<Object?> call(
    String namespace,
    String method,
    Map<String, Object?> args,
  );
}

/// A `{ok:false,error}` result envelope, or a transport-level failure.
class RemoteException implements Exception {
  RemoteException(this.code, this.message, [this.details = const {}]);

  /// Typert error code such as `gateway/input-invalid` or `session/not-found`.
  final String code;
  final String message;
  final Map<String, Object?> details;

  @override
  String toString() => 'RemoteException($code): $message';
}

/// Lifetime of one cancellable HTTP call. Aborting terminates its request;
/// application-level cancellation (for example pnpm installation) is separate.
class RemoteCancellation {
  Object? _reason;
  final List<void Function()> _listeners = [];
  bool get cancelled => _reason != null;
  Object get reason =>
      _reason ??
      RemoteException('transport/cancelled', 'Remote call cancelled');
  void throwIfCancelled() {
    if (cancelled) throw reason;
  }

  void cancel([Object? cause]) {
    if (cancelled) return;
    _reason =
        cause ??
        RemoteException('transport/cancelled', 'Remote call cancelled');
    final callbacks = [..._listeners];
    _listeners.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  void Function() listen(void Function() callback) {
    if (cancelled) {
      callback();
      return () {};
    }
    _listeners.add(callback);
    return () => _listeners.remove(callback);
  }
}

abstract interface class CancellableRemoteCaller implements RemoteCaller {
  Future<Object?> callWithCancellation(
    String namespace,
    String method,
    Map<String, Object?> args,
    RemoteCancellation cancellation,
  );
}

/// Binds generated calls to one reader lifetime without changing their wire
/// arguments. Legacy test callers are fenced, real HTTP callers abort on wire.
class ScopedRemoteCaller implements RemoteCaller {
  ScopedRemoteCaller(this.caller, this.cancellation);
  final RemoteCaller caller;
  final RemoteCancellation cancellation;
  @override
  Future<Object?> call(
    String namespace,
    String method,
    Map<String, Object?> args,
  ) async {
    cancellation.throwIfCancelled();
    if (caller is CancellableRemoteCaller) {
      return (caller as CancellableRemoteCaller).callWithCancellation(
        namespace,
        method,
        args,
        cancellation,
      );
    }
    final cancelled = Completer<Object?>();
    final off = cancellation.listen(
      () => cancelled.completeError(cancellation.reason),
    );
    try {
      return await Future.any([
        caller.call(namespace, method, args),
        cancelled.future,
      ]);
    } finally {
      off();
    }
  }
}
