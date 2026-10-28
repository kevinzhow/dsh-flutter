import 'dart:typed_data';
import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated_job.dart' as job_ns;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_flutter/src/backend.dart';
import 'package:dsh_flutter/src/local_prefs.dart';
import 'package:dsh_flutter/src/platform/notifications.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/testing.dart';
import 'package:flutter/widgets.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';

/// A [HostTrust] whose probe answers what the test scripts; nothing opens a
/// socket. Pins work as in the real one.
class FakeTrust extends HostTrust {
  FakeTrust({super.pins});

  /// What probing any https origin returns next.
  CertificateProbe next = const ProbeSystemTrusted();
  final List<Uri> probes = [];

  @override
  Future<CertificateProbe> probe(
    Uri origin, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    probes.add(origin);
    if (origin.scheme != 'https') return const ProbeNoTls();
    final pinned = pinnedFingerprint(origin);
    final answer = next;
    if (pinned != null) {
      final certificate = switch (answer) {
        ProbeUntrusted(:final certificate) => certificate,
        ProbePinned(:final certificate) => certificate,
        ProbeChanged(:final certificate) => certificate,
        _ => null,
      };
      if (certificate != null) {
        return certificate.sha256 == pinned
            ? ProbePinned(certificate)
            : ProbeChanged(certificate, pinned);
      }
    }
    return answer;
  }
}

/// A certificate for tests: a made-up fingerprint, no key material.
CertificateInfo fakeCertificate({
  String sha256 = 'AA:BB:CC:DD:EE:FF:00:11',
  String subject = '/CN=host.example',
  DateTime? notAfter,
}) => CertificateInfo(
  sha256: sha256,
  subject: subject,
  issuer: subject,
  notBefore: DateTime(2020),
  notAfter: notAfter ?? DateTime.now().add(const Duration(days: 300)),
);

/// The host's open-in-app routes, scripted: which applications are installed
/// and what was launched.
class FakeOpenInApp implements OpenInAppClient {
  List<String> installed = const [];
  final List<({String app, String path})> opened = [];
  Object? failOpen;

  @override
  Future<List<String>> apps() async => installed;

  @override
  Future<void> open(String app, String path) async {
    final failure = failOpen;
    if (failure != null) throw failure;
    opened.add((app: app, path: path));
  }

  @override
  Future<Uint8List?> icon(String app) async => null;
}

/// A [HostBackend] over a scriptable [FakeTransport]; no sockets.
class FakeBackend implements HostBackend {
  FakeBackend({FakeTransport? transport})
    : transport = transport ?? FakeTransport() {
    // A host with an empty settings document and no permission service.
    host.handlers['settings/describe'] = (_) => describeValue(const []);
    host.handlers['pluginManager/listBundles'] = (_) => const <Object?>[];
  }

  final FakeTransport transport;

  /// The unary host behind `remoteCaller`: tests script the settings-side
  /// namespaces on it.
  final FakeHost host = FakeHost();

  @override
  RemoteCaller get remoteCaller => host;

  /// The terminal host behind `terminalHost`: tests script terminals on it.
  final FakeTerminalHost terminals = FakeTerminalHost();
  @override
  TerminalHost get terminalHost => terminals.terminalHost;
  Stream<GenerationFrame> Function(job_ns.JobListRequest)? jobList;
  Stream<GenerationFrame> Function(job_ns.JobFollowRequest Function())?
  jobFollow;
  @override
  JobsHost get jobsHost => JobsHost(
    remote: job_ns.JobRemote(host),
    list: (request) => jobList?.call(request) ?? const Stream.empty(),
    follow: (request) => jobFollow?.call(request) ?? const Stream.empty(),
  );
  @override
  final FakeUploadClient uploader = FakeUploadClient();
  @override
  final FakeOpenInApp openInApp = FakeOpenInApp();
  @override
  final FakeDeliverables deliverables = FakeDeliverables();
  @override
  final FakeWorkspaceFiles files = FakeWorkspaceFiles();
  final StreamController<ConnectionStatus> stateController =
      StreamController<ConnectionStatus>.broadcast();
  @override
  final FakeTrust trust = FakeTrust();
  int reconnects = 0;

