import 'dart:async';

import 'package:dsh_client/generated_commands.dart'
    show
        CommandDescriptor,
        CommandResultError,
        CommandSubmitAttachment,
        CommandsRemote;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_ui/dsh_ui.dart' show rankByName;

import 'directory.dart';
import 'popup_controller.dart';
import 'presentation.dart';
import 'resolution.dart';

/// The command surface (dsh `CommandUiRuntime`): the `/` command source over
/// the session-keyed directory, the client-contribution registry and the
/// per-session popups. Candidate synthesis merges the Host catalog with
/// contributions by availability, gives first-party rows their localized face,
/// then position-filters; an empty query lists the Add and Commands sections in
/// usage order, a typed query ranks every row by name and label.
///
/// Every execute addresses the session's agent by its id: sessions are always
/// agent-backed.
class CommandSource extends InputTriggerSource {
  CommandSource({
    required this.registry,
    required this.triggers,
    required this.commands,
    required this.sessions,
    required DshI18n Function() i18n,
  }) : _i18n = i18n {
    directory = CommandDirectory(_fetch);
  }

  final CommandUiRegistry registry;
  final InputTriggerRegistry triggers;
  final CommandsRemote commands;
  final InputSessionPort sessions;
  final DshI18n Function() _i18n;
  late final CommandDirectory directory;
  final Map<String, PopupSelectController> _popups = {};

  @override
  TriggerChar get trigger => TriggerChar.slash;

  @override
  String get name => 'command';

  @override
  void prepareLaunch(String sessionId) => _popups[sessionId]?.dismiss();

  @override
  bool get adjudicatesEnter => true;
  @override
  bool get adjudicatesSpace => true;
  @override
  bool get resolvesClaims => true;

  Future<List<CommandDescriptor>> _fetch(String sessionId) async {
    if (sessions.isSubagentTranscript(sessionId)) return const [];
    // Waits for the session's initial history open; an unheld session rejects
    // without sending the RPC.
    await sessions.ensureOpen(sessionId, AbortSignal.never);
    return commands.list(sessionId);
  }

  /// The popup controller of one session (created on first use).
  PopupSelectController popupFor(String sessionId) =>
      _popups.putIfAbsent(sessionId, () {
        return PopupSelectController(
          consume: (segment) => _consume(sessionId, segment),
          focusComposer: () =>
              triggers.controllerOf(sessionId)?.port.requestFocus(),
        );
      });

  /// Close every popup open for [name] (its options went stale).
  void dismissCommand(String name) {
    for (final p in _popups.values) {
      if (p.openCommand == name) p.dismiss(focus: true);
    }
  }

  void releaseSession(String sessionId) => _popups.remove(sessionId)?.dispose();

  void dispose() {
    for (final p in _popups.values) {
      p.dispose();
    }
    _popups.clear();
  }

  bool _consume(String sessionId, TokenSegment segment) {
    final port = triggers.controllerOf(sessionId)?.port;
    if (port == null) return false;
    return switch (segment) {
      MenuSegment(:final span) => port.consumeSpan(span),
      EnterSegment(:final token) => port.consumeBareToken(token),
    };
  }

  void _notice(String sessionId, bool error, String text) =>
      triggers.controllerOf(sessionId)?.port.notify(error, text);

  @override
  void warm(String sessionId) => directory.warm(sessionId);

  @override
  Future<List<InputTriggerCandidate>> candidates(
    String sessionId,
    CandidateRequest req,
  ) async {
    final list = await directory.ensureReady(sessionId, req.signal);
    final i18n = _i18n();
    final rows = <InputTriggerCandidate>[];
    final seen = <String>{};
    for (final c in list) {
      seen.add(c.name);
      final face = builtinRowFace(c, i18n);
      rows.add(
        InputTriggerCandidate(
          name: c.name,
          label: face?.label,
          description: face?.description ?? c.description,
          icon: face?.icon,
          hint: c.input?.hint,
        ),
      );
    }
    for (final contribution in registry.contributions.values) {
      if (!contribution.available(sessionId)) continue;
      if (seen.contains(contribution.name)) {
        throw StateError(
          'contribution /${contribution.name} collides with a host command',
        );
      }
      rows.add(
        InputTriggerCandidate(
          name: contribution.name,
          label: contribution.label?.call(),
          description: contribution.description?.call(),
          icon: contribution.icon,
        ),
      );
    }
    final visible = [
      for (final r in rows)
        if (req.position == TriggerPosition.leading || r.hint == null) r,
    ];
    return req.query.isEmpty
        ? sectionRows(visible, i18n)
        : rankByName<InputTriggerCandidate>(
            visible,
            req.query,
            name: (c) => c.name,
            label: (c) => c.label,
          );
  }

