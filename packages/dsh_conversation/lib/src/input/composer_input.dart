/// The composer's input model (dsh `ui-conversation` `SessionInput`: the draft
/// document, the submit machine and the pick application verbs), without the
/// editor widget.
///
/// The draft is kept in dsh's *detect projection*: every atomic chip (a
/// reference chip, or the command chip that opens a claimed draft) is one
/// U+FFFC character, so a text field that draws those characters as inline
/// chips needs no offset mapping. The *clipboard projection* expands each chip
/// to its clipboard text (`@src/a.dart`, `/goal`); that is what a send
/// serializes and what a persisted draft holds.
library;

import 'package:dsh_models/dsh_models.dart' show Observable;

import 'trigger_controller.dart';
import 'trigger_types.dart';

/// The chip placeholder of the detect projection (object replacement
/// character). The only legitimate source of this character in a draft.
const String atomicChar = '￼';

/// One reference chip of the draft (dsh `Occurrence`, without its editor id).
class DraftChip {
  const DraftChip({
    required this.source,
    required this.ref,
    required this.label,
    required this.clipboardText,
    this.appearance,
    this.invalid = false,
  });

  /// The owning source's name (the serializer routing key).
  final String source;

  /// The owner-scoped reference id.
  final String ref;

  /// The inline label.
  final String label;

  /// `session`, `file`, `folder` or null.
  final String? appearance;

  /// The clipboard and persistence projection.
  final String clipboardText;
  final bool invalid;

  factory DraftChip.of(ReferenceInsert r) => DraftChip(
    source: r.source,
    ref: r.ref,
    label: r.label,
    appearance: r.appearance,
    clipboardText: r.clipboardText,
  );
}

/// The submit-plane phase.
enum InputPhase { plain, claimed, adjudicating, submitting }

/// An immutable view of the draft.
class InputSnapshot {
  const InputSnapshot({
    required this.text,
    required this.chips,
    required this.claim,
    required this.phase,
    required this.rev,
    required this.selStart,
    required this.selEnd,
  });

  /// The detect projection (chips are [atomicChar]).
  final String text;

  /// The reference chips, in order of their placeholders. The command chip is
  /// [claim], not part of this list.
  final List<DraftChip> chips;
  final CommandClaim? claim;
  final InputPhase phase;

  /// The draft revision: every edit (not a selection move) bumps it.
  final int rev;
  final int selStart;
  final int selEnd;
}

/// A transient message for the composer (a detached command's admission
/// failure, an attachment refusal).
class InputNotice {
  const InputNotice(this.error, this.text, this.seq);
  final bool error;
  final String text;
  final int seq;
}

/// How a [ComposerInput.submit] ended.
sealed class SubmitResult {
  const SubmitResult();
}

/// Nothing to send.
final class SubmitNothing extends SubmitResult {
  const SubmitNothing();
}

/// The message went through the default sink.
final class SubmitSent extends SubmitResult {
  const SubmitSent(this.text);

  /// The serialized text that was sent.
  final String text;
}

/// A claimed command ran; [outcome] is the host's answer.
final class SubmitCommandRan extends SubmitResult {
  const SubmitCommandRan(this.outcome);
  final SubmitOutcome outcome;
}

/// A source acted on the line itself (a popup opened, a detached run).
final class SubmitHandled extends SubmitResult {
  const SubmitHandled();
}

