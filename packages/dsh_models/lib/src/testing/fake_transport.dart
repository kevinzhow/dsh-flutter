import 'dart:async';

import 'package:dsh_client/dsh_client.dart';

import '../../dsh_models.dart';

/// Synthetic `{type:'event', event:{...}}` frame / history record.
Map<String, Object?> rec(
  int seq,
  String type, {
  Map<String, Object?> data = const {},
  String? surfaceOp,
}) => {
  'type': 'event',
  'event': {
    'type': type,
    'seq': seq,
    'time': 1000 + seq,
    'data': data,
    if (surfaceOp != null) 'surfaceOp': surfaceOp,
  },
};

Map<String, Object?> snapshot(
  List<Map<String, Object?>> records, {
  bool hasMore = false,
  int? cursor,
  int revision = 0,
  Map<String, Object?>? activeAttempt,
  Map<String, Object?> projections = const {},
}) => {
  'type': 'snapshot',
  'header': {'version': 4, 'id': 'sess', 'cwd': '/ws'},
  'cursor':
      cursor ?? (records.isEmpty ? -1 : (records.last['event']! as Map)['seq']),
  'records': records,
  'hasMore': hasMore,
  'projections': {'asOfSeq': cursor ?? 0, 'values': projections},
  'assistantStream': {
    'revision': revision,
    if (activeAttempt != null) 'activeAttempt': activeAttempt,
  },
};

Map<String, Object?> aframe(Map<String, Object?> frame) => {
  'type': 'assistant-stream',
  'frame': frame,
};

/// Scriptable [SessionTransport]: tests push frames into [follows].
class FakeTransport implements SessionTransport {
  final List<StreamController<GenerationFrame>> follows = [];
  final List<Map<String, Object?>> followRequests = [];
  final StreamController<GenerationFrame> controlController =
      StreamController.broadcast();
  final StreamController<HostEvent> events = StreamController.broadcast();
  final StreamController<ConnectionGeneration?> gens =
      StreamController.broadcast();

  Future<Map<String, Object?>> Function()? onList;
  Future<Map<String, Object?>> Function(Map<String, Object?> request)? onPage;
  final List<Map<String, Object?>> pageRequests = [];
  final List<Map<String, Object?>> prompts = [];
  final List<String> cancels = [];

  /// Durable image reads: `sessionId/attachmentId` per call; [onAttachment]
  /// answers (`{attachment, data}`), the default is a 1x1 PNG.
  final List<String> attachmentReads = [];
  Future<Map<String, Object?>> Function(String sessionId, String attachmentId)?
  onAttachment;

  /// Open a follow generation as the host would: [StreamOpened] then items.
  StreamController<GenerationFrame> get currentFollow => follows.last;

  void open(int generation, [Object? snapshotFrame]) {
    currentFollow.add(StreamOpened(generation));
    if (snapshotFrame != null) {
      currentFollow.add(StreamItem(generation, snapshotFrame));
    }
  }

  void item(int generation, Object? value) =>
      currentFollow.add(StreamItem(generation, value));

  void end(int generation, [Object? error]) =>
      currentFollow.add(StreamEnded(generation, error));

  @override
  Stream<GenerationFrame> follow(Map<String, Object?> Function() request) {
    followRequests.add(request());
    final c = StreamController<GenerationFrame>();
    follows.add(c);
    return c.stream;
  }

  @override
  Stream<GenerationFrame> control() => controlController.stream;

  @override
  Stream<HostEvent> get hostEvents => events.stream;

  @override
  Stream<ConnectionGeneration?> get generations => gens.stream;

  @override
  ConnectionGeneration? get generation => null;

  @override
  Future<Map<String, Object?>> list() =>
      onList?.call() ?? Future.value({'items': <Object?>[]});

  /// Every `session/create` request, in order.
  final List<Map<String, Object?>> createRequests = [];

  /// Answers a `session/create`; the default creates `new-session`.
  Future<Map<String, Object?>> Function(Map<String, Object?> request)? onCreate;

  @override
  Future<Map<String, Object?>> create(Map<String, Object?> request) async {
    createRequests.add(request);
    return onCreate?.call(request) ?? {'sessionId': 'new-session'};
  }

  /// Run before a prompt is recorded; throw to refuse it.
  void Function(Map<String, Object?> request)? onPrompt;

  @override
  Future<void> prompt(Map<String, Object?> request) async {
    onPrompt?.call(request);
    prompts.add(request);
  }

  @override
  Future<void> cancel(String sessionId) async => cancels.add(sessionId);

  @override
  Future<Map<String, Object?>> attachment(
    String sessionId,
    String attachmentId,
  ) {
    attachmentReads.add('$sessionId/$attachmentId');
    return onAttachment?.call(sessionId, attachmentId) ??
        Future.value({
          'attachment': {'attachmentId': attachmentId},
          'data': _onePixelPng,
        });
  }

  @override
  Future<Map<String, Object?>> page(Map<String, Object?> request) {
    pageRequests.add(request);
    return onPage!(request);
  }
}

Future<void> pump([int ms = 20]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// A valid 1x1 PNG (base64) for tests that need decodable image bytes.
const String _onePixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
