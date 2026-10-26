/// The input-trigger contract (dsh `ui-input-trigger` types and the input
/// currency `ui-conversation` owns): what a source offers, what a pick asks the
/// composer to do, and the menu state the view renders.
library;

import 'dart:async';

/// The character a source binds to.
enum TriggerChar {
  slash('/'),
  at('@');

  const TriggerChar(this.char);
  final String char;

  static TriggerChar? of(String char) => switch (char) {
    '/' => slash,
    '@' => at,
    _ => null,
  };
}

/// Where the trigger token sits: the trimmed draft starts with it, or inline.
enum TriggerPosition { leading, inline }

/// Which path produced a pick.
enum PickVia { menu, space, enter }

/// Resolve the candidate, or drill into it in place.
enum PickAction { pick, drill }

/// Trigger availability, derived from the input phase.
enum TriggerTier {
  /// `/` and `@` live.
  plain,

  /// `/` suppressed, `@` live (a command chip holds the draft's head).
  claimed,

  /// None (a submit is in flight).
  frozen,
}

/// A pick-time draft span guarded by the draft revision (compare-and-set).
class TokenSpan {
  const TokenSpan(this.start, this.end, this.draftRev);
  final int start;
  final int end;
  final int draftRev;

  TokenSpan withRev(int rev) => TokenSpan(start, end, rev);

  @override
  bool operator ==(Object other) =>
      other is TokenSpan &&
      other.start == start &&
      other.end == end &&
      other.draftRev == draftRev;

  @override
  int get hashCode => Object.hash(start, end, draftRev);

  @override
  String toString() => 'TokenSpan($start, $end, rev $draftRev)';
}

/// A trigger token detected under the caret.
class TriggerHit {
  const TriggerHit({
    required this.trigger,
    required this.query,
    required this.quoted,
    required this.position,
    required this.span,
  });

  final TriggerChar trigger;

  /// The text between the trigger character and the caret.
  final String query;

  /// True only for an open quoted `@file` token.
  final bool quoted;
  final TriggerPosition position;
  final TokenSpan span;

  TriggerHit withRev(int rev) => TriggerHit(
    trigger: trigger,
    query: query,
    quoted: quoted,
    position: position,
    span: span.withRev(rev),
  );

  @override
  bool operator ==(Object other) =>
      other is TriggerHit &&
      other.trigger == trigger &&
      other.query == query &&
      other.quoted == quoted &&
      other.position == position &&
      other.span == span;

  @override
  int get hashCode => Object.hash(trigger, query, quoted, position, span);
}

/// One menu row: pure display data.
class InputTriggerCandidate {
  const InputTriggerCandidate({
    required this.name,
    this.label,
    this.description,
    this.icon,
    this.hint,
    this.section,
    this.value,
    this.drill = false,
  });

  /// Identity: the pick payload, the exact-match key, the first search key.
  final String name;

  /// The display title; the name itself when absent. Every label is the second
  /// search key.
  final String? label;
  final String? description;

  /// A glyph key (`file`, `folder`, `session`, or a command glyph); the menu
  /// view maps it to its icon.
  final String? icon;
  final String? hint;

  /// A visual heading shared by adjacent candidates.
  final String? section;

  /// Opaque source-owned pick payload.
  final String? value;

  /// The row offers a drill action beside the settling pick.
  final bool drill;

  InputTriggerCandidate copyWith({String? section}) => InputTriggerCandidate(
    name: name,
    label: label,
    description: description,
    icon: icon,
    hint: hint,
    section: section ?? this.section,
    value: value,
    drill: drill,
  );
}

/// One crumb of a source's menu header.
class InputTriggerCrumb {
  const InputTriggerCrumb({
    required this.label,
    required this.value,
    this.current = false,
  });
  final String label;
  final String value;

  /// The step the menu shows now; the trailing, unclickable crumb.
  final bool current;
}

/// What a source needs to decide the header of the open menu.
class HeaderRequest {
  const HeaderRequest({
    required this.query,
    required this.quoted,
    required this.drilled,
  });
  final String query;
  final bool quoted;
  final bool drilled;
}

/// Non-text composer submission state visible to enter adjudication.
class SubmitEnvelope {
  const SubmitEnvelope({this.attachments = 0});
  final int attachments;
}

