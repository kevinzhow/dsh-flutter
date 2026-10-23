import 'package:dsh_client/src/generated/session_remote.g.dart';
import 'package:dsh_client/src/remote_caller.dart';
import 'package:test/test.dart';

/// Records every call and answers with the next queued value.
class FakeCaller implements RemoteCaller {
  final calls = <({String ns, String method, Map<String, Object?> args})>[];
  final replies = <Object?>[];

  @override
  Future<Object?> call(
    String namespace,
    String method,
    Map<String, Object?> args,
  ) async {
    calls.add((ns: namespace, method: method, args: args));
    return replies.removeAt(0);
  }
}

const sid = 'sess-0001';

Map<String, Object?> summaryJson({String id = sid}) => {
  'agentAvailable': true,
  'formatStatus': 'current',
  'sessionId': id,
  'updatedAt': 1760000000000,
  'running': false,
  'blank': false,
  'cwd': '/work/demo',
  'projections': {
    'kind': 'sequenced',
    'asOfSeq': 12,
    'values': {
      'title': 'Demo title',
      'todos': [
        {'content': 'write tests', 'status': 'in_progress'},
      ],
      'modelSelection': {
        'lastUsed': {'provider': 'p', 'model': 'm'},
        'next': null,
      },
      'plan': {'someFutureProjection': true},
    },
  },
};

