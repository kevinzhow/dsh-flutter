/// The input-trigger pipeline (dsh `ui-input-trigger` `controller` and
/// `service`): the source registry, and one controller per session that owns
/// the authoritative hit, the menu store and the candidate-fetch lifecycle, and
/// that executes pick outcomes through the composer's [TriggerEditorPort].
library;

import 'dart:async';

import 'package:dsh_models/dsh_models.dart' show Observable;

import 'trigger_detect.dart';
import 'trigger_menu.dart';
import 'trigger_types.dart';

/// What the pipeline needs of the composer to apply a pick (dsh's scoped
/// `slash/input-*` events). Every method answers whether the edit applied
/// (draft revision and span guards passed).
abstract interface class TriggerEditorPort {
  bool beginCommand(CommandClaim claim, TokenSpan span);
  bool insertReference(ReferenceInsert reference, TokenSpan span);
  bool insertText(String text, TokenSpan span, {bool keepCompleting = false});

  /// Consume the command token after business success: a menu pick removes its
  /// span (revision guard); an Enter-path line clears the draft when it still
  /// equals the bare [token].
  bool consumeSpan(TokenSpan span);
  bool consumeBareToken(String token);

  /// Show a transient message in the composer (a detached command's admission
  /// failure).
  void notify(bool error, String text);

  /// Return the keyboard to the composer with the caret it last held.
  void requestFocus();
}

/// The keys an open menu intercepts.
enum ArbitrateKey { up, down, enter, escape, tab, tabBack }

/// The menu's verdict on a key.
enum ArbitrateOutcome { consumed, pickHighlighted, pass }

/// Token identity a dismissal sticks to.
class _Dismissed {
  const _Dismissed(this.hit);
  final TriggerHit hit;

  bool matches(TriggerHit other) =>
      hit.trigger == other.trigger &&
      hit.query == other.query &&
      hit.quoted == other.quoted &&
      hit.span.start == other.span.start &&
      hit.span.end == other.span.end;
}

/// The root registry (dsh `InputTriggerService`): registration order is menu
/// group order and the matchSpace/matchEnter poll order.
class InputTriggerRegistry {
  final List<InputTriggerSource> _sources = [];
  final Map<String, InputTriggerController> _controllers = {};

  /// Every registered source, in registration order.
  List<InputTriggerSource> get all => List.unmodifiable(_sources);

  /// The sources of [trigger] in menu order (stable on ties).
  List<InputTriggerSource> sources(TriggerChar trigger) {
    final list = [
      for (final s in _sources)
        if (s.trigger == trigger) s,
    ];
    final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])];
    indexed.sort((a, b) {
      final byOrder = a.$2.order.compareTo(b.$2.order);
      return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
    });
    return [for (final e in indexed) e.$2];
  }

  /// Register one source; (trigger, name) must be unique. Returns the disposer.
  void Function() registerSource(InputTriggerSource source) {
    if (_sources.any(
      (s) => s.trigger == source.trigger && s.name == source.name,
    )) {
      throw StateError(
        'input source "${source.trigger.char}${source.name}" is already registered',
      );
    }
    _sources.add(source);
    for (final c in _controllers.values) {
      try {
        c._sourceAdded(source);
      } on Object catch (e) {
        // A faulty late-registration hook must not undo the registration.
        _log('late registration of ${source.name} failed: $e');
      }
    }
    return () {
      if (!_sources.remove(source)) return;
      for (final c in _controllers.values) {
        c._sourceRemoved(source);
      }
    };
  }

  /// The controller of one session (created on first use, disposed with
  /// [release]).
  InputTriggerController sessionOf(String sessionId, TriggerEditorPort port) =>
      _controllers.putIfAbsent(
        sessionId,
        () => InputTriggerController._(sessionId, this, port),
      );

  /// The controller of [sessionId] if one is running (a popup settling after
  /// the composer went away reaches the draft through it).
  InputTriggerController? controllerOf(String sessionId) =>
      _controllers[sessionId];

  /// Drop a closed session's controller.
  void release(String sessionId) => _controllers.remove(sessionId)?.dispose();

  /// Refresh every open menu (the locale changed).
  void refreshOpenMenus() {
    for (final c in _controllers.values) {
      c.refreshOpenMenu();
    }
  }
}

