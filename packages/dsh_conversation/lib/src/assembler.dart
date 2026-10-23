import 'contract.dart';
import 'event.dart';
import 'location_index.dart';
import 'registry.dart';

class _Dependency {
  const _Dependency(this.kind, this.key, this.revision, this.windowGap);
  final String kind;
  final String? key;
  final int? revision;
  final bool windowGap;
}

class _Context {
  _Context(this.key, this.kind, this.id, this.definition);
  final String key;
  final String kind;
  final String id;
  final ConversationDefinition definition;
  num? startSeq;
  ConversationMatch? start;
  List<ConversationMatch> matches = [];
  Object? state;
  int revision = 0;
  final Map<String, ViewNode?> current = {};
  final Map<LocationScope, LocationData?> locationData = {
    LocationScope.step: null,
    LocationScope.turn: null,
  };
  Map<String, _Dependency> dependencies = {};
}

class _PendingMatch {
  _PendingMatch(this.definition, this.id, this.match);
  final ConversationDefinition definition;
  final String id;
  final ConversationMatch match;
}

class _ViewState {
  _ViewState(this.definition);
  final ConversationViewDefinition definition;
  ConversationViewBuilder? builder;
  Object? snapshot;
}

/// dsh `conversationContextKey`: collision-free `(kind, id)` key.
String conversationContextKey(String kind, String id) =>
    '${kind.length}:$kind$id';

/// Session-owned incremental engine that assembles business Contexts from a
/// contiguous event window and materializes registered view snapshots (dsh
/// `ConversationNodeAssembler`, without Group Definitions).
class ConversationAssembler {
  ConversationAssembler(this._events, this._viewRegistry) {
    _resetViewBuilders();
  }

  final ConversationEventRegistry _events;
  final ConversationViewRegistry _viewRegistry;

  final Map<String, _Context> _contexts = {};
  final Map<String, List<_Context>> _contextsByKind = {};
  final Map<num, List<_Context>> _contextsBySeq = {};
  final Map<String, Set<_Context>> _contextsByTarget = {};
  final Map<num, ConvEvent> _inputs = {};
  final ConversationLocationIndex _locations = ConversationLocationIndex();
  final Set<_Context> _dirty = {};
  final Map<String, Set<_Context>> _dirtyByTarget = {};
  final Set<_Context> _revised = {};
  final Map<String, Set<_Context>> _dependents = {};
  final Map<String, _ViewState> _views = {};
  final Set<String> _activeTargets = {};
  bool _hasMore = false;
  bool _replacePending = true;
  bool _timelineDirty = true;

  /// The latest turn number when its start is loaded and it remains open.
  int? openTurn() {
    final snap = _locations.snapshot();
    final latest = snap.turnOrder.isEmpty ? null : snap.turnOrder.last;
    final turn = latest == null ? null : snap.turns[latest];
    return turn != null &&
            turn.status == BoundaryStatus.open &&
            turn.start != null
        ? turn.turn
        : null;
  }

  ConversationTimeline get timeline => _locations.snapshot();

  /// Replace the complete loaded window after open, resync, or gap repair.
  Publication replaceWindow(List<ConvEvent> entries, bool hasMore) {
    _contexts.clear();
    _contextsByKind.clear();
    _contextsBySeq.clear();
    _contextsByTarget.clear();
    _inputs.clear();
    _dirty.clear();
    _dirtyByTarget.clear();
    _revised.clear();
    _dependents.clear();
    _hasMore = hasMore;
    final sorted = [...entries]..sort((a, b) => a.seq.compareTo(b.seq));
    for (final e in sorted) {
      _inputs[e.seq] = e;
    }
    _locations.rebuild(sorted);
    _timelineDirty = true;
    for (final e in sorted) {
      _matchInput(e);
    }
    _replayDependencies();
    _revised.clear();
    for (final c in _contexts.values) {
      _markDirty(c);
    }
    _replacePending = true;
    return Publication.immediate;
  }

