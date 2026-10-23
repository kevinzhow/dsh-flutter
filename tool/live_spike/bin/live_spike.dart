// ignore_for_file: unnecessary_non_null_assertion
// Usage (from tool/live_spike): dart run bin/live_spike.dart [--port 18701] [--ws DIR] [--out FILE] [--raw DIR] [--session ID]
// The raw trace goes to --raw (outside version control); scrub it with tool/vectors/scrub_trace.py.
// Phase 0 live spike: drives dsh_client / dsh_models / dsh_conversation against
// a `dsh web` host this program starts and stops by PID. Never prints the
// launch token, cookies or model replies; results hold timings and shapes.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dsh_client/dsh_client.dart';
import 'package:dsh_client/generated.dart' as gen;
import 'package:dsh_conversation/dsh_conversation.dart';
import 'package:dsh_live_spike/checks.dart';
import 'package:dsh_live_spike/live_host.dart';
import 'package:dsh_live_spike/recorder.dart';
import 'package:dsh_models/dsh_models.dart';
import 'package:dsh_models/generated.dart' as genev;

String arg(List<String> a, String name, String fallback) {
  final i = a.indexOf('--$name');
  return i >= 0 && i + 1 < a.length ? a[i + 1] : fallback;
}

bool hasEvent(
  Session s,
  String type, {
  num after = -1,
  bool Function(EventEntry)? where,
}) => s.eventSource.window.entries.any(
  (e) =>
      !e.transient &&
      e.type == type &&
      e.seq > after &&
      (where?.call(e) ?? true),
);

num lastSeq(Session s) => s.eventSource.window.entries
    .where((e) => !e.transient)
    .fold<num>(-1, (a, e) => e.seq > a ? e.seq : a);

bool hasLiveText(Session s) => s.eventSource.window.entries.any(
  (e) =>
      e.transient && ((e.data as Map)['chunk'] as Map)['type'] == 'text-delta',
);

String assistantText(Session s) =>
    buildChatSnapshot(s.eventSource.window).nodes
        .where((n) => n.key == 'assistant-step')
        .map((n) => n.data['text'])
        .join();

/// Decode real host data with the generated codecs (tool/codegen output).
Future<String> decodeWithGenerated(List<Map<String, Object?>> steps) async {
  var frames = 0, events = 0, pages = 0;
  final unknownTypes = <String>{};
  void event(Object? wire) {
    final decoded = genev.SessionEvent.fromJson(wire);
    if (decoded is genev.UnknownSessionEvent) {
      unknownTypes.add('${(wire! as Map)['type']}');
    }
    events++;
  }

  for (final s in steps) {
    if (s['op'] == 'frame') {
      final f = s['frame']! as Map;
      gen.SessionStreams.follow.decodeFrame(f);
      frames++;
      if (f['type'] == 'event') event(f['event']);
      if (f['type'] == 'snapshot') {
        for (final r in f['records']! as List) {
          event((r as Map)['event']);
        }
      }
    } else if (s['op'] == 'page') {
      for (final r in ((s['response']! as Map)['records']! as List)) {
        event((r as Map)['event']);
      }
      pages++;
    }
  }
  if (unknownTypes.isNotEmpty) {
    throw StateError(
      'event types unknown to the generated schema: $unknownTypes',
    );
  }
  return '$frames follow frames, $events events ($pages pages) decoded, 0 unknown event types';
}

