import 'dart:async';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_flutter/src/app_controller.dart';
import 'package:dsh_flutter/src/backend.dart';
import 'package:dsh_i18n/dsh_i18n.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/testing.dart';
import 'package:dsh_slots/testing.dart';

/// A [HostBackend] over a scriptable [FakeTransport]; no sockets.
class FakeBackend implements HostBackend {
  FakeBackend({FakeTransport? transport})
    : transport = transport ?? FakeTransport();

  final FakeTransport transport;
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
}) => AppController(
  backend: backend,
  locale: locale,
  frameScheduler: FlushScheduler.immediate(),
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