  /// Publish a connection status as the live connection would.
  void emit(
    ConnectionState state, {
    int attempt = 0,
    DateTime? retryAt,
    CertificateRefusal? refusal,
  }) => stateController.add(
    ConnectionStatus(
      state: state,
      attempt: attempt,
      retryAt: retryAt,
      refusal: refusal,
    ),
  );

  /// The workspace follow stream: tests publish frames with [emitWorkspaces].
  final StreamController<GenerationFrame> workspaceFrames =
      StreamController<GenerationFrame>.broadcast(sync: true);

  @override
  Stream<GenerationFrame> workspaceFollow() => workspaceFrames.stream;

  /// Publish a workspace baseline as the Host's follow stream opens with.
  void emitWorkspaces(
    List<Map<String, Object?>> items, {
    List<String> archived = const [],
    List<String> pinned = const [],
  }) => workspaceFrames.add(
    StreamItem(1, {
      'type': 'baseline',
      'value': {
        'items': items,
        'archivedSessionIds': archived,
        'pinnedSessionIds': pinned,
      },
    }),
  );

  @override
  void reconnectNow() => reconnects++;
  final List<(Uri, String)> connects = [];
  final List<(String, Map<String, Object?>)> answers = [];
  Object? failWith;
  int disconnects = 0;

  @override
  Stream<ConnectionStatus> get statuses => stateController.stream;

  @override
  Future<SessionTransport> connect(Uri origin, String token) async {
    connects.add((origin, token));
    final failure = failWith;
    if (failure != null) throw failure;
    return transport;
  }

  /// Claims of timed questions: tests push the Host's remaining duration (or
  /// end the stream) on [claims]'s controllers.
  final List<(String, StreamController<Duration>)> claims = [];

  @override
  Stream<Duration> attachQuestionWait(WaterfallEvent event, String callId) {
    final controller = StreamController<Duration>();
    claims.add((callId, controller));
    return controller.stream;
  }

  @override
  Future<void> answer(WaterfallEvent event, WaterfallOutcome outcome) async {
    answers.add((event.eventId, outcome.toJson()));
  }

  @override
  Future<void> disconnect() async => disconnects++;

  @override
  Future<void> dispose() async {
    await stateController.close();
  }
}

Map<String, Object?> listRow(
  String id, {
  String? title,
  bool running = false,
  bool blank = false,
  String cwd = '/work/project-x',
}) => {
  'sessionId': id,
  'updatedAt': DateTime.now().millisecondsSinceEpoch,
  'running': running,
  'blank': blank,
  'agentAvailable': true,
  'cwd': cwd,
  if (title != null)
    'projections': {
      'kind': 'cached',
      'asOfSeq': 0,
      'values': {'title': title},
    },
};

AppController makeController(
  FakeBackend backend, {
  DshLocale locale = DshLocale.en,
  LocalPrefs? prefs,
  NotificationService? notifications,
}) => AppController(
  backend: backend,
  locale: locale,
  frameScheduler: FlushScheduler.immediate(),
  prefs: prefs,
  notifications: notifications,
);

/// A durable event record for follow snapshots and frames.
Map<String, Object?> userMessage(int seq, String text) => rec(
  seq,
  'user/message',
  surfaceOp: 'append',
  data: {
    'content': [
      {'type': 'text', 'text': text},
    ],
    'source': {'kind': 'user', 'rpcId': 'r$seq'},
    'role': 'user',
    'id': 'u$seq',
  },
);

/// A [NotificationService] that records what the app asked of the platform.
class FakeNotifications implements NotificationService {
  FakeNotifications({this.grant = NoticePermission.granted});

  /// What the permission starts as; a request moves it to [answer].
  NoticePermission grant;
  NoticePermission answer = NoticePermission.granted;
  @override
  bool supported = true;
  void Function(String sessionId)? onOpen;
  final List<({int id, String title, String body, String sessionId})> shown =
      [];
  final List<int> cancelled = [];
  int cancelAlls = 0;
  int requests = 0;
  int settingsOpens = 0;
  int initCalls = 0;

  /// Keep-alive state: the last start's text, null while stopped.
  ({String title, String body})? keepAlive;
  final List<String> keepAliveLog = [];

