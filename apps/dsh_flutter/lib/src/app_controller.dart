import 'dart:async';
import 'dart:io' show InternetAddress, SocketException;

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_workspace.dart' show WorkspaceView;
import 'package:dsh_client/generated_user_questions.dart'
    show AskUserQuestionAnswer, AskUserQuestionAnswerItem, UserQuestionsRemote;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_feature_approval/dsh_feature_approval.dart';
import 'package:dsh_feature_attachment/dsh_feature_attachment.dart';
import 'package:dsh_feature_chat/dsh_feature_chat.dart';
import 'package:dsh_feature_conversation/dsh_feature_conversation.dart';
import 'package:dsh_feature_documentpreview/dsh_feature_documentpreview.dart';
import 'package:dsh_feature_commands/dsh_feature_commands.dart';
import 'package:dsh_feature_directory_picker_browse/dsh_feature_directory_picker_browse.dart';
import 'package:dsh_feature_files/dsh_feature_files.dart';
import 'package:dsh_feature_input_trigger/dsh_feature_input_trigger.dart';
import 'package:dsh_feature_model_selection/dsh_feature_model_selection.dart';
import 'package:dsh_feature_permission_presets/dsh_feature_permission_presets.dart';
import 'package:dsh_feature_plan/dsh_feature_plan.dart';
import 'package:dsh_feature_reference/dsh_feature_reference.dart';
import 'package:dsh_feature_settings/dsh_feature_settings.dart';
import 'package:dsh_feature_sidebar_right/dsh_feature_sidebar_right.dart';
import 'package:dsh_feature_sidebar_terminal/dsh_feature_sidebar_terminal.dart';
import 'package:dsh_feature_subagent/dsh_feature_subagent.dart';
import 'package:dsh_feature_theme/dsh_feature_theme.dart';
import 'package:dsh_feature_tool/dsh_feature_tool.dart';
import 'package:dsh_feature_user_questions/dsh_feature_user_questions.dart';
import 'package:dsh_feature_workspace/dsh_feature_workspace.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_slots/dsh_slots.dart';
import 'package:dsh_theme/dsh_theme.dart';
import 'package:dsh_ui/dsh_ui.dart' show DshCodeHighlighter;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart' show GlobalKey, NavigatorState;
import 'package:url_launcher/url_launcher.dart';

import 'backend.dart';
import 'connection_store.dart';
import 'host_locale.dart';
import 'launch_link.dart';
import 'local_prefs.dart';
import 'notice_coordinator.dart';
import 'platform/notifications.dart';
import 'platform/platform_services.dart';
import 'screens/app_settings_rows.dart';
import 'screens/pairing_screen.dart' show RepairRoute;
import 'screens/settings_route.dart';
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
enum PairingErrorKind {
  /// The text is not a launch link.
  invalid,

  /// The host refused the launch token.
  rejected,

  /// Nothing answered.
  unreachable,

  /// Plain http to an address that is not this device or a private network
  /// (`detail` is the host).
  insecure,

  /// The TLS handshake was refused by the trust policy.
  certificate,
}

class PairingError {
  const PairingError(this.kind, [this.detail]);
  final PairingErrorKind kind;
  final String? detail;
}

/// A certificate waiting for the user's decision. Nothing has been sent to the
/// host: the certificate was read in a handshake that was closed right after.
class CertificatePrompt {
  CertificatePrompt({
    required this.origin,
    required this.certificate,
    this.previous,
  });

  final Uri origin;

  /// What the host presents now.
  final CertificateInfo certificate;

  /// The fingerprint trusted before, when this is a change (null for a first
  /// contact).
  final String? previous;

  /// The user has read the change warning and asked to look at the new
  /// certificate; only then may it be trusted.
  bool acknowledged = false;

  /// This is a different certificate than the one trusted before.
  bool get changed => previous != null;

  /// The decision UI may offer "trust" now.
  bool get canTrust => !changed || acknowledged;
}

/// How the connection to the host is protected.
enum LinkSecurity {
  /// https with a certificate the system trusts.
  encrypted,

  /// https with a certificate the user confirmed.
  pinned,

  /// Plain http (only loopback and private networks are allowed).
  plain,
}