void main() {
  late FakeCaller caller;
  late SessionRemote remote;

  setUp(() {
    caller = FakeCaller();
    remote = SessionRemote(caller);
  });

  void expectCall(String method, Map<String, Object?> args) {
    expect(caller.calls, hasLength(1));
    expect(caller.calls.single.ns, 'session');
    expect(caller.calls.single.method, method);
    expect(caller.calls.single.args, args);
  }

  group('unary methods', () {
    test('list sends the verbatim host parameter name _request', () async {
      caller.replies.add({
        'items': [summaryJson()],
      });
      final value = await remote.list(const SessionListRequest());
      expectCall('list', {'_request': <String, Object?>{}});
      final item = value.items.single;
      expect(item.sessionId, sid);
      expect(item.updatedAt, 1760000000000);
      expect(item.formatStatus, SessionSummaryFormatStatus.current);
      expect(item.projections!.kind, SessionProjectionHintsKind.sequenced);
      final values = item.projections!.values;
      expect(values.title, 'Demo title');
      expect(values.todos!.single.status, TodoItemStatus.inProgress);
      expect(values.modelSelection!.lastUsed!.model, 'm');
      expect(values.modelSelection!.next, isNull);
      // projections this generation does not model survive in `extra`
      expect(values.extra['plan'], {'someFutureProjection': true});
    });

    test('search', () async {
      caller.replies.add({
        'items': [
          {'sessionId': sid, 'snippet': 'hello'},
        ],
        'hasMore': true,
      });
      final value = await remote.search(
        const SessionSearchRequest(query: 'hello'),
      );
      expectCall('search', {
        'request': {'query': 'hello'},
      });
      expect(value.hasMore, isTrue);
      expect(value.items.single.snippet, 'hello');
    });

    test('create', () async {
      caller.replies.add({'sessionId': sid, 'agentPreset': 'default'});
      final value = await remote.create(
        const SessionCreateRequest(cwd: '/work/demo', agentPreset: 'default'),
      );
      expectCall('create', {
        'request': {'cwd': '/work/demo', 'agentPreset': 'default'},
      });
      expect(value.sessionId, sid);
      expect(value.agentPreset, 'default');
    });

    test('selectModel', () async {
      caller.replies.add({
        'selected': {'provider': 'p', 'model': 'm', 'reasoningEffort': 'high'},
      });
      final value = await remote.selectModel(
        const SessionSelectModelRequest(
          sessionId: sid,
          provider: 'p',
          model: 'm',
          reasoningEffort: 'high',
        ),
      );
      expectCall('selectModel', {
        'request': {
          'sessionId': sid,
          'provider': 'p',
          'model': 'm',
          'reasoningEffort': 'high',
        },
      });
      expect(value.selected.reasoningEffort, 'high');
    });

    test('initializeDefaultModel takes no args and returns nothing', () async {
      caller.replies.add(null);
      await remote.initializeDefaultModel();
      expectCall('initializeDefaultModel', {});
    });

    test('modelCatalog', () async {
      caller.replies.add({
        'default': {'provider': 'p', 'model': 'm'},
        'routableProviders': ['p'],
        'groups': [
          {
            'id': 'p',
            'name': 'Provider',
            'models': [
              {
                'id': 'm',
                'name': 'Model',
                'reasoning': {
                  'efforts': [
                    {'id': 'high', 'name': 'High'},
                  ],
                  'defaultEffort': 'high',
                },
              },
            ],
          },
        ],
        'failures': [
          {'id': 'q', 'name': 'Other', 'message': 'offline'},
        ],
      });
      final value = await remote.modelCatalog();
      expectCall('modelCatalog', {});
      expect(value.defaultSelection.model, 'm');
      expect(
        value.groups.single.models.single.reasoning!.defaultEffort,
        'high',
      );
      expect(value.failures.single.message, 'offline');
    });

    test('canOpenWorkspacePath returns a bool', () async {
      caller.replies.add(false);
      expect(await remote.canOpenWorkspacePath(), isFalse);
      expectCall('canOpenWorkspacePath', {});
    });

    test('openWorkspacePath', () async {
      caller.replies.add({'opened': true});
      final value = await remote.openWorkspacePath(
        const SessionOpenWorkspacePathRequest(
          path: '/work/a.txt',
          action: 'reveal',
        ),
      );
      expectCall('openWorkspacePath', {
        'request': {'action': 'reveal', 'path': '/work/a.txt'},
      });
      expect(value.toJson(), {'opened': true});
    });

    test('workspacePathApplications decodes a bare list', () async {
      caller.replies.add([
        {'id': 'app.edit', 'name': 'Editor', 'default': true, 'icon': null},
      ]);
      final apps = await remote.workspacePathApplications(
        const SessionWorkspacePathApplicationsRequest(path: '/work/a.txt'),
      );
      expectCall('workspacePathApplications', {
        'request': {'path': '/work/a.txt'},
      });
      expect(apps.single.isDefault, isTrue);
      expect(apps.single.icon, isNull);
    });

    test('rename, fork, cancel', () async {
      caller.replies.add({'title': 'New', 'seq': 7});
      final renamed = await remote.rename(
        const SessionRenameRequest(sessionId: sid, title: 'New'),
      );
      expect(renamed.seq, 7);
      expect(caller.calls.last.method, 'rename');
      expect(caller.calls.last.args, {
        'request': {'sessionId': sid, 'title': 'New'},
      });

      caller.replies.add({'sessionId': 'sess-0002'});
      final forked = await remote.fork(
        const SessionForkRequest(
          sessionId: sid,
          atSeq: 5,
          allowMigration: false,
        ),
      );
      expect(forked.sessionId, 'sess-0002');
      expect(caller.calls.last.args, {
        'request': {'sessionId': sid, 'atSeq': 5, 'allowMigration': false},
      });

      caller.replies.add({'accepted': true});
      await remote.cancel(const SessionCancelRequest(sessionId: sid));
      expect(caller.calls.last.method, 'cancel');
      expect(caller.calls.last.args, {
        'request': {'sessionId': sid},
      });
    });

    test('prompt encodes every content part kind', () async {
      caller.replies.add({'accepted': true});
      final value = await remote.prompt(
        SessionPromptRequest(
          requestId: 'req-1',
          sessionId: sid,
          mode: SessionPromptRequestMode.queue,
          content: const [
            PromptContentPartText(text: 'hi'),
            PromptContentPartImage(
              mediaType: ImageMediaType.imagePng,
              data: 'AAAA',
              name: 'a.png',
            ),
            PromptContentPartFile(receiptId: 'receipt-1'),
          ],
          clientTimeZone: 'Asia/Shanghai',
        ),
      );
      expectCall('prompt', {
        'request': {
          'requestId': 'req-1',
          'sessionId': sid,
          'mode': 'queue',
          'content': [
            {'type': 'text', 'text': 'hi'},
            {
              'type': 'image',
              'mediaType': 'image/png',
              'data': 'AAAA',
              'name': 'a.png',
            },
            {'type': 'file', 'receiptId': 'receipt-1'},
          ],
          'clientTimeZone': 'Asia/Shanghai',
        },
      });
      expect(value.toJson(), {'accepted': true});
    });

    test('attachment', () async {
      caller.replies.add({
        'attachment': {
          'attachmentId': 'att-1',
          'mediaType': 'image/webp',
          'bytes': 10,
          'width': 4,
          'height': 3,
          'originalDimensions': {'width': 8, 'height': 6},
        },
        'data': 'AAAA',
      });
      final value = await remote.attachment(
        const SessionAttachmentRequest(sessionId: sid, attachmentId: 'att-1'),
      );
      expectCall('attachment', {
        'request': {'sessionId': sid, 'attachmentId': 'att-1'},
      });
      expect(value.attachment.mediaType, ImageMediaType.imageWebp);
      expect(value.attachment.originalDimensions!.width, 8);
    });

    test('updateQueue encodes edit, remove and steer', () async {
      for (final (action, json) in <(QueueAction, Map<String, Object?>)>[
        (
          const QueueActionEdit(content: [TextBlock(text: 'edited')]),
          {
            'kind': 'edit',
            'content': [
              {'type': 'text', 'text': 'edited'},
            ],
          },
        ),
        (const QueueActionRemove(), {'kind': 'remove'}),
        (const QueueActionSteer(), {'kind': 'steer'}),
      ]) {
        caller.calls.clear();
        caller.replies.add({'accepted': true});
        await remote.updateQueue(
          SessionUpdateQueueRequest(
            sessionId: sid,
            itemId: 'msg-1',
            action: action,
          ),
        );
        expectCall('updateQueue', {
          'request': {'sessionId': sid, 'itemId': 'msg-1', 'action': json},
        });
      }
    });

    test('page with a subagent address and turn window', () async {
      caller.replies.add({
        'records': [
          {
            'type': 'event',
            'event': {
              'type': 'turn/start',
              'seq': 3,
              'time': 1760000000100,
              'data': {'turn': 1},
            },
          },
        ],
        'hasMore': false,
      });
      final value = await remote.page(
        SessionPageRequest(
          address: SessionAddressSubagent(
            parentSessionId: sid,
            childSessionId: 'sess-child',
            mode: SessionAddressSubagentMode.oneShot,
          ),
          throughSeq: 3,
          beforeSeq: 3,
          maxMessages: 20,
          turnWindow: SessionPageRequestTurnWindow(minMessages: 2, minTurns: 1),
        ),
      );
      expectCall('page', {
        'request': {
          'address': {
            'kind': 'subagent',
            'parentSessionId': sid,
            'childSessionId': 'sess-child',
            'mode': 'one-shot',
          },
          'throughSeq': 3,
          'beforeSeq': 3,
          'maxMessages': 20,
          'turnWindow': {'minMessages': 2, 'minTurns': 1},
        },
      });
      expect(value.hasMore, isFalse);
      final event = value.records.single.event;
      expect(event.type, 'turn/start');
      expect(event.seq, 3);
      expect(event.data, {'turn': 1});
      // the raw envelope can be handed to the models layer's SessionEvent.fromJson
      expect(event.toJson()['type'], 'turn/start');
    });

    test('projections: sequenced, migration-required and null', () async {
      caller.replies.add({
        'kind': 'sequenced',
        'asOfSeq': 9,
        'values': {'title': null},
      });
      final a = await remote.projections(
        const SessionProjectionsRequest(sessionId: sid),
      );
      expectCall('projections', {
        'request': {'sessionId': sid},
      });
      expect(a, isA<SessionProjectionsValueSequenced>());
      expect((a as SessionProjectionsValueSequenced).asOfSeq, 9);
      expect(a.values.title, isNull);

      caller.replies.add({
        'kind': 'migration-required',
        'values': <String, Object?>{},
      });
      final b = await remote.projections(
        const SessionProjectionsRequest(sessionId: sid),
      );
      expect(b, isA<SessionProjectionsValueMigrationRequired>());

      caller.replies.add(null);
      expect(
        await remote.projections(
          const SessionProjectionsRequest(sessionId: sid),
        ),
        isNull,
      );
    });
  });

  group('stream descriptors', () {
    test('follow encodes its request and has the session/follow endpoint', () {
      final d = SessionStreams.follow;
      expect(d.endpoint, 'session/follow');
      expect(
        d.encodeArgs(
          const SessionFollowRequest(
            address: SessionAddressSession(sessionId: sid),
            assistantStream: true,
            maxMessages: 30,
          ),
        ),
        {
          'request': {
            'address': {'kind': 'session', 'sessionId': sid},
            'assistantStream': true,
            'maxMessages': 30,
          },
        },
      );
    });

    test('follow decodes snapshot, event and assistant-stream frames', () {
      final d = SessionStreams.follow;
      final snapshot = d.decodeFrame({
        'type': 'snapshot',
        'header': {
          'version': 2,
          'id': sid,
          'createdAt': 1760000000000,
          'isSeeded': false,
          'cwd': '/work/demo',
        },
        'cursor': 4,
        'records': [
          {
            'type': 'event',
            'event': {
              'type': 'user/message',
              'seq': 1,
              'time': 1760000000001,
              'data': {'x': 1},
              'surfaceOp': 'append',
            },
          },
        ],
        'hasMore': true,
        'projections': {
          'asOfSeq': 4,
          'values': {'title': 'T'},
        },
        'assistantStream': {
          'revision': 2,
          'activeAttempt': {
            'attemptId': 'att-1',
            'startedAfterSeq': -1,
            'turn': 1,
            'step': 1,
            'nextIndex': 3,
            'stream': [
              {'any': 'json'},
            ],
          },
        },
      });
      expect(snapshot, isA<SessionFollowFrameSnapshot>());
      snapshot as SessionFollowFrameSnapshot;
      expect(snapshot.cursor, 4);
      expect(snapshot.header.cwd, '/work/demo');
      expect(snapshot.records.single.event.seq, 1);
      expect(snapshot.projections.values.title, 'T');
      final active = snapshot.assistantStream!.activeAttempt!;
      expect(active.startedAfterSeq, -1);
      expect(active.nextIndex, 3);

      final event = d.decodeFrame({
        'type': 'event',
        'event': {
          'type': 'turn/end',
          'seq': 5,
          'time': 1760000000200,
          'data': {'turn': 1},
          'ignorable': true,
        },
      });
      expect(event, isA<SessionEventEntry>());
      expect((event as SessionEventEntry).event.ignorable, isTrue);

      final start = d.decodeFrame({
        'type': 'assistant-stream',
        'frame': {
          'type': 'start',
          'attemptId': 'att-1',
          'revision': 3,
          'startedAfterSeq': 5,
          'turn': 2,
          'step': 1,
        },
      });
      expect(start, isA<SessionFollowFrameAssistantStream>());
      final chunk = d.decodeFrame({
        'type': 'assistant-stream',
        'frame': {
          'type': 'chunk',
          'attemptId': 'att-1',
          'revision': 3,
          'index': 0,
          'time': 1760000000300,
          'chunk': {'type': 'text-delta', 'text': 'hi'},
        },
      });
      expect(
        ((chunk as SessionFollowFrameAssistantStream).frame
                as SessionAssistantStreamFrameChunk)
            .chunk,
        {'type': 'text-delta', 'text': 'hi'},
      );
      final end = d.decodeFrame({
        'type': 'assistant-stream',
        'frame': {
          'type': 'end',
          'attemptId': 'att-1',
          'revision': 3,
          'index': 1,
          'outcome': {
            'kind': 'committed',
            'eventType': 'assistant/message',
            'seq': 6,
          },
        },
      });
      final outcome =
          ((end as SessionFollowFrameAssistantStream).frame
                  as SessionAssistantStreamFrameEnd)
              .outcome;
      expect(outcome, isA<SessionAssistantStreamFrameEndOutcomeCommitted>());
      expect(
        (outcome as SessionAssistantStreamFrameEndOutcomeCommitted).seq,
        6,
      );
    });

    test('a frame type from a newer host is kept raw, not fatal', () {
      final frame = SessionStreams.follow.decodeFrame({
        'type': 'future',
        'a': 1,
      });
      expect(frame, isA<SessionFollowFrameUnrecognized>());
      expect(frame.toJson(), {'type': 'future', 'a': 1});
    });

    test('control: no-arg args, baseline and projection frames', () {
      final d = SessionStreams.control;
      expect(d.endpoint, 'session/control');
      expect(d.encodeArgs(const NoStreamArgs()), isEmpty);
      final baseline = d.decodeFrame({
        'type': 'baseline',
        'value': {
          'projections': {
            sid: {
              'asOfSeq': 2,
              'values': {'title': 'T'},
            },
          },
        },
      });
      baseline as SessionControlFrameBaseline;
      expect(baseline.value.projections[sid]!.asOfSeq, 2);
      final update = d.decodeFrame({
        'type': 'projection',
        'sessionId': sid,
        'key': 'title',
        'value': 'New',
        'seq': 3,
      });
      update as SessionControlFrameProjection;
      expect(update.key, 'title');
      expect(update.value, 'New');
      expect(update.seq, 3);
    });
  });

  group('strictness', () {
    test(
      'a missing required field throws FormatException naming the path',
      () async {
        caller.replies.add({
          'items': [
            {'agentAvailable': true},
          ],
        });
        await expectLater(
          remote.list(const SessionListRequest()),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'session/list.items[0].sessionId: required field is missing',
            ),
          ),
        );
      },
    );

    test(
      'a wrongly typed field throws FormatException naming the path',
      () async {
        caller.replies.add({'title': 'x', 'seq': 'seven'});
        await expectLater(
          remote.rename(const SessionRenameRequest(sessionId: sid, title: 'x')),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('session/rename.seq: expected an integer'),
            ),
          ),
        );
      },
    );

    test(
      'unknown extra fields are ignored and unknown enum values kept',
      () async {
        caller.replies.add({
          'items': [
            {
              ...summaryJson(),
              'formatStatus': 'from-the-future',
              'newField': {'a': 1},
            },
          ],
        });
        final value = await remote.list(const SessionListRequest());
        final status = value.items.single.formatStatus!;
        expect(status.isKnown, isFalse);
        expect(status.value, 'from-the-future');
        expect(value.items.single.toJson()['formatStatus'], 'from-the-future');
      },
    );

    test('integral doubles decode as int, fractions do not', () {
      final ok = SessionRenameValue.fromJson({'title': 't', 'seq': 7.0});
      expect(ok.seq, 7);
      expect(
        () => SessionRenameValue.fromJson({'title': 't', 'seq': 7.5}),
        throwsFormatException,
      );
    });

    test('a constant tag mismatch is rejected', () {
      expect(
        () => SessionPromptValue.fromJson({'accepted': false}),
        throwsFormatException,
      );
    });

    test('RemoteException from the caller propagates', () {
      final failing = SessionRemote(_Failing());
      expect(
        failing.cancel(const SessionCancelRequest(sessionId: sid)),
        throwsA(isA<RemoteException>()),
      );
    });
  });
}

class _Failing implements RemoteCaller {
  @override
  Future<Object?> call(
    String namespace,
    String method,
    Map<String, Object?> args,
  ) => Future.error(RemoteException('session/not-found', 'no such session'));
}
