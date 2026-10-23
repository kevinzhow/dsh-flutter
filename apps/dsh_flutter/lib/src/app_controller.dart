import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_approval/dsh_feature_approval.dart';
import 'package:dsh_feature_attachment/dsh_feature_attachment.dart';
import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_feature_documentpreview/dsh_feature_documentpreview.dart';
import 'package:dsh_feature_files/dsh_feature_files.dart';
import 'package:dsh_feature_plan/dsh_feature_plan.dart';
import 'package:dsh_feature_sidebar_right/dsh_feature_sidebar_right.dart';
import 'package:dsh_feature_subagent/dsh_feature_subagent.dart';
import 'package:dsh_feature_tool/dsh_feature_tool.dart';
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show GlobalKey, NavigatorState;
import 'package:url_launcher/url_launcher.dart';

import 'backend.dart';
import 'connection_store.dart';
import 'launch_link.dart';
import 'platform/platform_services.dart';
import 'session_controller.dart';

/// Where the app is with its host.
enum ConnectionPhase {
  /// No host paired.
  disconnected,

  /// Pairing or reconnecting.
  connecting,

  /// A generation is live.
  connected,

  /// The host refused the saved token (typically: it restarted).
  needsPairing,
}

/// Why pairing failed, for the pairing screen.
enum PairingErrorKind { invalid, rejected, unreachable }

class PairingError {
  const PairingError(this.kind, [this.detail]);
  final PairingErrorKind kind;
  final String? detail;
}

/// Composition root state: backend, models, the slot registry with every
/// feature registered, locale and theme settings, and the session in view. No
/// feature imports another; they meet only here, through slots.
class AppController extends ChangeNotifier {
  AppController({
    required this.backend,
    ConnectionStore? store,
    this.scanner = const NoScanner(),
    DshLocale? locale,
    this.frameScheduler,
    this.platform = const PlatformServices(),
  }) : store = store ?? MemoryConnectionStore(),
       locale =
           locale ??
           DshLocale.fromTag(
             PlatformDispatcher.instance.locale.toLanguageTag(),
           ) {
    for (final slot in DshSlots.all) {
      slots.declare(slot);
    }
    approvals = ApprovalTracker(
      events: _events.stream,
      answer: (event, outcome) => backend.answer(event, outcome),
    );
    questions = QuestionTracker(
      events: _events.stream,
      answer: (event, outcome) => backend.answer(event, outcome),
    );
    registerConversationFeature(slots, i18n: () => i18n);
    registerChatFeature(slots, i18n: () => i18n);
    registerAttachmentFeature(slots, i18n: () => i18n);
    sidebar = registerSidebarRightFeature(
      slots,
      i18n: () => i18n,
      services: _SidebarBridge(this),
    );
    registerFilesFeature(slots, i18n: () => i18n);
    registerDocumentPreviewFeature(slots, i18n: () => i18n);
    registerToolFeature(
      slots,
      i18n: () => i18n,
      actions: ToolHostActions(
        openFile: (path, {line}) => _openFile(path, line: line),
        openUrl: (url) => unawaited(
          launchUrl(
            url,
            mode: LaunchMode.externalApplication,
          ).then((_) => true),
        ),
        openSubagent: (parent, childId) => _subagents.openById(parent, childId),
      ),
    );
    registerPlanFeature(slots, i18n: () => i18n);
    _subagents = registerSubagentFeature(
      slots,
      i18n: () => i18n,
      services: _SubagentBridge(this),
    );
    registerApprovalFeature(slots, tracker: approvals, i18n: () => i18n);
    registerUserQuestionsFeature(slots, tracker: questions, i18n: () => i18n);
    _stateSub = backend.states.listen(_onConnectionState);
    _approvalSub = approvals.pending.changes.listen((_) => notifyListeners());
    _questionSub = questions.pending.changes.listen((_) => notifyListeners());
  }

  final HostBackend backend;
  final ConnectionStore store;
  final LaunchScanner scanner;

  /// Pickers and file handling of the running platform.
  final PlatformServices platform;

  /// The right sidebar (file tree and previews) of every session.
  late final SidebarRightFeature sidebar;

  /// `animation-frame` publications of the conversation flush on this
  /// scheduler (null: a short timer; tests pass an immediate one).
  final FlushScheduler? frameScheduler;

  final SlotRegistry slots = SlotRegistry();

  /// The app's navigator: subagent transcripts push onto it.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  late final SubagentFeature _subagents;
  final StreamController<Object?> _listChanges =
      StreamController<Object?>.broadcast(sync: true);
  final Map<String, SessionController> _children = {};
  late final ApprovalTracker approvals;
  late final QuestionTracker questions;