/// The cancellation signal of a candidate fetch or a submit attempt (dsh
/// passes an `AbortSignal`).
class AbortSignal {
  AbortSignal._(this._reason);
  Object? _reason;

  bool get aborted => _reason != null;
  Object? get reason => _reason;

  final List<void Function()> _listeners = [];

  /// Throws the abort reason when aborted.
  void throwIfAborted() {
    if (_reason != null) throw _reason!;
  }

  /// Run [listener] once on abort (immediately when already aborted).
  void onAbort(void Function() listener) {
    if (aborted) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);

  /// A signal that never aborts.
  static final AbortSignal never = AbortSignal._(null);
}

/// Owns an [AbortSignal] (dsh `AbortController`).
class AbortController {
  final AbortSignal signal = AbortSignal._(null);

  /// Abort once; later calls are no-ops.
  void abort([Object? reason]) {
    if (signal.aborted) return;
    signal._reason = reason ?? const AbortedException();
    final listeners = [...signal._listeners];
    signal._listeners.clear();
    for (final l in listeners) {
      l();
    }
  }
}

class AbortedException implements Exception {
  const AbortedException([this.message = 'aborted']);
  final String message;
  @override
  String toString() => message;
}

/// A candidate request passed to a source.
class CandidateRequest {
  const CandidateRequest({
    required this.query,
    required this.quoted,
    required this.position,
    required this.drilled,
    required this.signal,
  });
  final String query;
  final bool quoted;
  final TriggerPosition position;
  final bool drilled;
  final AbortSignal signal;
}

/// Everything a source receives on pick.
class InputTriggerPick {
  const InputTriggerPick({
    required this.candidate,
    required this.sessionId,
    required this.position,
    required this.via,
    required this.action,
    required this.span,
  });
  final InputTriggerCandidate candidate;
  final String sessionId;
  final TriggerPosition position;
  final PickVia via;
  final PickAction action;
  final TokenSpan span;
}

/// A structured reference a pick inserts as one atomic chip.
class ReferenceInsert {
  const ReferenceInsert({
    required this.source,
    required this.ref,
    required this.label,
    required this.clipboardText,
    this.appearance,
  });
  final String source;
  final String ref;
  final String label;

  /// `session`, `file` or `folder`.
  final String? appearance;
  final String clipboardText;
}

/// The outcome of a submit transaction.
class SubmitOutcome {
  const SubmitOutcome.success([this.text]) : isError = false;
  const SubmitOutcome.error([this.text]) : isError = true;
  final bool isError;
  final String? text;
}

/// One attachment accompanying a command submission (`commands/execute`
/// wire form).
typedef SubmitAttachment = Map<String, Object?>;

/// A command a pick or Enter claimed: the composer keeps [token] in the draft
/// as a chip and reads the arguments after it.
class CommandClaim {
  const CommandClaim({
    required this.name,
    required this.token,
    required this.submit,
    this.hint,
    this.attachments = false,
  });

  /// The catalog name.
  final String name;

  /// The spelling the draft carries, with its argument separator (`/goal `).
  final String token;
  final String? hint;

  /// Whether composer attachments may accompany the invocation.
  final bool attachments;

  /// Run the command with the text after the token.
  final Future<SubmitOutcome> Function(
    String args,
    List<SubmitAttachment> attachments,
  )
  submit;
}

/// What a pick (or Space, Enter) asks the composer to do. `null` = the source
/// does not handle it.
sealed class PickOutcome {
  const PickOutcome();
}

/// The source already acted (popup opened, command executed detached).
final class PickHandled extends PickOutcome {
  const PickHandled();
}

/// Replace the leading token with a command chip.
final class PickClaim extends PickOutcome {
  const PickClaim(this.claim);
  final CommandClaim claim;
}

/// Splice plain text over the token; [keepCompleting] leaves the menu live.
final class PickInsertText extends PickOutcome {
  const PickInsertText(this.text, {this.keepCompleting = false});
  final String text;
  final bool keepCompleting;
}

/// Replace the token with an atomic reference chip.
final class PickInsertReference extends PickOutcome {
  const PickInsertReference(this.reference);
  final ReferenceInsert reference;
}

/// Reference codec of a source that produces insert outcomes.
abstract interface class ReferenceCodec {
  /// The clipboard/persistence projection of one reference.
  String clipboardText(String ref);

  /// The model serialization of one reference.
  Future<String> serialize(String ref, AbortSignal signal);
}