void _log(String message) {
  // ignore: avoid_print
  print('[input-trigger] $message');
}

/// The per-session half of the pipeline.
class InputTriggerController {
  InputTriggerController._(this.sessionId, this._registry, this.port) {
    for (final s in _registry.all) {
      _sourceAdded(s);
    }
  }

  final String sessionId;
  final InputTriggerRegistry _registry;
  final lexiconRevision = Observable(0);
  final _lexiconSubscriptions =
      <InputTriggerSource, StreamSubscription<Object?>>{};
  List<InputLexeme> lexemes(String text) {
    final found = <InputLexeme>[];
    for (final source in _registry.all) {
      for (final entry in source.lexicon(sessionId)) {
        if (entry.token.isEmpty) continue;
        final pattern = RegExp('(?<!\\S)${RegExp.escape(entry.token)}(?!\\S)');
        for (final match in pattern.allMatches(text)) {
          if (found.any((r) => match.start < r.end && match.end > r.start)) {
            continue;
          }
          found.add(InputLexeme(match.start, match.end, source.name, entry));
        }
      }
    }
    return found..sort((a, b) => a.start.compareTo(b.start));
  }

  /// The composer the picks are applied to.
  final TriggerEditorPort port;

  /// Menu state (survives session switches, dies with the controller).
  final Observable<MenuState> menu = Observable(menuClosed);

  /// The source opened through the launcher, or null.
  final Observable<String?> launcher = Observable(null);

  /// Crumbs per header-bearing source for the open menu.
  final Observable<Map<String, List<InputTriggerCrumb>>> headers = Observable(
    const {},
  );

  TriggerHit? _hit;
  _Dismissed? _dismissed;
  bool _drilled = false;
  AbortController? _fetch;
  bool _disposed = false;

  /// The authoritative hit (it outlives menu close for space adjudication).
  TriggerHit? get hit => _hit;

  /// Feed a draft/caret change through detection and drive the menu.
  void track(String draft, int caret, TriggerTier tier, int draftRev) {
    if (_disposed) return;
    final launched = launcher.value != null;
    _clearLauncher();
    final raw = detectTrigger(draft, caret, tier);
    if (raw == null) {
      // A launcher-opened menu is opened by a gesture, not a typed token: the
      // follow-up track that focus triggers must not close it.
      if (launched) return;
      _hit = null;
      // A frozen-tier track is the submit gesture's own bookkeeping.
      if (tier != TriggerTier.frozen) _dismissed = null;
      _stopFetch();
      _reduce(const MenuClose());
      return;
    }
    final hit = raw.withRev(draftRev);
    if (launched) _dismissed = null;
    final dismissed = _dismissed;
    if (dismissed != null) {
      if (!dismissed.matches(hit)) {
        _dismissed = null;
      } else {
        _hit = hit;
        return;
      }
    }
    final prev = menu.value;
    final prevHit = prev.hit;
    final same =
        !launched &&
        prev.open &&
        prevHit != null &&
        prevHit.trigger == hit.trigger &&
        prevHit.query == hit.query &&
        prevHit.quoted == hit.quoted &&
        prevHit.span.start == hit.span.start &&
        prevHit.span.end == hit.span.end;
    _hit = hit;
    if (same) return;
    final roster = _registry.sources(hit.trigger);
    if (roster.isEmpty) {
      _stopFetch();
      _reduce(const MenuClose());
      return;
    }
    if (launched ||
        !prev.open ||
        prevHit == null ||
        prevHit.trigger != hit.trigger) {
      menu.set(seedGroups(menu.value, _rosterOf(roster)));
    }
    _reduce(MenuHit(hit));
    _refreshHeaders(hit, roster);
    _fetchCandidates(hit, roster);
  }