  /// Decision table, menu column: contribution or decorated host command opens
  /// its popup or action; a host command with input claims; a bare host command
  /// executes detached.
  @override
  PickOutcome? onPick(InputTriggerPick pick) {
    final name = pick.candidate.name;
    final contribution = registry.contributions[name];
    if (contribution != null && contribution.available(pick.sessionId)) {
      _invoke(name, contribution.ui, pick.sessionId, MenuSegment(pick.span));
      return const PickHandled();
    }
    final desc = directory.resolve(pick.sessionId, name);
    if (desc == null) return null; // snapshot swapped between menu and pick
    final decoration = registry.decorations[name];
    if (decoration != null && decoration.available(pick.sessionId)) {
      _invoke(name, decoration.ui, pick.sessionId, MenuSegment(pick.span));
      return const PickHandled();
    }
    if (desc.input != null) {
      return PickClaim(
        _leadingClaim(desc, pick.sessionId, claimToken(desc, _i18n())),
      );
    }
    // A menu-pick execute consumes the trigger span before the detached run.
    _consumeVia(pick.sessionId, MenuSegment(pick.span));
    _runDetached(desc, pick.sessionId, '/$name');
    return const PickHandled();
  }

  /// Decision table, space column: a hot-catalog check; only host commands that
  /// take input claim.
  @override
  PickOutcome? matchSpace(String sessionId, String token) {
    final claim = _claimOf(sessionId, token);
    return claim == null ? null : PickClaim(claim);
  }

  /// Restore column: the space column's answer once the catalog is ready.
  @override
  Future<CommandClaim?> matchClaim(
    String sessionId,
    String token,
    AbortSignal signal,
  ) async {
    await directory.ensureReady(sessionId, signal);
    return _claimOf(sessionId, token);
  }

  CommandClaim? _claimOf(String sessionId, String token) {
    if (!token.startsWith('/')) return null;
    if (registry.contributions.containsKey(token.substring(1))) return null;
    final desc = directory.resolve(sessionId, token.substring(1));
    if (desc == null || desc.input == null) return null;
    return _leadingClaim(desc, sessionId, token.substring(1));
  }

  /// Decision table, enter column. Strong-waits the session's catalog (a warmup
  /// failure rejects: never a silent downgrade). Contributions and bare host
  /// commands act on the bare token only; commands with input are
  /// args-tolerant. A submission carrying attachments resolves only through a
  /// command that declares attachment acceptance; every other submitting route
  /// throws the refusal so the draft and attachments stay in place. An action
  /// submits nothing and runs regardless. A typed localized spelling reaches
  /// its descriptor: a line written `/计划` executes as `/plan`.
  @override
  Future<PickOutcome?> matchEnter(
    String sessionId,
    String line,
    AbortSignal signal,
    SubmitEnvelope envelope,
  ) async {
    final trimmed = line.trim();
    if (!trimmed.startsWith('/')) return null;
    final ws = trimmed.indexOf(RegExp(r'\s'));
    final token = ws == -1 ? trimmed : trimmed.substring(0, ws);
    final bare = ws == -1;
    final typedName = token.substring(1);
    if (typedName.isEmpty) return null;
    Never refuseAttachments() => throw SubmitRefused(
      _i18n().t(
        'command',
        'notice.attachmentsUnsupported',
        params: {'command': typedName},
      ),
    );
    final contribution = registry.contributions[typedName];
    if (contribution != null && contribution.available(sessionId)) {
      if (!bare) return null;
      if (envelope.attachments > 0 && contribution.ui is! ActionSpec) {
        refuseAttachments();
      }
      _invoke(typedName, contribution.ui, sessionId, EnterSegment(token));
      return const PickHandled();
    }
    await directory.ensureReady(sessionId, signal);
    final desc = directory.resolve(sessionId, typedName);
    if (desc == null) return null;
    final name = desc.name;
    final canonical = '/$name${trimmed.substring(token.length)}';
    if (bare) {
      final decoration = registry.decorations[name];
      if (decoration != null && decoration.available(sessionId)) {
        if (envelope.attachments > 0 && decoration.ui is! ActionSpec) {
          refuseAttachments();
        }
        _invoke(name, decoration.ui, sessionId, EnterSegment(token));
        return const PickHandled();
      }
    }
    if (desc.input != null) {
      if (envelope.attachments > 0 && desc.input!.attachments != true) {
        refuseAttachments();
      }
      return PickClaim(_leadingClaim(desc, sessionId, token.substring(1)));
    }
    if (!bare) return null;
    if (envelope.attachments > 0) refuseAttachments();
    _consumeVia(sessionId, EnterSegment(token));
    _runDetached(desc, sessionId, canonical);
    return const PickHandled();
  }

