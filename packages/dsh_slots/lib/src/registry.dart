import 'slot.dart';

/// Raised for programming errors in slot composition (dsh fails these during
/// plugin activation): undeclared slot, duplicate declaration, duplicate cell.
class SlotError extends Error {
  SlotError(this.message);
  final String message;
  @override
  String toString() => 'SlotError: $message';
}

class _Entry<P, R> {
  _Entry(
    this.id,
    this.key,
    this.priority,
    this.order,
    this.seq,
    this.builder,
    this.select,
  );
  final String id;
  final String? key;
  final int priority;
  final int order;
  final int seq;
  final Object
  builder; // SlotBuilder<P, R> or SlotBuilder<(P, Object?), R> for chain
  final Object? select; // ChainSelect<P, Object?>?
}

/// Typed slot registry with dsh's slot semantics.
///
/// Declaring a slot makes it live and records its dispatch shape; registering
/// into an undeclared slot, or declaring one that is already declared, throws.
/// A feature registers occupants only through slots and never imports another
/// feature (enforced by `tool/check_deps.py`).
class SlotRegistry {
  final Map<String, Slot<Object?, Object?>> _declared = {};
  final Map<String, List<_Entry<Object?, Object?>>> _cells = {};
  int _seq = 0;

  /// Make [slot] live. A name already declared fails ("declaring a child
  /// already owned elsewhere fails").
  void declare<P, R>(Slot<P, R> slot) {
    if (!slotNamePattern.hasMatch(slot.name)) {
      throw SlotError(
        'invalid slot name "${slot.name}" (expected <domain>.<entry>.<hole>)',
      );
    }
    if (_declared.containsKey(slot.name)) {
      throw SlotError('slot "${slot.name}" is already declared');
    }
    _declared[slot.name] = slot as Slot<Object?, Object?>;
    _cells[slot.name] = [];
  }

  bool isDeclared(String name) => _declared.containsKey(name);

  Iterable<String> get declaredNames => _declared.keys;

  List<_Entry<Object?, Object?>> _cellsOf(Slot<Object?, Object?> slot) {
    final declared = _declared[slot.name];
    if (declared == null) {
      throw SlotError('slot "${slot.name}" is not declared');
    }
    if (declared.cardinality != slot.cardinality) {
      throw SlotError(
        'slot "${slot.name}" is declared ${declared.cardinality.name}, '
        'not ${slot.cardinality.name}',
      );
    }
    return _cells[slot.name]!;
  }

  /// Register an occupant. [id] is required for `list`, [key] for `keyed`;
  /// a `single` and a `chain` cell address by registration only. Registering
  /// the same id/key twice in one slot throws; `single` allows several
  /// occupants and the lowest [priority] shadows the rest.
  void register<P, R>(
    Slot<P, R> slot,
    SlotBuilder<P, R> builder, {
    String? id,
    String? key,
    int priority = 0,
    int order = 0,
  }) {
    final cells = _cellsOf(slot as Slot<Object?, Object?>);
    switch (slot.cardinality) {
      case SlotCardinality.list:
        if (id == null) throw SlotError('list slot "${slot.name}" needs an id');
        if (cells.any((c) => c.id == id)) {
          throw SlotError(
            'slot "${slot.name}" already has a cell with id "$id"',
          );
        }
      case SlotCardinality.keyed:
        if (key == null) {
          throw SlotError('keyed slot "${slot.name}" needs a key');
        }
        if (cells.any((c) => c.key == key && c.priority == priority)) {
          throw SlotError(
            'slot "${slot.name}" already has a cell for key "$key"',
          );
        }
      case SlotCardinality.chain:
        throw SlotError('chain slot "${slot.name}" takes registerChain');
      case SlotCardinality.single:
        break;
    }
    cells.add(
      _Entry<Object?, Object?>(
        id ?? '',
        key,
        priority,
        order,
        _seq++,
        builder,
        null,
      ),
    );
  }

  /// Register a chain occupant: [select] decides whether it matches the owner
  /// props and what it matched; [builder] renders the match.
  void registerChain<P, M, R>(
    Slot<P, R> slot, {
    required ChainSelect<P, M> select,
    required R Function(P owner, M matched) builder,
    String? id,
    int priority = 0,
  }) {
    final cells = _cellsOf(slot as Slot<Object?, Object?>);
    if (slot.cardinality != SlotCardinality.chain) {
      throw SlotError('slot "${slot.name}" is not a chain slot');
    }
    if (id != null && cells.any((c) => c.id == id)) {
      throw SlotError('slot "${slot.name}" already has a cell with id "$id"');
    }
    cells.add(
      _Entry<Object?, Object?>(
        id ?? '',
        null,
        priority,
        0,
        _seq++,
        builder,
        select,
      ),
    );
  }

  List<_Entry<Object?, Object?>> _sorted(Slot<Object?, Object?> slot) =>
      [..._cellsOf(slot)]..sort((a, b) {
        final p = a.priority.compareTo(b.priority);
        if (p != 0) return p;
        final o = a.order.compareTo(b.order);
        return o != 0 ? o : a.seq.compareTo(b.seq);
      });

  /// `single`: the active (lowest priority) occupant, or null.
  R? renderSingle<P, R>(Slot<P, R> slot, P owner) {
    final cells = _sorted(slot as Slot<Object?, Object?>);
    if (cells.isEmpty) return null;
    return (cells.first.builder as dynamic)(owner) as R;
  }

  /// `list`: every occupant in order.
  List<R> renderList<P, R>(Slot<P, R> slot, P owner) => [
    for (final c in _sorted(slot as Slot<Object?, Object?>))
      (c.builder as dynamic)(owner) as R,
  ];

  /// `keyed`: the occupant for [key] (lowest priority among equals), or null.
  R? renderKeyed<P, R>(Slot<P, R> slot, String key, P owner) {
    final cells = _sorted(slot as Slot<Object?, Object?>)
        .where((c) => c.key == key);
    if (cells.isEmpty) return null;
    return (cells.first.builder as dynamic)(owner) as R;
  }

  /// `chain`: the first entry (priority order) whose `select` is non-null
  /// renders; null when none matches (the owner renders its fallback).
  R? renderChain<P, R>(Slot<P, R> slot, P owner) {
    for (final c in _sorted(slot as Slot<Object?, Object?>)) {
      final matched = (c.select! as dynamic)(owner);
      if (matched != null) {
        return (c.builder as dynamic)(owner, matched) as R;
      }
    }
    return null;
  }
}