  /// Toggle a menu containing exactly one source (the composer's launcher).
  void toggleSource(String source, TriggerHit hit) {
    if (_disposed) return;
    if (launcher.value == source && menu.value.open) {
      dismiss();
      return;
    }
    final match = _registry
        .sources(hit.trigger)
        .where((s) => s.name == source)
        .firstOrNull;
    if (match == null) {
      dismiss();
      return;
    }
    match.prepareLaunch(sessionId);
    _stopFetch();
    _hit = hit;
    launcher.set(source);
    menu.set(seedGroups(menu.value, _rosterOf([match])));
    _reduce(MenuHit(hit));
    _refreshHeaders(hit, [match]);
    _fetchCandidates(hit, [match]);
  }

  /// Pointer pick of one candidate.
  void pick(String source, int index, [PickAction action = PickAction.pick]) {
    final state = menu.value;
    final hit = _hit;
    if (_disposed || !state.open || hit == null) return;
    final group = state.groups.where((g) => g.source == source).firstOrNull;
    final candidate = group != null && group.ready && index < group.items.length
        ? group.items[index]
        : null;
    if (candidate == null) return;
    final src = _registry
        .sources(hit.trigger)
        .where((s) => s.name == source)
        .firstOrNull;
    if (src == null) return;
    _settle(src, candidate, hit, action);
  }

  /// Pointer pick of one header crumb: the drill path a folder row takes.
  void pickCrumb(String source, int index) {
    final hit = _hit;
    if (_disposed || !menu.value.open || hit == null) return;
    final crumbs = headers.value[source];
    if (crumbs == null || index >= crumbs.length) return;
    final crumb = crumbs[index];
    if (crumb.current) return;
    final src = _registry
        .sources(hit.trigger)
        .where((s) => s.name == source)
        .firstOrNull;
    if (src == null) return;
    _settle(
      src,
      InputTriggerCandidate(name: crumb.label, value: crumb.value),
      hit,
      PickAction.drill,
    );
  }

  /// Pointer hover: park the shared highlight.
  void hover(String source, int index) {
    if (_disposed) return;
    _reduce(MenuHover(source, index));
  }

  /// Keyboard arbitration while the menu is open.
  ArbitrateOutcome arbitrate(ArbitrateKey key, {bool composing = false}) {
    if (composing || _disposed) return ArbitrateOutcome.pass;
    final state = menu.value;
    if (!state.open) return ArbitrateOutcome.pass;
    switch (key) {
      case ArbitrateKey.up:
        _reduce(const MenuMove(-1));
        return ArbitrateOutcome.consumed;
      case ArbitrateKey.down:
        _reduce(const MenuMove(1));
        return ArbitrateOutcome.consumed;
      case ArbitrateKey.escape || ArbitrateKey.tabBack:
        // The exit gesture never settles a candidate.
        _rememberDismissed();
        _stopFetch();
        _reduce(const MenuClose());
        return ArbitrateOutcome.consumed;
      case ArbitrateKey.enter:
        final hl = state.highlight;
        if (hl == null) return ArbitrateOutcome.pass;
        final group = state.groups.firstWhere((g) => g.source == hl.source);
        // A pending refinement keeps the stale rows: Enter neither picks them
        // nor falls through to submit.
        if (!group.ready) return ArbitrateOutcome.consumed;
        pick(hl.source, hl.index);
        return ArbitrateOutcome.pickHighlighted;
      case ArbitrateKey.tab:
        final hl = state.highlight;
        if (hl == null) return ArbitrateOutcome.pass;
        final group = state.groups.firstWhere((g) => g.source == hl.source);
        if (!group.ready) return ArbitrateOutcome.consumed;
        if (hl.index >= group.items.length) return ArbitrateOutcome.pass;
        if (group.items[hl.index].drill) {
          pick(hl.source, hl.index, PickAction.drill);
          return ArbitrateOutcome.consumed;
        }
        pick(hl.source, hl.index);
        return ArbitrateOutcome.pickHighlighted;
    }
  }