  final StreamController<HostEvent> _events =
      StreamController<HostEvent>.broadcast(sync: true);
  StreamSubscription<ConnectionState>? _stateSub;
  StreamSubscription<HostEvent>? _hostEventSub;
  StreamSubscription<SessionListSnapshot>? _listSub;
  StreamSubscription<List<PendingApproval>>? _approvalSub;
  StreamSubscription<List<PendingQuestion>>? _questionSub;
  final Map<String, SessionController> _sessions = {};
  SessionTransport? _transport;

  ConnectionPhase phase = ConnectionPhase.disconnected;
  PairingError? pairingError;

  /// True while the live connection dropped and is retrying.
  bool reconnecting = false;

  SessionManager? manager;
  String? openSessionId;
  Object? createError;

  DshLocale locale;
  ThemePreference themePreference = ThemePreference.system;

  DshI18n get i18n => DshI18n(locale);
  ThemeSettings get themeSettings => ThemeSettings(preference: themePreference);

  /// The origin of the paired host (no token), for display.
  String? hostOrigin;

  SessionListSnapshot get sessionList =>
      manager?.list.value ?? const SessionListSnapshot();

  SessionController? get openSession =>
      openSessionId == null ? null : _sessions[openSessionId];

  // ---- pairing ---------------------------------------------------------

  /// Reconnect to the host saved by the last successful pairing, if any.
  Future<void> restore() async {
    final saved = await store.load();
    if (saved == null) return;
    await _connect(Uri.parse(saved.origin), saved.token, remember: false);
  }

  /// Pair from the pairing form ([text] is a launch link or host address).
  /// Returns whether the app is now connected; [pairingError] says why not.
  Future<bool> pair(String text, {String token = ''}) async {
    final LaunchLink link;
    try {
      link = LaunchLink.parse(text, token: token);
    } on FormatException {
      pairingError = const PairingError(PairingErrorKind.invalid);
      notifyListeners();
      return false;
    }
    return _connect(link.origin, link.token, remember: true);
  }

  Future<bool> _connect(
    Uri origin,
    String token, {
    required bool remember,
  }) async {
    pairingError = null;
    phase = ConnectionPhase.connecting;
    hostOrigin = origin.toString();
    notifyListeners();
    try {
      final transport = await backend.connect(origin, token);
      _adopt(transport);
      phase = ConnectionPhase.connected;
      reconnecting = false;
      if (remember) await store.save(SavedHost(origin.toString(), token));
      notifyListeners();
      unawaited(manager!.refreshList().catchError((Object _) {}));
      return true;
    } on ConnectException catch (e) {
      phase = e.failure == ConnectFailure.rejected
          ? ConnectionPhase.needsPairing
          : ConnectionPhase.disconnected;
      pairingError = PairingError(
        e.failure == ConnectFailure.rejected
            ? PairingErrorKind.rejected
            : PairingErrorKind.unreachable,
        e.detail,
      );
    } on Object catch (e) {
      phase = ConnectionPhase.disconnected;
      pairingError = PairingError(PairingErrorKind.unreachable, '$e');
    }
    notifyListeners();
    return false;
  }

  void _adopt(SessionTransport transport) {
    if (identical(_transport, transport) && manager != null) return;
    _transport = transport;
    unawaited(_hostEventSub?.cancel());
    _hostEventSub = transport.hostEvents.listen(_events.add);
    unawaited(_listSub?.cancel());
    final m = manager = SessionManager(transport)..start();
    _listSub = m.list.changes.listen((_) {
      _listChanges.add(null);
      notifyListeners();
    });
  }

  void _onConnectionState(ConnectionState s) {
    switch (s) {
      case ConnectionState.needsPairing:
        phase = ConnectionPhase.needsPairing;
        pairingError = const PairingError(PairingErrorKind.rejected);
        reconnecting = false;
      case ConnectionState.connected:
        reconnecting = false;
        if (phase == ConnectionPhase.needsPairing) {
          phase = ConnectionPhase.connected;
          pairingError = null;
        }
      case ConnectionState.pairing || ConnectionState.connecting:
        reconnecting = phase == ConnectionPhase.connected;
      case ConnectionState.idle || ConnectionState.stopped:
        break;
    }
    notifyListeners();
  }

  /// Forget the host and return to the pairing screen.
  Future<void> disconnect() async {
    await store.clear();
    await backend.disconnect();
    await _resetModels();
    phase = ConnectionPhase.disconnected;
    pairingError = null;
    hostOrigin = null;
    notifyListeners();
  }

  Future<void> _resetModels() async {
    openSessionId = null;
    for (final s in [..._sessions.values, ..._children.values]) {
      await s.dispose();
    }
    _sessions.clear();
    _children.clear();
    await _hostEventSub?.cancel();
    _hostEventSub = null;
    await _listSub?.cancel();
    _listSub = null;
    await manager?.dispose();
    manager = null;
    _transport = null;
  }

  // ---- sessions --------------------------------------------------------

