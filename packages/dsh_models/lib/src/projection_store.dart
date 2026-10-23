import 'observable.dart';

sealed class _Row {
  const _Row(this.value);
  final Object? value;
}

class _Cached extends _Row {
  const _Cached(super.value);
}

class _Sequenced extends _Row {
  const _Sequenced(super.value, this.seq);
  final num seq;
}

/// Per-session projection values (dsh `ProjectionValueStore`): finished whole
/// values computed on the host, seeded by a follow snapshot or a control
/// baseline and updated by control frames. Sequenced rows merge under
/// higher-seq-wins; a cached row (from a header-only list) has no comparable
/// seq and always yields.
class ProjectionStore {
  final Map<String, _Row> _rows = {};
  final Observable<Map<String, Object?>> _values = Observable(const {});

  Map<String, Object?> get values => _values.value;
  Stream<Map<String, Object?>> get changes => _values.changes;

  Object? get(String key) => _rows[key]?.value;

  /// Seq of a sequenced row, or null for a cached/missing row.
  num? seqOf(String key) {
    final row = _rows[key];
    return row is _Sequenced ? row.seq : null;
  }

  /// One control `projection` frame or one list-block value.
  void apply(String key, Object? value, num seq) {
    final row = _rows[key];
    if (row is _Sequenced && seq <= row.seq) return;
    _rows[key] = _Sequenced(value, seq);
    _changed();
  }

  /// List block of kind `cached`: fills only keys with no sequenced row.
  void applyCached(Map<String, Object?> values) {
    var changed = false;
    for (final e in values.entries) {
      if (_rows[e.key] is _Sequenced) continue;
      _rows[e.key] = _Cached(e.value);
      changed = true;
    }
    if (changed) _changed();
  }

  /// Complete baseline at [asOfSeq] (follow snapshot or control baseline):
  /// drops cached rows, applies every key, and drops rows the baseline does not
  /// carry unless a newer sequenced frame already wrote them.
  void seed(num asOfSeq, Map<String, Object?> values) {
    _rows.removeWhere((_, r) => r is _Cached);
    for (final e in values.entries) {
      apply(e.key, e.value, asOfSeq);
    }
    _rows.removeWhere((key, r) {
      if (values.containsKey(key)) return false;
      return !(r is _Sequenced && r.seq > asOfSeq);
    });
    _changed();
  }

  void clear() {
    _rows.clear();
    _changed();
  }

  void _changed() {
    _values.set(
      Map.unmodifiable({for (final e in _rows.entries) e.key: e.value.value}),
    );
  }
}