  /// Add one contiguous live tail event.
  Publication append(ConvEvent event) {
    if (_inputs.containsKey(event.seq)) return Publication.none;
    if (_revised.isNotEmpty) _revised.clear();
    _inputs[event.seq] = event;
    var publication = Publication.none;
    if (event.type != 'assistant/live-chunk' && _isBoundary(event.type)) {
      final previous = _locations.snapshot();
      final changed = _locations.appendBoundary(event);
      if (!identical(_locations.snapshot(), previous)) {
        _timelineDirty = true;
        publication = Publication.immediate;
      }
      _replayContexts(_refreshMatchLocations(changed));
      if (changed.isNotEmpty) publication = Publication.immediate;
    } else {
      _locations.appendNonBoundary(event);
    }
    publication = publication.max(_matchInput(event));
    if (_replayRevisedDependents()) publication = Publication.immediate;
    if (_revised.isNotEmpty) _revised.clear();
    return publication;
  }

  /// Retire one Assistant attempt's transient matches and apply its optional
  /// durable settlement.
  Publication settleAssistant(String attemptId, ConvEvent? entry) {
    _revised.clear();
    final retired = [
      for (final c in _inputs.values)
        if (c.transient && c.data['attemptId'] == attemptId) c,
    ];
    final retiredSeqs = {for (final r in retired) r.seq};
    final affected = <_Context>{};
    for (final seq in retiredSeqs) {
      _inputs.remove(seq);
      affected.addAll(_contextsBySeq[seq] ?? const []);
      _contextsBySeq.remove(seq);
    }
    for (final c in affected) {
      c.matches = [
        for (final m in c.matches)
          if (!retiredSeqs.contains(m.event.seq)) m,
      ];
    }
    _locations.removeAssistantTransients(retired);

    var publication = retired.isEmpty
        ? Publication.none
        : Publication.immediate;
    if (entry != null && !_inputs.containsKey(entry.seq)) {
      _inputs[entry.seq] = entry;
      _locations.insertAssistantSettlement(entry);
      final pending = <String, List<_PendingMatch>>{};
      publication = publication.max(_collectInput(entry, pending));
      _applyPendingMatches(pending, affected);
    }
    _replayContexts(affected);
    if (_replayRevisedDependents()) publication = Publication.immediate;
    _revised.clear();
    return publication;
  }

  /// Add an older page while preserving existing Context identities.
  Publication prepend(List<ConvEvent> entries, bool hasMore) {
    _revised.clear();
    var publication = Publication.none;
    final previousHasMore = _hasMore;
    final fresh = [
      for (final e in entries)
        if (!_inputs.containsKey(e.seq)) e,
    ]..sort((a, b) => a.seq.compareTo(b.seq));
    for (final e in fresh) {
      _inputs[e.seq] = e;
    }
    _hasMore = hasMore;
    final previousTimeline = _locations.snapshot();
    final changedLocations = _locations.rebuild(_sortedInputs());
    if (!identical(_locations.snapshot(), previousTimeline)) {
      _timelineDirty = true;
    }
    final affected = _refreshMatchLocations(changedLocations);
    final pending = <String, List<_PendingMatch>>{};
    for (final e in fresh) {
      publication = publication.max(_collectInput(e, pending));
    }
    _applyPendingMatches(pending, affected);
    _replayContexts(affected);
    if ((_revised.isNotEmpty || previousHasMore != hasMore) &&
        _replayDependencies()) {
      publication = Publication.immediate;
    }
    if (changedLocations.isNotEmpty) publication = Publication.immediate;
    _revised.clear();
    return publication;
  }