  /// Space adjudication over the just-completed leading token. True when a
  /// claim was applied (the caller consumes the keystroke).
  bool onSpace() {
    final hit = _hit;
    if (_disposed || hit == null || hit.position != TriggerPosition.leading) {
      return false;
    }
    final token = '${hit.trigger.char}${hit.query}';
    for (final src in _registry.sources(hit.trigger)) {
      if (!src.adjudicatesSpace) continue;
      final outcome = src.matchSpace(sessionId, token);
      if (outcome == null) continue;
      if (outcome is PickHandled) return true;
      return _execute(outcome, hit.span);
    }
    return false;
  }

  /// Serialize one reference to its model form through its source's codec; a
  /// missing owner or codec rejects (the send blocks, never a silent
  /// downgrade).
  Future<String> serializeReference(
    String source,
    String ref,
    AbortSignal signal,
  ) {
    final owner = _registry.all.where((s) => s.name == source).firstOrNull;
    final codec = owner?.codec;
    if (codec == null) {
      return Future.error(
        StateError('no serializer for reference source "$source"'),
      );
    }
    return codec.serialize(ref, signal);
  }

  /// Route a chip to its owner (a file chip opens its preview).
  bool openReference(String source, String ref, String? appearance) {
    if (_disposed) return false;
    for (final owner in _registry.all) {
      if (owner.name == source &&
          owner.openReference(sessionId, ref, appearance)) {
        dismiss();
        return true;
      }
    }
    return false;
  }

  /// Enter-time adjudication: the first non-null answer of a source whose
  /// trigger is the line's first character wins; rejects when a polled source
  /// refuses (the caller must not silently downgrade).
  Future<PickOutcome?> adjudicate(
    String line,
    AbortSignal signal,
    SubmitEnvelope envelope,
  ) async {
    for (final src in _registry.all) {
      if (signal.aborted) throw signal.reason ?? const AbortedException();
      if (!src.adjudicatesEnter || !line.startsWith(src.trigger.char)) continue;
      final outcome = await src.matchEnter(sessionId, line, signal, envelope);
      if (outcome != null) return outcome;
    }
    return null;
  }

  /// Resolve the claim a persisted command chip names; never acts.
  Future<CommandClaim?> resolveClaim(String token, AbortSignal signal) async {
    for (final src in _registry.all) {
      if (signal.aborted) throw signal.reason ?? const AbortedException();
      if (!src.resolvesClaims || !token.startsWith(src.trigger.char)) continue;
      final claim = await src.matchClaim(sessionId, token, signal);
      if (claim != null) return claim;
    }
    return null;
  }

  /// External dismiss (a press outside the composer area).
  void dismiss() {
    if (_disposed) return;
    _rememberDismissed();
    _stopFetch();
    _reduce(const MenuClose());
  }

  /// Re-fetch the open menu without changing its hit or visible rows.
  void refreshOpenMenu() {
    final hit = _hit;
    if (_disposed || !menu.value.open || hit == null) return;
    final launched = launcher.value;
    final roster = [
      for (final s in _registry.sources(hit.trigger))
        if (launched == null || s.name == launched) s,
    ];
    if (roster.isEmpty) return;
    _fetchCandidates(hit, roster);
  }

  /// Teardown: close and abort.
  void dispose() {
    _disposed = true;
    for (final sub in _lexiconSubscriptions.values) {
      unawaited(sub.cancel());
    }
    _lexiconSubscriptions.clear();
    unawaited(lexiconRevision.dispose());
    _stopFetch();
    _reduce(const MenuClose());
    _hit = null;
  }

  List<({String name, bool showGroupTitle})> _rosterOf(
    List<InputTriggerSource> sources,
  ) => [
    for (final s in sources) (name: s.name, showGroupTitle: s.showGroupTitle),
  ];

  void _sourceAdded(InputTriggerSource source) {
    final stream = source.lexiconChanges;
    if (stream != null) {
      _lexiconSubscriptions[source] = stream.listen((_) {
        if (!_disposed) lexiconRevision.set(lexiconRevision.value + 1);
      });
    }
    source.warm(sessionId);
    if (!_disposed) lexiconRevision.set(lexiconRevision.value + 1);
  }

