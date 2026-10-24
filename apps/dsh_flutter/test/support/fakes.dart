import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_flutter/src/backend.dart';
import 'package:dsh_flutter/src/local_prefs.dart';
import 'package:dsh_flutter/src/platform/notifications.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/testing.dart';

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
  @override
  final FakeUploadClient uploader = FakeUploadClient();
  @override
  final FakeWorkspaceFiles files = FakeWorkspaceFiles();
  final StreamController<ConnectionState> stateController =
      StreamController<ConnectionState>.broadcast();
  final List<(Uri, String)> connects = [];
  final List<(String, Map<String, Object?>)> answers = [];
  Object? failWith;
  int disconnects = 0;

  @override
  Stream<ConnectionState> get states => stateController.stream;

  @override
  Future<SessionTransport> connect(Uri origin, String token) async {
    connects.add((origin, token));
    final failure = failWith;
    if (failure != null) throw failure;
    return transport;
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
  String cwd = '/work/project-x',
}) => {
  'sessionId': id,
  'updatedAt': DateTime.now().millisecondsSinceEpoch,
  'running': running,
  'blank': false,
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
