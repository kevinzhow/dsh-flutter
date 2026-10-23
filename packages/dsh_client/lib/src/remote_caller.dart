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
