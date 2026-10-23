import 'contract.dart';

/// Raised on registry misuse (dsh fails these at plugin activation).
class ConversationRegistryError extends Error {
  ConversationRegistryError(this.message);
  final String message;
  @override
  String toString() => 'ConversationRegistryError: $message';
}

/// Registry of business Definitions (dsh `ConversationEventRegistry`): ordinary
/// Definitions in registration order plus one unmatched-event fallback.
class ConversationEventRegistry {
  final Map<String, ConversationDefinition> _definitions = {};
  ConversationDefinition? _fallback;

  /// Register a uniquely named Definition.
  void register(ConversationDefinition definition) {
    _assertTarget(definition);
    if (_definitions.containsKey(definition.kind)) {
      throw ConversationRegistryError(
        'conversation Definition "${definition.kind}" is already registered',
      );
    }
    _definitions[definition.kind] = definition;
  }

  /// Register the sole fallback used only when no ordinary Definition of its
  /// target matched.
  void registerFallback(ConversationDefinition definition) {
    _assertTarget(definition);
    if (definition.target == null) {
      throw ConversationRegistryError(
        'conversation fallback Definition must declare a target',
      );
    }
    if (_fallback != null) {
      throw ConversationRegistryError(
        'conversation fallback Definition is already registered',
      );
    }
    _fallback = definition;
  }

  Iterable<ConversationDefinition> get entries => _definitions.values;
  ConversationDefinition? get fallback => _fallback;

  /// Definitions that may match an event of [type], in registration order.
  List<ConversationDefinition> forEvent(String type) => [
    for (final d in _definitions.values)
      if (d.eventTypes == null || d.eventTypes!.contains(type)) d,
  ];

  static void _assertTarget(ConversationDefinition d) {
    // dsh: `target` and `buildViewNode` must be declared together. Dart cannot
    // introspect an override, so a Definition states it through `target`.
  }
}

/// One incremental builder per Session and target (dsh `ConversationViewBuilder`).
abstract class ConversationViewBuilder {
  /// Replace the complete materialized node set.
  Object replace(List<ViewNode> nodes, ConversationTimeline timeline);

  /// Apply only nodes whose materialized values changed in this transaction.
  Object apply(List<ViewNode> upserts, ConversationTimeline timeline);
}

/// Registry contribution that creates a builder when a Session first uses the
/// target (dsh `ConversationViewDefinition`).
abstract class ConversationViewDefinition {
  String get target;
  ConversationViewBuilder create();
  bool isActive(Object snapshot) => true;
}

class ConversationViewRegistry {
  final Map<String, ConversationViewDefinition> _views = {};

  void register(ConversationViewDefinition definition) {
    if (_views.containsKey(definition.target)) {
      throw ConversationRegistryError(
        'conversation view target "${definition.target}" is already registered',
      );
    }
    _views[definition.target] = definition;
  }

  Iterable<ConversationViewDefinition> get entries => _views.values;
}

/// Reference-stable Turn/Step facts published beside view nodes (dsh
/// `ConversationTimelineSnapshot`).
class ConversationTimeline {
  const ConversationTimeline(this.turnOrder, this.turns);
  static const empty = ConversationTimeline([], {});
  final List<int> turnOrder;
  final Map<int, TurnLocation> turns;
}