  Future<void> refreshSessions() async {
    try {
      await manager?.refreshList();
    } on Object {
      // The list snapshot carries the error state.
    }
    notifyListeners();
  }

  /// Make [sessionId] the session in view and start following it.
  Future<SessionController?> open(String sessionId) async {
    final m = manager;
    if (m == null) return null;
    final controller = _sessions.putIfAbsent(
      sessionId,
      () => SessionController(
        m.get(sessionId),
        scheduler: frameScheduler,
        cwdReader: () => manager?.summaryOf(sessionId)?.cwd,
        hostHome: _transport?.generation?.hostHome ?? '',
        uploader: backend.uploader,
        files: backend.files,
        platform: platform,
      ),
    );
    openSessionId = sessionId;
    notifyListeners();
    unawaited(controller.open().then((_) => notifyListeners()));
    return controller;
  }

  void closeSession() {
    openSessionId = null;
    notifyListeners();
  }

  /// A tool card (or anything else) asked to show [path]: open it in the
  /// sidebar of the session in view.
  void _openFile(String path, {int? line}) {
    final session = openSession;
    if (session == null) return;
    sidebar.openFile(session.owner, path, line: line);
  }

  /// Files dropped on the window (desktop) go to the session in view.
  void dropFiles(List<LocalFile> files) => openSession?.dropFiles(files);

  /// `session/create` in the host's default directory, then open it.
  Future<void> createSession() async {
    final m = manager;
    if (m == null) return;
    createError = null;
    try {
      final s = await m.create();
      await open(s.sessionId);
    } on Object catch (e) {
      createError = e;
      notifyListeners();
    }
  }

  // ---- settings --------------------------------------------------------

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
    unawaited(_stateSub?.cancel());
    unawaited(_approvalSub?.cancel());
    unawaited(_questionSub?.cancel());
    unawaited(_resetModels());
    unawaited(approvals.dispose());
    unawaited(questions.dispose());
    unawaited(_events.close());
    unawaited(backend.dispose());
    super.dispose();
  }
}

/// The app's side of the subagent feature: child sessions as read-only
/// owners, list facts for activity and usage, and the navigator.
class _SubagentBridge implements SubagentServices {
  _SubagentBridge(this.app);

  final AppController app;

  @override
  GlobalKey<NavigatorState> get navigatorKey => app.navigatorKey;

  @override
  Stream<Object?> get changes => app._listChanges.stream;

  @override
  SessionOwner childOwner(SessionOwner parent, SubagentEntry entry) {
    final m = app.manager!;
    final controller = app._children.putIfAbsent(
      '${parent.sessionId}:${entry.id}',
      () => SessionController(
        m.getSubagent(
          parentSessionId: parent.sessionId,
          childSessionId: entry.id,
          mode: entry.mode,
        ),
        scheduler: app.frameScheduler,
        cwdReader: () => parent.cwd,
        hostHome: parent.hostHome,
        uploader: app.backend.uploader,
        files: app.backend.files,
        platform: app.platform,
        readOnly: true,
      ),
    );
    unawaited(controller.open());
    return controller.owner;
  }

  @override
  SubagentStatus statusOf(String childId) {
    final m = app.manager;
    if (m == null) return const SubagentStatus();
    final summary = m.summaryOf(childId);
    final values = {...?summary?.projections, ...m.projectionValues(childId)};
    final usage = values['tokenUsage'];
    int? tokens;
    if (usage is Map) {
      num n(String k) => usage[k] is num ? usage[k] as num : 0;
      tokens =
          (n('uncachedInputTokens') +
                  n('outputTokens') +
                  n('cacheReadTokens') +
                  n('cacheWriteTokens'))
              .round();
    }
    final running = summary?.running ?? false;
    final timing = values['subagentTiming'];
    num? duration;
    var completed = false;
    if (timing is Map) {
      final settled = timing['settledMs'] is num
          ? timing['settledMs'] as num
          : 0;
      final active = timing['active'];
      var extra = 0.0;
      if (active is Map && active['since'] is num) {
        final end = running
            ? DateTime.now().millisecondsSinceEpoch
            : (active['through'] is num
                  ? active['through'] as num
                  : active['since'] as num);
        extra = (end - (active['since'] as num))
            .clamp(0, double.infinity)
            .toDouble();
      }
      duration = settled + extra;
      completed = !running && timing['lastTurnCompleted'] == true;
    }
    return SubagentStatus(
      running: running,
      completed: completed,
      tokens: tokens,
      durationMs: duration,
    );
  }
}

/// The sidebar's seat in the app: it pushes its phone sheet onto the app
/// navigator.
class _SidebarBridge implements SidebarServices {
  _SidebarBridge(this.app);

  final AppController app;

  @override
  GlobalKey<NavigatorState> get navigatorKey => app.navigatorKey;
}
