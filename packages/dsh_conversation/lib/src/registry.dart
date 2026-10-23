import 'package:dsh_models/dsh_models.dart';

import 'types.dart';

/// Raised on registry misuse (dsh fails these at plugin activation).
class ConversationRegistryError extends Error {
  ConversationRegistryError(this.message);
  final String message;
  @override
  String toString() => 'ConversationRegistryError: $message';
}

/// Declares that [target] understands session events of [eventType].
///
/// dsh's `ui-conversation` event registry correlates durable events and
/// client-only `assistant/live-chunk` rows into business contexts; each target
/// (`ui-chat`, `ui-trajectory`) registers its own definitions. The skeleton
/// keeps only the declaration; builders are the full-port work of phase 1.
class EventDefinition {
  const EventDefinition({
    required this.target,
    required this.eventType,
    required this.nodeKey,
  });
  final ConversationTarget target;
  final String eventType;

  /// The node key this event contributes to (a `conversation.<target>.node` key).
  final String nodeKey;
}

/// Builds one target's snapshot from the event window.
typedef TargetBuilder = ConversationSnapshot Function(EventWindow window);

/// The single registry of the skeleton: event definitions per target plus one
/// builder per target.
class ConversationRegistry {
  final List<EventDefinition> _definitions = [];
  final Map<ConversationTarget, TargetBuilder> _builders = {};

  /// Register an event definition. The same `(target, eventType)` twice fails.
  void defineEvent(EventDefinition definition) {
    final clash = _definitions.any(
      (d) =>
          d.target == definition.target && d.eventType == definition.eventType,
    );
    if (clash) {
      throw ConversationRegistryError(
        '${definition.target} already defines ${definition.eventType}',
      );
    }
    _definitions.add(definition);
  }

  void registerTarget(ConversationTarget target, TargetBuilder builder) {
    if (_builders.containsKey(target)) {
      throw ConversationRegistryError('target $target is already registered');
    }
    _builders[target] = builder;
  }

  Iterable<EventDefinition> definitionsFor(ConversationTarget target) =>
      _definitions.where((d) => d.target == target);

  /// Materialize [target] for [window]; throws for an unregistered target.
  ConversationSnapshot snapshot(ConversationTarget target, EventWindow window) {
    final builder = _builders[target];
    if (builder == null) {
      throw ConversationRegistryError('target $target is not registered');
    }
    return builder(window);
  }
}