  /// Invoke one contribution or decoration (menu pick or bare Enter): open the
  /// session's popup, or consume the token and run the action.
  void _invoke(
    String name,
    CommandUiSpec ui,
    String sessionId,
    TokenSegment segment,
  ) {
    switch (ui) {
      case ActionSpec(:final run):
        _consumeVia(sessionId, segment);
        run(sessionId);
      case PopupSelectSpec():
        popupFor(sessionId).open(name, ui, sessionId, segment);
    }
  }

  /// The command claim. The composer keeps the claimed token in the draft and
  /// reads the arguments after it, so the token is the spelling the draft will
  /// carry (the locale's token for a menu pick, the typed spelling for Space and
  /// Enter); the submit always sends the catalog name.
  CommandClaim _leadingClaim(
    CommandDescriptor desc,
    String sessionId,
    String shown,
  ) {
    final line = '/${desc.name} ';
    return CommandClaim(
      name: desc.name,
      token: '/$shown ',
      hint: desc.input?.hint,
      attachments: desc.input?.attachments == true,
      submit: (args, attachments) =>
          _execute(sessionId, line + args, attachments),
    );
  }

  /// The `commands/execute` transaction: pure admission semantics. An unmatched
  /// line reports an error outcome; an admitted command reports plain success
  /// whatever its handler answered, because the Host durably logged the
  /// lifecycle and the outcome renders as a flow node. With attachments, a
  /// handler error keeps the draft for correction. A refused call throws.
  Future<SubmitOutcome> _execute(
    String sessionId,
    String line,
    List<SubmitAttachment> attachments,
  ) async {
    final execution = await commands.execute(sessionId, line, [
      for (final a in attachments) CommandSubmitAttachment.fromJson(a),
    ]);
    if (execution == null) {
      return SubmitOutcome.error('unknown or malformed command: $line');
    }
    final result = execution.result;
    if (attachments.isNotEmpty && result is CommandResultError) {
      return SubmitOutcome.error(result.text);
    }
    return const SubmitOutcome.success();
  }

  /// Fire-and-forget execute for the handled paths. Only an admission failure
  /// (which never entered a handler and logged nothing) falls back to the
  /// composer notice.
  void _runDetached(CommandDescriptor desc, String sessionId, String line) {
    unawaited(
      _execute(sessionId, line, const []).then((outcome) {
        if (outcome.isError) {
          _notice(sessionId, true, outcome.text ?? '/${desc.name} failed');
        }
      }, onError: (Object error) => _notice(sessionId, true, '$error')),
    );
  }

  void _consumeVia(String sessionId, TokenSegment segment) =>
      _consume(sessionId, segment);

  /// Host events that make the catalog stale.
  void onCommandsChanged() => directory.invalidateAll();
  void onPresetSelected(String sessionId) => directory.resetSession(sessionId);
  void onConnectionReset() => directory.resetConnected();
}