Future<void> main(List<String> args) async {
  final port = int.parse(arg(args, 'port', '18701'));
  final ws = arg(args, 'ws', '../../.local/live-spike/ws');
  final out = arg(args, 'out', '../../.local/live-spike/results.json');
  final rawDir = arg(args, 'raw', '../../.local/live-spike/raw');
  final pinned = arg(args, 'pinned', '0.2.1-rc.2');
  final reuseSession = arg(args, 'session', '');
  final codecOnly = args.contains('--codec-only');
  Directory(ws).createSync(recursive: true);
  Directory(rawDir).createSync(recursive: true);
  final c = Checks();
  final clock = Stopwatch()..start();

  LiveHost? host;
  LiveHost? host2;
  DshConnection? conn;
  DshConnection? conn2;
  try {
    // ---- host + pairing -------------------------------------------------
    var token = '';
    await c.check('host start (spawn to launch token)', () async {
      host = await LiveHost.start(port: port, workspace: ws);
      token = await host!.token;
      await host!.waitListening();
      return 'pid recorded, 127.0.0.1:$port, ${clock.elapsedMilliseconds} ms since spike start';
    });
    if (host == null || token.isEmpty) throw StateError('no host');

    conn = DshConnection(origin: host!.origin);
    await c.check('pairing: /connect + mux + \$events ready', () async {
      conn!.start(token);
      final g = await conn!.untilConnected();
      return 'generation ${g.id}, clientId set=${g.clientId.isNotEmpty}, home set=${g.hostHome.isNotEmpty}, interactions=answer';
    });
    final transport = DshSessionTransport(conn);

    await c.check('version exposure (pluginManager/listBundles)', () async {
      final v = await readHostVersion(conn!.caller);
      c.facts['hostVersion'] = v;
      if (v == null) throw StateError('no version found');
      if (v != pinned) throw StateError('host $v differs from pin $pinned');
      return 'host $v == pin';
    });

    // ---- list shape -----------------------------------------------------
    await c.check('session/list reply shape', () async {
      final raw = await transport.list();
      final items = (raw['items']! as List).cast<Map<String, Object?>>();
      final keys = <String>{for (final i in items) ...i.keys};
      final kinds = <Object?>{
        for (final i in items) (i['projections'] as Map?)?['kind'],
      };
      final pkeys = <String>{
        for (final i in items)
          ...(((i['projections'] as Map?)?['values'] as Map?)?.keys
                  .cast<String>() ??
              <String>[]),
      };
      c.facts['sessionListTopKeys'] = raw.keys.toList();
      c.facts['sessionSummaryKeys'] = keys.toList()..sort();
      c.facts['listProjectionBlockKinds'] = kinds.toList();
      c.facts['listProjectionValueKeys'] = pkeys.toList()..sort();
      c.facts['sessionCount'] = items.length;
      return '${items.length} rows; summary keys ${keys.toList()..sort()}; block kinds $kinds; value keys ${pkeys.toList()..sort()}';
    });

    await c.check('generated SessionRemote: typed list + modelCatalog against the real host', () async {
      final remote = gen.SessionRemote(conn!.caller);
      final list = await remote.list(const gen.SessionListRequest());
      final catalog = await remote.modelCatalog();
      return '${list.items.length} typed rows, model catalog with ${catalog.groups.length} provider groups decoded';
    });

    // ---- models over a recording transport -------------------------------
    final recorder = RecordingTransport(transport);
    final manager = SessionManager(recorder)..start();
    final sessions = ClientSessions(manager);
    await c.check('SessionManager list baseline', () async {
      await manager.refreshList();
      final l = manager.list.value;
      if (l.phase != ListPhase.ready) {
        throw StateError('list not ready: ${l.error}');
      }
      return '${l.items.length} rows, ${l.items.where((i) => i.title != null).length} with title projection';
    });

    late Session session;
    late String sessionId;
    await c.check(
      reuseSession.isEmpty
          ? 'create session (scratch workspace)'
          : 'reuse scratch session',
      () async {
        session = reuseSession.isEmpty
            ? await manager.create(cwd: ws)
            : manager.get(reuseSession);
        sessionId = session.sessionId;
        c.facts['scratchSessionId'] = sessionId;
        await manager.refreshList();
        await until(
          'session row',
          () => manager.list.value.items.any((i) => i.sessionId == sessionId),
          timeout: const Duration(seconds: 10),
        );
        return 'row visible in list';
      },
    );

    await c.check('open: follow snapshot into the event window', () async {
      final binding = sessions.bind(sessionId);
      await binding.session.open();
      final snap = binding.session.snapshot.value;
      if (snap.openState != OpenState.open) {
        throw StateError('open state ${snap.openState}');
      }
      return 'window ${session.eventSource.window.entries.length} entries, hasMore=${snap.hasMore}, projection keys ${session.projections.values.keys.length}';
    });

    if (codecOnly) {
      await c.check(
        'generated codecs decode real follow frames and pages',
        () async {
          var guard = 0;
          while (session.snapshot.value.hasMore && guard++ < 4) {
            await session.loadOlder();
          }
          return decodeWithGenerated(recorder.steps);
        },
      );
      return;
    }
    await c.check('follow snapshot frame shape + session/control baseline shape', () async {
      final snap =
          recorder.steps.firstWhere(
                (s) =>
                    s['op'] == 'frame' &&
                    (s['frame'] as Map)['type'] == 'snapshot',
              )['frame']!
              as Map;
      c.facts['followSnapshotKeys'] = snap.keys.toList();
      c.facts['followSnapshotHeaderKeys'] = (snap['header'] as Map).keys
          .toList();
      c.facts['followSnapshotProjectionsKeys'] = (snap['projections'] as Map)
          .keys
          .toList();
      c.facts['followSnapshotAssistantStreamKeys'] =
          (snap['assistantStream'] as Map).keys.toList();
      final control = await transport
          .control()
          .firstWhere((f) => f is StreamItem)
          .timeout(const Duration(seconds: 15));
      final baseline = (control as StreamItem).value! as Map;
      final proj = (baseline['value'] as Map)['projections'] as Map;
      c.facts['controlBaselineKeys'] = baseline.keys.toList();
      c.facts['controlBaselineSessions'] = proj.length;
      c.facts['controlBaselineBlockKeys'] = proj.isEmpty
          ? <Object?>[]
          : (proj.values.first as Map).keys.toList();
      return 'snapshot ${snap.keys.toList()}; header ${(snap['header'] as Map).keys.toList()}; control baseline sessions=${proj.length}';
    });

    // ---- prompt + streaming ---------------------------------------------
    await c.check('prompt: streamed assistant output', () async {
      final sw = Stopwatch()..start();
      final base = lastSeq(session);
      await session.prompt('Reply with exactly: hi');
      final tAccepted = sw.elapsedMilliseconds;
      await until(
        'first live text chunk',
        () => hasLiveText(session),
        timeout: const Duration(seconds: 90),
      );
      final tFirst = sw.elapsedMilliseconds;
      await until(
        'turn/end',
        () => hasEvent(session, 'turn/end', after: base),
        timeout: const Duration(seconds: 120),
      );
      final tEnd = sw.elapsedMilliseconds;
      final text = assistantText(session).trim().toLowerCase();
      final streamedThenSettled = !session.eventSource.window.entries.any(
        (e) => e.transient,
      );
      c.facts['promptTimingsMs'] = {
        'accepted': tAccepted,
        'firstChunk': tFirst,
        'turnEnd': tEnd,
      };
      if (!text.contains('hi')) {
        throw StateError(
          'reply text did not contain hi (length ${text.length})',
        );
      }
      if (!streamedThenSettled) {
        throw StateError('transient rows remained after turn/end');
      }
      return 'accepted ${tAccepted}ms, first chunk ${tFirst}ms, turn end ${tEnd}ms, settled=true, echo retired=${session.snapshot.value.pendingSubmissions.isEmpty}';
    });

    // ---- cancel ---------------------------------------------------------
    await c.check('cancel an active turn', () async {
      final base = lastSeq(session);
      await session.prompt(
        'Write the integers from 1 to 400, one per line, with no other text.',
      );
      await until(
        'streaming started',
        () => hasLiveText(session),
        timeout: const Duration(seconds: 90),
      );
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final sw = Stopwatch()..start();
      await session.cancel();
      final tAck = sw.elapsedMilliseconds;
      await until(
        'turn/end after cancel',
        () => hasEvent(session, 'turn/end', after: base),
        timeout: const Duration(seconds: 60),
      );
      final end = session.eventSource.window.entries.lastWhere(
        (e) => e.type == 'turn/end',
      );
      final reason = ((end.data as Map)['reason'] as Map?)?['kind'];
      c.facts['cancelReasonKind'] = reason;
      await until(
        'session idle',
        () => !session.snapshot.value.running,
        timeout: const Duration(seconds: 30),
      );
      return 'cancel ack ${tAck}ms, turn/end after ${sw.elapsedMilliseconds}ms, reason.kind=$reason, running=false';
    });

    // ---- approval round trip + two answerers -----------------------------
    conn2 = DshConnection(origin: host!.origin);
    conn2!.start(token);
    await conn2!.untilConnected();
    final eventsA = <HostEvent>[];
    final eventsB = <HostEvent>[];
    final subA = conn!.hostEvents.listen(eventsA.add);
    final subB = conn2!.hostEvents.listen(eventsB.add);
    await c.check('switch the scratch session to workspace-write+ask (commands/execute /permission)', () async {
      final before =
          (session.projections.get('permissions') as Map?)?['currentValue'];
      c.facts['permissionPresetBefore'] = before;
      final catalog = await conn!.caller.call(
        'permissionPresets',
        'catalog',
        const {},
      );
      c.facts['permissionCatalogOptionNames'] = [
        for (final o in ((catalog as Map)['options'] as List))
          (o as Map)['value'],
      ];
      if (before != 'workspace-write') {
        await conn!.caller.call('commands', 'execute', {
          'agentId': sessionId,
          'line': '/permission workspace-write',
          'submittedAttachments': <Object?>[],
        });
        await until(
          'permissions projection to follow the command',
          () =>
              (session.projections.get('permissions')
                  as Map?)?['currentValue'] ==
              'workspace-write',
          timeout: const Duration(seconds: 30),
        );
      }
      return 'preset before=$before, now ${(session.projections.get('permissions') as Map?)?['currentValue']}, catalog ${c.facts['permissionCatalogOptionNames']}';
    });
    await c.check('approval round trip (A answers) + two answerers (B late answer)', () async {
      final base = lastSeq(session);
      final sw = Stopwatch()..start();
      await session.prompt(
        'Use the bash tool to run exactly this command: echo hi > $ws/../approval-probe.txt . '
        'It writes outside the working directory, so the sandbox will deny it. When it does, retry the exact '
        'command once with escalated sandbox_permissions and a one-sentence justification. Then reply done.',
      );
      WaterfallEvent? waterfall(List<HostEvent> l) {
        for (final e in l) {
          if (e is WaterfallEvent && e.event == 'approval/request') return e;
        }
        return null;
      }

      try {
        await until(
          'approval/request on A',
          () => waterfall(eventsA) != null,
          timeout: const Duration(seconds: 120),
        );
      } on Timeout2 {
        final calls = session.eventSource.window.entries
            .where((e) => e.type == 'tool/call' && e.seq > base)
            .map((e) {
              final d = e.data as Map?;
              return '${d?['name']}(${'${d?['args'] ?? d?['arguments']}'.replaceAll('\n', ' ')})';
            })
            .toList();
        throw StateError(
          'no approval/request within 120s; tool calls this turn: $calls',
        );
      }
      final tReq = sw.elapsedMilliseconds;
      final wA = waterfall(eventsA)!;
      c.facts['approvalRequestKeys'] = wA.request.keys.toList()..sort();
      c.facts['approvalAgentIsSessionId'] = wA.agentId == sessionId;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final bGot = waterfall(eventsB) != null;
      final tAns = Stopwatch()..start();
      await conn!.answer(wA, const WaterfallResult('allowed-once'));
      final answerMs = tAns.elapsedMilliseconds;
      // B answers late with the opposite outcome.
      String bOutcome;
      final wB = waterfall(eventsB);
      if (wB == null) {
        bOutcome = 'B never received the request';
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final cancelsOnB = eventsB
            .whereType<CancelEvent>()
            .where((e) => e.eventId == wB.eventId)
            .length;
        try {
          await conn2!.answer(wB, const WaterfallResult('rejected'));
          bOutcome =
              'B late answer accepted by host without error (cancel frames on B before answering: $cancelsOnB)';
        } on RemoteException catch (e) {
          bOutcome =
              'B late answer refused: ${e.code} (cancel frames on B before answering: $cancelsOnB)';
        }
      }
      c.facts['twoAnswerers'] = {
        'bReceivedRequest': bGot,
        'bLateAnswer': bOutcome,
      };
      await until(
        'tool/result after approval',
        () => hasEvent(session, 'tool/result', after: base),
        timeout: const Duration(seconds: 60),
      );
      await until(
        'turn/end after approval',
        () => hasEvent(session, 'turn/end', after: base),
        timeout: const Duration(seconds: 120),
      );
      final decided = session.eventSource.window.entries
          .where((e) => e.type == 'approval/decided' && e.seq > base)
          .map((e) => (e.data as Map)['outcome'])
          .toList();
      c.facts['approvalDecided'] = decided;
      if (!decided.contains('allowed-once')) {
        throw StateError('approval/decided was $decided');
      }
      return 'request after ${tReq}ms, answer POST ${answerMs}ms, audit decided=$decided; B received request=$bGot; $bOutcome';
    });
    await subA.cancel();
    await subB.cancel();
    await conn2!.stop();

    // ---- behaviour-vector trace (small window, live tail, paging) --------
    await c.check('record behaviour-vector trace (window of 2, live turn, loadOlder)', () async {
      final rec = RecordingTransport(transport);
      final s2 = Session(
        sessionId,
        rec,
        pageOptions: const {
          'maxMessages': 2,
          'turnWindow': {'minMessages': 1, 'minTurns': 1},
        },
      );
      rec.action('open');
      await s2.open();
      final hasMoreAtOpen = s2.snapshot.value.hasMore;
      final base = lastSeq(s2);
      await s2.prompt('Reply with exactly: ok');
      await until(
        'turn/end (trace session)',
        () => hasEvent(s2, 'turn/end', after: base),
        timeout: const Duration(seconds: 120),
      );
      var pages = 0;
      while (s2.snapshot.value.hasMore && pages < 6) {
        rec.action('loadOlder');
        await s2.loadOlder();
        pages++;
      }
      await s2.dispose();
      c.facts['generatedCodecsOnTrace'] = await decodeWithGenerated(rec.steps);
      File('$rawDir/trace.json').writeAsStringSync(
        jsonEncode({
          'format': 'dsh-session-trace/1',
          'hostVersion': c.facts['hostVersion'],
          'openOptions': s2.pageOptions,
          'steps': rec.steps,
        }),
      );
      return 'hasMore at open=$hasMoreAtOpen, loadOlder pages=$pages, ${rec.steps.length} steps, raw trace kept outside the repo';
    });

    // ---- host restart -> re-pair ----------------------------------------
    final oldCredential = conn!.generation?.credential;
    final revisionBefore = session.eventSource.window.revision;
    await c.check('host restart: socket lost, token refused, re-pair, follow reopened', () async {
      final sw = Stopwatch()..start();
      await host!.stop();
      await until(
        'connection to notice the loss',
        () => conn!.generation == null,
        timeout: const Duration(seconds: 30),
      );
      final tLost = sw.elapsedMilliseconds;
      host2 = await LiveHost.start(port: port, workspace: ws);
      final token2 = await host2!.token;
      await host2!.waitListening();
      final tUp = sw.elapsedMilliseconds;
      await conn!.untilState(
        (s) => s == ConnectionState.needsPairing,
        timeout: const Duration(seconds: 60),
      );
      final tNeeds = sw.elapsedMilliseconds;
      final rejected = conn!.lastError is PairingRejected;
      // The pre-restart cookie must be refused: its Peer died with the process.
      String oldCookie = 'no credential';
      if (oldCredential != null) {
        final stale = HttpRemoteCaller(oldCredential);
        try {
          await stale.call('session', 'list', {'_request': {}});
          oldCookie = 'old cookie still accepted';
        } on UnauthorizedException {
          oldCookie = 'old cookie refused (401)';
        } finally {
          stale.close();
        }
      }
      final pairStart = sw.elapsedMilliseconds;
      conn!.start(token2);
      final g = await conn!.untilConnected(
        timeout: const Duration(seconds: 30),
      );
      final tRepair = sw.elapsedMilliseconds - pairStart;
      await until(
        'follow window replaced after re-pair',
        () =>
            session.eventSource.window.revision > revisionBefore &&
            session.snapshot.value.openState == OpenState.open,
        timeout: const Duration(seconds: 30),
      );
      await until(
        'list baseline refetched',
        () => manager.list.value.items.any((i) => i.sessionId == sessionId),
        timeout: const Duration(seconds: 30),
      );
      c.facts['restartTimingsMs'] = {
        'lossDetected': tLost,
        'newHostListening': tUp,
        'needsPairing': tNeeds,
        'repair': tRepair,
      };
      if (!rejected) {
        throw StateError('expected PairingRejected, got ${conn!.lastError}');
      }
      return 'loss seen ${tLost}ms, new host listening ${tUp}ms, needsPairing ${tNeeds}ms, $oldCookie, re-pair to connected ${tRepair}ms (generation ${g.id}), follow reopened, list refetched';
    });
  } on Object catch (e, st) {
    stdout.writeln('ABORT ${e.runtimeType}: $e\n$st');
    c.results.add({
      'check': 'spike aborted',
      'status': 'fail',
      'ms': 0,
      'note': '${e.runtimeType}: $e',
    });
    if (host != null) {
      stdout.writeln('stderr tail: ${host!.redactedStderrTail}');
    }
  } finally {
    await conn?.stop();
    await conn2?.stop();
    for (final h in [host, host2]) {
      if (h != null) {
        await h.stop();
        stdout.writeln('stopped dsh pid ${h.pid}');
      }
    }
    c.writeTo(out);
    stdout.writeln('results: $out');
  }
}