  /// Materialize dirty Contexts and advance every active view builder.
  /// Returns whether any view snapshot was rebuilt or incrementally applied.
  bool flush() {
    if (!_replacePending && _dirty.isEmpty && !_timelineDirty) return false;
    if (_replacePending) {
      _replaceLocationData();
      final updated = <_ViewState>[];
      _locations.takeChangedTurns();
      for (final target in _activeTargets) {
        final view = _views[target];
        if (view == null) continue;
        _updateView(
          view,
          true,
          _buildTargetNodes(target, _contextsByTarget[target]),
        );
        updated.add(view);
      }
      _replacePending = false;
      _dirty.clear();
      _dirtyByTarget.clear();
      _timelineDirty = false;
      return updated.isNotEmpty;
    }

    final updated = <_ViewState>[];
    if (_applyDirtyLocationData()) _timelineDirty = true;
    _locations.takeChangedTurns();
    final timelineDirty = _timelineDirty;
    for (final target in _activeTargets) {
      final view = _views[target];
      if (view?.builder == null) continue;
      final upserts = _buildTargetUpserts(target, _dirtyByTarget[target]);
      if (upserts.isEmpty && !timelineDirty) continue;
      _updateView(view!, false, upserts);
      updated.add(view);
    }
    _dirty.clear();
    _dirtyByTarget.clear();
    _timelineDirty = false;
    return updated.isNotEmpty;
  }

  /// Add one target to the monotonic active set and materialize it.
  bool activateTarget(String target) {
    final view = _views[target];
    if (_activeTargets.contains(target)) return false;
    final published = flush();
    _activeTargets.add(target);
    if (view == null) return published;
    _updateView(
      view,
      true,
      _buildTargetNodes(target, _contextsByTarget[target]),
    );
    return true;
  }

  /// The latest snapshot of a registered target, or null before activation.
  Object? snapshot(String target) => _views[target]?.snapshot;

  /// Targets whose owners classify their latest snapshot as visible activity.
  Set<String> activityTargets() => {
    for (final t in _activeTargets)
      if (_views[t] case final v?
          when v.snapshot != null && v.definition.isActive(v.snapshot!))
        v.definition.target,
  };

  // ---- internals -------------------------------------------------------

