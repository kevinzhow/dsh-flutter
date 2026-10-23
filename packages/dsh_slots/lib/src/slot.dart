/// Slot cardinality (dsh `SlotMap` rows, docs/subsystems/slots.md).
enum SlotCardinality {
  /// One cell; the lowest `priority` wins.
  single,

  /// Cells addressed by required `id`, ordered by `order` then registration.
  list,

  /// The owner dispatches an `entryKey`; the matching cell renders.
  keyed,

  /// Each entry supplies a pure `select(owner)`; the first non-null result in
  /// priority order renders and receives it as `matched`.
  chain,
}

/// Slot scope: which session binding the occupant sees.
enum SlotScope { root, sessionMaybe, session }

/// A declared slot. [P] is the owner props type, [R] the rendered output
/// (a `Widget` in Flutter features; the registry itself is pure Dart).
///
/// The [name] is dsh's own: `<domain>.<entry>.<hole>`, lowercase dotted
/// segments, e.g. `conversation.session.header.actions` or
/// `tool.call.toolview`. `root` is the only one-segment name.
class Slot<P, R> {
  const Slot(this.name, this.cardinality, this.scope);

  final String name;
  final SlotCardinality cardinality;
  final SlotScope scope;

  /// A typed view of the same declared slot (same name, cardinality, scope):
  /// the owner feature that knows the owner props type [P2] and render type
  /// [R2] hands this to occupants.
  Slot<P2, R2> typed<P2, R2>() => Slot<P2, R2>(name, cardinality, scope);

  @override
  String toString() => 'Slot($name)';
}

final RegExp slotNamePattern = RegExp(r'^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)*$');

/// Builds the occupant for one render occurrence from the owner props.
typedef SlotBuilder<P, R> = R Function(P owner);

/// Chain entry: `select` is pure; non-null means "I match" and carries the
/// value the builder receives.
typedef ChainSelect<P, M> = M? Function(P owner);