/// Resolves a host name to its addresses (injectable for tests).
typedef HostResolver = Future<List<InternetAddress>> Function(String host);

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
    this.highlighter,
    LocalPrefs? prefs,
    this.notifications,
    HostResolver? resolver,
  }) : _resolve = resolver ?? InternetAddress.lookup,
       store = store ?? MemoryConnectionStore(),
       prefs = prefs ?? MemoryLocalPrefs(),
       _deviceLocale = DshLocale.fromTag(
         PlatformDispatcher.instance.locale.toLanguageTag(),
       ),
       locale =
           locale ??
           (prefs?.locale == null
               ? DshLocale.fromTag(
                   PlatformDispatcher.instance.locale.toLanguageTag(),
                 )
               : DshLocale.fromTag(prefs!.locale!)) {
    final cache = this.prefs.themeCache;
    if (cache != null) {
      try {
        themeSettings = ThemeSettings.fromJson(cache);
      } on ThemeException {
        // A cache this build cannot read is no cache.
      }
    }
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
      host: QuestionHost(
        attachWait: backend.attachQuestionWait,
        answerContinued: _answerContinued,
        continued: _continuedQuestions,
        projectionChanges: _projectionEvents.stream,
      ),
    );
    registerConversationFeature(
      slots,
      i18n: () => i18n,
      commandUi: commandUi,
      inputOf: (id) => _sessions[id]?.owner.input,
      workspaces: workspaceServices,
    );
    registerWorkspaceFeature(
      slots,
      services: workspaceServices,
      i18n: () => i18n,
    );
    registerInputTriggerFeature(slots, i18n: () => i18n);
    // What a tapped link or file path may open, shared by the chat's
    // Markdown links and the tool cards.
    final hostActions = ToolHostActions(
      openFile: (path, {line}) => _openFile(path, line: line),
      openUrl: (url) => unawaited(
        launchUrl(url, mode: LaunchMode.externalApplication).then((_) => true),
      ),
      openSubagent: (parent, childId) => _subagents.openById(parent, childId),
      revealQuestion: (parent, callId) =>
          questions.reveal(parent.sessionId, callId),
    );
    registerChatFeature(slots, i18n: () => i18n, host: hostActions);
    registerAttachmentFeature(slots, i18n: () => i18n);
    sidebar = registerSidebarRightFeature(
      slots,
      i18n: () => i18n,
      services: _SidebarBridge(this),
    );
    registerFilesFeature(slots, i18n: () => i18n);
    terminals = ClientTerminals(
      host: backend.terminalHost,
      prefs: PrefsTerminalPrefs(this.prefs),
    );
    registerSidebarTerminalFeature(
      slots,
      i18n: () => i18n,
      terminals: terminals,
    );
    registerDocumentPreviewFeature(slots, i18n: () => i18n);
    registerToolFeature(slots, i18n: () => i18n, actions: hostActions);
    registerPlanFeature(slots, i18n: () => i18n);
    _subagents = registerSubagentFeature(
      slots,
      i18n: () => i18n,
      services: _SubagentBridge(this),
    );
    registerApprovalFeature(slots, tracker: approvals, i18n: () => i18n);
    registerUserQuestionsFeature(slots, tracker: questions, i18n: () => i18n);
    registerSettingsFeature(
      slots,
      i18n: () => i18n,
      hostVersion: () => hostVersion,
    );
    registerAppSettingsRows(slots, this);
    final notifier = notifications;
    if (notifier != null) {
      notices = NoticeCoordinator(
        service: notifier,
        approvals: approvals,
        questions: questions,
        i18n: () => i18n,
        sessionTitle: _sessionTitle,
        runningSessions: _runningSessions,
        onOpen: _openFromNotice,
        enabled: this.prefs.notificationsEnabled,
      );
      unawaited(notices!.init());
    }
    _stateSub = backend.statuses.listen(_onStatus);
    _approvalSub = approvals.pending.changes.listen((_) => notifyListeners());
    _questionSub = questions.pending.changes.listen((_) => notifyListeners());
  }

  final HostBackend backend;
  final ConnectionStore store;

  /// What the device itself remembers (language, theme cache, notifications).
  final LocalPrefs prefs;

  /// Local notifications and the keep-alive of the connection while in the
  /// background (null: none, as in tests and on the desktop).
  final NotificationService? notifications;
  NoticeCoordinator? notices;
  final DshLocale _deviceLocale;
  final LaunchScanner scanner;

  /// Pickers and file handling of the running platform.
  final PlatformServices platform;

  /// The syntax highlighter every code surface uses (null: plain text).
  final DshCodeHighlighter? highlighter;

  /// The right sidebar (file tree, previews, terminals) of every session.
  late final SidebarRightFeature sidebar;

  /// The terminal views behind the sidebar's terminal tabs.
  late final ClientTerminals terminals;

  /// `animation-frame` publications of the conversation flush on this
  /// scheduler (null: a short timer; tests pass an immediate one).
  final FlushScheduler? frameScheduler;

  final SlotRegistry slots = SlotRegistry();

  /// The `/` and `@` sources of every session's composer, and the client
  /// commands features contribute to the `/` menu (dsh `ctx.inputTriggers` and
  /// `ctx.commandUi`).
  final InputTriggerRegistry inputTriggers = InputTriggerRegistry();
  final CommandUiRegistry commandUi = CommandUiRegistry();
  late final InputSessionPort _sessionPort = _AppSessionPort(this);

  /// The app's navigator: subagent transcripts push onto it.
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  late final SubagentFeature _subagents;
  final StreamController<Object?> _listChanges =
      StreamController<Object?>.broadcast(sync: true);
  final Map<String, SessionController> _children = {};
  late final ApprovalTracker approvals;
  late final QuestionTracker questions;

  final StreamController<String> _projectionEvents =
      StreamController<String>.broadcast(sync: true);
  StreamSubscription<String>? _projectionSub;

  /// The questions the agent went on without, as the `userQuestions`
  /// projection of every session lists them.
  List<ProjectedQuestion> _continuedQuestions() {
    final m = manager;
    if (m == null) return const [];
    return [
      for (final id in m.projectionSessionIds)
        ...ProjectedQuestion.rowsOf(
          id,
          m.projectionValues(id)['userQuestions'],
        ),
    ];
  }

  Future<bool> _answerContinued(
    String sessionId,
    String callId,
    List<QuestionAnswer> answers,
  ) => UserQuestionsRemote(backend.remoteCaller).answer(
    sessionId,
    callId,
    AskUserQuestionAnswer(
      answers: [
        for (final a in answers)
          AskUserQuestionAnswerItem(
            id: a.id,
            selected: a.selected,
            custom: a.custom != null && a.custom!.isNotEmpty ? a.custom : null,
          ),
      ],
    ),
  );

  final StreamController<HostEvent> _events =
      StreamController<HostEvent>.broadcast(sync: true);
  final HostResolver _resolve;
  StreamSubscription<ConnectionStatus>? _stateSub;
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

  /// The latest connection status of the host (retry number, next retry).
  ConnectionStatus status = const ConnectionStatus(state: ConnectionState.idle);

  /// The connection came back a moment ago (the indicator confirms for two
  /// seconds, as dsh web does).
  bool recovered = false;
  Timer? _recoveredTimer;

  /// How long the "connected again" confirmation stays.
  static const Duration recoveredFor = Duration(seconds: 2);

  /// A certificate waiting for the user's decision, if any.
  CertificatePrompt? certificatePrompt;
  String? _pendingToken;
  bool _pendingRemember = false;

  /// The launch token of the live connection, in memory only (the keystore
  /// holds the persisted copy). Used to continue after a certificate decision.
  String? _activeToken;

  /// The host remembered from the last run that could not be reached at
  /// start-up (origin only): the pairing screen offers to retry or forget it.
  String? savedHostOrigin;

  SessionManager? manager;
  String? openSessionId;
  Object? createError;

  /// The Host's workspaces, live (empty until the follow stream's baseline).
  /// One observable for the life of the controller, so the surfaces that read
  /// it survive a re-pair.
  final Observable<WorkspaceSnapshot> workspaceState = Observable(
    const WorkspaceSnapshot(),
  );
  late final WorkspaceServices workspaceServices = _WorkspaceBridge(this);
  WorkspaceList? _workspaceList;
  WorkspaceNavigation? _navigation;
  StreamSubscription<WorkspaceSnapshot>? _workspaceSub;

  /// The New session screen is up: no session is open and the conversation
  /// area asks for a workspace first (dsh's sessionless hero).
  bool newSessionPending = false;

  DshLocale locale;

  /// The theme in force: the host's `ui-theme` section once connected (shared
  /// with dsh web), the last one seen before.
  ThemeSettings themeSettings = ThemeSettings();

  /// The release the host reports, once known.
  String? hostVersion;

  /// The host-backed services, present while connected.
  HostRemotes? remotes;
  ConfigForms? forms;
  ThemeSettingsService? _theme;
  HostLocale? _hostLocale;
  PermissionPresetsFeature? _permissions;
  ModelSelectionFeature? _models;
  final List<void Function()> _hostOffs = [];
  StreamSubscription<ThemeSettings>? _themeSub;
  String? _pendingOpen;

  DshI18n get i18n => DshI18n(locale);

  /// Whether the persisted theme can be edited now.
  bool get hostSettingsLive => _theme != null;

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
    final ok = await _connect(
      Uri.parse(saved.origin),
      saved.token,
      remember: false,
    );
    if (!ok &&
        pairingError?.kind == PairingErrorKind.unreachable &&
        manager == null) {
      savedHostOrigin = saved.origin;
      notifyListeners();
    }
  }

  /// Retry the host remembered from the last run.
  Future<void> retrySavedHost() async {
    savedHostOrigin = null;
    await restore();
  }

  /// Forget the host remembered from the last run.
  Future<void> forgetSavedHost() async {
    savedHostOrigin = null;
    pairingError = null;
    await store.clear();
    notifyListeners();
  }

  /// Pair from the pairing form ([text] is a launch link or host address).
  /// Returns whether the app is now connected; [pairingError] or
  /// [certificatePrompt] say why not.
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

  /// Plain http is for this device and private networks only: a name is
  /// resolved and every address it has must be one of those.
  Future<PairingError?> _checkPlainHttp(Uri origin) async {
    var scope = classifyHost(origin.host);
    if (scope == HostScope.name) {
      try {
        scope = classifyAddresses(await _resolve(origin.host));
      } on SocketException catch (e) {
        return PairingError(PairingErrorKind.unreachable, e.message);
      }
    }
    return scope == HostScope.public
        ? PairingError(PairingErrorKind.insecure, origin.host)
        : null;
  }

  Future<bool> _connect(
    Uri origin,
    String token, {
    required bool remember,
  }) async {
    final before = phase;
    void failed() {
      phase = before == ConnectionPhase.connecting
          ? ConnectionPhase.disconnected
          : before;
      notifyListeners();
    }

    pairingError = null;
    certificatePrompt = null;
    savedHostOrigin = null;
    phase = ConnectionPhase.connecting;
    hostOrigin = origin.toString();
    notifyListeners();
    if (origin.scheme == 'http') {
      final problem = await _checkPlainHttp(origin);
      if (problem != null) {
        pairingError = problem;
        failed();
        return false;
      }
    } else {
      final probe = await backend.trust.probe(origin);
      switch (probe) {
        case ProbeUntrusted(:final certificate):
          _holdForCertificate(origin, token, remember, certificate, null);
          failed();
          return false;
        case ProbeChanged(:final certificate, :final pinned):
          _holdForCertificate(origin, token, remember, certificate, pinned);
          failed();
          return false;
        case ProbeUnreachable(:final error):
          pairingError = PairingError(
            PairingErrorKind.unreachable,
            describeTransportError(error),
          );
          failed();
          return false;
        case ProbeNoTls() || ProbeSystemTrusted() || ProbePinned():
          break;
      }
    }
    try {
      final transport = await backend.connect(origin, token);
      _adopt(transport);
      phase = ConnectionPhase.connected;
      reconnecting = false;
      _activeToken = token;
      _pendingToken = null;
      if (remember) await store.save(SavedHost(origin.toString(), token));
      notifyListeners();
      notices?.setConnected(true);
      unawaited(notices?.requestIfNeeded());
      unawaited(
        manager!
            .refreshList()
            .then((_) {
              final id = _pendingOpen;
              if (id != null && manager?.summaryOf(id) != null) {
                _pendingOpen = null;
                return open(id);
              }
              return null;
            })
            .catchError((Object _) => null),
      );
      return true;
    } on ConnectException catch (e) {
      switch (e.failure) {
        case ConnectFailure.rejected:
          phase = ConnectionPhase.needsPairing;
          pairingError = const PairingError(PairingErrorKind.rejected);
        case ConnectFailure.unreachable:
          phase = before == ConnectionPhase.connecting
              ? ConnectionPhase.disconnected
              : before;
          pairingError = PairingError(PairingErrorKind.unreachable, e.detail);
        case ConnectFailure.certificate:
          phase = before == ConnectionPhase.connecting
              ? ConnectionPhase.disconnected
              : before;
          final refusal = e.refusal;
          if (refusal != null) {
            _holdForCertificate(
              origin,
              token,
              remember,
              refusal.presented,
              refusal.pinned,
            );
          } else {
            pairingError = const PairingError(PairingErrorKind.certificate);
          }
      }
    } on Object catch (e) {
      phase = ConnectionPhase.disconnected;
      pairingError = PairingError(
        PairingErrorKind.unreachable,
        describeTransportError(e),
      );
    }
    notifyListeners();
    return false;
  }

  void _holdForCertificate(
    Uri origin,
    String token,
    bool remember,
    CertificateInfo certificate,
    String? pinned,
  ) {
    _pendingToken = token;
    _pendingRemember = remember;
    certificatePrompt = CertificatePrompt(
      origin: origin,
      certificate: certificate,
      previous: pinned,
    );
    pairingError = const PairingError(PairingErrorKind.certificate);
  }

  /// The user compared the fingerprint and trusts the certificate: pin it and
  /// connect (the handshake itself then holds the host to exactly it).
  Future<bool> trustCertificate() async {
    final prompt = certificatePrompt;
    final token = _pendingToken;
    if (prompt == null || token == null || !prompt.canTrust) return false;
    await backend.trust.pin(prompt.origin, prompt.certificate);
    return _connect(prompt.origin, token, remember: _pendingRemember);
  }

  /// The user does not trust the certificate: nothing was sent, nothing is
  /// kept.
  void declineCertificate() {
    certificatePrompt = null;
    pairingError = null;
    _pendingToken = null;
    notifyListeners();
  }

  /// The user read the change warning and wants to look at the new
  /// certificate: the old pin is dropped (the user still has to trust the new
  /// one explicitly).
  Future<void> reviewCertificateChange() async {
    final prompt = certificatePrompt;
    if (prompt == null || !prompt.changed) return;
    await backend.trust.forget(prompt.origin);
    prompt.acknowledged = true;
    notifyListeners();
  }

  /// A live connection was refused because the host now shows another
  /// certificate than the trusted one: put the decision in front of the user.
  void reviewRefusedCertificate() {
    final refusal = status.refusal;
    final token = _activeToken;
    final origin = hostOrigin == null ? null : Uri.parse(hostOrigin!);
    if (refusal == null || token == null || origin == null) return;
    _holdForCertificate(
      origin,
      token,
      false,
      refusal.presented,
      refusal.pinned,
    );
    notifyListeners();
    openRepair();
  }

  /// How the connection is protected, for the indicator and Settings.
  LinkSecurity get security {
    final origin = hostOrigin == null ? null : Uri.parse(hostOrigin!);
    if (origin == null || origin.scheme != 'https') return LinkSecurity.plain;
    return backend.trust.pinnedFingerprint(origin) == null
        ? LinkSecurity.encrypted
        : LinkSecurity.pinned;
  }

  /// The fingerprint trusted for the current host, if any.
  String? get pinnedFingerprint {
    final origin = hostOrigin == null ? null : Uri.parse(hostOrigin!);
    return origin == null ? null : backend.trust.pinnedFingerprint(origin);
  }

  /// Forget the trusted certificate of the current host and leave it.
  Future<void> forgetCertificate() async {
    final origin = hostOrigin == null ? null : Uri.parse(hostOrigin!);
    if (origin == null) return;
    await backend.trust.forget(origin);
    await disconnect();
  }

  void _adopt(SessionTransport transport) {
    if (identical(_transport, transport) && manager != null) return;
    _transport = transport;
    unawaited(_hostEventSub?.cancel());
    _hostEventSub = transport.hostEvents.listen(_events.add);
    unawaited(_listSub?.cancel());
    final m = manager = SessionManager(transport)..start();
    unawaited(_projectionSub?.cancel());
    _projectionSub = m.projectionChanges.listen(_projectionEvents.add);
    _listSub = m.list.changes.listen((_) {
      _listChanges.add(null);
      notices?.sessionsChanged();
      notifyListeners();
    });
    _attachHost(transport);
  }

  /// Start the settings-side services over the live host and fill their slots.
  void _attachHost(SessionTransport transport) {
    _detachHost();
    final r = remotes = HostRemotes(
      caller: backend.remoteCaller,
      hostEvents: _events.stream,
      generations: transport.generations,
      currentGeneration: () => transport.generation,
    );
    final f = forms = ConfigForms(r);
    final theme = _theme = ThemeSettingsService(
      host: f.get('ui-theme'),
      initial: themeSettings,
    );
    _themeSub = theme.settings.changes.listen((next) {
      themeSettings = next;
      unawaited(prefs.setThemeCache(next.toJson()));
      notifyListeners();
    });
    _hostLocale = HostLocale(
      host: f.get(localeSettingsNamespace),
      initial: locale,
      deviceLocale: _deviceLocale,
      onChange: (next) {
        locale = next;
        unawaited(prefs.setLocale(next.name));
        notifyListeners();
      },
    );
    _hostOffs.add(
      registerThemeFeature(
        slots,
        service: theme,
        i18n: () => i18n,
        touch: platform.touchInput,
      ),
    );
    _permissions = registerPermissionPresetsFeature(
      slots,
      remotes: r,
      forms: f,
      i18n: () => i18n,
      commandUi: commandUi,
      projectionsOf: (id) => _sessions[id]?.session.projections,
    );
    _models = registerModelSelectionFeature(
      slots,
      remotes: r,
      i18n: () => i18n,
      commandUi: commandUi,
      projectionsOf: (id) => _sessions[id]?.session.projections,
      isSubagent: _sessionPort.isSubagentTranscript,
    );
    final commands = registerCommandsFeature(
      slots,
      triggers: inputTriggers,
      commandUi: commandUi,
      remotes: r,
      sessions: _sessionPort,
      i18n: () => i18n,
    );
    _hostOffs.add(commands.dispose);
    _hostOffs.add(
      registerReferenceFeature(
        triggers: inputTriggers,
        remotes: r,
        sessions: _sessionPort,
        i18n: () => i18n,
      ),
    );
    _hostOffs.add(
      registerDirectoryPickerBrowseFeature(
        slots,
        remote: r.directoryPicker,
        i18n: () => i18n,
      ),
    );
    _attachWorkspaces(r);
    unawaited(
      readHostVersion(backend.remoteCaller).then((v) {
        hostVersion = v;
        notifyListeners();
      }, onError: (Object _) {}),
    );
  }

  void _detachHost() {
    for (final off in _hostOffs) {
      off();
    }
    _hostOffs.clear();
    unawaited(_themeSub?.cancel());
    _themeSub = null;
    _hostLocale?.dispose();
    _hostLocale = null;
    final theme = _theme;
    _theme = null;
    if (theme != null) unawaited(theme.dispose());
    final permissions = _permissions;
    _permissions = null;
    if (permissions != null) unawaited(permissions.dispose());
    final models = _models;
    _models = null;
    if (models != null) unawaited(models.dispose());
    final f = forms;
    forms = null;
    if (f != null) unawaited(f.dispose());
    _detachWorkspaces();
    remotes = null;
    hostVersion = null;
  }

  void _onStatus(ConnectionStatus next) {
    status = next;
    switch (next.state) {
      case ConnectionState.needsPairing:
        phase = ConnectionPhase.needsPairing;
        pairingError = const PairingError(PairingErrorKind.rejected);
        reconnecting = false;
      case ConnectionState.certificateRefused:
        reconnecting = false;
      case ConnectionState.connected:
        final wasDown = reconnecting;
        reconnecting = false;
        if (phase == ConnectionPhase.needsPairing) {
          phase = ConnectionPhase.connected;
          pairingError = null;
        }
        if (wasDown) {
          recovered = true;
          _recoveredTimer?.cancel();
          _recoveredTimer = Timer(recoveredFor, () {
            recovered = false;
            notifyListeners();
          });
        }
      case ConnectionState.pairing ||
          ConnectionState.connecting ||
          ConnectionState.waiting:
        reconnecting = phase == ConnectionPhase.connected;
        if (reconnecting) {
          recovered = false;
          _recoveredTimer?.cancel();
        }
      case ConnectionState.idle || ConnectionState.stopped:
        break;
    }
    notifyListeners();
  }

  /// Retry now instead of waiting out the backoff.
  void reconnectNow() => backend.reconnectNow();

  /// Forget the host and return to the pairing screen.
  Future<void> disconnect() async {
    await store.clear();
    await backend.disconnect();
    await _resetModels();
    phase = ConnectionPhase.disconnected;
    pairingError = null;
    certificatePrompt = null;
    _pendingToken = null;
    _activeToken = null;
    hostOrigin = null;
    reconnecting = false;
    recovered = false;
    status = const ConnectionStatus(state: ConnectionState.idle);
    notifyListeners();
  }

  Future<void> _resetModels() async {
    openSessionId = null;
    newSessionPending = false;
    for (final s in [..._sessions.values, ..._children.values]) {
      await s.dispose();
    }
    _sessions.clear();
    _children.clear();
    await _hostEventSub?.cancel();
    _hostEventSub = null;
    await _listSub?.cancel();
    _listSub = null;
    await _projectionSub?.cancel();
    _projectionSub = null;
    await manager?.dispose();
    manager = null;
    _transport = null;
    _detachHost();
    // The sidebars belong to the host that was left; its terminals keep
    // running there until the host reaps them.
    sidebar.reset();
    await terminals.detachAll();
    notices?.setConnected(false);
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

  /// The controller of [sessionId], made on first use (its model stays
  /// resident like dsh's session manager keeps it).
  SessionController? _controllerFor(String sessionId) {
    final m = manager;
    if (m == null) return null;
    return _sessions.putIfAbsent(
      sessionId,
      () => SessionController(
        m.get(sessionId),
        scheduler: frameScheduler,
        triggers: inputTriggers,
        cwdReader: () => manager?.summaryOf(sessionId)?.cwd,
        blankReader: () => manager?.summaryOf(sessionId)?.blank,
        hostHome: _transport?.generation?.hostHome ?? '',
        uploader: backend.uploader,
        files: backend.files,
        platform: platform,
      ),
    );
  }

  /// Make [sessionId] the session in view and start following it.
  Future<SessionController?> open(String sessionId) async {
    final controller = _controllerFor(sessionId);
    if (controller == null) return null;
    openSessionId = sessionId;
    newSessionPending = false;
    notifyListeners();
    unawaited(controller.open().then((_) => notifyListeners()));
    return controller;
  }

  void closeSession() {
    openSessionId = null;
    newSessionPending = false;
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

  // ---- workspaces ------------------------------------------------------

  void _attachWorkspaces(HostRemotes r) {
    final m = manager;
    if (m == null) return;
    _detachWorkspaces();
    final list = _workspaceList = WorkspaceList(
      remote: r.workspace,
      follow: backend.workspaceFollow,
    )..start();
    workspaceState.set(list.value);
    _workspaceSub = list.state.changes.listen((next) {
      workspaceState.set(next);
      notifyListeners();
    });
    _navigation = WorkspaceNavigation(
      workspaces: list,
      sessions: m,
      current: () => openSessionId,
      show: (id) async {
        await open(id);
      },
      clear: () {
        openSessionId = null;
        newSessionPending = true;
        notifyListeners();
      },
      onFailure: (error) {
        createError = error;
        notifyListeners();
      },
    );
  }

  void _detachWorkspaces() {
    unawaited(_workspaceSub?.cancel());
    _workspaceSub = null;
    final list = _workspaceList;
    _workspaceList = null;
    _navigation = null;
    if (list != null) unawaited(list.dispose());
    workspaceState.set(const WorkspaceSnapshot());
  }

  /// Both lists have arrived, or [timeout] ran out: "+" right after connecting
  /// must not read an unloaded list as "no workspace".
  Future<void> _listsReady({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final m = manager;
    if (m == null) return;
    bool ready() =>
        workspaceState.value.phase == WorkspacePhase.ready &&
        m.list.value.phase == ListPhase.ready;
    if (ready()) return;
    final done = Completer<void>();
    void check(Object? _) {
      if (!done.isCompleted && ready()) done.complete();
    }

    final subs = [
      workspaceState.changes.listen(check),
      m.list.changes.listen(check),
    ];
    try {
      await done.future.timeout(timeout, onTimeout: () {});
    } finally {
      for (final sub in subs) {
        unawaited(sub.cancel());
      }
    }
  }

  /// "New session": a fresh session in [workspaceId], else in the workspace in
  /// view, else in the most recent one. With no workspace on a fresh account
  /// the Host's default one is prepared first; with none to choose from the
  /// New session screen asks for one (dsh `UiWorkspaceService.startSession`).
  Future<void> startSession([String? workspaceId]) async {
    final nav = _navigation;
    final list = _workspaceList;
    final m = manager;
    if (nav == null || list == null || m == null) return;
    createError = null;
    await _listsReady();
    if (identical(nav, _navigation)) {
      final fresh =
          workspaceId == null &&
          workspaceState.value.phase == WorkspacePhase.ready &&
          workspaceState.value.items.isEmpty &&
          m.list.value.phase == ListPhase.ready &&
          m.list.value.items.isEmpty;
      if (fresh) {
        try {
          await list.initializeDefault();
        } on Object {
          // An ineligible account or a refusal leaves the chooser.
        }
      }
    }
    try {
      await nav.startSession(workspaceId);
    } on Object {
      // Reported through [createError].
    }
  }

  /// A workspace was picked for the conversation being prepared: its first
  /// reusable blank session opens, and the draft of [from] moves over.
  Future<void> openWorkspace(String workspaceId, {String? from}) async {
    final nav = _navigation;
    if (nav == null) return;
    createError = null;
    await nav.openWorkspace(
      workspaceId,
      beforeOpen: (next) => _moveDraft(from, next),
    );
  }

  /// The unsent text of the blank session [from] follows the pick to [to]
  /// (dsh moves the draft and its attachments; here the text moves and chips
  /// become their plain text).
  void _moveDraft(String? from, String to) {
    if (from == null || from == to) return;
    final source = _sessions[from]?.owner.input;
    final target = _controllerFor(to)?.owner.input;
    if (source == null || target == null) return;
    final text = source.clipboardText;
    if (text.isEmpty) return;
    target.setPlainText(text);
    source.clear();
  }

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

  /// Change the interface language: written to the host's settings document
  /// when connected (the choice is shared with dsh web), kept on the device
  /// otherwise.
  void setLocale(DshLocale l) {
    final host = _hostLocale;
    if (host != null) {
      host.set(l);
      return;
    }
    locale = l;
    unawaited(prefs.setLocale(l.name));
    notifyListeners();
  }

  /// Whether the language can be saved on the host.
  bool get localeOnHost => _hostLocale != null && _hostLocale!.available;

  /// Turn notifications on or off (a device setting).
  void setNotificationsEnabled(bool enabled) {
    unawaited(prefs.setNotificationsEnabled(enabled));
    notices?.setEnabled(enabled);
    notifyListeners();
  }

  bool get notificationsEnabled => prefs.notificationsEnabled;

  /// The app moved to or from the foreground ([AppLifecycleState] resumed).
  void setForeground(bool foreground) {
    notices?.setForeground(foreground);
    // A connection that went quiet while the app was away is retried at once
    // instead of after the rest of its backoff.
    if (foreground && reconnecting) backend.reconnectNow();
  }

  /// Open the page that pairs again over the app (sessions stay behind it).
  void openRepair() {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute<void>(builder: (_) => RepairRoute(controller: this)),
    );
  }

  /// Open the settings page over the app.
  void openSettings() {
    final nav = navigatorKey.currentState;
    if (nav == null) return;
    nav.push(
      MaterialPageRoute<void>(builder: (_) => SettingsRoute(controller: this)),
    );
  }

  String _sessionTitle(String sessionId) {
    for (final e in sessionList.items) {
      if (e.sessionId == sessionId && (e.title?.trim().isNotEmpty ?? false)) {
        return e.title!.trim();
      }
    }
    final title = manager?.projectionValues(sessionId)['title'];
    return title is String && title.trim().isNotEmpty
        ? title.trim()
        : i18n.t(appNamespace, 'sessions.untitled');
  }

  int _runningSessions() =>
      sessionList.items.where((e) => e.summary.running).length;

  /// A notification was tapped: show that session, now or once the list is in.
  void _openFromNotice(String sessionId) {
    final m = manager;
    if (m != null && m.summaryOf(sessionId) != null) {
      unawaited(open(sessionId));
    } else {
      _pendingOpen = sessionId;
    }
  }

  @override
  void dispose() {
    _recoveredTimer?.cancel();
    unawaited(_stateSub?.cancel());
    unawaited(_approvalSub?.cancel());
    unawaited(_questionSub?.cancel());
    unawaited(_resetModels());
    unawaited(notices?.dispose());
    unawaited(approvals.dispose());
    unawaited(questions.dispose());
    unawaited(terminals.dispose());
    unawaited(_projectionEvents.close());
    unawaited(_events.close());
    unawaited(backend.dispose());
    super.dispose();
  }
}

/// The app's side of the subagent feature: child sessions as read-only
/// owners, list facts for activity and usage, and the navigator.
class _WorkspaceBridge implements WorkspaceServices {
  _WorkspaceBridge(this._app);

  final AppController _app;

  @override
  Observable<WorkspaceSnapshot> get workspaces => _app.workspaceState;

  @override
  Future<WorkspaceView> createWorkspace(String path) {
    final list = _app._workspaceList;
    if (list == null) return Future.error(NotConnected());
    return list.create(path);
  }

  @override
  Future<void> startSession([String? workspaceId]) =>
      _app.startSession(workspaceId);

  @override
  Future<void> openWorkspace(String workspaceId, {String? from}) =>
      _app.openWorkspace(workspaceId, from: from);
}

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

/// The sessions the trigger sources ask about (dsh's `ctx.sessions` seat).
class _AppSessionPort implements InputSessionPort {
  _AppSessionPort(this.app);

  final AppController app;

  @override
  Future<void> ensureOpen(String sessionId, AbortSignal signal) async {
    final controller = app._sessions[sessionId];
    if (controller == null) {
      throw StateError('session "$sessionId" is not held by this client');
    }
    final state = controller.session.snapshot.value;
    if (state.openState == OpenState.error) {
      throw state.openError ?? StateError('session "$sessionId" is not open');
    }
    if (state.openState != OpenState.open) {
      final aborted = Completer<void>();
      signal.onAbort(
        () => aborted.completeError(signal.reason ?? const AbortedException()),
      );
      await Future.any<void>([controller.open(), aborted.future]);
    }
    final settled = controller.session.snapshot.value;
    if (settled.openState != OpenState.open) {
      throw settled.openError ?? StateError('session "$sessionId" is not open');
    }
  }

  @override
  bool isSubagentTranscript(String sessionId) => false;

  @override
  SessionSummary? summary(String sessionId) =>
      app.manager?.summaryOf(sessionId);

  @override
  String get hostHome => app._transport?.generation?.hostHome ?? '';

  @override
  void openFile(String sessionId, String path) {
    final controller = app._sessions[sessionId];
    if (controller == null) return;
    app.sidebar.openFile(controller.owner, path);
  }
}