  List<ConvEvent> _sortedInputs() =>
      _inputs.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));

  Publication _matchInput(ConvEvent input) =>
      _dispatchInput(input, _acceptMatch);

  Publication _collectInput(
    ConvEvent input,
    Map<String, List<_PendingMatch>> pending,
  ) => _dispatchInput(input, (definition, id, match) {
    final key = conversationContextKey(definition.kind, id);
    (pending[key] ??= []).add(_PendingMatch(definition, id, match));
    return definition.publication(match);
  });

  Publication _dispatchInput(
    ConvEvent event,
    Publication Function(ConversationDefinition, String, ConversationMatch)
    accept,
  ) {
    ConversationMatch? startMatch;
    ConversationMatch? updateMatch;
    ConversationLocation? location;
    ConversationMatch matchFor(MatchRole role) {
      location ??= _locations.locationOf(event);
      return role == MatchRole.start
          ? startMatch ??= ConversationMatch(event, role, location!)
          : updateMatch ??= ConversationMatch(event, role, location!);
    }

    final definitions = <ConversationDefinition>[];
    final results = <MatchResult>[];
    for (final d in _events.forEvent(event.type)) {
      final r = d.match(event);
      if (r == null) continue;
      definitions.add(d);
      results.add(r);
    }
    // Claims are resolved before any acceptance (order independent).
    Map<String, String>? claims;
    for (var i = 0; i < results.length; i++) {
      if (!results[i].exclusive) continue;
      final d = definitions[i];
      final target = d.target;
      if (target == null) {
        throw StateError(
          'conversation Definition "${d.kind}" claims ${event.type} at seq ${seqText(event.seq)} without a target',
        );
      }
      final claimant = claims?[target];
      if (claimant != null) {
        throw StateError(
          'conversation Definitions "$claimant" and "${d.kind}" both claim ${event.type} at seq ${seqText(event.seq)} on target "$target"',
        );
      }
      (claims ??= {})[target] = d.kind;
    }
    final seenTargets = <String>{};
    var publication = Publication.none;
    for (var i = 0; i < results.length; i++) {
      final d = definitions[i];
      final r = results[i];
      final target = d.target;
      if (target != null &&
          !r.exclusive &&
          (claims?.containsKey(target) ?? false)) {
        continue;
      }
      if (target != null) seenTargets.add(target);
      publication = publication.max(accept(d, r.id, matchFor(r.role)));
    }
    final fallback = _events.fallback;
    final fTarget = fallback?.target;
    if (fallback != null && fTarget != null && !seenTargets.contains(fTarget)) {
      final r = fallback.match(event);
      if (r != null) {
        publication = publication.max(accept(fallback, r.id, matchFor(r.role)));
      }
    }
    return publication;
  }

  _Context _createContext(ConversationDefinition d, String id, String key) {
    final c = _Context(key, d.kind, id, d);
    _contexts[key] = c;
    final target = d.target;
    if (target != null) {
      (_contextsByTarget[target] ??= {}).add(c);
    }
    return c;
  }

  NodeContext _snapshotOf(_Context c) => NodeContext(
    key: c.key,
    kind: c.kind,
    id: c.id,
    matches: c.matches,
    start: c.start,
    state: c.state,
    current: c.current,
  );

  Publication _acceptMatch(
    ConversationDefinition definition,
    String id,
    ConversationMatch match,
  ) {
    final latest = _contextsByKind[definition.kind]?.lastOrNull;
    final key = latest?.id == id
        ? latest!.key
        : conversationContextKey(definition.kind, id);
    final context = _contexts[key] ?? _createContext(definition, id, key);
    final starting = match.role == MatchRole.start && context.start == null;
    final previous = context.matches.lastOrNull;
    if (previous != null && previous.event.seq >= match.event.seq) {
      throw StateError(
        'conversation Context $key received non-appended Match ${seqText(match.event.seq)}',
      );
    }
    if (starting && context.matches.isNotEmpty) {
      throw StateError(
        'conversation Context $key received an update before its start Match',
      );
    }
    context.matches.add(match);
    if (starting) {
      context.startSeq = match.event.seq;
      context.start = match;
      _indexStartedContext(context);
    }
    (_contextsBySeq[match.event.seq] ??= []).add(context);

    if (starting) {
      _replayContext(context);
    } else if (context.state != null) {
      context.state = _requireState(
        definition,
        'update',
        definition.update(_snapshotOf(context), match),
      );
      context.revision++;
      _revised.add(context);
    }
    _markDirty(context);
    return definition.publication(match);
  }

  void _applyPendingMatches(
    Map<String, List<_PendingMatch>> pending,
    Set<_Context> affected,
  ) {
    for (final entry in pending.entries) {
      final key = entry.key;
      final entries = entry.value;
      if (entries.isEmpty) continue;
      final first = entries.first;
      final context =
          _contexts[key] ?? _createContext(first.definition, first.id, key);
      final additions = <ConversationMatch>[];
      for (final e in entries) {
        if (!identical(e.definition, context.definition) ||
            e.id != context.id) {
          throw StateError(
            'conversation Context $key received inconsistent Definition identity',
          );
        }
        (_contextsBySeq[e.match.event.seq] ??= []).add(context);
        additions.add(e.match);
      }
      additions.sort((a, b) => a.event.seq.compareTo(b.event.seq));
      context.matches = _mergeMatches(key, additions, context.matches);
      affected.add(context);
      _markDirty(context);
    }
  }

  static List<ConversationMatch> _mergeMatches(
    String key,
    List<ConversationMatch> additions,
    List<ConversationMatch> existing,
  ) {
    final merged = <ConversationMatch>[];
    var added = 0;
    var current = 0;
    while (added < additions.length || current < existing.length) {
      final left = added < additions.length ? additions[added] : null;
      final right = current < existing.length ? existing[current] : null;
      if (left != null && right != null && left.event.seq == right.event.seq) {
        throw StateError(
          'conversation Context $key received duplicate Match ${seqText(left.event.seq)}',
        );
      }
      if (right == null || (left != null && left.event.seq < right.event.seq)) {
        merged.add(left!);
        added++;
      } else {
        merged.add(right);
        current++;
      }
    }
    return merged;
  }

  void _replayContexts(Set<_Context> contexts) {
    _refreshStarts(contexts);
    final ordered = [...contexts]
      ..sort(
        (a, b) => (a.startSeq ?? double.infinity).compareTo(
          b.startSeq ?? double.infinity,
        ),
      );
    for (final c in ordered) {
      if (c.start == null) {
        c.state = null;
        _replaceDependencies(c, {});
        c.revision++;
        _revised.add(c);
        _markDirty(c);
        continue;
      }
      _replayContext(c);
    }
  }

  void _refreshStarts(Set<_Context> contexts) {
    final changed = <_Context>{};
    final startsByKind = <String, List<_Context>>{};
    for (final c in contexts) {
      final start = c.matches
          .where((m) => m.role == MatchRole.start)
          .firstOrNull;
      if (identical(start, c.start)) continue;
      c.start = start;
      c.startSeq = start?.event.seq;
      changed.add(c);
      final starts = startsByKind.putIfAbsent(c.kind, () => []);
      if (start != null) starts.add(c);
    }
    for (final entry in startsByKind.entries) {
      final existing = _contextsByKind[entry.key] ?? const <_Context>[];
      _contextsByKind[entry.key] = [
        for (final c in existing)
          if (!changed.contains(c)) c,
      ];
      _indexStartedContexts(entry.key, entry.value);
    }
  }

  void _replayContext(_Context c) {
    final start = c.start;
    if (start == null) {
      c.state = null;
      return;
    }
    if (!identical(c.matches.first, start)) {
      throw StateError(
        'conversation Context ${c.key} received an update before its start Match',
      );
    }
    final dependencies = <String, _Dependency>{};
    final reader = _readerFor(start.event.seq, dependencies);
    c.state = null;
    c.state = _requireState(
      c.definition,
      'start',
      c.definition.start(_snapshotOf(c), start, reader),
    );
    _replaceDependencies(c, dependencies);
    for (var i = 1; i < c.matches.length; i++) {
      c.state = _requireState(
        c.definition,
        'update',
        c.definition.update(_snapshotOf(c), c.matches[i]),
      );
    }
    c.revision++;
    _revised.add(c);
    _markDirty(c);
  }

  void _markDirty(_Context c) {
    if (!_dirty.add(c)) return;
    final target = c.definition.target;
    if (target == null || !_activeTargets.contains(target)) return;
    (_dirtyByTarget[target] ??= {}).add(c);
  }

  void _replaceDependencies(_Context c, Map<String, _Dependency> next) {
    for (final d in c.dependencies.values) {
      if (d.key == null) continue;
      final set = _dependents[d.key!];
      set?.remove(c);
      if (set != null && set.isEmpty) _dependents.remove(d.key);
    }
    c.dependencies = next;
    for (final d in next.values) {
      if (d.key == null) continue;
      (_dependents[d.key!] ??= {}).add(c);
    }
  }

  bool _replayRevisedDependents() {
    if (_dependents.isEmpty) return false;
    final pending = [..._revised];
    final affected = <_Context>{};
    for (var i = 0; i < pending.length; i++) {
      for (final dependent
          in _dependents[pending[i].key] ?? const <_Context>{}) {
        if (!affected.add(dependent)) continue;
        pending.add(dependent);
      }
    }
    if (affected.isNotEmpty) _replayContexts(affected);
    return affected.isNotEmpty;
  }

  ContextReader _readerFor(num beforeSeq, Map<String, _Dependency> deps) =>
      _Reader((kind) {
        final predecessor = _previousContext(kind, beforeSeq);
        deps[kind] = _Dependency(
          kind,
          predecessor?.key,
          predecessor?.revision,
          predecessor == null && _hasMore,
        );
        if (predecessor?.state == null) return null;
        final seq = predecessor!.startSeq;
        if (seq == null) return null;
        return PreviousContext(
          key: predecessor.key,
          kind: predecessor.kind,
          id: predecessor.id,
          startSeq: seq,
          state: predecessor.state!,
          matches: predecessor.matches,
        );
      });

  _Context? _previousContext(String kind, num beforeSeq) {
    final candidates = _contextsByKind[kind] ?? const <_Context>[];
    final at = _insertionIndex(candidates, beforeSeq);
    for (var i = at - 1; i >= 0; i--) {
      if (candidates[i].state != null) return candidates[i];
    }
    return null;
  }

  static int _insertionIndex(List<_Context> contexts, num seq) {
    var low = 0;
    var high = contexts.length;
    while (low < high) {
      final mid = low + (high - low) ~/ 2;
      if (contexts[mid].startSeq! < seq) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  void _indexStartedContext(_Context c) {
    final seq = c.startSeq;
    if (seq == null) return;
    final candidates = _contextsByKind.putIfAbsent(c.kind, () => []);
    final previous = candidates.lastOrNull;
    if (previous == null || previous.startSeq! < seq) {
      candidates.add(c);
    } else {
      candidates.insert(_insertionIndex(candidates, seq), c);
    }
  }

  void _indexStartedContexts(String kind, List<_Context> additions) {
    if (additions.isEmpty) return;
    final sorted = [...additions]
      ..sort((a, b) => a.startSeq!.compareTo(b.startSeq!));
    final existing = _contextsByKind[kind] ?? const <_Context>[];
    final merged = <_Context>[];
    var before = 0;
    var added = 0;
    while (before < existing.length || added < sorted.length) {
      final left = before < existing.length ? existing[before] : null;
      final right = added < sorted.length ? sorted[added] : null;
      if (right == null || (left != null && left.startSeq! < right.startSeq!)) {
        merged.add(left!);
        before++;
      } else {
        merged.add(right);
        added++;
      }
    }
    _contextsByKind[kind] = merged;
  }

  bool _replayDependencies() {
    var replayed = false;
    final ordered = [
      for (final c in _contexts.values)
        if (c.startSeq != null) c,
    ]..sort((a, b) => a.startSeq!.compareTo(b.startSeq!));
    for (final c in ordered) {
      if (c.state == null || c.dependencies.isEmpty) continue;
      final before = c.startSeq;
      if (before == null) continue;
      var changed = false;
      for (final d in c.dependencies.values) {
        final current = _previousContext(d.kind, before);
        final windowGap = current == null && _hasMore;
        if (current?.key != d.key ||
            current?.revision != d.revision ||
            windowGap != d.windowGap) {
          changed = true;
          break;
        }
      }
      if (changed) {
        _replayContext(c);
        replayed = true;
      }
    }
    return replayed;
  }

  Set<_Context> _refreshMatchLocations(Set<num> changedSeqs) {
    final affected = <_Context>{};
    if (changedSeqs.isEmpty) return affected;
    for (final seq in changedSeqs) {
      affected.addAll(_contextsBySeq[seq] ?? const []);
    }
    for (final c in affected) {
      var start = c.start;
      final matches = <ConversationMatch>[];
      for (final m in c.matches) {
        if (!changedSeqs.contains(m.event.seq)) {
          matches.add(m);
          continue;
        }
        final refreshed = m.withLocation(_locations.locationOf(m.event));
        if (identical(m, start)) start = refreshed;
        matches.add(refreshed);
      }
      c.matches = matches;
      c.start = start;
    }
    return affected;
  }

  ViewNode? _buildNode(_Context c, String target) {
    if (c.definition.target != target) return null;
    final node = c.definition.buildViewNode(_snapshotOf(c));
    if (node == null) return null;
    if (node.key != c.key) {
      throw StateError(
        'conversation Definition "${c.kind}" returned unstable key "${node.key}"; expected "${c.key}"',
      );
    }
    if (node.target != target) {
      throw StateError(
        'conversation Definition "${c.kind}" returned target "${node.target}" while building "$target"',
      );
    }
    return node;
  }

  void _updateView(_ViewState view, bool replacing, List<ViewNode> nodes) {
    final builder = view.builder ?? view.definition.create();
    view.builder = builder;
    final timeline = _locations.snapshot();
    view.snapshot = replacing
        ? builder.replace(nodes, timeline)
        : builder.apply(nodes, timeline);
  }

  List<ViewNode> _buildTargetNodes(
    String target,
    Iterable<_Context>? contexts,
  ) {
    final nodes = <ViewNode>[];
    for (final c in contexts ?? const <_Context>[]) {
      final node = _buildNode(c, target);
      c.current[target] = node;
      if (node != null) nodes.add(node);
    }
    return nodes;
  }

  List<ViewNode> _buildTargetUpserts(
    String target,
    Iterable<_Context>? contexts,
  ) {
    final upserts = <ViewNode>[];
    for (final c in contexts ?? const <_Context>[]) {
      final previous = c.current[target];
      final node = _buildNode(c, target);
      if (node == null && previous != null) {
        throw StateError(
          'conversation Definition "${c.kind}" withdrew materialized target "$target"; return the same key with hidden visibility instead',
        );
      }
      c.current[target] = node;
      if (node != null) upserts.add(node);
    }
    return upserts;
  }

  LocationData? _buildLocationData(
    _Context c,
    LocationScope scope,
    LocationData? previous,
  ) {
    final data = c.definition.buildLocationData(
      _snapshotOf(c),
      scope,
      previous,
    );
    if (data == null) return null;
    if (data.scope != scope) {
      throw StateError(
        'conversation Definition "${c.kind}" published ${data.scope.name} data through its ${scope.name} scope',
      );
    }
    if (data.key != c.kind) {
      throw StateError(
        'conversation Definition "${c.kind}" published Location data key "${data.key}"; expected its owned kind',
      );
    }
    return data;
  }

  void _replaceLocationData() {
    final entries = <({String owner, LocationData data})>[];
    for (final scope in LocationScope.values) {
      for (final c in _contexts.values) {
        final data = _buildLocationData(c, scope, c.locationData[scope]);
        c.locationData[scope] = data;
        if (data != null) entries.add((owner: c.key, data: data));
      }
      // Turn publishers may read Step data from this same flush.
      _locations.replaceData(entries);
    }
  }

  bool _applyDirtyLocationData() {
    var changed = false;
    for (final scope in LocationScope.values) {
      final changes = <LocationDataChange>[];
      for (final c in _dirty) {
        final previous = c.locationData[scope];
        final next = _buildLocationData(c, scope, previous);
        if (identical(previous, next)) continue;
        c.locationData[scope] = next;
        changes.add(LocationDataChange(c.key, previous, next));
      }
      changed = _locations.applyData(changes) || changed;
    }
    return changed;
  }

  void _resetViewBuilders() {
    _views.clear();
    for (final d in _viewRegistry.entries) {
      _views[d.target] = _ViewState(d);
    }
    _replacePending = true;
  }

  static bool _isBoundary(String type) =>
      type == 'turn/start' ||
      type == 'turn/end' ||
      type == 'step/start' ||
      type == 'step/end';

  static Object _requireState(
    ConversationDefinition d,
    String phase,
    Object? state,
  ) {
    if (state == null) {
      throw StateError(
        'conversation Definition "${d.kind}" returned null from $phase()',
      );
    }
    return state;
  }
}

class _Reader implements ContextReader {
  _Reader(this._previous);
  final PreviousContext? Function(String kind) _previous;
  @override
  PreviousContext? previous(String kind) => _previous(kind);
}