  void _sourceRemoved(InputTriggerSource source) {
    unawaited(_lexiconSubscriptions.remove(source)?.cancel());
    if (!_disposed) lexiconRevision.set(lexiconRevision.value + 1);
    final state = menu.value;
    final hit = state.hit;
    if (state.open && hit != null && hit.trigger == source.trigger) {
      _reduce(MenuSourceFailed(state.generation, source.name));
    }
  }

  bool _execute(PickOutcome? outcome, TokenSpan span) {
    switch (outcome) {
      case null || PickHandled():
        return false;
      case PickClaim(:final claim):
        return port.beginCommand(claim, span);
      case PickInsertText(:final text, :final keepCompleting):
        return port.insertText(text, span, keepCompleting: keepCompleting);
      case PickInsertReference(:final reference):
        return port.insertReference(reference, span);
    }
  }

  void _fetchCandidates(TriggerHit hit, List<InputTriggerSource> roster) {
    _stopFetch();
    final controller = AbortController();
    _fetch = controller;
    final generation = menu.value.generation;
    for (final source in roster) {
      source
          .candidates(
            sessionId,
            CandidateRequest(
              query: hit.query,
              quoted: hit.quoted,
              position: hit.position,
              drilled: _drilled,
              signal: controller.signal,
            ),
          )
          .then(
            (items) {
              if (controller.signal.aborted || _disposed) return;
              _reduce(MenuSourceSettled(generation, source.name, items));
            },
            onError: (Object error) {
              if (controller.signal.aborted || _disposed) return;
              _log('source "${source.name}" candidates failed: $error');
              _reduce(MenuSourceFailed(generation, source.name));
            },
          );
    }
  }

  void _stopFetch() {
    _fetch?.abort();
    _fetch = null;
  }

  /// Run one candidate (or crumb) through its source and apply the outcome. A
  /// drill is the one pick that leaves the menu open, so it is also the one
  /// that records how the next query was reached.
  void _settle(
    InputTriggerSource src,
    InputTriggerCandidate candidate,
    TriggerHit hit,
    PickAction action,
  ) {
    final outcome = src.onPick(
      InputTriggerPick(
        candidate: candidate,
        sessionId: sessionId,
        position: hit.position,
        via: PickVia.menu,
        action: action,
        span: hit.span,
      ),
    );
    _stopFetch();
    // A settling pick is the user's decision about this token: the menu stays
    // closed for it until the text changes.
    if (action == PickAction.pick) _rememberDismissed();
    _reduce(const MenuClose());
    _drilled = action == PickAction.drill;
    if (!_execute(outcome, hit.span)) _drilled = false;
  }

  void _refreshHeaders(TriggerHit hit, List<InputTriggerSource> roster) {
    final crumbs = <String, List<InputTriggerCrumb>>{};
    for (final src in roster) {
      List<InputTriggerCrumb>? published;
      try {
        published = src.header(
          sessionId,
          HeaderRequest(
            query: hit.query,
            quoted: hit.quoted,
            drilled: _drilled,
          ),
        );
      } on Object catch (e) {
        _log('source "${src.name}" header failed: $e');
        continue;
      }
      if (published == null || published.isEmpty) continue;
      crumbs[src.name] = published;
    }
    _setHeaders(crumbs);
  }

  void _setHeaders(Map<String, List<InputTriggerCrumb>> next) {
    if (headers.value.isEmpty && next.isEmpty) return;
    headers.set(next);
  }

  void _rememberDismissed() {
    final hit = _hit;
    _dismissed = hit == null ? null : _Dismissed(hit);
  }

  void _clearLauncher() {
    if (launcher.value != null) launcher.set(null);
  }

  void _reduce(MenuEvent ev) {
    final cur = menu.value;
    final next = menuReduce(cur, ev);
    if (!identical(next, cur)) menu.set(next);
    if (next.open) return;
    _clearLauncher();
    _drilled = false;
    _setHeaders(const {});
  }
}