/// A submit refused before anything was sent (the draft stays).
class SubmitRefused implements Exception {
  const SubmitRefused(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The composer model of one session.
class ComposerInput implements TriggerEditorPort {
  ComposerInput({required this.sessionId});

  final String sessionId;

  /// The live draft.
  final Observable<InputSnapshot> state = Observable(
    const InputSnapshot(
      text: '',
      chips: [],
      claim: null,
      phase: InputPhase.plain,
      rev: 0,
      selStart: 0,
      selEnd: 0,
    ),
  );

  /// The latest transient message.
  final Observable<InputNotice?> notice = Observable(null);

  InputTriggerController? _triggers;
  InputTriggerRegistry? _registry;
  int _noticeSeq = 0;
  AbortController? _attempt;
  bool _disposed = false;

  InputSnapshot get snapshot => state.value;

  /// The trigger pipeline of this session once [bind] attached a registry.
  InputTriggerController? get triggers => _triggers;

  /// Attach the app's trigger registry: the pipeline of this session starts
  /// (and warms its sources). Binding again with the same registry is a no-op.
  void bind(InputTriggerRegistry registry) {
    if (identical(_registry, registry)) return;
    _registry?.release(sessionId);
    _registry = registry;
    _triggers = registry.sessionOf(sessionId, this);
    _track();
  }

  /// Release the pipeline and abort any submit in flight.
  void dispose() {
    _disposed = true;
    _attempt?.abort();
    _registry?.release(sessionId);
    _registry = null;
    _triggers = null;
  }

  // ---- projections ------------------------------------------------------

  /// The clipboard projection: chips expand to their clipboard text.
  String get clipboardText => _clipboardOf(snapshot);

  static String _clipboardOf(InputSnapshot s) {
    final out = StringBuffer();
    var chip = 0;
    for (var i = 0; i < s.text.length; i++) {
      final ch = s.text[i];
      if (ch != atomicChar) {
        out.write(ch);
      } else if (i == 0 && s.claim != null) {
        out.write(s.claim!.token.trimRight());
      } else if (chip < s.chips.length) {
        out.write(s.chips[chip++].clipboardText);
      }
    }
    return out.toString();
  }

  TriggerTier get _tier => switch (snapshot.phase) {
    InputPhase.plain => TriggerTier.plain,
    InputPhase.claimed => TriggerTier.claimed,
    InputPhase.adjudicating || InputPhase.submitting => TriggerTier.frozen,
  };

  bool get _editable =>
      snapshot.phase == InputPhase.plain ||
      snapshot.phase == InputPhase.claimed;

  // ---- user edits -------------------------------------------------------

  /// A user edit reported by the text field: [text] is the new detect
  /// projection and [selStart]..[selEnd] the new selection. Chips whose
  /// placeholder left the text leave the draft; a command chip that left
  /// releases the claim. Placeholders the user typed or pasted are stripped.
  /// Returns the text the model holds afterwards (the field adopts it when it
  /// differs).
  String textChanged(String text, int selStart, int selEnd) {
    final s = snapshot;
    if (!_editable) return s.text;
    if (text == s.text) {
      _selection(selStart, selEnd);
      return s.text;
    }
    final (prefix, suffix) = _editRegion(s.text, text, selStart, selEnd);
    final removed = s.text.substring(prefix, s.text.length - suffix);
    // Space adjudication (dsh `KEY_SPACE`): a lone space typed right after a
    // completed leading `/command` claims it before the space lands. The chip
    // insertion carries its own separator, so the typed space is consumed.
    if (removed.isEmpty &&
        text.substring(prefix, text.length - suffix) == ' ' &&
        selStart == selEnd &&
        selEnd == prefix + 1 &&
        s.selStart == s.selEnd &&
        s.selEnd == prefix &&
        (_triggers?.onSpace() ?? false)) {
      return snapshot.text;
    }
    var inserted = text.substring(prefix, text.length - suffix);
    // Chips that the edit removed: the placeholders inside the removed region.
    var claim = s.claim;
    final chips = [...s.chips];
    var before = 0; // chips before the region
    for (var i = 0; i < prefix; i++) {
      if (s.text[i] == atomicChar && !(i == 0 && s.claim != null)) before++;
    }
    for (var i = 0; i < removed.length; i++) {
      if (removed[i] != atomicChar) continue;
      if (prefix + i == 0 && s.claim != null) {
        claim = null;
      } else if (before < chips.length) {
        // The next chip slides into `before`.
        chips.removeAt(before);
      }
    }
    var hadStray = false;
    if (inserted.contains(atomicChar)) {
      hadStray = true;
      inserted = inserted.replaceAll(atomicChar, '');
    }
    final next =
        s.text.substring(0, prefix) +
        inserted +
        s.text.substring(s.text.length - suffix);
    var start = selStart;
    var end = selEnd;
    if (hadStray) {
      start = (prefix + inserted.length).clamp(0, next.length);
      end = start;
    }
    _commit(
      next,
      chips,
      claim,
      start.clamp(0, next.length),
      end.clamp(0, next.length),
    );
    return next;
  }

  /// The edited region as (common prefix, common suffix) lengths. The caret
  /// disambiguates repeated characters (two adjacent chips): a deletion leaves
  /// the caret at the start of what it removed, typing leaves it at the end of
  /// what it inserted.
  static (int, int) _editRegion(
    String old,
    String next,
    int selStart,
    int selEnd,
  ) {
    final limit = old.length < next.length ? old.length : next.length;
    var prefix = 0;
    while (prefix < limit && old[prefix] == next[prefix]) {
      prefix++;
    }
    if (selStart == selEnd) {
      final s = next.length - selEnd;
      final p = prefix < selEnd ? prefix : selEnd;
      if (s >= 0 &&
          p + s <= old.length &&
          p + s <= next.length &&
          old.startsWith(next.substring(0, p)) &&
          old.endsWith(next.substring(next.length - s))) {
        return (p, s);
      }
    }
    var suffix = 0;
    while (suffix < limit - prefix &&
        old[old.length - 1 - suffix] == next[next.length - 1 - suffix]) {
      suffix++;
    }
    return (prefix, suffix);
  }

  void _selection(int start, int end) {
    final s = snapshot;
    if (s.selStart == start && s.selEnd == end) return;
    state.set(_with(s, selStart: start, selEnd: end));
    _track();
  }

  InputSnapshot _with(
    InputSnapshot s, {
    String? text,
    List<DraftChip>? chips,
    Object? claim = _keep,
    InputPhase? phase,
    int? rev,
    int? selStart,
    int? selEnd,
  }) => InputSnapshot(
    text: text ?? s.text,
    chips: chips ?? s.chips,
    claim: identical(claim, _keep) ? s.claim : claim as CommandClaim?,
    phase: phase ?? s.phase,
    rev: rev ?? s.rev,
    selStart: selStart ?? s.selStart,
    selEnd: selEnd ?? s.selEnd,
  );

  static const Object _keep = Object();

  void _commit(
    String text,
    List<DraftChip> chips,
    CommandClaim? claim,
    int selStart,
    int selEnd,
  ) {
    final s = snapshot;
    final phase = !_editable
        ? s.phase
        : claim == null
        ? InputPhase.plain
        : InputPhase.claimed;
    state.set(
      InputSnapshot(
        text: text,
        chips: chips,
        claim: claim,
        phase: phase,
        rev: s.rev + 1,
        selStart: selStart,
        selEnd: selEnd,
      ),
    );
    _track();
  }

  void _track() {
    final triggers = _triggers;
    if (triggers == null || _disposed) return;
    final s = snapshot;
    if (s.selStart != s.selEnd) {
      triggers.dismiss();
      return;
    }
    triggers.track(s.text, s.selEnd, _tier, s.rev);
  }

  // ---- programmatic edits (the pick application verbs) ------------------

  /// Replace the whole draft with plain text (a persisted or programmatic
  /// write); the caret lands at the end.
  void setPlainText(String text) {
    final clean = text.replaceAll(atomicChar, '');
    if (clean == snapshot.text &&
        snapshot.chips.isEmpty &&
        snapshot.claim == null) {
      return;
    }
    _commit(clean, const [], null, clean.length, clean.length);
  }

  /// Clear the draft (a committed send).
  void clear() => _commit('', const [], null, 0, 0);

  /// Insert pasted text over the selection (placeholders stripped).
  void paste(String text) {
    final clean = text.replaceAll(atomicChar, '');
    if (clean.isEmpty || !_editable) return;
    final s = snapshot;
    final a = s.selStart <= s.selEnd ? s.selStart : s.selEnd;
    final b = s.selStart <= s.selEnd ? s.selEnd : s.selStart;
    _replace(TokenSpan(a, b, s.rev), clean, force: true);
  }

  /// The live selection (a collapsed span at the end when none).
  TokenSpan selectionSpan() {
    final s = snapshot;
    final a = s.selStart <= s.selEnd ? s.selStart : s.selEnd;
    final b = s.selStart <= s.selEnd ? s.selEnd : s.selStart;
    return TokenSpan(a, b, s.rev);
  }

  bool _spanOk(TokenSpan span) =>
      span.draftRev == snapshot.rev &&
      span.start >= 0 &&
      span.start <= span.end &&
      span.end <= snapshot.text.length;

  /// Replace [span] with [text] keeping every chip outside it.
  bool _replace(TokenSpan span, String text, {bool force = false}) {
    if (!force && !_spanOk(span)) return false;
    final s = snapshot;
    final chips = <DraftChip>[];
    var chip = 0;
    for (var i = 0; i < s.text.length; i++) {
      if (s.text[i] != atomicChar || (i == 0 && s.claim != null)) continue;
      final inside = i >= span.start && i < span.end;
      if (!inside) chips.add(s.chips[chip]);
      chip++;
    }
    // A replaced range that held the command chip releases the claim.
    final claim = s.claim != null && span.start == 0 && span.end > 0
        ? null
        : s.claim;
    final next =
        s.text.substring(0, span.start) + text + s.text.substring(span.end);
    final caret = span.start + text.length;
    _commit(next, chips, claim, caret, caret);
    return true;
  }

  int _chipsBefore(String text, int index, CommandClaim? claim) {
    var n = 0;
    for (var i = 0; i < index; i++) {
      if (text[i] == atomicChar && !(i == 0 && claim != null)) n++;
    }
    return n;
  }

  @override
  bool beginCommand(CommandClaim claim, TokenSpan span) {
    if (!_editable || !_spanOk(span)) return false;
    final s = snapshot;
    // Leading-trigger contract: only whitespace may precede the span.
    if (s.text.substring(0, span.start).trim().isNotEmpty) return false;
    final separator = claim.token.substring(claim.token.trimRight().length);
    final tail = span.end < s.text.length ? s.text[span.end] : '';
    final add = separator.isEmpty || tail == separator[0] ? '' : separator;
    // The chips the range [0, end) held leave with it.
    final kept = <DraftChip>[];
    var chip = 0;
    for (var i = 0; i < s.text.length; i++) {
      if (s.text[i] != atomicChar || (i == 0 && s.claim != null)) continue;
      if (i >= span.end) kept.add(s.chips[chip]);
      chip++;
    }
    final next = '$atomicChar$add${s.text.substring(span.end)}';
    final caret = 1 + add.length;
    _commit(next, kept, claim, caret, caret);
    return true;
  }

  @override
  bool insertReference(ReferenceInsert reference, TokenSpan span) {
    if (!_editable || !_spanOk(span)) return false;
    final s = snapshot;
    final tail = span.end < s.text.length ? s.text[span.end] : '';
    final add = tail == ' ' ? '' : ' ';
    final chips = <DraftChip>[];
    var chip = 0;
    var inserted = false;
    final before = _chipsBefore(s.text, span.start, s.claim);
    for (var i = 0; i < s.text.length; i++) {
      if (s.text[i] != atomicChar || (i == 0 && s.claim != null)) continue;
      final inside = i >= span.start && i < span.end;
      if (!inside) {
        if (!inserted && chips.length == before) {
          chips.add(DraftChip.of(reference));
          inserted = true;
        }
        chips.add(s.chips[chip]);
      }
      chip++;
    }
    if (!inserted) chips.add(DraftChip.of(reference));
    final next =
        '${s.text.substring(0, span.start)}$atomicChar$add${s.text.substring(span.end)}';
    final caret = span.start + 1 + add.length;
    _commit(next, chips, s.claim, caret, caret);
    return true;
  }

  @override
  bool insertText(String text, TokenSpan span, {bool keepCompleting = false}) =>
      _replace(span, text.replaceAll(atomicChar, ''));

  @override
  bool consumeSpan(TokenSpan span) {
    if (span.draftRev != snapshot.rev || span.start == span.end) return false;
    return _replace(span, '');
  }

  @override
  bool consumeBareToken(String token) {
    if (token.isEmpty || clipboardText.trim() != token) return false;
    clear();
    return true;
  }

  /// Insert reference chips after the selection without deleting it (a picked
  /// file); a space precedes the first when the text before does not end in
  /// whitespace.
  bool addReferences(List<ReferenceInsert> references) {
    if (references.isEmpty) return true;
    if (!_editable) return false;
    var s = snapshot;
    final at = s.selEnd;
    final before = s.text.substring(0, at);
    final lead = before.isNotEmpty && !RegExp(r'\s$').hasMatch(before);
    var span = TokenSpan(at, at, s.rev);
    if (lead) {
      _replace(span, ' ');
      s = snapshot;
      span = TokenSpan(s.selEnd, s.selEnd, s.rev);
    }
    for (final r in references) {
      s = snapshot;
      if (!insertReference(r, TokenSpan(s.selEnd, s.selEnd, s.rev))) {
        return false;
      }
    }
    return true;
  }

  ({bool Function() available, void Function() open})? _filePicker;

  /// Bind the mounted composer's file action (the `File` command): whether it
  /// accepts files now, and the opener. Returns the unbind.
  void Function() bindFilePicker(
    bool Function() available,
    void Function() open,
  ) {
    final binding = (available: available, open: open);
    _filePicker = binding;
    return () {
      if (identical(_filePicker, binding)) _filePicker = null;
    };
  }

  /// Whether a mounted composer accepts files now.
  bool get canPickFiles => _filePicker?.available() ?? false;

  /// Open the mounted composer's file picker; false when none accepts.
  bool pickFiles() {
    final picker = _filePicker;
    if (picker == null || !picker.available()) return false;
    picker.open();
    return true;
  }

  void Function()? _focus;

  /// Bind the mounted composer's focus action. Returns the unbind.
  void Function() bindFocus(void Function() focus) {
    _focus = focus;
    return () {
      if (identical(_focus, focus)) _focus = null;
    };
  }

  @override
  void requestFocus() => _focus?.call();

  /// Show a transient message.
  @override
  void notify(bool error, String text) {
    _noticeSeq++;
    notice.set(InputNotice(error, text, _noticeSeq));
  }

  // ---- submit -----------------------------------------------------------

  /// Submit the draft (dsh Enter and the Send button).
  ///
  /// [send] is the default sink and receives the serialized, trimmed text;
  /// [attachments] says how many composer attachments accompany it. A draft
  /// opening with `/` is adjudicated by the command source first; a claimed
  /// draft runs its command with the text after the token. Failures throw;
  /// the draft stays until the host accepted.
  Future<SubmitResult> submit({
    required Future<void> Function(String text) send,
    int attachments = 0,
    List<SubmitAttachment> Function()? commandAttachments,
    String Function(String token)? unsupportedAttachments,
  }) async {
    if (!_editable) return const SubmitNothing();
    final draft = clipboardText;
    final claim = snapshot.claim;
    final controller = AbortController();
    _attempt?.abort();
    _attempt = controller;
    final signal = controller.signal;
    if (claim != null) {
      return _runClaim(
        claim,
        _argsAfter(draft, claim.token),
        attachments,
        commandAttachments,
        unsupportedAttachments,
        signal,
      );
    }
    final trimmed = draft.trim();
    if (trimmed.isEmpty && attachments == 0) return const SubmitNothing();
    final triggers = _triggers;
    if (trimmed.startsWith('/') && triggers != null) {
      _setPhase(InputPhase.adjudicating);
      final PickOutcome? outcome;
      try {
        outcome = await triggers.adjudicate(
          draft,
          signal,
          SubmitEnvelope(attachments: attachments),
        );
      } finally {
        if (snapshot.phase == InputPhase.adjudicating) {
          _setPhase(InputPhase.plain);
        }
      }
      if (_disposed || signal.aborted) return const SubmitNothing();
      switch (outcome) {
        case PickClaim(:final claim):
          return _runClaim(
            claim,
            _argsAfter(draft, claim.token),
            attachments,
            commandAttachments,
            unsupportedAttachments,
            signal,
          );
        case PickHandled():
          return const SubmitHandled();
        case PickInsertText() || PickInsertReference():
          return const SubmitHandled();
        case null:
          break;
      }
    }
    return _sendDefault(draft, send, signal);
  }

  Future<SubmitResult> _sendDefault(
    String draft,
    Future<void> Function(String text) send,
    AbortSignal signal,
  ) async {
    final s = snapshot;
    var text = draft;
    if (s.chips.isNotEmpty) {
      final triggers = _triggers;
      if (triggers == null) {
        throw const SubmitRefused(
          'no serializer for the references of this draft',
        );
      }
      // Splice each chip's model form over its clipboard range.
      final out = StringBuffer();
      var chip = 0;
      for (var i = 0; i < s.text.length; i++) {
        final ch = s.text[i];
        if (ch != atomicChar) {
          out.write(ch);
        } else if (i == 0 && s.claim != null) {
          out.write(s.claim!.token.trimRight());
        } else {
          final c = s.chips[chip++];
          out.write(await triggers.serializeReference(c.source, c.ref, signal));
        }
      }
      text = out.toString();
      if (signal.aborted || _disposed) return const SubmitNothing();
    }
    final sent = text.trim();
    await send(sent);
    if (!_disposed) clear();
    return SubmitSent(sent);
  }

  Future<SubmitResult> _runClaim(
    CommandClaim claim,
    String args,
    int attachments,
    List<SubmitAttachment> Function()? commandAttachments,
    String Function(String token)? unsupported,
    AbortSignal signal,
  ) async {
    if (attachments > 0 && !claim.attachments) {
      throw SubmitRefused(
        unsupported?.call(claim.token.trim()) ??
            '${claim.token.trim()} does not accept attachments',
      );
    }
    _setPhase(InputPhase.submitting);
    final SubmitOutcome outcome;
    try {
      outcome = await claim.submit(
        args,
        attachments > 0 ? (commandAttachments?.call() ?? const []) : const [],
      );
    } finally {
      if (!_disposed && snapshot.phase == InputPhase.submitting) {
        _setPhase(
          snapshot.claim == null ? InputPhase.plain : InputPhase.claimed,
        );
      }
    }
    if (_disposed || signal.aborted) return SubmitCommandRan(outcome);
    if (outcome.isError) {
      throw SubmitRefused(outcome.text ?? 'command failed');
    }
    clear();
    if (outcome.text != null) notify(false, outcome.text!);
    return SubmitCommandRan(outcome);
  }

  void _setPhase(InputPhase phase) {
    final s = snapshot;
    if (s.phase == phase) return;
    state.set(_with(s, phase: phase));
    final triggers = _triggers;
    if (triggers != null &&
        (phase == InputPhase.adjudicating || phase == InputPhase.submitting)) {
      triggers.track(s.text, 0, TriggerTier.frozen, s.rev);
    }
  }

  /// The text after a claimed command token (dsh `argsAfter`).
  static String argsOf(String draft, String token) => _argsAfter(draft, token);

  static String _argsAfter(String draft, String token) {
    final s = draft.trimLeft();
    if (s.startsWith(token)) return s.substring(token.length);
    final base = token.trimRight();
    if (s.startsWith(base)) {
      final rest = s.substring(base.length);
      return RegExp(r'^\s').hasMatch(rest) ? rest.substring(1) : rest;
    }
    return '';
  }
}
