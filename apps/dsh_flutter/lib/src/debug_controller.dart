import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_approval/dsh_feature_approval.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/foundation.dart';

import 'backend.dart';

/// Composition root state of the phase-0 debug app: wires backend, models,
/// conversation registry, the slot registry with the approval feature, locale
/// and theme settings. No feature imports another; they meet only here.
class DebugController extends ChangeNotifier {
  DebugController(this.backend) {
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
    tracker = ApprovalTracker(
      events: _events.stream,
      answer: (event, outcome) => backend.answer(event, outcome),
    );
    registerApprovalFeature(slots, tracker: tracker, i18n: () => i18n);
    _approvalSub = tracker.pending.changes.listen((_) => notifyListeners());
    _statusSub = backend.status.listen((s) {
      status = s;
      notifyListeners();
    });
  }

  final DebugBackend backend;
  final SlotRegistry slots = SlotRegistry();
  final ConversationRegistry conversation = defaultConversationRegistry();
  late final ApprovalTracker tracker;

  final StreamController<HostEvent> _events =
      StreamController<HostEvent>.broadcast();
  StreamSubscription<String>? _statusSub;
  StreamSubscription<List<PendingApproval>>? _approvalSub;
  StreamSubscription<HostEvent>? _eventSub;
  StreamSubscription<SessionListSnapshot>? _listSub;
  StreamSubscription<SessionSnapshot>? _sessionSub;
  StreamSubscription<EventWindow>? _windowSub;

  String status = 'idle';
  String? error;
  SessionManager? manager;
  Session? session;
  DshLocale locale = DshLocale.en;
  ThemePreference themePreference = ThemePreference.system;

  DshI18n get i18n => DshI18n(locale);
  ThemeSettings get themeSettings => ThemeSettings(preference: themePreference);

  ConversationSnapshot get chat => session == null
      ? const ConversationSnapshot(chatTarget, [])
      : conversation.snapshot(chatTarget, session!.eventSource.window);

  /// Pair, then show the list. Calling again with a new token re-pairs.
  Future<void> connect(String url, String token) async {
    error = null;
    status = 'connecting';
    notifyListeners();
    try {
      final transport = await backend.connect(url, token);
      if (manager == null) {
        manager = SessionManager(transport)..start();
        await _eventSub?.cancel();
        _eventSub = transport.hostEvents.listen(_events.add);
        _listSub = manager!.list.changes.listen((_) => notifyListeners());
      }
      await manager!.refreshList();
    } on Object catch (e) {
      error = e is RemoteException ? '${e.code}: ${e.message}' : '$e';
    }
    notifyListeners();
  }

  Future<void> createSession(String cwd) async {
    final m = manager;
    if (m == null) return;
    try {
      final s = await m.create(cwd: cwd.isEmpty ? null : cwd);
      await openSession(s.sessionId);
    } on Object catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  Future<void> openSession(String sessionId) async {
    final m = manager;
    if (m == null) return;
    await _sessionSub?.cancel();
    await _windowSub?.cancel();
    final s = m.get(sessionId);
    session = s;
    _sessionSub = s.snapshot.changes.listen((_) => notifyListeners());
    _windowSub = s.eventSource.changes.listen((_) => notifyListeners());
    notifyListeners();
    await s.open();
    notifyListeners();
  }

  Future<void> send(String text) async {
    final s = session;
    if (s == null || text.trim().isEmpty) return;
    try {
      await s.prompt(text.trim());
    } on Object catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  Future<void> cancel() async {
    try {
      await session?.cancel();
    } on Object catch (e) {
      error = '$e';
      notifyListeners();
    }
  }

  void setLocale(DshLocale l) {
    locale = l;
    notifyListeners();
  }

  void setThemePreference(ThemePreference p) {
    themePreference = p;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_statusSub?.cancel());
    unawaited(_approvalSub?.cancel());
    unawaited(_eventSub?.cancel());
    unawaited(_listSub?.cancel());
    unawaited(_sessionSub?.cancel());
    unawaited(_windowSub?.cancel());
    unawaited(manager?.dispose());
    unawaited(tracker.dispose());
    unawaited(_events.close());
    unawaited(backend.dispose());
    super.dispose();
  }
}