  @override
  Future<void> init({required void Function(String sessionId) onOpen}) async {
    initCalls++;
    this.onOpen = onOpen;
  }

  @override
  Future<NoticePermission> permission() async => grant;

  @override
  Future<NoticePermission> requestPermission() async {
    requests++;
    grant = answer;
    return grant;
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String sessionId,
  }) async =>
      shown.add((id: id, title: title, body: body, sessionId: sessionId));

  @override
  Future<void> cancel(int id) async => cancelled.add(id);

  @override
  Future<void> cancelAll() async => cancelAlls++;

  @override
  Future<void> startKeepAlive({
    required String title,
    required String body,
  }) async {
    keepAlive = (title: title, body: body);
    keepAliveLog.add('start');
  }

  @override
  Future<void> stopKeepAlive() async {
    keepAlive = null;
    keepAliveLog.add('stop');
  }

  @override
  Future<void> openSettings() async => settingsOpens++;
}

/// Open the session [id] from the sidebar tree: its group (Ungrouped, for a
/// session no workspace accounts) opens first when the row is not showing.
Future<void> openRow(
  WidgetTester t,
  String id, {
  Future<void> Function(WidgetTester t)? settle,
}) async {
  final row = find.byKey(ValueKey('session-row-$id'));
  Future<void> wait() async =>
      settle != null ? await settle(t) : await t.pump();
  // On a phone the tree is in the drawer.
  final menu = find.byKey(const ValueKey('phone-menu'));
  if (row.evaluate().isEmpty &&
      menu.evaluate().isNotEmpty &&
      find.byKey(const ValueKey('phone-drawer')).evaluate().isEmpty) {
    await t.tap(menu);
    await wait();
    await t.pump(const Duration(milliseconds: 300));
  }
  if (row.evaluate().isEmpty) {
    final group = find.byKey(const ValueKey('workspace-row-'));
    if (group.evaluate().isNotEmpty) {
      await t.tap(group);
      await wait();
    }
  }
  await t.tap(row);
  // A phone's drawer slides shut over 220ms.
  if (menu.evaluate().isNotEmpty) {
    await t.pump(const Duration(milliseconds: 300));
  }
}

/// Open Settings from the sidebar foot: the "More" menu, then Settings.
Future<void> openSettingsUi(
  WidgetTester t, {
  Future<void> Function(WidgetTester t)? settle,
}) async {
  Future<void> wait() async =>
      settle != null ? await settle(t) : await t.pump();
  await t.tap(find.byKey(const ValueKey('settings-trigger')));
  await wait();
  // The source portal measures its actual anchor before mounting the visible
  // card. Allow that composition pass before trying to press its first row.
  for (
    var frame = 0;
    frame < 3 &&
        find.byKey(const ValueKey('settings-more-settings')).evaluate().isEmpty;
    frame++
  ) {
    await t.pump();
  }
  await t.tap(find.byKey(const ValueKey('settings-more-settings')));
  await wait();
}

class FakeDeliverables implements DeliverablesClient {
  @override
  Future<List<NativeFileApplication>> applications(
    DeliveryFile file, {
    DeliverablesCancel? cancel,
  }) async => const [];

  final Map<String, ChangesSummary> summaries = {};
  final Map<String, ChangesDiff> diffs = {};
  final List<DeliveryFile> opened = [];
  PresentedHost metadata = const PresentedHost(
    name: 'Synthetic remote',
    available: true,
    fileManager: 'directory',
  );
  @override
  Future<ChangesSummary> summary(
    String id,
    num seq, {
    DeliverablesCancel? cancel,
  }) async =>
      summaries['$id:$seq'] ?? (throw const DeliverablesHttpFailure(404));
  @override
  Future<ChangesDiff> diff(
    String id,
    num seq,
    int index, {
    DeliverablesCancel? cancel,
  }) async =>
      diffs['$id:$seq:$index'] ?? (throw const DeliverablesHttpFailure(404));
  @override
  Future<PresentedHost> host({DeliverablesCancel? cancel}) async => metadata;
  @override
  Future<void> open(
    DeliveryFile file, {
    NativeFileAction action = NativeFileAction.open,
    String? application,
    DeliverablesCancel? cancel,
  }) async {
    opened.add(file);
  }
}