/// A catalog-confirmed literal reference; it remains ordinary editable text.
class InputLexiconEntry {
  const InputLexiconEntry(this.token, this.ref, {this.appearance});
  final String token, ref;
  final String? appearance;
}

class InputLexeme {
  const InputLexeme(this.start, this.end, this.source, this.entry);
  final int start, end;
  final String source;
  final InputLexiconEntry entry;
}

/// One trigger source. Only [candidates] and [onPick] are required; the other
/// hooks are participation claims, as in dsh.
abstract class InputTriggerSource {
  TriggerChar get trigger;

  /// The menu group label; unique per trigger.
  String get name;

  /// Close source-owned option popups before its programmatic launcher opens.
  void prepareLaunch(String sessionId) {}

  /// Menu group order (lower first).
  int get order => 0;

  /// Whether the menu renders the source-title row.
  bool get showGroupTitle => true;

  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest req,
  );

  /// A breadcrumb above this source's group; null for none.
  List<InputTriggerCrumb>? header(String sessionId, HeaderRequest req) => null;

  PickOutcome? onPick(InputTriggerPick pick);

  /// Synchronous space-time adjudication over hot state.
  PickOutcome? matchSpace(String sessionId, String token) => null;

  /// Enter-time adjudication; may wait for the source's own warmup.
  Future<PickOutcome?> matchEnter(
    String sessionId,
    String line,
    AbortSignal signal,
    SubmitEnvelope envelope,
  ) async => null;

  /// Whether this source adjudicates Enter at all (dsh: implementing the hook).
  bool get adjudicatesEnter => false;

  /// Whether this source adjudicates Space.
  bool get adjudicatesSpace => false;

  /// Restore-time claim resolution; never acts.
  Future<CommandClaim?> matchClaim(
    String sessionId,
    String token,
    AbortSignal signal,
  ) async => null;

  bool get resolvesClaims => false;

  /// Scope-birth prewarm.
  void warm(String sessionId) {}

  /// Open a reference preview without touching the draft.
  bool openReference(String sessionId, String ref, String? appearance) => false;

  /// Settled catalog facts; never turn an unconfirmed word into a reference.
  List<InputLexiconEntry> lexicon(String sessionId) => const [];
  Stream<Object?>? get lexiconChanges => null;

  ReferenceCodec? get codec => null;
}

/// One menu group (one per source).
class MenuGroup {
  const MenuGroup({
    required this.source,
    required this.showGroupTitle,
    required this.ready,
    required this.items,
  });
  final String source;
  final bool showGroupTitle;
  final bool ready;
  final List<InputTriggerCandidate> items;

  MenuGroup copyWith({bool? ready, List<InputTriggerCandidate>? items}) =>
      MenuGroup(
        source: source,
        showGroupTitle: showGroupTitle,
        ready: ready ?? this.ready,
        items: items ?? this.items,
      );
}

/// Position of the highlight: a source and an index within its group.
class MenuHighlight {
  const MenuHighlight(this.source, this.index);
  final String source;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is MenuHighlight && other.source == source && other.index == index;

  @override
  int get hashCode => Object.hash(source, index);
}

/// The menu state the view renders.
class MenuState {
  const MenuState({
    this.open = false,
    this.hit,
    this.generation = 0,
    this.groups = const [],
    this.highlight,
  });
  final bool open;
  final TriggerHit? hit;

  /// Monotonic per-hit generation; stale source settlements are dropped.
  final int generation;
  final List<MenuGroup> groups;
  final MenuHighlight? highlight;
}

/// Menu reduction events.
sealed class MenuEvent {
  const MenuEvent();
}

final class MenuHit extends MenuEvent {
  const MenuHit(this.hit);
  final TriggerHit? hit;
}

final class MenuSourceSettled extends MenuEvent {
  const MenuSourceSettled(this.generation, this.source, this.items);
  final int generation;
  final String source;
  final List<InputTriggerCandidate> items;
}

final class MenuSourceFailed extends MenuEvent {
  const MenuSourceFailed(this.generation, this.source);
  final int generation;
  final String source;
}

final class MenuMove extends MenuEvent {
  const MenuMove(this.dir);
  final int dir;
}

final class MenuHover extends MenuEvent {
  const MenuHover(this.source, this.index);
  final String source;
  final int index;
}

final class MenuClose extends MenuEvent {
  const MenuClose();
}
