import 'dart:async';

/// Minimal observable value (dsh's `ObservableSnapshot` + `Notifier`): a cached
/// current value and a synchronous change stream. Pure Dart so models stay
/// free of Flutter; UI adapters wrap it in `ValueListenable` or Riverpod.
class Observable<T> {
  Observable(T initial) : _value = initial;

  T _value;
  final StreamController<T> _changes = StreamController<T>.broadcast(
    sync: true,
  );

  T get value => _value;
  Stream<T> get changes => _changes.stream;

  void set(T next) {
    _value = next;
    if (!_changes.isClosed) _changes.add(next);
  }

  /// Re-publish the same (mutated) value.
  void touch() => set(_value);

  /// Ends the change stream. A broadcast controller reports done only once
  /// every listener has left, so a listener that outlives the observable must
  /// not hold the caller back.
  Future<void> dispose() {
    unawaited(_changes.close());
    return Future.value();
  }
}
